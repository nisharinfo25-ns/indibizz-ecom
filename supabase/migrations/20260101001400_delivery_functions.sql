-- IndiaBizz :: 0015 delivery app workflows, partner staff administration,
-- pickup verification, delivery OTP proof, COD handover and assignment expiry.
--
-- Safety rules enforced here:
--   * A barcode scan can never mark a shipment picked up.
--   * PICKED_UP requires the pickup OTP, the expected package count, GOOD
--     condition and a valid scan for every sealed package.
--   * DELIVERED requires the customer delivery OTP and the exact COD amount.
--   * COD cash is only settled after the owner verifies the counted amount.

-- ---------------------------------------------------------------------------
-- Shared staff helpers
-- ---------------------------------------------------------------------------
create or replace function public.staff_can_access_shipment(p_shipment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.delivery_assignments da
    where da.shipment_id = p_shipment_id
      and da.staff_user_id = auth.uid()
      and da.status in ('PENDING','ACCEPTED','COMPLETED')
  )
  or exists (
    select 1
    from public.pickup_assignments pa
    join public.pickup_requests pk on pk.id = pa.pickup_request_id
    where pk.shipment_id = p_shipment_id
      and pa.staff_user_id = auth.uid()
      and pa.status in ('PENDING','ACCEPTED','COMPLETED')
  );
$$;

create or replace function public.staff_can_access_pickup(p_pickup_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.pickup_assignments pa
    where pa.pickup_request_id = p_pickup_id
      and pa.staff_user_id = auth.uid()
      and pa.status in ('PENDING','ACCEPTED','COMPLETED')
  );
$$;

create or replace function app_private.staff_identity_or_raise()
returns table (
  staff_type public.staff_type,
  staff_profile_id uuid,
  partner_staff_id uuid,
  partner_id uuid,
  capacity_per_day integer,
  is_available boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return query select * from app_private.require_staff_identity();
end;
$$;

create or replace function app_private.assignment_offer_seconds(p_town_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select ap.offer_timeout_seconds from app_private.policy_for_town(p_town_id) ap),
    300
  );
$$;

-- Best-effort automatic delivery assignment. Used after a rejection/expiry or
-- when the owner did not assign after pickup. The pickup staff member is
-- preferred by the explicit hand-off path in staff_verify_pickup().
create or replace function app_private.try_auto_assign_delivery(p_shipment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_policy public.assignment_policies%rowtype;
  v_candidate record;
  v_assignment_id uuid;
  v_expires timestamptz;
begin
  select * into v_shipment from public.shipments where id = p_shipment_id for update;
  if v_shipment.id is null
     or v_shipment.status not in (
       'PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','DELIVERY_ATTEMPTED',
       'CUSTOMER_UNAVAILABLE','SHIPMENT_DELAYED','PICKUP_FAILED'
     ) then
    return null;
  end if;
  if exists (
    select 1 from public.delivery_assignments
    where shipment_id = p_shipment_id and status in ('PENDING','ACCEPTED')
  ) then
    return null;
  end if;

  select * into v_order from public.orders where id = v_shipment.order_id;
  select * into v_policy from app_private.policy_for_town(v_order.town_id);

  if v_policy.id is null then
    v_policy.auto_assign_enabled := true;
    v_policy.manual_only := false;
    v_policy.offer_timeout_seconds := 300;
    v_policy.max_active_tasks_per_staff := 10;
    v_policy.prefer_own_team := true;
    v_policy.weight_workload := 10;
    v_policy.weight_distance := 1;
    v_policy.candidate_limit := 20;
  end if;
  if not v_policy.auto_assign_enabled or v_policy.manual_only then
    return null;
  end if;

  select * into v_candidate
  from (
    select
      'OWN'::public.staff_type as staff_type,
      sp.id as staff_profile_id,
      null::uuid as partner_staff_id,
      null::uuid as partner_id,
      sp.user_id,
      (
        app_private.staff_active_workload(sp.user_id) * v_policy.weight_workload
        + coalesce(app_private.haversine_km(
            sp.current_latitude, sp.current_longitude, t.latitude, t.longitude), 25
          ) * v_policy.weight_distance
      )::numeric(12,4) as score
    from public.staff_profiles sp
    join public.profiles p on p.id = sp.user_id
    join public.towns t on t.id = v_order.town_id
    where sp.status = 'ACTIVE'
      and sp.is_available
      and p.status = 'ACTIVE'
      and p.role = 'OWN_DELIVERY_STAFF'
      and app_private.staff_active_workload(sp.user_id)
          < least(sp.capacity_per_day, v_policy.max_active_tasks_per_staff)
      and exists (
        select 1 from public.staff_service_areas sa
        where sa.staff_user_id = sp.user_id
          and sa.town_id = v_order.town_id
          and (sa.pincode is null or sa.pincode = v_order.pincode)
      )
      and not exists (
        select 1 from public.delivery_assignments prior
        where prior.shipment_id = p_shipment_id
          and prior.staff_user_id = sp.user_id
          and prior.status in ('REJECTED','EXPIRED')
      )
    union all
    select
      'PARTNER'::public.staff_type,
      null::uuid,
      ps.id,
      ps.partner_id,
      ps.user_id,
      (
        app_private.staff_active_workload(ps.user_id) * v_policy.weight_workload
        + coalesce(app_private.haversine_km(
            ps.current_latitude, ps.current_longitude, t.latitude, t.longitude), 25
          ) * v_policy.weight_distance
        + case when v_policy.prefer_own_team then 500 else 0 end
      )::numeric(12,4)
    from public.partner_staff ps
    join public.delivery_partners dp on dp.id = ps.partner_id and dp.status = 'APPROVED'
    join public.profiles p on p.id = ps.user_id
    join public.towns t on t.id = v_order.town_id
    where ps.status = 'ACTIVE'
      and ps.is_available
      and p.status = 'ACTIVE'
      and p.role in ('PARTNER_ADMIN','PARTNER_DELIVERY_STAFF')
      and app_private.staff_active_workload(ps.user_id)
          < least(ps.capacity_per_day, v_policy.max_active_tasks_per_staff)
      and exists (
        select 1 from public.partner_service_areas psa
        where psa.partner_id = ps.partner_id
          and psa.town_id = v_order.town_id
          and (psa.pincode is null or psa.pincode = v_order.pincode)
      )
      and not exists (
        select 1 from public.delivery_assignments prior
        where prior.shipment_id = p_shipment_id
          and prior.staff_user_id = ps.user_id
          and prior.status in ('REJECTED','EXPIRED')
      )
  ) candidates
  order by score asc, user_id
  limit 1;

  if v_candidate.user_id is null then
    return null;
  end if;

  v_expires := now() + make_interval(secs => v_policy.offer_timeout_seconds);
  begin
    insert into public.delivery_assignments (
      shipment_id, staff_user_id, staff_type, staff_profile_id,
      partner_staff_id, partner_id, status, mode, assigned_by, expires_at
    ) values (
      p_shipment_id, v_candidate.user_id, v_candidate.staff_type,
      v_candidate.staff_profile_id, v_candidate.partner_staff_id,
      v_candidate.partner_id, 'PENDING', 'AUTO', null, v_expires
    ) returning id into v_assignment_id;
  exception when unique_violation then
    return null;
  end;

  perform app_private.log_shipment_event(
    p_shipment_id, 'ASSIGNMENT_REASSIGNED', v_shipment.status, v_shipment.status,
    'SYSTEM', null, null, null, null, null,
    jsonb_build_object(
      'assignment_id', v_assignment_id, 'kind', 'delivery',
      'mode', 'AUTO', 'staff_user_id', v_candidate.user_id
    )
  );
  perform app_private.notify_user(
    v_candidate.user_id, 'DELIVERY_ASSIGNED', 'New delivery assigned',
    'Shipment ' || v_shipment.shipment_number || ' for order ' || v_order.order_number
      || ' is available. Accept it to continue.',
    jsonb_build_object(
      'shipment_id', p_shipment_id, 'assignment_id', v_assignment_id,
      'shipment_number', v_shipment.shipment_number, 'order_number', v_order.order_number,
      'cod_amount_paise', v_shipment.expected_cod_paise
    ),
    'delivery-assigned:' || v_assignment_id::text
  );
  perform app_private.notify_owner(
    'DELIVERY_ASSIGNED', 'Delivery ' || v_shipment.shipment_number || ' auto-assigned',
    'An eligible delivery person was assigned. They must accept the task.',
    jsonb_build_object('shipment_id', p_shipment_id, 'assignment_id', v_assignment_id),
    'delivery-auto-owner:' || v_assignment_id::text
  );
  perform app_private.write_audit(
    'DELIVERY_AUTO_ASSIGNED', 'delivery_assignment', v_assignment_id, null,
    jsonb_build_object(
      'shipment_id', p_shipment_id, 'staff_user_id', v_candidate.user_id,
      'score', v_candidate.score
    ),
    'SYSTEM', null
  );
  return v_assignment_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff dashboard / read model
-- ---------------------------------------------------------------------------
create or replace function public.staff_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_staff record;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
  v_name text;
  v_phone text;
  v_partner_name text;
  v_cash bigint;
begin
  select * into v_staff from app_private.require_staff_identity();
  if v_staff.staff_type is null then
    raise exception using errcode = '42501', message = 'Active delivery staff authorization required.';
  end if;

  if v_staff.staff_type = 'OWN' then
    select sp.display_name, sp.phone into v_name, v_phone
    from public.staff_profiles sp where sp.id = v_staff.staff_profile_id;
  else
    select ps.display_name, ps.phone, dp.name into v_name, v_phone, v_partner_name
    from public.partner_staff ps
    join public.delivery_partners dp on dp.id = ps.partner_id
    where ps.id = v_staff.partner_staff_id;
  end if;

  select coalesce(sum(ct.amount_paise), 0) into v_cash
  from public.cod_transactions ct
  where ct.staff_user_id = v_uid
    and ct.entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL');

  return jsonb_build_object(
    'generated_at', now(),
    'staff', jsonb_build_object(
      'user_id', v_uid,
      'display_name', coalesce(v_name, ''),
      'phone', coalesce(v_phone, ''),
      'staff_type', v_staff.staff_type,
      'partner_id', v_staff.partner_id,
      'partner_name', v_partner_name,
      'capacity_per_day', v_staff.capacity_per_day,
      'is_available', v_staff.is_available,
      'active_tasks', app_private.staff_active_workload(v_uid)
    ),
    'active_pickups', (
      select count(*) from public.pickup_assignments
      where staff_user_id = v_uid and status in ('PENDING','ACCEPTED')
    ),
    'active_deliveries', (
      select count(*) from public.delivery_assignments
      where staff_user_id = v_uid and status in ('PENDING','ACCEPTED')
    ),
    'pickups_completed_today', (
      select count(*) from public.pickup_verifications pv
      join public.pickup_assignments pa on pa.id = pv.assignment_id
      where pa.staff_user_id = v_uid and pv.verified_at >= v_day_start
    ),
    'deliveries_completed_today', (
      select count(*) from public.delivery_assignments da
      join public.shipments s on s.id = da.shipment_id
      where da.staff_user_id = v_uid and da.status = 'COMPLETED'
        and s.delivered_at >= v_day_start
    ),
    'cod_collected_today_paise', coalesce((
      select sum(ct.amount_paise) from public.cod_transactions ct
      where ct.staff_user_id = v_uid and ct.entry_type = 'COLLECTED'
        and ct.created_at >= v_day_start
    ), 0),
    'cash_in_custody_paise', v_cash,
    'unread_notifications', (
      select count(*) from public.notifications n
      where n.recipient_id = v_uid and n.read_at is null
    )
  );
end;
$$;

create or replace function public.staff_list_pickup_assignments(
  p_status public.assignment_status default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  perform app_private.require_staff_identity();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'assignment_id', pa.id,
      'pickup_id', pk.id,
      'pickup_number', pk.pickup_number,
      'assignment_status', pa.status,
      'pickup_status', pk.status,
      'mode', pa.mode,
      'assigned_at', pa.assigned_at,
      'responded_at', pa.responded_at,
      'expires_at', pa.expires_at,
      'order_id', o.id,
      'order_number', o.order_number,
      'shipment_id', s.id,
      'shipment_number', s.shipment_number,
      'shipment_status', s.status,
      'package_count_expected', pk.package_count_expected,
      'sealed_packages', (
        select count(*) from public.packages pkg
        where pkg.shipment_id = s.id and pkg.is_sealed
      ),
      'scanned_packages', (
        select count(distinct bs.package_id) from public.barcode_scans bs
        where bs.pickup_request_id = pk.id and bs.result = 'VALID'
      ),
      'pickup_town', o.town_name,
      'pickup_pincode', o.pincode,
      'customer_name', o.recipient_name,
      'otp_expires_at', (
        select c.expires_at from public.pickup_otp_challenges c
        where c.pickup_request_id = pk.id
      ),
      'can_accept', pa.status = 'PENDING' and (pa.expires_at is null or pa.expires_at >= now()),
      'can_scan', pa.status = 'ACCEPTED' and pk.status in ('ACCEPTED','ARRIVED'),
      'can_verify', pa.status = 'ACCEPTED' and pk.status = 'ARRIVED'
    ) order by
      case when pa.status in ('PENDING','ACCEPTED') then 0 else 1 end,
      pa.assigned_at desc)
    from (
      select * from public.pickup_assignments
      where staff_user_id = v_uid
        and (p_status is null or status = p_status)
      order by assigned_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 100)
    ) pa
    join public.pickup_requests pk on pk.id = pa.pickup_request_id
    join public.shipments s on s.id = pk.shipment_id
    join public.orders o on o.id = pk.order_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.staff_get_pickup(p_assignment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_business jsonb := app_private.get_setting('business', '{}'::jsonb);
  v_packages jsonb;
  v_scans jsonb;
  v_scanned integer;
  v_otp_expires timestamptz;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.pickup_assignments where id = p_assignment_id;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id;
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id;
  select * into v_order from public.orders where id = v_pickup.order_id;

  select count(distinct bs.package_id) into v_scanned
  from public.barcode_scans bs
  where bs.pickup_request_id = v_pickup.id and bs.result = 'VALID';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'package_number', p.package_number, 'package_code', p.package_code,
    'status', p.status, 'is_sealed', p.is_sealed, 'weight_grams', p.weight_grams,
    'scanned', exists (
      select 1 from public.barcode_scans bs
      where bs.pickup_request_id = v_pickup.id and bs.package_id = p.id and bs.result = 'VALID'
    )
  ) order by p.package_number), '[]'::jsonb)
  into v_packages
  from public.packages p where p.shipment_id = v_shipment.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'raw_code', bs.raw_code, 'result', bs.result, 'message', bs.message,
    'package_id', bs.package_id, 'scanned_at', bs.scanned_at
  ) order by bs.scanned_at desc), '[]'::jsonb)
  into v_scans
  from (
    select * from public.barcode_scans
    where pickup_request_id = v_pickup.id
    order by scanned_at desc limit 30
  ) bs;

  select c.expires_at into v_otp_expires
  from public.pickup_otp_challenges c where c.pickup_request_id = v_pickup.id;

  return jsonb_build_object(
    'assignment', jsonb_build_object(
      'id', v_assignment.id, 'status', v_assignment.status, 'mode', v_assignment.mode,
      'assigned_at', v_assignment.assigned_at, 'expires_at', v_assignment.expires_at,
      'responded_at', v_assignment.responded_at
    ),
    'pickup', jsonb_build_object(
      'id', v_pickup.id, 'pickup_number', v_pickup.pickup_number,
      'status', v_pickup.status, 'condition', v_pickup.condition,
      'package_count_expected', v_pickup.package_count_expected,
      'package_count_verified', v_pickup.package_count_verified,
      'requested_at', v_pickup.requested_at, 'verified_at', v_pickup.verified_at,
      'otp_expires_at', v_otp_expires, 'scanned_packages', v_scanned
    ),
    'shipment', jsonb_build_object(
      'id', v_shipment.id, 'shipment_number', v_shipment.shipment_number,
      'status', v_shipment.status, 'package_count', v_shipment.package_count,
      'expected_cod_paise', v_shipment.expected_cod_paise
    ),
    'order', jsonb_build_object(
      'id', v_order.id, 'order_number', v_order.order_number, 'status', v_order.status,
      'customer_name', v_order.recipient_name, 'customer_phone', v_order.phone,
      'town_name', v_order.town_name, 'district', v_order.district,
      'state', v_order.state, 'pincode', v_order.pincode,
      'total_paise', v_order.total_paise, 'cod_amount_paise', v_order.cod_amount_paise
    ),
    'seller', jsonb_build_object(
      'name', coalesce(v_business ->> 'display_name', 'IndiaBizz'),
      'legal_name', coalesce(v_business ->> 'legal_name', ''),
      'address', coalesce(v_business ->> 'address', ''),
      'phone', coalesce(v_business ->> 'phone', '')
    ),
    'packages', v_packages,
    'recent_scans', v_scans,
    'can_accept', v_assignment.status = 'PENDING'
      and (v_assignment.expires_at is null or v_assignment.expires_at >= now()),
    'can_scan', v_assignment.status = 'ACCEPTED'
      and v_pickup.status in ('ACCEPTED','ARRIVED'),
    'can_verify', v_assignment.status = 'ACCEPTED' and v_pickup.status = 'ARRIVED',
    'is_verified', v_pickup.status = 'VERIFIED'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Pickup assignment response and physical verification
-- ---------------------------------------------------------------------------
create or replace function public.staff_accept_pickup(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.pickup_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status in ('PENDING','ACCEPTED'), 'This pickup offer is no longer open.');
  if v_assignment.status = 'ACCEPTED' then
    return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'ACCEPTED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(
    v_assignment.expires_at is null or v_assignment.expires_at >= now(),
    'This pickup offer has expired. Ask the owner to reassign it.'
  );

  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  perform app_private.assert_true(v_pickup.id is not null and v_pickup.status in ('ASSIGNED','ACCEPTED'), 'This pickup is no longer available.');
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;

  update public.pickup_assignments
  set status = 'ACCEPTED', responded_at = now()
  where id = v_assignment.id;
  update public.pickup_requests set status = 'ACCEPTED'
  where id = v_pickup.id and status = 'ASSIGNED';
  update public.shipments set status = 'PICKUP_ACCEPTED'
  where id = v_shipment.id and status in ('PICKUP_ASSIGNED','PICKUP_REQUESTED');

  perform app_private.log_shipment_event(
    v_shipment.id, 'PICKUP_ACCEPTED', v_shipment.status, 'PICKUP_ACCEPTED',
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment.id, 'pickup_id', v_pickup.id)
  );
  perform app_private.notify_owner(
    'PICKUP_ACCEPTED', 'Pickup ' || v_pickup.pickup_number || ' accepted',
    'The delivery person accepted the pickup and is on the way.',
    jsonb_build_object('pickup_id', v_pickup.id, 'assignment_id', v_assignment.id),
    'pickup-accepted:' || v_assignment.id::text
  );
  perform app_private.write_audit(
    'PICKUP_ACCEPTED', 'pickup_assignment', v_assignment.id,
    jsonb_build_object('status', 'PENDING'), jsonb_build_object('status', 'ACCEPTED'),
    'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'ACCEPTED', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_reject_pickup(p_assignment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_policy public.assignment_policies%rowtype;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a reason for rejecting the pickup.');
  select * into v_assignment from public.pickup_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'PENDING', 'Only a pending pickup offer can be rejected.');
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;

  update public.pickup_assignments
  set status = 'REJECTED', responded_at = now(), rejection_reason = v_reason
  where id = v_assignment.id;

  if not exists (
    select 1 from public.pickup_assignments
    where pickup_request_id = v_pickup.id and status in ('PENDING','ACCEPTED')
  ) then
    update public.pickup_requests set status = 'REQUESTED' where id = v_pickup.id;
    update public.shipments set status = 'PICKUP_REQUESTED'
    where id = v_shipment.id and status in ('PICKUP_ASSIGNED','PICKUP_ACCEPTED');
  end if;

  perform app_private.log_shipment_event(
    v_shipment.id, 'PICKUP_REJECTED', v_shipment.status, 'PICKUP_REQUESTED',
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment.id, 'reason', v_reason)
  );
  perform app_private.notify_owner(
    'PICKUP_REJECTED', 'Pickup ' || v_pickup.pickup_number || ' declined',
    'The delivery person declined the pickup. Reason: ' || v_reason,
    jsonb_build_object('pickup_id', v_pickup.id, 'assignment_id', v_assignment.id),
    'pickup-rejected:' || v_assignment.id::text
  );
  perform app_private.write_audit(
    'PICKUP_REJECTED', 'pickup_assignment', v_assignment.id,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'REJECTED', 'reason', v_reason),
    'DELIVERY_APP', v_uid
  );

  select * into v_policy from app_private.policy_for_town(
    (select town_id from app_private.pickup_location(v_pickup.order_id))
  );
  if coalesce(v_policy.retry_on_rejection, true) then
    perform app_private.try_auto_assign_pickup(v_pickup.id);
  end if;

  return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'REJECTED', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_arrive_at_pickup(
  p_assignment_id uuid,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.pickup_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the pickup before marking arrival.');
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  perform app_private.assert_true(v_pickup.status in ('ACCEPTED','ARRIVED'), 'This pickup is not ready for arrival.');
  if v_pickup.status = 'ARRIVED' then
    return jsonb_build_object('assignment_id', v_assignment.id, 'pickup_status', 'ARRIVED', 'idempotent_replay', true);
  end if;
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;

  update public.pickup_requests set status = 'ARRIVED' where id = v_pickup.id;
  update public.shipments set status = 'ARRIVED_AT_PICKUP' where id = v_shipment.id;

  perform app_private.log_shipment_event(
    v_shipment.id, 'ARRIVED_AT_PICKUP', v_shipment.status, 'ARRIVED_AT_PICKUP',
    'DELIVERY_APP', v_uid, null, null, p_latitude, p_longitude,
    jsonb_build_object('assignment_id', v_assignment.id, 'pickup_id', v_pickup.id)
  );
  perform app_private.notify_owner(
    'PICKUP_ACCEPTED', 'Delivery person arrived for ' || v_pickup.pickup_number,
    'Verify the packages physically and share the pickup OTP only after the count and condition match.',
    jsonb_build_object('pickup_id', v_pickup.id, 'assignment_id', v_assignment.id),
    'pickup-arrived:' || v_assignment.id::text
  );
  perform app_private.write_audit(
    'PICKUP_ARRIVED', 'pickup_assignment', v_assignment.id, null,
    jsonb_build_object('pickup_id', v_pickup.id), 'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('assignment_id', v_assignment.id, 'pickup_status', 'ARRIVED', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_scan_package(
  p_assignment_id uuid,
  p_raw_code text,
  p_idempotency_key text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_device_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_pkg public.packages%rowtype;
  v_existing public.barcode_scans%rowtype;
  v_code text := btrim(coalesce(p_raw_code, ''));
  v_result public.scan_result;
  v_message text;
  v_scanned integer;
  v_expected integer;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(char_length(coalesce(p_idempotency_key, '')) between 8 and 100, 'A valid scan idempotency key is required.');
  perform app_private.assert_true(v_code <> '' and char_length(v_code) <= 200, 'Scan a valid package barcode.');

  select * into v_existing from public.barcode_scans where idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    perform app_private.assert_true(v_existing.scanned_by = v_uid, 'This scan key is already in use.');
    select count(distinct bs.package_id) into v_scanned
    from public.barcode_scans bs
    where bs.pickup_request_id = v_existing.pickup_request_id and bs.result = 'VALID';
    select package_count_expected into v_expected
    from public.pickup_requests where id = v_existing.pickup_request_id;
    return jsonb_build_object(
      'scan_id', v_existing.id, 'result', v_existing.result, 'message', v_existing.message,
      'package_id', v_existing.package_id, 'scanned_packages', v_scanned,
      'expected_packages', v_expected, 'idempotent_replay', true
    );
  end if;

  select * into v_assignment from public.pickup_assignments where id = p_assignment_id;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  perform app_private.assert_true(
    v_assignment.status = 'ACCEPTED' and v_assignment.expires_at is not null,
    'Accept the pickup before scanning packages.'
  );
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  perform app_private.assert_true(v_pickup.status in ('ACCEPTED','ARRIVED'), 'Packages can only be scanned at an active pickup.');
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id;
  select * into v_order from public.orders where id = v_pickup.order_id;

  select * into v_pkg from public.packages where package_code = v_code;
  if v_pkg.id is null then
    select * into v_pkg from public.packages where package_number = v_code;
  end if;

  if v_pkg.id is null then
    v_result := 'INVALID_CODE';
    v_message := 'This barcode does not belong to any IndiaBizz package.';
  elsif v_shipment.status = 'CANCELLED' or v_order.status = 'CANCELLED' then
    v_result := 'CANCELLED_ORDER';
    v_message := 'This order has been cancelled.';
  elsif v_pkg.shipment_id <> v_pickup.shipment_id then
    v_result := 'WRONG_PACKAGE';
    v_message := 'This package belongs to a different shipment.';
  elsif exists (
    select 1 from public.barcode_scans bs
    where bs.pickup_request_id = v_pickup.id
      and bs.package_id = v_pkg.id
      and bs.result = 'VALID'
  ) then
    v_result := 'DUPLICATE';
    v_message := 'This package was already scanned for this pickup.';
  elsif v_pkg.status not in ('PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED','PICKUP_ACCEPTED') then
    v_result := 'ALREADY_COLLECTED';
    v_message := 'This package has already left the seller.';
  else
    v_result := 'VALID';
    v_message := 'Package verified.';
  end if;

  select count(distinct bs.package_id) into v_scanned
  from public.barcode_scans bs
  where bs.pickup_request_id = v_pickup.id and bs.result = 'VALID';

  insert into public.barcode_scans (
    package_id, shipment_id, pickup_request_id, assignment_id, scanned_by,
    scan_context, raw_code, result, message, latitude, longitude, device_id,
    idempotency_key, metadata
  ) values (
    case when v_result = 'WRONG_PACKAGE' then v_pkg.id else v_pkg.id end,
    v_pickup.shipment_id, v_pickup.id, v_assignment.id, v_uid,
    'PICKUP', left(v_code, 200), v_result, v_message, p_latitude, p_longitude,
    nullif(btrim(coalesce(p_device_id, '')), ''), p_idempotency_key,
    jsonb_build_object('assignment_status', v_assignment.status, 'pickup_status', v_pickup.status)
  );

  if v_result = 'VALID' then
    v_scanned := v_scanned + 1;
  end if;

  perform app_private.write_audit(
    'PACKAGE_SCANNED', 'package', v_pkg.id, null,
    jsonb_build_object('result', v_result, 'pickup_id', v_pickup.id),
    'DELIVERY_APP', v_uid
  );

  -- This function deliberately performs no pickup/shipment status transition.
  -- PICKED_UP is only reachable through staff_verify_pickup().
  return jsonb_build_object(
    'scan_id', (select id from public.barcode_scans where idempotency_key = p_idempotency_key),
    'result', v_result,
    'message', v_message,
    'package_id', v_pkg.id,
    'package_number', v_pkg.package_number,
    'scanned_packages', v_scanned,
    'expected_packages', v_pickup.package_count_expected,
    'is_ready_for_verification', v_scanned >= v_pickup.package_count_expected,
    'idempotent_replay', false
  );
end;
$$;

create or replace function public.staff_verify_pickup(
  p_assignment_id uuid,
  p_otp text,
  p_package_count integer,
  p_condition public.package_condition default 'GOOD',
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_challenge public.pickup_otp_challenges%rowtype;
  v_policy public.assignment_policies%rowtype;
  v_scanned integer;
  v_sealed integer;
  v_physical integer;
  v_total_packages integer;
  v_otp text := btrim(coalesce(p_otp, ''));
  v_attempts_left integer;
  v_verification_id uuid;
  v_delivery_id uuid;
  v_delivery_expires timestamptz;
  v_existing public.pickup_verifications%rowtype;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(v_otp ~ '^[0-9]{6}$', 'Enter the 6-digit pickup OTP.');
  perform app_private.assert_true(coalesce(p_notes, '') = '' or char_length(p_notes) <= 2000, 'Notes are too long.');

  select * into v_assignment from public.pickup_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;
  select * into v_order from public.orders where id = v_pickup.order_id for update;

  if v_pickup.status = 'VERIFIED' then
    return jsonb_build_object(
      'ok', true, 'idempotent_replay', true, 'pickup_id', v_pickup.id,
      'pickup_status', 'VERIFIED', 'shipment_id', v_shipment.id,
      'shipment_status', v_shipment.status
    );
  end if;

  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the pickup before verification.');
  perform app_private.assert_true(v_pickup.status = 'ARRIVED', 'Mark your arrival before verifying the pickup.');
  perform app_private.assert_true(p_condition = 'GOOD', 'A damaged package cannot be accepted. Record a pickup failure instead.');

  select count(distinct bs.package_id) into v_scanned
  from public.barcode_scans bs
  where bs.pickup_request_id = v_pickup.id and bs.result = 'VALID';
  select count(*) filter (where is_sealed), count(*) into v_sealed, v_physical
  from public.packages where shipment_id = v_shipment.id;

  perform app_private.assert_true(
    coalesce(p_package_count, 0) = v_pickup.package_count_expected,
    'The counted package total does not match the pickup request.'
  );
  perform app_private.assert_true(
    v_scanned = v_pickup.package_count_expected,
    'Scan every sealed package before verifying the pickup.'
  );
  perform app_private.assert_true(
    v_sealed = v_physical and v_physical = v_pickup.package_count_expected,
    'All packages must be sealed and match the pickup count.'
  );

  select * into v_challenge from public.pickup_otp_challenges
  where pickup_request_id = v_pickup.id
  for update;
  perform app_private.assert_true(v_challenge.id is not null, 'Pickup OTP has not been issued. Ask the owner to regenerate it.');
  if v_challenge.expires_at < now() then
    return jsonb_build_object('ok', false, 'error_code', 'OTP_EXPIRED', 'message', 'The pickup OTP has expired. Ask the owner to regenerate it.');
  end if;
  if v_challenge.attempts >= v_challenge.max_attempts then
    return jsonb_build_object('ok', false, 'error_code', 'OTP_LOCKED', 'message', 'Too many incorrect OTP attempts. Ask the owner to regenerate the pickup OTP.');
  end if;
  if extensions.crypt(v_otp, v_challenge.otp_hash) <> v_challenge.otp_hash then
    update public.pickup_otp_challenges
    set attempts = attempts + 1
    where id = v_challenge.id;
    v_attempts_left := greatest(v_challenge.max_attempts - v_challenge.attempts - 1, 0);
    return jsonb_build_object(
      'ok', false, 'error_code', 'INVALID_OTP',
      'message', 'Incorrect pickup OTP. ' || v_attempts_left::text || ' attempt(s) left.',
      'attempts_left', v_attempts_left
    );
  end if;

  select * into v_existing from public.pickup_verifications where assignment_id = v_assignment.id;
  if v_existing.id is not null then
    return jsonb_build_object('ok', true, 'idempotent_replay', true, 'pickup_id', v_pickup.id);
  end if;

  insert into public.pickup_verifications (
    pickup_request_id, assignment_id, verified_by, package_count, condition,
    otp_verified, metadata
  ) values (
    v_pickup.id, v_assignment.id, v_uid, p_package_count, 'GOOD', true,
    jsonb_build_object('notes', coalesce(p_notes, ''), 'scanned_packages', v_scanned)
  ) returning id into v_verification_id;

  update public.pickup_requests
  set status = 'VERIFIED', condition = 'GOOD', package_count_verified = p_package_count,
      verified_at = now(), verified_by = v_uid
  where id = v_pickup.id;

  update public.pickup_assignments
  set status = 'COMPLETED', responded_at = coalesce(responded_at, now()), completed_at = now()
  where id = v_assignment.id;

  update public.packages
  set status = 'PICKED_UP'
  where shipment_id = v_shipment.id
    and status in ('PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED','PICKUP_ACCEPTED');

  update public.shipments
  set status = 'PICKED_UP', picked_up_at = now()
  where id = v_shipment.id;

  update public.orders
  set status = 'PICKED_UP'
  where id = v_order.id and status in ('PICKUP_REQUESTED','READY_FOR_PICKUP');

  if v_shipment.expected_cod_paise > 0 then
    insert into public.cod_transactions (
      shipment_id, order_id, customer_id, staff_user_id, partner_id,
      entry_type, amount_paise, description, recorded_by, idempotency_key, metadata
    ) values (
      v_shipment.id, v_order.id, v_order.customer_id, v_uid, v_assignment.partner_id,
      'EXPECTED', v_shipment.expected_cod_paise,
      'COD expected for shipment ' || v_shipment.shipment_number,
      v_uid, 'shipment:' || v_shipment.id::text || ':cod-expected',
      jsonb_build_object('pickup_id', v_pickup.id)
    ) on conflict (idempotency_key) do nothing;
  end if;

  perform app_private.log_shipment_event(
    v_shipment.id, 'PICKED_UP', v_shipment.status, 'PICKED_UP',
    'DELIVERY_APP', v_uid, v_verification_id::text, null, null, null,
    jsonb_build_object(
      'pickup_id', v_pickup.id, 'assignment_id', v_assignment.id,
      'package_count', p_package_count, 'condition', 'GOOD',
      'scanned_packages', v_scanned
    )
  );

  select * into v_policy from app_private.policy_for_town(v_order.town_id);
  if coalesce(v_policy.auto_create_delivery_assignment, true)
     and not exists (
       select 1 from public.delivery_assignments
       where shipment_id = v_shipment.id and status in ('PENDING','ACCEPTED')
     ) then
    v_delivery_expires := now() + make_interval(secs => coalesce(v_policy.offer_timeout_seconds, 300));
    insert into public.delivery_assignments (
      shipment_id, pickup_assignment_id, staff_user_id, staff_type,
      staff_profile_id, partner_staff_id, partner_id, status, mode, expires_at
    ) values (
      v_shipment.id, v_assignment.id, v_uid, v_assignment.staff_type,
      v_assignment.staff_profile_id, v_assignment.partner_staff_id,
      v_assignment.partner_id, 'PENDING', 'AUTO', v_delivery_expires
    ) returning id into v_delivery_id;

    perform app_private.log_shipment_event(
      v_shipment.id, 'ASSIGNMENT_REASSIGNED', 'PICKED_UP', 'PICKED_UP',
      'SYSTEM', null, null, null, null, null,
      jsonb_build_object(
        'assignment_id', v_delivery_id, 'kind', 'delivery',
        'mode', 'AUTO', 'staff_user_id', v_uid, 'from_pickup', true
      )
    );
    perform app_private.notify_user(
      v_uid, 'DELIVERY_ASSIGNED', 'Delivery task ready',
      'Shipment ' || v_shipment.shipment_number || ' is now in your custody. Accept the delivery task when you are ready.',
      jsonb_build_object(
        'shipment_id', v_shipment.id, 'assignment_id', v_delivery_id,
        'order_number', v_order.order_number,
        'cod_amount_paise', v_shipment.expected_cod_paise
      ),
      'delivery-assigned:' || v_delivery_id::text
    );
  end if;

  perform app_private.notify_owner(
    'PICKUP_VERIFIED', 'Pickup ' || v_pickup.pickup_number || ' verified',
    'OTP, package count and condition verified. The shipment is with the delivery person.',
    jsonb_build_object(
      'pickup_id', v_pickup.id, 'shipment_id', v_shipment.id,
      'assignment_id', v_assignment.id, 'delivery_assignment_id', v_delivery_id,
      'package_count', p_package_count
    ),
    'pickup-verified:' || v_pickup.id::text
  );
  perform app_private.notify_user(
    v_order.customer_id, 'PICKUP_VERIFIED', 'Order ' || v_order.order_number || ' picked up',
    'Your order has left the seller and is on its way. You will receive a delivery OTP when it is out for delivery.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id),
    'pickup-verified-customer:' || v_pickup.id::text
  );
  perform app_private.write_audit(
    'PICKUP_VERIFIED', 'pickup_request', v_pickup.id,
    jsonb_build_object('status', 'ARRIVED'),
    jsonb_build_object(
      'status', 'VERIFIED', 'verification_id', v_verification_id,
      'package_count', p_package_count, 'delivery_assignment_id', v_delivery_id
    ),
    'DELIVERY_APP', v_uid
  );

  return jsonb_build_object(
    'ok', true,
    'idempotent_replay', false,
    'pickup_id', v_pickup.id,
    'pickup_status', 'VERIFIED',
    'verification_id', v_verification_id,
    'shipment_id', v_shipment.id,
    'shipment_status', 'PICKED_UP',
    'delivery_assignment_id', v_delivery_id,
    'package_count', p_package_count
  );
end;
$$;

create or replace function public.staff_fail_pickup(
  p_assignment_id uuid,
  p_reason text,
  p_package_damaged boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.pickup_assignments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a reason for the pickup failure.');
  select * into v_assignment from public.pickup_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Pickup assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Only an accepted pickup can fail.');
  select * into v_pickup from public.pickup_requests where id = v_assignment.pickup_request_id for update;
  perform app_private.assert_true(v_pickup.status in ('ACCEPTED','ARRIVED'), 'This pickup is no longer active.');
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;

  update public.pickup_assignments
  set status = 'COMPLETED', responded_at = coalesce(responded_at, now()),
      completed_at = now(), rejection_reason = v_reason
  where id = v_assignment.id;
  update public.pickup_requests
  set status = 'FAILED', failure_reason = v_reason,
      condition = case when p_package_damaged then 'DAMAGED'::public.package_condition else 'PENDING'::public.package_condition end
  where id = v_pickup.id;
  update public.pickup_otp_challenges set expires_at = now() where pickup_request_id = v_pickup.id;
  update public.shipments set status = case when p_package_damaged then 'PACKAGE_DAMAGED'::public.shipment_status else 'PICKUP_FAILED'::public.shipment_status end
  where id = v_shipment.id;
  update public.packages set status = 'READY_FOR_PICKUP'
  where shipment_id = v_shipment.id and status not in ('PICKED_UP','DELIVERED','RETURNED','CANCELLED');
  update public.orders set status = 'READY_FOR_PICKUP' where id = v_pickup.order_id;

  perform app_private.log_shipment_event(
    v_shipment.id,
    case when p_package_damaged then 'PACKAGE_DAMAGED'::public.shipment_event_type else 'PICKUP_FAILED'::public.shipment_event_type end,
    v_shipment.status,
    case when p_package_damaged then 'PACKAGE_DAMAGED'::public.shipment_status else 'PICKUP_FAILED'::public.shipment_status end,
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object('pickup_id', v_pickup.id, 'assignment_id', v_assignment.id, 'reason', v_reason)
  );
  perform app_private.notify_owner(
    'PICKUP_FAILED', 'Pickup ' || v_pickup.pickup_number || ' failed',
    'The pickup could not be completed. Reason: ' || v_reason,
    jsonb_build_object('pickup_id', v_pickup.id, 'shipment_id', v_shipment.id, 'damaged', p_package_damaged),
    'pickup-failed:' || v_pickup.id::text
  );
  perform app_private.write_audit(
    'PICKUP_FAILED', 'pickup_request', v_pickup.id,
    jsonb_build_object('status', v_pickup.status),
    jsonb_build_object('status', 'FAILED', 'reason', v_reason, 'damaged', p_package_damaged),
    'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('pickup_id', v_pickup.id, 'pickup_status', 'FAILED', 'shipment_status', case when p_package_damaged then 'PACKAGE_DAMAGED' else 'PICKUP_FAILED' end);
end;
$$;

-- ---------------------------------------------------------------------------
-- Delivery assignment read model
-- ---------------------------------------------------------------------------
create or replace function public.staff_list_delivery_assignments(
  p_status public.assignment_status default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_max_attempts integer := app_private.get_int_setting('logistics.max_delivery_attempts', 3)::integer;
begin
  perform app_private.require_staff_identity();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'assignment_id', da.id,
      'shipment_id', s.id,
      'shipment_number', s.shipment_number,
      'assignment_status', da.status,
      'shipment_status', s.status,
      'mode', da.mode,
      'assigned_at', da.assigned_at,
      'responded_at', da.responded_at,
      'expires_at', da.expires_at,
      'order_id', o.id,
      'order_number', o.order_number,
      'customer_name', o.recipient_name,
      'customer_phone', o.phone,
      'line1', o.line1,
      'line2', o.line2,
      'landmark', o.landmark,
      'town_name', o.town_name,
      'district', o.district,
      'state', o.state,
      'pincode', o.pincode,
      'package_count', s.package_count,
      'total_paise', o.total_paise,
      'cod_amount_paise', s.expected_cod_paise,
      'attempts', (
        select count(*) from public.delivery_attempts a where a.shipment_id = s.id
      ),
      'max_attempts', v_max_attempts,
      'otp_expires_at', (
        select c.expires_at from public.delivery_otp_challenges c
        where c.shipment_id = s.id
      ),
      'can_accept', da.status = 'PENDING' and (da.expires_at is null or da.expires_at >= now()),
      'can_start', da.status = 'ACCEPTED' and s.status = 'ARRIVED_AT_DESTINATION',
      'can_deliver', da.status = 'ACCEPTED' and s.status = 'OUT_FOR_DELIVERY'
    ) order by
      case when da.status in ('PENDING','ACCEPTED') then 0 else 1 end,
      da.assigned_at desc)
    from (
      select * from public.delivery_assignments
      where staff_user_id = v_uid
        and (p_status is null or status = p_status)
      order by assigned_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 100)
    ) da
    join public.shipments s on s.id = da.shipment_id
    join public.orders o on o.id = s.order_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.staff_get_delivery(p_assignment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_items jsonb;
  v_packages jsonb;
  v_attempts jsonb;
  v_events jsonb;
  v_otp_expires timestamptz;
  v_require_photo boolean := app_private.get_bool_setting('logistics.require_photo', false);
  v_max_attempts integer := app_private.get_int_setting('logistics.max_delivery_attempts', 3)::integer;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id;
  select * into v_order from public.orders where id = v_shipment.order_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'product_name', oi.product_name, 'sku', oi.sku, 'quantity', oi.quantity,
    'line_total_paise', oi.line_total_paise
  ) order by oi.created_at), '[]'::jsonb)
  into v_items
  from public.order_items oi where oi.order_id = v_order.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'package_number', p.package_number, 'package_code', p.package_code,
    'status', p.status, 'is_sealed', p.is_sealed, 'weight_grams', p.weight_grams
  ) order by p.package_number), '[]'::jsonb)
  into v_packages
  from public.packages p where p.shipment_id = v_shipment.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'attempt_number', a.attempt_number, 'reason', a.reason, 'notes', a.notes,
    'attempted_at', a.attempted_at, 'next_retry_at', a.next_retry_at
  ) order by a.attempt_number desc), '[]'::jsonb)
  into v_attempts
  from public.delivery_attempts a where a.shipment_id = v_shipment.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'event_type', e.event_type, 'new_status', e.new_status,
    'created_at', e.created_at, 'location_text', e.location_text
  ) order by e.created_at desc), '[]'::jsonb)
  into v_events
  from (
    select * from public.shipment_events
    where shipment_id = v_shipment.id
    order by created_at desc limit 20
  ) e;

  select c.expires_at into v_otp_expires
  from public.delivery_otp_challenges c where c.shipment_id = v_shipment.id;

  return jsonb_build_object(
    'assignment', jsonb_build_object(
      'id', v_assignment.id, 'status', v_assignment.status, 'mode', v_assignment.mode,
      'assigned_at', v_assignment.assigned_at, 'responded_at', v_assignment.responded_at,
      'expires_at', v_assignment.expires_at
    ),
    'shipment', jsonb_build_object(
      'id', v_shipment.id, 'shipment_number', v_shipment.shipment_number,
      'status', v_shipment.status, 'package_count', v_shipment.package_count,
      'weight_grams', v_shipment.weight_grams,
      'expected_cod_paise', v_shipment.expected_cod_paise,
      'picked_up_at', v_shipment.picked_up_at, 'delivered_at', v_shipment.delivered_at
    ),
    'order', jsonb_build_object(
      'id', v_order.id, 'order_number', v_order.order_number, 'status', v_order.status,
      'payment_status', v_order.payment_status,
      'recipient_name', v_order.recipient_name, 'phone', v_order.phone,
      'line1', v_order.line1, 'line2', v_order.line2, 'landmark', v_order.landmark,
      'town_name', v_order.town_name, 'district', v_order.district,
      'state', v_order.state, 'pincode', v_order.pincode,
      'total_paise', v_order.total_paise, 'cod_amount_paise', v_order.cod_amount_paise,
      'customer_note', v_order.customer_note
    ),
    'items', v_items,
    'packages', v_packages,
    'attempts', v_attempts,
    'events', v_events,
    'otp_expires_at', v_otp_expires,
    'max_attempts', v_max_attempts,
    'require_photo', v_require_photo,
    'can_accept', v_assignment.status = 'PENDING'
      and (v_assignment.expires_at is null or v_assignment.expires_at >= now()),
    'can_start', v_assignment.status = 'ACCEPTED' and v_shipment.status = 'ARRIVED_AT_DESTINATION',
    'can_deliver', v_assignment.status = 'ACCEPTED' and v_shipment.status = 'OUT_FOR_DELIVERY'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Delivery assignment response and delivery lifecycle
-- ---------------------------------------------------------------------------
create or replace function public.staff_accept_delivery(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status in ('PENDING','ACCEPTED'), 'This delivery offer is no longer open.');
  if v_assignment.status = 'ACCEPTED' then
    return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'ACCEPTED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(
    v_assignment.expires_at is null or v_assignment.expires_at >= now(),
    'This delivery offer has expired. Ask the owner to reassign it.'
  );
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  perform app_private.assert_true(
    v_shipment.status in ('PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','DELIVERY_ATTEMPTED','CUSTOMER_UNAVAILABLE','SHIPMENT_DELAYED'),
    'This shipment cannot be delivered in its current status.'
  );

  update public.delivery_assignments
  set status = 'ACCEPTED', responded_at = now()
  where id = v_assignment.id;

  perform app_private.notify_owner(
    'DELIVERY_ACCEPTED', 'Delivery ' || v_shipment.shipment_number || ' accepted',
    'The delivery person accepted the delivery task.',
    jsonb_build_object('shipment_id', v_shipment.id, 'assignment_id', v_assignment.id),
    'delivery-accepted:' || v_assignment.id::text
  );
  perform app_private.write_audit(
    'DELIVERY_ACCEPTED', 'delivery_assignment', v_assignment.id,
    jsonb_build_object('status', 'PENDING'), jsonb_build_object('status', 'ACCEPTED'),
    'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'ACCEPTED', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_reject_delivery(p_assignment_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
  v_policy public.assignment_policies%rowtype;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a reason for rejecting the delivery.');
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'PENDING', 'Only a pending delivery offer can be rejected.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  select * into v_order from public.orders where id = v_shipment.order_id;

  update public.delivery_assignments
  set status = 'REJECTED', responded_at = now(), rejection_reason = v_reason
  where id = v_assignment.id;

  perform app_private.log_shipment_event(
    v_shipment.id, 'ASSIGNMENT_REASSIGNED', v_shipment.status, v_shipment.status,
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment.id, 'kind', 'delivery', 'reason', v_reason, 'rejected', true)
  );
  perform app_private.notify_owner(
    'DELIVERY_REJECTED', 'Delivery ' || v_shipment.shipment_number || ' declined',
    'The delivery person declined the task. Reason: ' || v_reason,
    jsonb_build_object('shipment_id', v_shipment.id, 'assignment_id', v_assignment.id),
    'delivery-rejected:' || v_assignment.id::text
  );
  perform app_private.write_audit(
    'DELIVERY_REJECTED', 'delivery_assignment', v_assignment.id,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', 'REJECTED', 'reason', v_reason),
    'DELIVERY_APP', v_uid
  );

  select * into v_policy from app_private.policy_for_town(v_order.town_id);
  if coalesce(v_policy.retry_on_rejection, true) then
    perform app_private.try_auto_assign_delivery(v_shipment.id);
  end if;

  return jsonb_build_object('assignment_id', v_assignment.id, 'status', 'REJECTED', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_mark_in_transit(
  p_assignment_id uuid,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the delivery before starting transit.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  perform app_private.assert_true(
    v_shipment.status in ('PICKED_UP','DELIVERY_ATTEMPTED','CUSTOMER_UNAVAILABLE','SHIPMENT_DELAYED'),
    'This shipment cannot start transit in its current status.'
  );

  update public.shipments set status = 'IN_TRANSIT' where id = v_shipment.id;
  update public.orders set status = 'IN_TRANSIT' where id = v_shipment.order_id;
  update public.packages set status = 'IN_TRANSIT'
  where shipment_id = v_shipment.id
    and status in ('PICKED_UP','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED','PICKUP_ACCEPTED','DELIVERY_FAILED');

  perform app_private.log_shipment_event(
    v_shipment.id, 'IN_TRANSIT', v_shipment.status, 'IN_TRANSIT',
    'DELIVERY_APP', v_uid, null, null, p_latitude, p_longitude,
    jsonb_build_object('assignment_id', v_assignment.id)
  );
  perform app_private.write_audit(
    'SHIPMENT_IN_TRANSIT', 'shipment', v_shipment.id, null,
    jsonb_build_object('status', 'IN_TRANSIT'), 'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('assignment_id', v_assignment.id, 'shipment_status', 'IN_TRANSIT', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_mark_arrived_at_destination(
  p_assignment_id uuid,
  p_latitude double precision default null,
  p_longitude double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the delivery before marking arrival.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  perform app_private.assert_true(v_shipment.status in ('IN_TRANSIT','ARRIVED_AT_DESTINATION'), 'Start transit before marking arrival.');
  if v_shipment.status = 'ARRIVED_AT_DESTINATION' then
    return jsonb_build_object('assignment_id', v_assignment.id, 'shipment_status', 'ARRIVED_AT_DESTINATION', 'idempotent_replay', true);
  end if;

  update public.shipments set status = 'ARRIVED_AT_DESTINATION' where id = v_shipment.id;
  update public.orders set status = 'ARRIVED_AT_DESTINATION' where id = v_shipment.order_id;

  perform app_private.log_shipment_event(
    v_shipment.id, 'ARRIVED_AT_DESTINATION', v_shipment.status, 'ARRIVED_AT_DESTINATION',
    'DELIVERY_APP', v_uid, null, null, p_latitude, p_longitude,
    jsonb_build_object('assignment_id', v_assignment.id)
  );
  perform app_private.write_audit(
    'SHIPMENT_ARRIVED_AT_DESTINATION', 'shipment', v_shipment.id, null,
    jsonb_build_object('status', 'ARRIVED_AT_DESTINATION'), 'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('assignment_id', v_assignment.id, 'shipment_status', 'ARRIVED_AT_DESTINATION', 'idempotent_replay', false);
end;
$$;

create or replace function public.staff_start_out_for_delivery(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_otp text;
  v_expires timestamptz := now() + interval '30 minutes';
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the delivery before starting it.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  select * into v_order from public.orders where id = v_shipment.order_id;
  perform app_private.assert_true(
    v_shipment.status in ('ARRIVED_AT_DESTINATION','IN_TRANSIT'),
    'Mark arrival at the destination before starting the delivery.'
  );

  v_otp := app_private.generate_otp_code();
  insert into public.delivery_otp_challenges (shipment_id, otp_hash, expires_at, attempts, last_sent_at)
  values (v_shipment.id, extensions.crypt(v_otp, extensions.gen_salt('bf', 8)), v_expires, 0, now())
  on conflict (shipment_id) do update
    set otp_hash = excluded.otp_hash,
        expires_at = excluded.expires_at,
        attempts = 0,
        last_sent_at = now();

  update public.shipments set status = 'OUT_FOR_DELIVERY' where id = v_shipment.id;
  update public.orders set status = 'OUT_FOR_DELIVERY' where id = v_order.id;
  update public.packages set status = 'OUT_FOR_DELIVERY'
  where shipment_id = v_shipment.id and status in ('PICKED_UP','IN_TRANSIT','DELIVERY_FAILED');

  perform app_private.log_shipment_event(
    v_shipment.id, 'OUT_FOR_DELIVERY', v_shipment.status, 'OUT_FOR_DELIVERY',
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment.id)
  );
  perform app_private.notify_user(
    v_order.customer_id, 'DELIVERY_OTP', 'Delivery OTP for order ' || v_order.order_number,
    'Delivery OTP: ' || v_otp || ' (valid for 30 minutes). Share it with the delivery person only after you receive your order.',
    jsonb_build_object(
      'order_id', v_order.id, 'shipment_id', v_shipment.id, 'otp', v_otp
    ),
    null
  );
  perform app_private.notify_user(
    v_order.customer_id, 'OUT_FOR_DELIVERY', 'Order ' || v_order.order_number || ' is out for delivery',
    'Your order is on the way. Keep ₹' || to_char(v_shipment.expected_cod_paise / 100.0, 'FM999999990.00') || ' ready for cash on delivery.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id),
    'out-for-delivery:' || v_shipment.id::text
  );
  perform app_private.notify_owner(
    'OUT_FOR_DELIVERY', 'Delivery ' || v_shipment.shipment_number || ' started',
    'The delivery person is out for delivery. The customer has received a delivery OTP.',
    jsonb_build_object('shipment_id', v_shipment.id, 'assignment_id', v_assignment.id),
    'out-for-delivery-owner:' || v_shipment.id::text
  );
  perform app_private.write_audit(
    'OUT_FOR_DELIVERY', 'shipment', v_shipment.id,
    jsonb_build_object('status', v_shipment.status),
    jsonb_build_object('status', 'OUT_FOR_DELIVERY'), 'DELIVERY_APP', v_uid
  );

  -- The OTP is intentionally never returned to the delivery app.
  return jsonb_build_object(
    'assignment_id', v_assignment.id, 'shipment_status', 'OUT_FOR_DELIVERY',
    'otp_expires_at', v_expires, 'idempotent_replay', false
  );
end;
$$;

create or replace function public.staff_resend_delivery_otp(p_assignment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_challenge public.delivery_otp_challenges%rowtype;
  v_otp text;
  v_expires timestamptz := now() + interval '30 minutes';
begin
  perform app_private.require_staff_identity();
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the delivery before requesting an OTP.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  perform app_private.assert_true(v_shipment.status = 'OUT_FOR_DELIVERY', 'The shipment is not out for delivery.');
  select * into v_order from public.orders where id = v_shipment.order_id;

  select * into v_challenge from public.delivery_otp_challenges
  where shipment_id = v_shipment.id for update;
  perform app_private.assert_true(v_challenge.id is not null, 'No delivery OTP has been issued yet.');
  perform app_private.assert_true(
    v_challenge.last_sent_at <= now() - interval '60 seconds',
    'Please wait at least 60 seconds before requesting another OTP.'
  );

  v_otp := app_private.generate_otp_code();
  update public.delivery_otp_challenges
  set otp_hash = extensions.crypt(v_otp, extensions.gen_salt('bf', 8)),
      expires_at = v_expires, attempts = 0, last_sent_at = now()
  where id = v_challenge.id;

  perform app_private.notify_user(
    v_order.customer_id, 'DELIVERY_OTP', 'New delivery OTP for order ' || v_order.order_number,
    'Delivery OTP: ' || v_otp || ' (valid for 30 minutes). Share it only after receiving your order.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id, 'otp', v_otp),
    null
  );
  perform app_private.write_audit(
    'DELIVERY_OTP_REGENERATED', 'delivery_otp', v_challenge.id, null,
    jsonb_build_object('assignment_id', v_assignment.id), 'DELIVERY_APP', v_uid
  );
  return jsonb_build_object(
    'assignment_id', v_assignment.id, 'otp_expires_at', v_expires,
    'message', 'A new OTP was sent to the customer.', 'idempotent_replay', false
  );
end;
$$;

create or replace function public.staff_complete_delivery(
  p_assignment_id uuid,
  p_otp text,
  p_recipient_name text default null,
  p_note text default null,
  p_photo_path text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_cod_collected_paise bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_challenge public.delivery_otp_challenges%rowtype;
  v_otp text := btrim(coalesce(p_otp, ''));
  v_attempts_left integer;
  v_require_photo boolean := app_private.get_bool_setting('logistics.require_photo', false);
  v_recipient text := nullif(btrim(coalesce(p_recipient_name, '')), '');
  v_note text := trim(coalesce(p_note, ''));
  v_photo text := nullif(btrim(coalesce(p_photo_path, '')), '');
  v_cod bigint := 0;
  v_payment public.payment_status;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(v_otp ~ '^[0-9]{6}$', 'Enter the 6-digit delivery OTP.');
  perform app_private.assert_true(char_length(v_note) <= 2000, 'Delivery note is too long.');

  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  select * into v_order from public.orders where id = v_shipment.order_id for update;

  if v_shipment.status = 'DELIVERED' then
    return jsonb_build_object(
      'ok', true, 'idempotent_replay', true, 'shipment_id', v_shipment.id,
      'shipment_status', 'DELIVERED', 'delivered_at', v_shipment.delivered_at
    );
  end if;

  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Accept the delivery before completing it.');
  perform app_private.assert_true(v_shipment.status = 'OUT_FOR_DELIVERY', 'Start the delivery before completing it.');

  v_cod := v_shipment.expected_cod_paise;
  perform app_private.assert_true(
    (v_cod > 0 and coalesce(p_cod_collected_paise, -1) = v_cod)
    or (v_cod = 0 and coalesce(p_cod_collected_paise, 0) = 0),
    'Confirm the exact COD amount collected from the customer.'
  );
  if v_require_photo then
    perform app_private.assert_true(v_photo is not null, 'A delivery photo is required.');
  end if;
  if v_photo is not null then
    perform app_private.assert_true(
      v_photo like v_shipment.id::text || '/%',
      'The delivery photo path must be inside this shipment folder.'
    );
  end if;

  select * into v_challenge from public.delivery_otp_challenges
  where shipment_id = v_shipment.id for update;
  perform app_private.assert_true(v_challenge.id is not null, 'No delivery OTP has been issued. Ask the customer to refresh the OTP.');
  if v_challenge.expires_at < now() then
    return jsonb_build_object('ok', false, 'error_code', 'OTP_EXPIRED', 'message', 'The delivery OTP has expired. Send a fresh OTP to the customer.');
  end if;
  if v_challenge.attempts >= v_challenge.max_attempts then
    return jsonb_build_object('ok', false, 'error_code', 'OTP_LOCKED', 'message', 'Too many incorrect OTP attempts. Send a fresh OTP to the customer.');
  end if;
  if extensions.crypt(v_otp, v_challenge.otp_hash) <> v_challenge.otp_hash then
    update public.delivery_otp_challenges set attempts = attempts + 1 where id = v_challenge.id;
    v_attempts_left := greatest(v_challenge.max_attempts - v_challenge.attempts - 1, 0);
    return jsonb_build_object(
      'ok', false, 'error_code', 'INVALID_OTP',
      'message', 'Incorrect delivery OTP. ' || v_attempts_left::text || ' attempt(s) left.',
      'attempts_left', v_attempts_left
    );
  end if;

  insert into public.delivery_proofs (
    shipment_id, package_id, proof_type, storage_path, otp_verified,
    recipient_name, note, captured_by, latitude, longitude, metadata
  ) values (
    v_shipment.id, null, 'DELIVERY_OTP', v_photo, true,
    coalesce(v_recipient, v_order.recipient_name), v_note, v_uid, p_latitude, p_longitude,
    jsonb_build_object('cod_amount_paise', v_cod, 'assignment_id', v_assignment.id)
  );

  update public.delivery_assignments
  set status = 'COMPLETED', responded_at = coalesce(responded_at, now()), completed_at = now()
  where id = v_assignment.id;

  v_payment := case when v_cod > 0 then 'COLLECTED'::public.payment_status else 'SETTLED'::public.payment_status end;

  update public.shipments
  set status = 'DELIVERED', delivered_at = now()
  where id = v_shipment.id;
  update public.orders
  set status = 'DELIVERED', payment_status = v_payment, delivered_at = now()
  where id = v_order.id;
  update public.packages
  set status = 'DELIVERED'
  where shipment_id = v_shipment.id and status not in ('RETURNED','CANCELLED');

  if v_cod > 0 then
    insert into public.cod_transactions (
      shipment_id, order_id, customer_id, staff_user_id, partner_id,
      entry_type, amount_paise, description, recorded_by, idempotency_key, metadata
    ) values (
      v_shipment.id, v_order.id, v_order.customer_id, v_uid, v_assignment.partner_id,
      'COLLECTED', v_cod, 'COD collected at delivery', v_uid,
      'shipment:' || v_shipment.id::text || ':cod-collected',
      jsonb_build_object('assignment_id', v_assignment.id, 'proof', 'DELIVERY_OTP')
    ) on conflict (idempotency_key) do nothing;
  end if;

  perform app_private.log_shipment_event(
    v_shipment.id, 'DELIVERED', v_shipment.status, 'DELIVERED',
    'DELIVERY_APP', v_uid, v_photo, null, p_latitude, p_longitude,
    jsonb_build_object(
      'assignment_id', v_assignment.id, 'otp_verified', true,
      'recipient_name', coalesce(v_recipient, v_order.recipient_name),
      'cod_amount_paise', v_cod
    )
  );
  if v_cod > 0 then
    perform app_private.log_shipment_event(
      v_shipment.id, 'COD_COLLECTED', 'DELIVERED', 'DELIVERED',
      'DELIVERY_APP', v_uid, null, null, p_latitude, p_longitude,
      jsonb_build_object('assignment_id', v_assignment.id, 'amount_paise', v_cod)
    );
  end if;

  perform app_private.notify_user(
    v_order.customer_id, 'DELIVERED', 'Order ' || v_order.order_number || ' delivered',
    case when v_cod > 0
      then 'Delivered. COD collected: ₹' || to_char(v_cod / 100.0, 'FM999999990.00') || '. Thank you for shopping with IndiaBizz.'
      else 'Delivered. Thank you for shopping with IndiaBizz.' end,
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id, 'cod_amount_paise', v_cod),
    'delivered:' || v_shipment.id::text
  );
  perform app_private.notify_owner(
    'DELIVERED', 'Order ' || v_order.order_number || ' delivered',
    'Delivery verified by customer OTP.' ||
      case when v_cod > 0 then ' COD collected: ₹' || to_char(v_cod / 100.0, 'FM999999990.00') || '.' else '' end,
    jsonb_build_object(
      'order_id', v_order.id, 'shipment_id', v_shipment.id,
      'assignment_id', v_assignment.id, 'cod_amount_paise', v_cod
    ),
    'delivered-owner:' || v_shipment.id::text
  );
  perform app_private.write_audit(
    'DELIVERY_COMPLETED', 'shipment', v_shipment.id,
    jsonb_build_object('status', 'OUT_FOR_DELIVERY'),
    jsonb_build_object(
      'status', 'DELIVERED', 'otp_verified', true,
      'cod_amount_paise', v_cod, 'photo_path', v_photo
    ),
    'DELIVERY_APP', v_uid
  );

  return jsonb_build_object(
    'ok', true, 'idempotent_replay', false,
    'shipment_id', v_shipment.id, 'shipment_status', 'DELIVERED',
    'order_id', v_order.id, 'order_status', 'DELIVERED',
    'payment_status', v_payment, 'cod_collected_paise', v_cod
  );
end;
$$;

create or replace function public.staff_fail_delivery(
  p_assignment_id uuid,
  p_reason public.delivery_failure_reason,
  p_notes text default null,
  p_next_retry_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_assignment public.delivery_assignments%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_attempt integer;
  v_max integer := app_private.get_int_setting('logistics.max_delivery_attempts', 3)::integer;
  v_notes text := trim(coalesce(p_notes, ''));
  v_new_shipment_status public.shipment_status;
  v_event public.shipment_event_type;
  v_final boolean;
begin
  perform app_private.require_staff_identity();
  perform app_private.assert_true(char_length(v_notes) <= 2000, 'Notes are too long.');
  select * into v_assignment from public.delivery_assignments where id = p_assignment_id for update;
  perform app_private.assert_true(
    v_assignment.id is not null and v_assignment.staff_user_id = v_uid,
    'Delivery assignment not found.'
  );
  perform app_private.assert_true(v_assignment.status = 'ACCEPTED', 'Only an accepted delivery can be marked failed.');
  select * into v_shipment from public.shipments where id = v_assignment.shipment_id for update;
  select * into v_order from public.orders where id = v_shipment.order_id for update;
  perform app_private.assert_true(
    v_shipment.status in ('OUT_FOR_DELIVERY','IN_TRANSIT','ARRIVED_AT_DESTINATION'),
    'This delivery is not active.'
  );

  select count(*) + 1 into v_attempt from public.delivery_attempts where shipment_id = v_shipment.id;
  v_final := v_attempt >= v_max;

  insert into public.delivery_attempts (
    shipment_id, assignment_id, attempt_number, reason, notes, attempted_by, next_retry_at
  ) values (
    v_shipment.id, v_assignment.id, v_attempt, p_reason, v_notes, v_uid, p_next_retry_at
  );

  v_new_shipment_status := case p_reason
    when 'CUSTOMER_UNAVAILABLE' then 'CUSTOMER_UNAVAILABLE'::public.shipment_status
    when 'CUSTOMER_REFUSED' then 'DELIVERY_REJECTED'::public.shipment_status
    when 'PACKAGE_DAMAGED' then 'PACKAGE_DAMAGED'::public.shipment_status
    else 'DELIVERY_ATTEMPTED'::public.shipment_status
  end;
  v_event := case p_reason
    when 'CUSTOMER_UNAVAILABLE' then 'CUSTOMER_UNAVAILABLE'::public.shipment_event_type
    when 'CUSTOMER_REFUSED' then 'DELIVERY_REJECTED'::public.shipment_event_type
    when 'PACKAGE_DAMAGED' then 'PACKAGE_DAMAGED'::public.shipment_event_type
    else 'DELIVERY_ATTEMPTED'::public.shipment_event_type
  end;

  update public.delivery_assignments
  set status = 'COMPLETED', responded_at = coalesce(responded_at, now()),
      completed_at = now(), rejection_reason = v_notes
  where id = v_assignment.id;
  update public.shipments set status = v_new_shipment_status where id = v_shipment.id;
  update public.orders set status = 'DELIVERY_FAILED' where id = v_order.id;
  update public.packages set status = 'DELIVERY_FAILED'
  where shipment_id = v_shipment.id and status not in ('DELIVERED','RETURNED','CANCELLED');
  update public.delivery_otp_challenges set expires_at = now() where shipment_id = v_shipment.id;

  perform app_private.log_shipment_event(
    v_shipment.id, v_event, v_shipment.status, v_new_shipment_status,
    'DELIVERY_APP', v_uid, null, null, null, null,
    jsonb_build_object(
      'assignment_id', v_assignment.id, 'attempt', v_attempt,
      'reason', p_reason, 'notes', v_notes, 'final_attempt', v_final
    )
  );
  perform app_private.notify_user(
    v_order.customer_id, 'DELIVERY_FAILED',
    'Delivery attempt for order ' || v_order.order_number,
    'We could not complete this delivery attempt. The seller will contact you to arrange another attempt.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id, 'reason', p_reason),
    'delivery-failed:' || v_shipment.id::text || ':' || v_attempt::text
  );
  perform app_private.notify_owner(
    'DELIVERY_FAILED', 'Delivery attempt ' || v_attempt || ' failed',
    'Shipment ' || v_shipment.shipment_number || ': ' || p_reason ||
      case when v_final then '. Maximum attempts reached; manual resolution is required.' else '.' end,
    jsonb_build_object(
      'shipment_id', v_shipment.id, 'assignment_id', v_assignment.id,
      'attempt', v_attempt, 'max_attempts', v_max, 'final', v_final, 'reason', p_reason
    ),
    'delivery-failed-owner:' || v_shipment.id::text || ':' || v_attempt::text
  );
  perform app_private.write_audit(
    'DELIVERY_ATTEMPT_FAILED', 'shipment', v_shipment.id,
    jsonb_build_object('status', v_shipment.status),
    jsonb_build_object(
      'status', v_new_shipment_status, 'attempt', v_attempt,
      'reason', p_reason, 'final', v_final
    ),
    'DELIVERY_APP', v_uid
  );

  return jsonb_build_object(
    'shipment_id', v_shipment.id, 'attempt', v_attempt,
    'max_attempts', v_max, 'final_attempt', v_final,
    'shipment_status', v_new_shipment_status, 'requires_reassignment', true
  );
end;
$$;

create or replace function public.staff_update_location(
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_staff record;
begin
  select * into v_staff from app_private.require_staff_identity();
  perform app_private.assert_true(
    p_latitude between -90 and 90 and p_longitude between -180 and 180,
    'Invalid location coordinates.'
  );
  if v_staff.staff_type = 'OWN' then
    update public.staff_profiles
    set current_latitude = p_latitude, current_longitude = p_longitude,
        last_location_at = now()
    where id = v_staff.staff_profile_id;
  else
    update public.partner_staff
    set current_latitude = p_latitude, current_longitude = p_longitude,
        last_location_at = now()
    where id = v_staff.partner_staff_id;
  end if;
  return jsonb_build_object('updated', true, 'recorded_at', now());
end;
$$;

create or replace function public.staff_set_availability(p_is_available boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_staff record;
  v_available boolean := coalesce(p_is_available, false);
begin
  select * into v_staff from app_private.require_staff_identity();
  if v_staff.staff_type = 'OWN' then
    update public.staff_profiles set is_available = v_available where id = v_staff.staff_profile_id;
  else
    update public.partner_staff set is_available = v_available where id = v_staff.partner_staff_id;
  end if;
  perform app_private.write_audit(
    'STAFF_AVAILABILITY_CHANGED', 'staff', v_uid, null,
    jsonb_build_object('is_available', v_available), 'DELIVERY_APP', v_uid
  );
  return jsonb_build_object('is_available', v_available);
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff COD custody and handover
-- ---------------------------------------------------------------------------
create or replace function app_private.staff_cash_items(p_staff_user_id uuid)
returns table (
  shipment_id uuid,
  order_id uuid,
  customer_id uuid,
  partner_id uuid,
  shipment_number text,
  order_number text,
  expected_paise bigint,
  collected_paise bigint,
  net_paise bigint,
  first_collected_at timestamptz,
  last_collected_at timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    ct.shipment_id,
    s.order_id,
    o.customer_id,
    (array_agg(ct.partner_id))[1] as partner_id,
    s.shipment_number,
    o.order_number,
    s.expected_cod_paise,
    sum(case when ct.entry_type = 'COLLECTED' then ct.amount_paise else 0 end)::bigint as collected_paise,
    sum(case when ct.entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL') then ct.amount_paise else 0 end)::bigint as net_paise,
    min(ct.created_at) as first_collected_at,
    max(ct.created_at) as last_collected_at
  from public.cod_transactions ct
  join public.shipments s on s.id = ct.shipment_id
  join public.orders o on o.id = s.order_id
  where ct.staff_user_id = p_staff_user_id
  group by ct.shipment_id, s.order_id, o.customer_id, s.shipment_number, o.order_number, s.expected_cod_paise
  having sum(case when ct.entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL') then ct.amount_paise else 0 end) > 0;
$$;

create or replace function public.staff_cod_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_cash bigint;
begin
  perform app_private.require_staff_identity();
  select coalesce(sum(ci.net_paise), 0) into v_cash
  from app_private.staff_cash_items(v_uid) ci;

  return jsonb_build_object(
    'cash_in_custody_paise', v_cash,
    'pending_settlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id, 'settlement_number', cs.settlement_number,
        'handed_over_paise', cs.handed_over_paise, 'status', cs.status,
        'declared_at', cs.declared_at
      ) order by cs.declared_at desc)
      from public.cod_settlements cs
      where cs.staff_user_id = v_uid and cs.status = 'PENDING_VERIFICATION'
    ), '[]'::jsonb),
    'unsettled_shipments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'shipment_id', ci.shipment_id, 'shipment_number', ci.shipment_number,
        'order_id', ci.order_id, 'order_number', ci.order_number,
        'expected_paise', ci.expected_paise, 'collected_paise', ci.collected_paise,
        'net_paise', ci.net_paise, 'last_collected_at', ci.last_collected_at
      ) order by ci.last_collected_at desc)
      from app_private.staff_cash_items(v_uid) ci
    ), '[]'::jsonb),
    'recent_settlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id, 'settlement_number', cs.settlement_number,
        'expected_paise', cs.expected_paise, 'collected_paise', cs.collected_paise,
        'handed_over_paise', cs.handed_over_paise, 'counted_paise', cs.counted_paise,
        'shortage_paise', cs.shortage_paise, 'excess_paise', cs.excess_paise,
        'status', cs.status, 'declared_at', cs.declared_at, 'verified_at', cs.verified_at
      ) order by cs.declared_at desc)
      from (
        select * from public.cod_settlements
        where staff_user_id = v_uid
        order by declared_at desc limit 20
      ) cs
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.staff_declare_cash_handover(p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_staff record;
  v_items record;
  v_count integer := 0;
  v_expected bigint := 0;
  v_collected bigint := 0;
  v_net bigint := 0;
  v_period_start timestamptz := now();
  v_period_end timestamptz := now();
  v_settlement_id uuid;
  v_number text;
  v_note text := trim(coalesce(p_note, ''));
begin
  select * into v_staff from app_private.require_staff_identity();
  perform app_private.assert_true(char_length(v_note) <= 500, 'Note is too long.');

  for v_items in
    select * from app_private.staff_cash_items(v_uid) order by last_collected_at
  loop
    v_count := v_count + 1;
    v_expected := v_expected + v_items.expected_paise;
    v_collected := v_collected + v_items.collected_paise;
    v_net := v_net + v_items.net_paise;
    v_period_start := least(v_period_start, v_items.first_collected_at);
    v_period_end := greatest(v_period_end, v_items.last_collected_at);
  end loop;

  perform app_private.assert_true(v_count > 0, 'There is no collected cash waiting to be handed over.');
  v_number := app_private.next_document_number('SET', 'public.settlement_number_seq'::regclass);

  insert into public.cod_settlements (
    settlement_number, staff_user_id, staff_type, staff_profile_id,
    partner_staff_id, partner_id, period_start, period_end,
    expected_paise, collected_paise, handed_over_paise, status, note
  ) values (
    v_number, v_uid, v_staff.staff_type, v_staff.staff_profile_id,
    v_staff.partner_staff_id, v_staff.partner_id, v_period_start, v_period_end,
    v_expected, v_collected, v_net, 'PENDING_VERIFICATION', v_note
  ) returning id into v_settlement_id;

  for v_items in
    select * from app_private.staff_cash_items(v_uid) order by last_collected_at
  loop
    insert into public.cod_settlement_items (
      settlement_id, shipment_id, expected_paise, collected_paise
    ) values (
      v_settlement_id, v_items.shipment_id, v_items.expected_paise, v_items.collected_paise
    );
    insert into public.cod_transactions (
      shipment_id, order_id, customer_id, staff_user_id, partner_id, settlement_id,
      entry_type, amount_paise, description, recorded_by, idempotency_key, metadata
    ) values (
      v_items.shipment_id, v_items.order_id, v_items.customer_id, v_uid,
      v_items.partner_id, v_settlement_id, 'HANDOVER', -v_items.net_paise,
      'Cash handed over for settlement ' || v_number, v_uid,
      'settlement:' || v_settlement_id::text || ':handover:' || v_items.shipment_id::text,
      jsonb_build_object('collected_paise', v_items.collected_paise, 'net_paise', v_items.net_paise)
    ) on conflict (idempotency_key) do nothing;
  end loop;

  perform app_private.notify_owner(
    'COD_HANDOVER_DECLARED', 'Cash handover ' || v_number,
    'A delivery person declared ₹' || to_char(v_net / 100.0, 'FM999999990.00') ||
      ' in cash. Count it and verify the settlement.',
    jsonb_build_object(
      'settlement_id', v_settlement_id, 'settlement_number', v_number,
      'handed_over_paise', v_net, 'shipment_count', v_count
    ),
    'cod-handover:' || v_settlement_id::text
  );
  perform app_private.notify_user(
    v_uid, 'COD_HANDOVER_DECLARED', 'Cash handover declared',
    'Your handover ' || v_number || ' for ₹' || to_char(v_net / 100.0, 'FM999999990.00') ||
      ' is awaiting owner verification.',
    jsonb_build_object('settlement_id', v_settlement_id, 'settlement_number', v_number),
    'cod-handover-staff:' || v_settlement_id::text
  );
  perform app_private.write_audit(
    'COD_HANDOVER_DECLARED', 'cod_settlement', v_settlement_id, null,
    jsonb_build_object(
      'settlement_number', v_number, 'expected_paise', v_expected,
      'collected_paise', v_collected, 'handed_over_paise', v_net,
      'shipment_count', v_count
    ),
    'DELIVERY_APP', v_uid
  );

  return jsonb_build_object(
    'settlement_id', v_settlement_id, 'settlement_number', v_number,
    'status', 'PENDING_VERIFICATION', 'expected_paise', v_expected,
    'collected_paise', v_collected, 'handed_over_paise', v_net,
    'shipment_count', v_count
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner delivery OTP support
-- ---------------------------------------------------------------------------
create or replace function public.owner_reset_delivery_otp(p_shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_otp text;
  v_expires timestamptz := now() + interval '30 minutes';
begin
  select * into v_shipment from public.shipments where id = p_shipment_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');
  perform app_private.assert_true(v_shipment.status = 'OUT_FOR_DELIVERY', 'A delivery OTP is only valid while the shipment is out for delivery.');
  select * into v_order from public.orders where id = v_shipment.order_id;

  v_otp := app_private.generate_otp_code();
  insert into public.delivery_otp_challenges (shipment_id, otp_hash, expires_at, attempts, last_sent_at)
  values (v_shipment.id, extensions.crypt(v_otp, extensions.gen_salt('bf', 8)), v_expires, 0, now())
  on conflict (shipment_id) do update
    set otp_hash = excluded.otp_hash, expires_at = excluded.expires_at,
        attempts = 0, last_sent_at = now();

  perform app_private.notify_user(
    v_order.customer_id, 'DELIVERY_OTP', 'New delivery OTP for order ' || v_order.order_number,
    'Delivery OTP: ' || v_otp || ' (valid for 30 minutes). Share it only after receiving your order.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id),
    null
  );
  perform app_private.write_audit(
    'DELIVERY_OTP_RESET', 'shipment', v_shipment.id, null,
    jsonb_build_object('expires_at', v_expires), 'SELLER_APP', v_uid
  );
  return jsonb_build_object(
    'shipment_id', v_shipment.id, 'otp_expires_at', v_expires,
    'message', 'A new delivery OTP was sent to the customer.'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Partner administrator staff controls
-- ---------------------------------------------------------------------------
create or replace function public.partner_suspend_staff(p_staff_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
  v_target public.partner_staff%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  v_uid := app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a suspension reason.');
  perform app_private.assert_true(p_staff_user_id <> v_uid, 'You cannot suspend your own partner administrator account.');
  select * into v_target from public.partner_staff
  where user_id = p_staff_user_id and partner_id = v_partner
  for update;
  perform app_private.assert_true(v_target.id is not null, 'Partner staff member not found.');
  perform app_private.assert_true(not v_target.is_admin, 'Only the owner can suspend a partner administrator.');
  perform app_private.assert_true(v_target.status = 'ACTIVE', 'This staff member is not active.');
  perform app_private.assert_true(
    app_private.staff_active_workload(p_staff_user_id) = 0,
    'Reassign or resolve all active tasks before suspending this staff member.'
  );

  update public.partner_staff set status = 'SUSPENDED', is_available = false where id = v_target.id;
  perform set_config('indibizz.privileged', 'on', true);
  update public.profiles set status = 'SUSPENDED' where id = p_staff_user_id;
  perform set_config('indibizz.privileged', 'off', true);

  perform app_private.notify_user(
    p_staff_user_id, 'STAFF_ACCOUNT', 'Partner access suspended',
    'Your partner delivery access was suspended. Reason: ' || v_reason,
    jsonb_build_object('partner_id', v_partner, 'reason', v_reason), null
  );
  perform app_private.write_audit(
    'PARTNER_STAFF_SUSPENDED', 'partner_staff', v_target.id,
    jsonb_build_object('status', 'ACTIVE'),
    jsonb_build_object('status', 'SUSPENDED', 'reason', v_reason),
    'PARTNER_APP', v_uid
  );
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'status', 'SUSPENDED');
end;
$$;

create or replace function public.partner_reactivate_staff(p_staff_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
  v_target public.partner_staff%rowtype;
begin
  v_uid := app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  select * into v_target from public.partner_staff
  where user_id = p_staff_user_id and partner_id = v_partner
  for update;
  perform app_private.assert_true(v_target.id is not null, 'Partner staff member not found.');
  perform app_private.assert_true(not v_target.is_admin, 'Only the owner can reactivate a partner administrator.');
  perform app_private.assert_true(v_target.status = 'SUSPENDED', 'This staff member is not suspended.');

  update public.partner_staff set status = 'ACTIVE', is_available = true where id = v_target.id;
  perform set_config('indibizz.privileged', 'on', true);
  update public.profiles set status = 'ACTIVE' where id = p_staff_user_id;
  perform set_config('indibizz.privileged', 'off', true);
  perform app_private.notify_user(
    p_staff_user_id, 'STAFF_ACCOUNT', 'Partner access restored',
    'Your partner delivery access is active again.',
    jsonb_build_object('partner_id', v_partner), null
  );
  perform app_private.write_audit(
    'PARTNER_STAFF_REACTIVATED', 'partner_staff', v_target.id,
    jsonb_build_object('status', 'SUSPENDED'), jsonb_build_object('status', 'ACTIVE'),
    'PARTNER_APP', v_uid
  );
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'status', 'ACTIVE');
end;
$$;

-- ---------------------------------------------------------------------------
-- Assignment expiry worker (service-role only, called by an Edge Function cron)
-- ---------------------------------------------------------------------------
create or replace function public.system_expire_assignments(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pickup record;
  v_delivery record;
  v_pickup_count integer := 0;
  v_delivery_count integer := 0;
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and coalesce(current_setting('indibizz.worker', true), 'off') <> 'on' then
    raise exception using errcode = '42501', message = 'Service role authorization required.';
  end if;

  for v_pickup in
    select pa.id, pa.pickup_request_id, pa.staff_user_id, pk.pickup_number,
           pk.shipment_id, pk.order_id
    from public.pickup_assignments pa
    join public.pickup_requests pk on pk.id = pa.pickup_request_id
    where pa.status = 'PENDING' and pa.expires_at is not null and pa.expires_at < now()
    order by pa.expires_at
    limit v_limit
    for update of pa skip locked
  loop
    update public.pickup_assignments
    set status = 'EXPIRED', responded_at = now()
    where id = v_pickup.id and status = 'PENDING';

    update public.pickup_requests set status = 'REQUESTED'
    where id = v_pickup.pickup_request_id and status = 'ASSIGNED';
    update public.shipments set status = 'PICKUP_REQUESTED'
    where id = v_pickup.shipment_id and status in ('PICKUP_ASSIGNED','PICKUP_ACCEPTED');

    perform app_private.notify_owner(
      'PICKUP_ASSIGNED', 'Pickup ' || v_pickup.pickup_number || ' offer expired',
      'The delivery person did not respond in time. The pickup is available for reassignment.',
      jsonb_build_object('pickup_id', v_pickup.pickup_request_id, 'assignment_id', v_pickup.id),
      'pickup-expired:' || v_pickup.id::text
    );
    perform app_private.write_audit(
      'PICKUP_ASSIGNMENT_EXPIRED', 'pickup_assignment', v_pickup.id, null,
      jsonb_build_object('pickup_id', v_pickup.pickup_request_id),
      'CRON', null
    );
    perform app_private.try_auto_assign_pickup(v_pickup.pickup_request_id);
    v_pickup_count := v_pickup_count + 1;
  end loop;

  for v_delivery in
    select da.id, da.shipment_id, da.staff_user_id, s.shipment_number, s.order_id
    from public.delivery_assignments da
    join public.shipments s on s.id = da.shipment_id
    where da.status = 'PENDING' and da.expires_at is not null and da.expires_at < now()
    order by da.expires_at
    limit v_limit
    for update of da skip locked
  loop
    update public.delivery_assignments
    set status = 'EXPIRED', responded_at = now()
    where id = v_delivery.id and status = 'PENDING';

    perform app_private.notify_owner(
      'DELIVERY_ASSIGNED', 'Delivery ' || v_delivery.shipment_number || ' offer expired',
      'The delivery person did not respond in time. The shipment is available for reassignment.',
      jsonb_build_object('shipment_id', v_delivery.shipment_id, 'assignment_id', v_delivery.id),
      'delivery-expired:' || v_delivery.id::text
    );
    perform app_private.write_audit(
      'DELIVERY_ASSIGNMENT_EXPIRED', 'delivery_assignment', v_delivery.id, null,
      jsonb_build_object('shipment_id', v_delivery.shipment_id),
      'CRON', null
    );
    perform app_private.try_auto_assign_delivery(v_delivery.shipment_id);
    v_delivery_count := v_delivery_count + 1;
  end loop;

  return jsonb_build_object(
    'expired_pickup_assignments', v_pickup_count,
    'expired_delivery_assignments', v_delivery_count,
    'processed_at', now()
  );
end;
$$;
