-- IndiaBizz :: 0012 pickup / delivery assignment and operational monitoring.

create or replace function app_private.pickup_location(p_order_id uuid)
returns table (town_id uuid, pincode text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_business jsonb := app_private.get_setting('business', '{}'::jsonb);
  v_town uuid;
  v_pin text;
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id;
  v_town := nullif(v_business ->> 'pickup_town_id', '')::uuid;
  v_pin := nullif(btrim(coalesce(v_business ->> 'pickup_pincode', '')), '');
  if v_town is not null and exists (select 1 from public.towns t where t.id = v_town and t.is_active) then
    return query select v_town, coalesce(v_pin, v_order.pincode);
  else
    return query select v_order.town_id, v_order.pincode;
  end if;
end;
$$;

create or replace function app_private.policy_for_town(p_town_id uuid)
returns public.assignment_policies
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.*
  from public.assignment_policies p
  where p.town_id = p_town_id or p.town_id is null
  order by (p.town_id is not null) desc
  limit 1;
$$;

create or replace function app_private.staff_active_workload(p_user_id uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (select count(*)::integer from public.pickup_assignments pa
      where pa.staff_user_id = p_user_id and pa.status in ('PENDING','ACCEPTED'))
    + (select count(*)::integer from public.delivery_assignments da
      where da.staff_user_id = p_user_id and da.status in ('PENDING','ACCEPTED'));
$$;

create or replace function app_private.haversine_km(
  p_lat1 double precision, p_lon1 double precision,
  p_lat2 double precision, p_lon2 double precision
)
returns double precision
language sql
immutable
as $$
  select case
    when p_lat1 is null or p_lon1 is null or p_lat2 is null or p_lon2 is null then null
    else 6371 * 2 * asin(sqrt(
      power(sin(radians(p_lat2 - p_lat1) / 2), 2)
      + cos(radians(p_lat1)) * cos(radians(p_lat2))
      * power(sin(radians(p_lon2 - p_lon1) / 2), 2)
    ))
  end;
$$;

create or replace function app_private.try_auto_assign_pickup(p_pickup_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_pickup public.pickup_requests%rowtype;
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_town uuid;
  v_pin text;
  v_policy public.assignment_policies%rowtype;
  v_candidate record;
  v_assignment_id uuid;
  v_expires timestamptz;
  v_owner uuid;
begin
  select * into v_pickup from public.pickup_requests where id = p_pickup_id for update;
  if v_pickup.id is null or v_pickup.status not in ('REQUESTED') then
    return null;
  end if;
  if exists (
    select 1 from public.pickup_assignments
    where pickup_request_id = p_pickup_id and status in ('PENDING','ACCEPTED')
  ) then
    return null;
  end if;

  select * into v_order from public.orders where id = v_pickup.order_id;
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id;
  select town_id, pincode into v_town, v_pin from app_private.pickup_location(v_order.id);
  select * into v_policy from app_private.policy_for_town(v_town);

  if v_policy.id is null then
    v_policy.auto_assign_enabled := true;
    v_policy.manual_only := false;
    v_policy.offer_timeout_seconds := 300;
    v_policy.max_active_tasks_per_staff := 10;
    v_policy.prefer_own_team := true;
    v_policy.weight_workload := 10;
    v_policy.weight_distance := 1;
    v_policy.candidate_limit := 20;
    v_policy.retry_on_rejection := true;
  end if;
  if not v_policy.auto_assign_enabled or v_policy.manual_only then
    return null;
  end if;

  select * into v_candidate
  from (
    -- Own IndiaBizz delivery staff
    select
      'OWN'::public.staff_type as staff_type,
      sp.id as staff_profile_id,
      null::uuid as partner_staff_id,
      null::uuid as partner_id,
      sp.user_id,
      (
        app_private.staff_active_workload(sp.user_id) * v_policy.weight_workload
        + coalesce(app_private.haversine_km(sp.current_latitude, sp.current_longitude, t.latitude, t.longitude), 25) * v_policy.weight_distance
      )::numeric(12,4) as score
    from public.staff_profiles sp
    join public.profiles p on p.id = sp.user_id
    join public.towns t on t.id = v_town
    where sp.status = 'ACTIVE'
      and sp.is_available
      and p.status = 'ACTIVE'
      and p.role = 'OWN_DELIVERY_STAFF'
      and app_private.staff_active_workload(sp.user_id) < least(sp.capacity_per_day, v_policy.max_active_tasks_per_staff)
      and exists (
        select 1 from public.staff_service_areas sa
        where sa.staff_user_id = sp.user_id
          and sa.town_id = v_town
          and (sa.pincode is null or sa.pincode = v_pin)
      )
      and not exists (
        select 1 from public.pickup_assignments prior
        where prior.pickup_request_id = p_pickup_id
          and prior.staff_user_id = sp.user_id
          and prior.status in ('REJECTED','EXPIRED')
      )
    union all
    -- Approved external partner personnel
    select
      'PARTNER'::public.staff_type,
      null::uuid,
      ps.id,
      ps.partner_id,
      ps.user_id,
      (
        app_private.staff_active_workload(ps.user_id) * v_policy.weight_workload
        + coalesce(app_private.haversine_km(ps.current_latitude, ps.current_longitude, t.latitude, t.longitude), 25) * v_policy.weight_distance
        + case when v_policy.prefer_own_team then 500 else 0 end
      )::numeric(12,4)
    from public.partner_staff ps
    join public.delivery_partners dp on dp.id = ps.partner_id and dp.status = 'APPROVED'
    join public.profiles p on p.id = ps.user_id
    join public.towns t on t.id = v_town
    where ps.status = 'ACTIVE'
      and ps.is_available
      and p.status = 'ACTIVE'
      and p.role in ('PARTNER_ADMIN','PARTNER_DELIVERY_STAFF')
      and app_private.staff_active_workload(ps.user_id) < least(ps.capacity_per_day, v_policy.max_active_tasks_per_staff)
      and exists (
        select 1 from public.partner_service_areas psa
        where psa.partner_id = ps.partner_id
          and psa.town_id = v_town
          and (psa.pincode is null or psa.pincode = v_pin)
      )
      and not exists (
        select 1 from public.pickup_assignments prior
        where prior.pickup_request_id = p_pickup_id
          and prior.staff_user_id = ps.user_id
          and prior.status in ('REJECTED','EXPIRED')
      )
  ) candidates
  order by score asc, user_id
  limit greatest(v_policy.candidate_limit, 1);

  if v_candidate.user_id is null then
    return null;
  end if;

  v_expires := now() + make_interval(secs => v_policy.offer_timeout_seconds);
  begin
    insert into public.pickup_assignments (
      pickup_request_id, staff_user_id, staff_type, staff_profile_id,
      partner_staff_id, partner_id, status, mode, score, assigned_by, expires_at
    ) values (
      p_pickup_id, v_candidate.user_id, v_candidate.staff_type,
      v_candidate.staff_profile_id, v_candidate.partner_staff_id,
      v_candidate.partner_id, 'PENDING', 'AUTO', v_candidate.score, null, v_expires
    ) returning id into v_assignment_id;
  exception when unique_violation then
    return null;
  end;

  update public.pickup_requests set status = 'ASSIGNED' where id = p_pickup_id;
  update public.shipments set status = 'PICKUP_ASSIGNED' where id = v_pickup.shipment_id;
  perform app_private.log_shipment_event(
    v_pickup.shipment_id, 'PICKUP_ASSIGNED', v_shipment.status, 'PICKUP_ASSIGNED',
    'SYSTEM', null, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment_id, 'pickup_id', p_pickup_id, 'mode', 'AUTO')
  );
  perform app_private.notify_user(
    v_candidate.user_id, 'PICKUP_ASSIGNED', 'New pickup assigned',
    'Pickup ' || v_pickup.pickup_number || ' for order ' || v_order.order_number || ' is available. Accept it and review the pickup details.',
    jsonb_build_object(
      'pickup_id', p_pickup_id, 'assignment_id', v_assignment_id,
      'pickup_number', v_pickup.pickup_number, 'order_number', v_order.order_number,
      'package_count', v_pickup.package_count_expected
    ),
    'pickup-assigned:' || v_assignment_id::text
  );
  perform app_private.notify_owner(
    'PICKUP_ASSIGNED', 'Pickup ' || v_pickup.pickup_number || ' automatically assigned',
    'An eligible delivery person was assigned. They must accept the pickup.',
    jsonb_build_object('pickup_id', p_pickup_id, 'assignment_id', v_assignment_id),
    'pickup-auto-owner:' || v_assignment_id::text
  );
  perform app_private.write_audit(
    'PICKUP_AUTO_ASSIGNED', 'pickup_assignment', v_assignment_id, null,
    jsonb_build_object('pickup_id', p_pickup_id, 'staff_user_id', v_candidate.user_id, 'score', v_candidate.score),
    'SYSTEM', null
  );
  return v_assignment_id;
end;
$$;

create or replace function public.owner_list_pickups(p_status public.pickup_status default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', pk.id,
      'pickup_number', pk.pickup_number,
      'status', pk.status,
      'condition', pk.condition,
      'package_count_expected', pk.package_count_expected,
      'package_count_verified', pk.package_count_verified,
      'requested_at', pk.requested_at,
      'verified_at', pk.verified_at,
      'order_id', o.id,
      'order_number', o.order_number,
      'order_status', o.status,
      'customer_name', o.recipient_name,
      'customer_phone', o.phone,
      'town_name', o.town_name,
      'pincode', o.pincode,
      'total_paise', o.total_paise,
      'shipment_id', s.id,
      'shipment_number', s.shipment_number,
      'shipment_status', s.status,
      'otp', (
        select n.data ->> 'otp' from public.notifications n
        where n.type = 'PICKUP_OTP' and n.data ->> 'pickup_id' = pk.id::text
        order by n.created_at desc limit 1
      ),
      'otp_expires_at', (select c.expires_at from public.pickup_otp_challenges c where c.pickup_request_id = pk.id),
      'scanned_packages', (
        select count(distinct bs.package_id) from public.barcode_scans bs
        where bs.pickup_request_id = pk.id and bs.result = 'VALID'
      ),
      'assignment', (
        select jsonb_build_object(
          'id', pa.id, 'staff_user_id', pa.staff_user_id,
          'staff_name', coalesce(sp.display_name, ps.display_name),
          'staff_phone', coalesce(sp.phone, ps.phone),
          'staff_type', pa.staff_type, 'status', pa.status, 'mode', pa.mode,
          'partner_name', dp.name, 'assigned_at', pa.assigned_at, 'expires_at', pa.expires_at
        )
        from public.pickup_assignments pa
        left join public.staff_profiles sp on sp.id = pa.staff_profile_id
        left join public.partner_staff ps on ps.id = pa.partner_staff_id
        left join public.delivery_partners dp on dp.id = pa.partner_id
        where pa.pickup_request_id = pk.id and pa.status in ('PENDING','ACCEPTED')
        limit 1
      )
    ) order by pk.requested_at desc)
    from public.pickup_requests pk
    join public.orders o on o.id = pk.order_id
    join public.shipments s on s.id = pk.shipment_id
    where p_status is null or pk.status = p_status
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_list_delivery_personnel()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'staff_user_id', x.user_id,
      'staff_type', x.staff_type,
      'staff_record_id', x.staff_record_id,
      'partner_id', x.partner_id,
      'partner_name', x.partner_name,
      'display_name', x.display_name,
      'phone', x.phone,
      'employee_code', x.employee_code,
      'status', x.status,
      'is_available', x.is_available,
      'capacity_per_day', x.capacity_per_day,
      'active_tasks', app_private.staff_active_workload(x.user_id),
      'coverage_town_ids', x.coverage_town_ids,
      'coverage_label', x.coverage_label
    ) order by x.is_available desc, x.display_name)
    from (
      select
        sp.user_id, 'OWN'::public.staff_type as staff_type, sp.id as staff_record_id,
        null::uuid as partner_id, null::text as partner_name,
        sp.display_name, sp.phone, sp.employee_code, sp.status, sp.is_available,
        sp.capacity_per_day,
        coalesce((select jsonb_agg(distinct sa.town_id) from public.staff_service_areas sa where sa.staff_user_id = sp.user_id), '[]'::jsonb) as coverage_town_ids,
        coalesce((select string_agg(distinct t.name, ', ' order by t.name) from public.staff_service_areas sa join public.towns t on t.id = sa.town_id where sa.staff_user_id = sp.user_id), 'No coverage') as coverage_label
      from public.staff_profiles sp
      union all
      select
        ps.user_id, 'PARTNER', ps.id, ps.partner_id, dp.name,
        ps.display_name, ps.phone, null, ps.status, ps.is_available,
        ps.capacity_per_day,
        coalesce((select jsonb_agg(distinct psa.town_id) from public.partner_service_areas psa where psa.partner_id = ps.partner_id), '[]'::jsonb),
        coalesce((select string_agg(distinct t.name, ', ' order by t.name) from public.partner_service_areas psa join public.towns t on t.id = psa.town_id where psa.partner_id = ps.partner_id), 'No coverage')
      from public.partner_staff ps
      join public.delivery_partners dp on dp.id = ps.partner_id
    ) x
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_assign_pickup(
  p_pickup_id uuid,
  p_staff_user_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_order public.orders%rowtype;
  v_staff record;
  v_previous public.pickup_assignments%rowtype;
  v_assignment_id uuid;
  v_policy public.assignment_policies%rowtype;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_expires timestamptz;
begin
  select * into v_pickup from public.pickup_requests where id = p_pickup_id for update;
  perform app_private.assert_true(v_pickup.id is not null, 'Pickup request not found.');
  perform app_private.assert_true(v_pickup.status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED'), 'This pickup is no longer assignable.');
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;
  select * into v_order from public.orders where id = v_pickup.order_id;

  select * into v_staff from app_private.staff_identity(p_staff_user_id);
  perform app_private.assert_true(v_staff.staff_type is not null, 'Select an active delivery person or partner staff member.');

  select * into v_previous from public.pickup_assignments
  where pickup_request_id = p_pickup_id and status in ('PENDING','ACCEPTED')
  order by assigned_at desc limit 1;

  if v_previous.id is not null and v_previous.staff_user_id = p_staff_user_id then
    return jsonb_build_object('pickup_id', p_pickup_id, 'assignment_id', v_previous.id, 'idempotent_replay', true);
  end if;
  if v_previous.id is not null then
    perform app_private.assert_true(v_reason is not null and char_length(v_reason) between 3 and 500, 'Enter a reason for overriding the current assignment.');
    update public.pickup_assignments
    set status = 'CANCELLED', responded_at = now(), rejection_reason = v_reason
    where id = v_previous.id;
    perform app_private.notify_user(
      v_previous.staff_user_id, 'PICKUP_REJECTED', 'Pickup assignment changed',
      'Pickup ' || v_pickup.pickup_number || ' has been reassigned by the owner. Reason: ' || coalesce(v_reason, ''),
      jsonb_build_object('pickup_id', p_pickup_id, 'assignment_id', v_previous.id),
      null
    );
  end if;

  select * into v_policy from app_private.policy_for_town((select town_id from app_private.pickup_location(v_order.id)));
  v_expires := now() + make_interval(secs => coalesce(v_policy.offer_timeout_seconds, 86400));
  insert into public.pickup_assignments (
    pickup_request_id, staff_user_id, staff_type, staff_profile_id,
    partner_staff_id, partner_id, status, mode, assigned_by, expires_at
  ) values (
    p_pickup_id, p_staff_user_id, v_staff.staff_type, v_staff.staff_profile_id,
    v_staff.partner_staff_id, v_staff.partner_id, 'PENDING', 'MANUAL', v_uid, v_expires
  ) returning id into v_assignment_id;

  update public.pickup_requests set status = 'ASSIGNED' where id = p_pickup_id;
  update public.shipments set status = 'PICKUP_ASSIGNED' where id = v_shipment.id;
  perform app_private.log_shipment_event(
    v_shipment.id,
    case when v_previous.id is null then 'PICKUP_ASSIGNED'::public.shipment_event_type else 'ASSIGNMENT_REASSIGNED'::public.shipment_event_type end,
    v_shipment.status, 'PICKUP_ASSIGNED', 'SELLER_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_assignment_id, 'pickup_id', p_pickup_id, 'mode', 'MANUAL', 'reason', v_reason)
  );
  perform app_private.notify_user(
    p_staff_user_id, 'PICKUP_ASSIGNED', 'New pickup assigned',
    'Pickup ' || v_pickup.pickup_number || ' for order ' || v_order.order_number || ' has been assigned to you.',
    jsonb_build_object('pickup_id', p_pickup_id, 'assignment_id', v_assignment_id, 'order_number', v_order.order_number),
    'pickup-assigned-manual:' || v_assignment_id::text
  );
  perform app_private.write_audit(
    case when v_previous.id is null then 'PICKUP_MANUALLY_ASSIGNED' else 'PICKUP_REASSIGNED' end,
    'pickup_assignment', v_assignment_id,
    case when v_previous.id is null then null else jsonb_build_object('staff_user_id', v_previous.staff_user_id) end,
    jsonb_build_object('pickup_id', p_pickup_id, 'staff_user_id', p_staff_user_id, 'reason', v_reason),
    'SELLER_APP', v_uid
  );
  return jsonb_build_object('pickup_id', p_pickup_id, 'assignment_id', v_assignment_id, 'idempotent_replay', false);
end;
$$;

create or replace function public.owner_cancel_pickup(p_pickup_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_pickup public.pickup_requests%rowtype;
  v_shipment public.shipments%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a reason for cancelling the pickup.');
  select * into v_pickup from public.pickup_requests where id = p_pickup_id for update;
  perform app_private.assert_true(v_pickup.id is not null, 'Pickup request not found.');
  if v_pickup.status = 'CANCELLED' then
    return jsonb_build_object('pickup_id', p_pickup_id, 'status', 'CANCELLED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(v_pickup.status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED'), 'This pickup cannot be cancelled.');
  select * into v_shipment from public.shipments where id = v_pickup.shipment_id for update;
  perform app_private.assert_true(v_shipment.status not in ('PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','OUT_FOR_DELIVERY','DELIVERED'), 'The shipment has already been picked up.');

  update public.pickup_requests set status = 'CANCELLED', cancelled_at = now(), failure_reason = v_reason where id = p_pickup_id;
  update public.pickup_assignments
  set status = 'CANCELLED', responded_at = now(), rejection_reason = v_reason
  where pickup_request_id = p_pickup_id and status in ('PENDING','ACCEPTED');
  update public.shipments set status = 'READY_FOR_PICKUP' where id = v_shipment.id;
  update public.packages set status = 'READY_FOR_PICKUP'
  where shipment_id = v_shipment.id and status in ('PACKED','PICKUP_REQUESTED','READY_FOR_PICKUP');
  update public.orders set status = 'READY_FOR_PICKUP' where id = v_pickup.order_id;
  perform app_private.log_shipment_event(
    v_shipment.id, 'PICKUP_FAILED', v_shipment.status, 'READY_FOR_PICKUP',
    'SELLER_APP', v_uid, null, null, null, null,
    jsonb_build_object('pickup_id', p_pickup_id, 'reason', v_reason, 'cancelled', true)
  );
  perform app_private.write_audit('PICKUP_CANCELLED', 'pickup_request', p_pickup_id,
    jsonb_build_object('status', v_pickup.status),
    jsonb_build_object('status', 'CANCELLED', 'reason', v_reason), 'SELLER_APP', v_uid);
  return jsonb_build_object('pickup_id', p_pickup_id, 'status', 'CANCELLED', 'idempotent_replay', false);
end;
$$;

create or replace function public.owner_reopen_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  select * into v_shipment from public.shipments where order_id = p_order_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');
  perform app_private.assert_true(
    v_shipment.status in ('PICKUP_FAILED','PACKAGE_DAMAGED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED','PICKUP_ACCEPTED','ARRIVED_AT_PICKUP'),
    'This shipment cannot be reopened for pickup.'
  );
  update public.pickup_requests set status = 'CANCELLED', cancelled_at = now()
  where shipment_id = v_shipment.id and status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED','FAILED');
  update public.pickup_assignments set status = 'CANCELLED', responded_at = now()
  where pickup_request_id in (select id from public.pickup_requests where shipment_id = v_shipment.id)
    and status in ('PENDING','ACCEPTED');
  update public.shipments set status = 'READY_FOR_PICKUP' where id = v_shipment.id;
  update public.packages set status = 'READY_FOR_PICKUP'
  where shipment_id = v_shipment.id and status in ('PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED');
  update public.orders set status = 'READY_FOR_PICKUP' where id = p_order_id;
  perform app_private.write_audit('PICKUP_REOPENED', 'shipment', v_shipment.id, jsonb_build_object('status', v_shipment.status), jsonb_build_object('status', 'READY_FOR_PICKUP'), 'SELLER_APP', v_uid);
  return jsonb_build_object('order_id', p_order_id, 'status', 'READY_FOR_PICKUP');
end;
$$;

-- ---------------------------------------------------------------------------
-- Delivery assignments
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_deliveries(p_status public.shipment_status default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'shipment_id', s.id, 'shipment_number', s.shipment_number,
      'status', s.status, 'package_count', s.package_count,
      'expected_cod_paise', s.expected_cod_paise,
      'created_at', s.created_at, 'picked_up_at', s.picked_up_at,
      'delivered_at', s.delivered_at,
      'order_id', o.id, 'order_number', o.order_number,
      'customer_name', o.recipient_name, 'customer_phone', o.phone,
      'town_name', o.town_name, 'pincode', o.pincode,
      'assignment', (
        select jsonb_build_object(
          'id', da.id, 'staff_user_id', da.staff_user_id, 'status', da.status,
          'staff_name', coalesce(sp.display_name, ps.display_name),
          'staff_phone', coalesce(sp.phone, ps.phone),
          'staff_type', da.staff_type, 'partner_name', dp.name,
          'assigned_at', da.assigned_at
        )
        from public.delivery_assignments da
        left join public.staff_profiles sp on sp.id = da.staff_profile_id
        left join public.partner_staff ps on ps.id = da.partner_staff_id
        left join public.delivery_partners dp on dp.id = da.partner_id
        where da.shipment_id = s.id and da.status in ('PENDING','ACCEPTED')
        limit 1
      ),
      'last_event', (
        select jsonb_build_object('event_type', e.event_type, 'created_at', e.created_at)
        from public.shipment_events e where e.shipment_id = s.id
        order by e.created_at desc limit 1
      ),
      'attempts', (select count(*) from public.delivery_attempts a where a.shipment_id = s.id)
    ) order by s.created_at desc)
    from public.shipments s
    join public.orders o on o.id = s.order_id
    where p_status is null or s.status = p_status
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_assign_delivery(
  p_shipment_id uuid,
  p_staff_user_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_shipment public.shipments%rowtype;
  v_staff record;
  v_previous public.delivery_assignments%rowtype;
  v_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  select * into v_shipment from public.shipments where id = p_shipment_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');
  perform app_private.assert_true(
    v_shipment.status in ('PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','DELIVERY_ATTEMPTED','CUSTOMER_UNAVAILABLE','SHIPMENT_DELAYED'),
    'Delivery can only be reassigned before it is out for delivery or after a failed attempt.'
  );
  select * into v_staff from app_private.staff_identity(p_staff_user_id);
  perform app_private.assert_true(v_staff.staff_type is not null, 'Select an active delivery person.');

  select * into v_previous from public.delivery_assignments
  where shipment_id = p_shipment_id and status in ('PENDING','ACCEPTED')
  order by assigned_at desc limit 1;
  if v_previous.id is not null and v_previous.staff_user_id = p_staff_user_id then
    return jsonb_build_object('shipment_id', p_shipment_id, 'assignment_id', v_previous.id, 'idempotent_replay', true);
  end if;
  if v_previous.id is not null then
    perform app_private.assert_true(v_reason is not null and char_length(v_reason) between 3 and 500, 'Enter a reason for reassigning delivery.');
    update public.delivery_assignments set status = 'CANCELLED', responded_at = now(), rejection_reason = v_reason where id = v_previous.id;
    perform app_private.notify_user(v_previous.staff_user_id, 'DELIVERY_REJECTED', 'Delivery task changed',
      'Shipment ' || v_shipment.shipment_number || ' has been reassigned. Reason: ' || coalesce(v_reason, ''),
      jsonb_build_object('shipment_id', p_shipment_id), null);
  end if;

  insert into public.delivery_assignments (
    shipment_id, staff_user_id, staff_type, staff_profile_id, partner_staff_id,
    partner_id, status, mode, assigned_by, expires_at
  ) values (
    p_shipment_id, p_staff_user_id, v_staff.staff_type, v_staff.staff_profile_id,
    v_staff.partner_staff_id, v_staff.partner_id, 'PENDING', 'MANUAL', v_uid,
    now() + interval '24 hours'
  ) returning id into v_id;

  perform app_private.log_shipment_event(
    p_shipment_id, 'ASSIGNMENT_REASSIGNED', v_shipment.status, v_shipment.status,
    'SELLER_APP', v_uid, null, null, null, null,
    jsonb_build_object('assignment_id', v_id, 'staff_user_id', p_staff_user_id, 'reason', v_reason, 'kind', 'delivery')
  );
  perform app_private.notify_user(
    p_staff_user_id, 'DELIVERY_ASSIGNED', 'Delivery task assigned',
    'Shipment ' || v_shipment.shipment_number || ' has been assigned to you.',
    jsonb_build_object('shipment_id', p_shipment_id, 'assignment_id', v_id),
    'delivery-assigned:' || v_id::text
  );
  perform app_private.write_audit('DELIVERY_MANUALLY_ASSIGNED', 'delivery_assignment', v_id,
    case when v_previous.id is null then null else jsonb_build_object('staff_user_id', v_previous.staff_user_id) end,
    jsonb_build_object('shipment_id', p_shipment_id, 'staff_user_id', p_staff_user_id, 'reason', v_reason),
    'SELLER_APP', v_uid);
  return jsonb_build_object('shipment_id', p_shipment_id, 'assignment_id', v_id, 'idempotent_replay', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Staff administration
-- ---------------------------------------------------------------------------
create or replace function public.owner_set_staff_availability(p_staff_user_id uuid, p_is_available boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v record;
begin
  select * into v from app_private.staff_identity(p_staff_user_id);
  perform app_private.assert_true(v.staff_type is not null, 'Delivery person not found.');
  if v.staff_type = 'OWN' then
    update public.staff_profiles set is_available = coalesce(p_is_available, false) where user_id = p_staff_user_id;
  else
    update public.partner_staff set is_available = coalesce(p_is_available, false) where user_id = p_staff_user_id;
  end if;
  perform app_private.write_audit('STAFF_AVAILABILITY_CHANGED', 'staff', p_staff_user_id, null,
    jsonb_build_object('is_available', coalesce(p_is_available, false)), 'SELLER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'is_available', coalesce(p_is_available, false));
end;
$$;

create or replace function public.owner_update_staff_profile(
  p_staff_user_id uuid,
  p_display_name text,
  p_capacity_per_day integer default 25,
  p_employee_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v record;
begin
  select * into v from app_private.staff_identity(p_staff_user_id);
  perform app_private.assert_true(v.staff_type = 'OWN', 'Only own IndiaBizz staff can be edited here.');
  perform app_private.assert_true(char_length(trim(coalesce(p_display_name, ''))) between 2 and 160, 'Enter a valid name.');
  perform app_private.assert_true(coalesce(p_capacity_per_day, 25) between 1 and 500, 'Capacity must be between 1 and 500.');
  perform app_private.assert_true(p_employee_code is null or p_employee_code = '' or p_employee_code ~ '^[A-Za-z0-9_-]{2,24}$', 'Invalid employee code.');
  update public.staff_profiles
  set display_name = trim(p_display_name),
      capacity_per_day = p_capacity_per_day,
      employee_code = nullif(trim(coalesce(p_employee_code, '')), '')
  where user_id = p_staff_user_id;
  perform app_private.write_audit('STAFF_PROFILE_UPDATED', 'staff', p_staff_user_id, null,
    jsonb_build_object('display_name', trim(p_display_name), 'capacity_per_day', p_capacity_per_day),
    'SELLER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id);
end;
$$;

create or replace function public.owner_suspend_delivery_person(p_staff_user_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v record;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a suspension reason.');
  select * into v from app_private.staff_identity(p_staff_user_id);
  perform app_private.assert_true(v.staff_type is not null, 'Delivery person not found.');
  perform app_private.assert_true(
    app_private.staff_active_workload(p_staff_user_id) = 0,
    'Reassign or resolve all active tasks before suspending this delivery person.'
  );
  if v.staff_type = 'OWN' then
    update public.staff_profiles set status = 'SUSPENDED', is_available = false where user_id = p_staff_user_id;
  else
    update public.partner_staff set status = 'SUSPENDED', is_available = false where user_id = p_staff_user_id;
  end if;
  perform set_config('indibizz.privileged', 'on', true);
  update public.profiles set status = 'SUSPENDED' where id = p_staff_user_id;
  perform set_config('indibizz.privileged', 'off', true);
  perform app_private.notify_user(p_staff_user_id, 'STAFF_ACCOUNT', 'Account suspended',
    'Your IndiaBizz delivery access has been suspended. Reason: ' || v_reason,
    jsonb_build_object('reason', v_reason), null);
  perform app_private.write_audit('STAFF_SUSPENDED', 'staff', p_staff_user_id, null,
    jsonb_build_object('reason', v_reason), 'SELLER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'status', 'SUSPENDED');
end;
$$;

create or replace function public.owner_reactivate_delivery_person(p_staff_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_role public.user_role;
  v_staff_type public.staff_type;
begin
  select role into v_role from public.profiles where id = p_staff_user_id;
  perform app_private.assert_true(v_role in ('OWN_DELIVERY_STAFF','PARTNER_ADMIN','PARTNER_DELIVERY_STAFF'), 'Delivery person not found.');
  v_staff_type := case when v_role = 'OWN_DELIVERY_STAFF' then 'OWN'::public.staff_type else 'PARTNER'::public.staff_type end;
  if v_staff_type = 'OWN' then
    update public.staff_profiles set status = 'ACTIVE' where user_id = p_staff_user_id;
  else
    update public.partner_staff set status = 'ACTIVE' where user_id = p_staff_user_id;
  end if;
  perform set_config('indibizz.privileged', 'on', true);
  update public.profiles set status = 'ACTIVE' where id = p_staff_user_id;
  perform set_config('indibizz.privileged', 'off', true);
  perform app_private.write_audit('STAFF_REACTIVATED', 'staff', p_staff_user_id, null, null, 'SELLER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'status', 'ACTIVE');
end;
$$;

-- Invitation creation is shared by OWNER and permitted partner admins.
create or replace function app_private.create_staff_invite(
  p_actor uuid,
  p_phone text,
  p_role public.user_role,
  p_display_name text,
  p_partner_id uuid,
  p_can_manage_partner_staff boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_phone text := public.normalize_phone(p_phone);
  v_code text;
  v_id uuid;
  v_number integer := 0;
begin
  perform app_private.assert_true(public.is_valid_phone(v_phone), 'Enter a valid mobile number.');
  perform app_private.assert_true(p_role in ('OWN_DELIVERY_STAFF','PARTNER_ADMIN','PARTNER_DELIVERY_STAFF'), 'Invalid staff role.');
  perform app_private.assert_true(char_length(trim(coalesce(p_display_name, ''))) between 2 and 160, 'Enter the staff member name.');
  perform app_private.assert_true((p_role = 'OWN_DELIVERY_STAFF' and p_partner_id is null) or (p_role <> 'OWN_DELIVERY_STAFF' and p_partner_id is not null), 'Partner is required for partner staff.');
  if p_partner_id is not null then
    perform app_private.assert_true(exists (
      select 1 from public.delivery_partners dp where dp.id = p_partner_id and dp.status = 'APPROVED'
    ), 'The partner organization must be approved first.');
  end if;
  perform app_private.assert_true(not exists (
    select 1 from public.staff_invites si
    where si.phone = v_phone and si.used_at is null and si.revoked_at is null
  ), 'An active invitation already exists for this phone number.');
  perform app_private.assert_true(not exists (
    select 1 from public.profiles p where p.phone = v_phone and p.role <> 'CUSTOMER'
  ), 'This phone number already belongs to a staff account.');

  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  insert into public.staff_invites (
    phone, role, partner_id, display_name, can_manage_partner_staff,
    invite_code_hash, expires_at, created_by
  ) values (
    v_phone, p_role, p_partner_id, trim(p_display_name),
    coalesce(p_can_manage_partner_staff, false),
    extensions.crypt(v_code, extensions.gen_salt('bf', 8)),
    now() + interval '7 days', p_actor
  ) returning id into v_id;
  perform app_private.write_audit('STAFF_INVITE_CREATED', 'staff_invite', v_id, null,
    jsonb_build_object('phone', v_phone, 'role', p_role, 'partner_id', p_partner_id),
    'SELLER_APP', p_actor);
  return jsonb_build_object(
    'invite_id', v_id, 'activation_code', v_code,
    'phone', v_phone, 'role', p_role, 'expires_in_days', 7
  );
end;
$$;

create or replace function public.owner_create_staff_invite(
  p_phone text,
  p_role public.user_role,
  p_display_name text,
  p_partner_id uuid default null,
  p_can_manage_partner_staff boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
begin
  return app_private.create_staff_invite(v_uid, p_phone, p_role, p_display_name, p_partner_id, p_can_manage_partner_staff);
end;
$$;

create or replace function public.redeem_staff_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_phone text;
  v_profile public.profiles%rowtype;
  v_invite public.staff_invites%rowtype;
  v_partner public.delivery_partners%rowtype;
  v_found boolean := false;
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_code, ''))) between 6 and 32, 'Enter the activation code.');
  select * into v_profile from public.profiles where id = v_uid;
  perform app_private.assert_true(v_profile.role = 'CUSTOMER', 'This account is already provisioned for staff access.');
  perform app_private.assert_true(v_profile.phone is not null, 'Verify your mobile number before activating staff access.');

  for v_invite in
    select * from public.staff_invites
    where phone = v_profile.phone and used_at is null and revoked_at is null
    for update
  loop
    if v_invite.expires_at < now() then
      continue;
    end if;
    if extensions.crypt(upper(trim(p_code)), v_invite.invite_code_hash) = v_invite.invite_code_hash then
      v_found := true;
      exit;
    end if;
  end loop;
  perform app_private.assert_true(v_found, 'Activation code is invalid or expired.');

  if v_invite.partner_id is not null then
    select * into v_partner from public.delivery_partners where id = v_invite.partner_id;
    perform app_private.assert_true(v_partner.status = 'APPROVED', 'The partner organization is not active.');
  end if;

  perform set_config('indibizz.privileged', 'on', true);
  update public.profiles
  set role = v_invite.role, status = 'ACTIVE', full_name = v_invite.display_name
  where id = v_uid;
  perform set_config('indibizz.privileged', 'off', true);

  if v_invite.role = 'OWN_DELIVERY_STAFF' then
    insert into public.staff_profiles (user_id, employee_code, display_name, phone, status, created_by)
    values (v_uid, 'IBD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)), v_invite.display_name, v_profile.phone, 'ACTIVE', v_invite.created_by)
    on conflict (user_id) do update set status = 'ACTIVE', display_name = excluded.display_name;
  else
    insert into public.partner_staff (
      partner_id, user_id, display_name, phone, status, is_admin,
      can_manage_partner_staff, created_by
    ) values (
      v_invite.partner_id, v_uid, v_invite.display_name, v_profile.phone, 'ACTIVE',
      v_invite.role = 'PARTNER_ADMIN', v_invite.can_manage_partner_staff, v_invite.created_by
    ) on conflict (user_id) do update
      set status = 'ACTIVE', display_name = excluded.display_name,
          is_admin = excluded.is_admin, can_manage_partner_staff = excluded.can_manage_partner_staff;
  end if;

  update public.staff_invites set used_at = now(), used_by = v_uid where id = v_invite.id;
  perform app_private.notify_user(v_uid, 'STAFF_ACCOUNT', 'Staff access activated',
    'Your IndiaBizz delivery access is active.', jsonb_build_object('role', v_invite.role), null);
  perform app_private.write_audit('STAFF_INVITE_REDEEMED', 'staff_invite', v_invite.id, null,
    jsonb_build_object('user_id', v_uid, 'role', v_invite.role), 'DELIVERY_APP', v_uid);
  return jsonb_build_object('role', v_invite.role, 'partner_id', v_invite.partner_id, 'status', 'ACTIVE');
end;
$$;

create or replace function public.owner_list_staff_invites()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', si.id, 'phone', si.phone, 'role', si.role,
      'partner_id', si.partner_id, 'partner_name', dp.name,
      'display_name', si.display_name, 'expires_at', si.expires_at,
      'used_at', si.used_at, 'revoked_at', si.revoked_at,
      'can_manage_partner_staff', si.can_manage_partner_staff,
      'created_at', si.created_at
    ) order by si.created_at desc)
    from public.staff_invites si
    left join public.delivery_partners dp on dp.id = si.partner_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_revoke_staff_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
begin
  update public.staff_invites
  set revoked_at = now()
  where id = p_invite_id and used_at is null and revoked_at is null;
  perform app_private.assert_true(found, 'Active invitation not found.');
  perform app_private.write_audit('STAFF_INVITE_REVOKED', 'staff_invite', p_invite_id, null, null, 'SELLER_APP', v_uid);
  return jsonb_build_object('revoked', true);
end;
$$;
