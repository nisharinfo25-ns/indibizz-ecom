-- IndiaBizz :: 0013 partners, towns/coverage and configuration.

-- ---------------------------------------------------------------------------
-- Partner organizations (owner-only creation/approval; never public)
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_partners()
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
      'id', dp.id, 'name', dp.name, 'code', dp.code, 'contact_name', dp.contact_name,
      'phone', dp.phone, 'email', dp.email, 'status', dp.status,
      'cod_credit_limit_paise', dp.cod_credit_limit_paise,
      'settlement_cycle_days', dp.settlement_cycle_days, 'notes', dp.notes,
      'approved_at', dp.approved_at, 'created_at', dp.created_at,
      'staff_count', (select count(*) from public.partner_staff ps where ps.partner_id = dp.id),
      'active_staff_count', (select count(*) from public.partner_staff ps where ps.partner_id = dp.id and ps.status = 'ACTIVE'),
      'coverage', coalesce((
        select jsonb_agg(jsonb_build_object('town_id', psa.town_id, 'town_name', t.name, 'pincode', psa.pincode))
        from public.partner_service_areas psa join public.towns t on t.id = psa.town_id
        where psa.partner_id = dp.id
      ), '[]'::jsonb)
    ) order by dp.created_at desc)
    from public.delivery_partners dp
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_save_partner(
  p_name text,
  p_code text,
  p_contact_name text default '',
  p_phone text default null,
  p_email text default null,
  p_status public.partner_status default 'PENDING',
  p_cod_credit_limit_paise bigint default 0,
  p_settlement_cycle_days integer default 1,
  p_notes text default '',
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_phone text := case when p_phone is null or btrim(p_phone) = '' then null else public.normalize_phone(p_phone) end;
  v_id uuid;
  v_code text := upper(trim(coalesce(p_code, '')));
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_name, ''))) between 2 and 160, 'Enter a partner name.');
  perform app_private.assert_true(v_code ~ '^[A-Z0-9][A-Z0-9_-]{2,19}$', 'Partner code must be 3-20 uppercase letters, digits, hyphen or underscore.');
  perform app_private.assert_true(v_phone is null or public.is_valid_phone(v_phone), 'Enter a valid partner contact phone.');
  perform app_private.assert_true(coalesce(p_cod_credit_limit_paise, 0) >= 0, 'COD credit limit cannot be negative.');
  perform app_private.assert_true(coalesce(p_settlement_cycle_days, 1) between 0 and 30, 'Settlement cycle is invalid.');
  if p_id is not null then
    select dp.id into v_id from public.delivery_partners dp where dp.id = p_id;
    perform app_private.assert_true(v_id is not null, 'Partner not found.');
  end if;
  if v_id is null then
    insert into public.delivery_partners (
      name, code, contact_name, phone, email, status, cod_credit_limit_paise,
      settlement_cycle_days, notes, created_by, approved_by, approved_at
    ) values (
      trim(p_name), v_code, coalesce(p_contact_name, ''), nullif(v_phone, ''),
      nullif(trim(coalesce(p_email, '')), ''), coalesce(p_status, 'PENDING'),
      coalesce(p_cod_credit_limit_paise, 0), coalesce(p_settlement_cycle_days, 1),
      coalesce(p_notes, ''), v_uid,
      case when p_status = 'APPROVED' then v_uid else null end,
      case when p_status = 'APPROVED' then now() else null end
    ) returning id into v_id;
  else
    update public.delivery_partners
    set name = trim(p_name), code = v_code, contact_name = coalesce(p_contact_name, ''),
        phone = nullif(v_phone, ''), email = nullif(trim(coalesce(p_email, '')), ''),
        status = coalesce(p_status, status),
        cod_credit_limit_paise = coalesce(p_cod_credit_limit_paise, cod_credit_limit_paise),
        settlement_cycle_days = coalesce(p_settlement_cycle_days, settlement_cycle_days),
        notes = coalesce(p_notes, notes),
        approved_by = case when p_status = 'APPROVED' and approved_at is null then v_uid else approved_by end,
        approved_at = case when p_status = 'APPROVED' and approved_at is null then now() else approved_at end
    where id = v_id;
  end if;
  perform app_private.write_audit(
    case when p_id is null then 'PARTNER_CREATED' else 'PARTNER_UPDATED' end,
    'delivery_partner', v_id, null, jsonb_build_object('name', trim(p_name), 'status', coalesce(p_status, 'PENDING')),
    'SELLER_APP', v_uid);
  return (select jsonb_build_object('id', id, 'name', name, 'code', code, 'status', status) from public.delivery_partners where id = v_id);
end;
$$;

create or replace function public.owner_set_partner_status(p_partner_id uuid, p_status public.partner_status, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_partner public.delivery_partners%rowtype;
begin
  perform app_private.assert_true(p_status in ('APPROVED','SUSPENDED','DEACTIVATED'), 'Invalid partner status.');
  select * into v_partner from public.delivery_partners where id = p_partner_id for update;
  perform app_private.assert_true(v_partner.id is not null, 'Partner not found.');
  if p_status = 'DEACTIVATED' then
    perform app_private.assert_true(
      not exists (
        select 1 from public.pickup_assignments pa where pa.partner_id = p_partner_id and pa.status in ('PENDING','ACCEPTED')
        union all
        select 1 from public.delivery_assignments da where da.partner_id = p_partner_id and da.status in ('PENDING','ACCEPTED')
      ),
      'Reassign the partner''s active tasks before deactivation.'
    );
  end if;
  update public.delivery_partners
  set status = p_status,
      approved_by = case when p_status = 'APPROVED' then v_uid else approved_by end,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      notes = case when p_reason is null then notes else notes || E'\n' || now()::date || ': ' || p_reason end
  where id = p_partner_id;
  if p_status = 'SUSPENDED' then
    update public.partner_staff set is_available = false where partner_id = p_partner_id;
  end if;
  perform app_private.write_audit('PARTNER_STATUS_CHANGED', 'delivery_partner', p_partner_id,
    jsonb_build_object('status', v_partner.status), jsonb_build_object('status', p_status, 'reason', p_reason), 'SELLER_APP', v_uid);
  return jsonb_build_object('partner_id', p_partner_id, 'status', p_status);
end;
$$;

create or replace function public.owner_set_partner_coverage(p_partner_id uuid, p_areas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_area jsonb;
  v_town uuid;
  v_pin text;
begin
  perform app_private.assert_true(exists (select 1 from public.delivery_partners dp where dp.id = p_partner_id), 'Partner not found.');
  perform app_private.assert_true(jsonb_typeof(coalesce(p_areas, '[]'::jsonb)) = 'array', 'Coverage must be an array.');
  delete from public.partner_service_areas where partner_id = p_partner_id;
  for v_area in select * from jsonb_array_elements(coalesce(p_areas, '[]'::jsonb))
  loop
    v_town := (v_area ->> 'town_id')::uuid;
    v_pin := nullif(btrim(coalesce(v_area ->> 'pincode', '')), '');
    perform app_private.assert_true(exists (select 1 from public.towns t where t.id = v_town), 'Invalid town in coverage.');
    if v_pin is not null then
      perform app_private.assert_true(exists (
        select 1 from public.serviceable_pincodes sp
        where sp.town_id = v_town and sp.pincode = v_pin and sp.is_active
      ), 'PIN code is not serviceable for the selected town.');
    end if;
    insert into public.partner_service_areas (partner_id, town_id, pincode, created_by)
    values (p_partner_id, v_town, v_pin, v_uid)
    on conflict do nothing;
  end loop;
  perform app_private.write_audit('PARTNER_COVERAGE_SET', 'delivery_partner', p_partner_id, null,
    jsonb_build_object('areas', p_areas), 'SELLER_APP', v_uid);
  return jsonb_build_object('partner_id', p_partner_id, 'area_count', (select count(*) from public.partner_service_areas where partner_id = p_partner_id));
end;
$$;

-- Partner administrator self-service -------------------------------------------------
create or replace function public.partner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_partner_admin();
  v_partner uuid := public.current_partner_id();
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata';
begin
  return jsonb_build_object(
    'partner_id', v_partner,
    'partner_name', (select dp.name from public.delivery_partners dp where dp.id = v_partner),
    'active_staff', (select count(*) from public.partner_staff ps where ps.partner_id = v_partner and ps.status = 'ACTIVE'),
    'available_staff', (select count(*) from public.partner_staff ps where ps.partner_id = v_partner and ps.status = 'ACTIVE' and ps.is_available),
    'pending_pickups', (
      select count(*) from public.pickup_assignments pa
      where pa.partner_id = v_partner and pa.status in ('PENDING','ACCEPTED')
    ),
    'active_deliveries', (
      select count(*) from public.delivery_assignments da
      where da.partner_id = v_partner and da.status in ('PENDING','ACCEPTED')
    ),
    'delivered_today', (
      select count(*) from public.delivery_assignments da
      where da.partner_id = v_partner and da.status = 'COMPLETED' and da.completed_at >= v_day_start
    ),
    'cod_outstanding_paise', coalesce((
      select sum(ct.amount_paise) from public.cod_transactions ct
      where ct.partner_id = v_partner and ct.entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL')
    ), 0),
    'recent_tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'assignment_type', x.assignment_type, 'assignment_id', x.assignment_id,
        'staff_name', x.staff_name, 'status', x.status, 'created_at', x.created_at,
        'order_number', x.order_number, 'pickup_number', x.pickup_number,
        'shipment_number', x.shipment_number
      ) order by x.created_at desc)
      from (
        select 'PICKUP' as assignment_type, pa.id as assignment_id, ps.display_name as staff_name,
          pa.status, pa.assigned_at as created_at, o.order_number, pk.pickup_number, s.shipment_number
        from public.pickup_assignments pa
        join public.partner_staff ps on ps.id = pa.partner_staff_id
        join public.pickup_requests pk on pk.id = pa.pickup_request_id
        join public.orders o on o.id = pk.order_id
        join public.shipments s on s.id = pk.shipment_id
        where pa.partner_id = v_partner
        union all
        select 'DELIVERY', da.id, ps.display_name, da.status, da.assigned_at,
          o.order_number, null, s.shipment_number
        from public.delivery_assignments da
        join public.partner_staff ps on ps.id = da.partner_staff_id
        join public.shipments s on s.id = da.shipment_id
        join public.orders o on o.id = s.order_id
        where da.partner_id = v_partner
      ) x
      limit 10
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.partner_list_staff()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_partner uuid;
begin
  perform app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'user_id', ps.user_id, 'display_name', ps.display_name, 'phone', ps.phone,
      'status', ps.status, 'is_admin', ps.is_admin,
      'can_manage_partner_staff', ps.can_manage_partner_staff,
      'is_available', ps.is_available, 'capacity_per_day', ps.capacity_per_day,
      'active_tasks', app_private.staff_active_workload(ps.user_id),
      'created_at', ps.created_at
    ) order by ps.is_admin desc, ps.display_name)
    from public.partner_staff ps
    where ps.partner_id = v_partner
  ), '[]'::jsonb);
end;
$$;

create or replace function public.partner_set_staff_availability(p_staff_user_id uuid, p_is_available boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
begin
  v_uid := app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  update public.partner_staff
  set is_available = coalesce(p_is_available, false)
  where user_id = p_staff_user_id and partner_id = v_partner
    and (user_id = v_uid or not is_admin);
  perform app_private.assert_true(found, 'Staff member not found or cannot be modified.');
  perform app_private.write_audit('PARTNER_STAFF_AVAILABILITY', 'partner_staff', p_staff_user_id, null,
    jsonb_build_object('is_available', coalesce(p_is_available, false)), 'PARTNER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'is_available', coalesce(p_is_available, false));
end;
$$;

create or replace function public.partner_create_staff_invite(
  p_phone text,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
  v_can_manage boolean;
begin
  v_uid := app_private.require_partner_admin();
  select ps.partner_id, ps.can_manage_partner_staff into v_partner, v_can_manage
  from public.partner_staff ps where ps.user_id = v_uid and ps.status = 'ACTIVE';
  perform app_private.assert_true(v_can_manage, 'Your partner account is not permitted to manage staff.');
  return app_private.create_staff_invite(v_uid, p_phone, 'PARTNER_DELIVERY_STAFF', p_display_name, v_partner, false);
end;
$$;

create or replace function public.partner_list_invites()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
begin
  v_uid := app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', si.id, 'phone', si.phone, 'display_name', si.display_name,
      'expires_at', si.expires_at, 'used_at', si.used_at, 'revoked_at', si.revoked_at,
      'created_at', si.created_at
    ) order by si.created_at desc)
    from public.staff_invites si
    where si.partner_id = v_partner
  ), '[]'::jsonb);
end;
$$;

create or replace function public.partner_revoke_invite(p_invite_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
  v_partner uuid;
begin
  v_uid := app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  update public.staff_invites
  set revoked_at = now()
  where id = p_invite_id and partner_id = v_partner and used_at is null and revoked_at is null;
  perform app_private.assert_true(found, 'Invitation not found.');
  perform app_private.write_audit('PARTNER_INVITE_REVOKED', 'staff_invite', p_invite_id, null, null, 'PARTNER_APP', v_uid);
  return jsonb_build_object('revoked', true);
end;
$$;

create or replace function public.partner_list_tasks()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_partner uuid;
begin
  perform app_private.require_partner_admin();
  v_partner := public.current_partner_id();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'task_type', x.task_type, 'assignment_id', x.assignment_id,
      'staff_name', x.staff_name, 'status', x.status, 'created_at', x.created_at,
      'order_id', x.order_id, 'order_number', x.order_number,
      'shipment_id', x.shipment_id, 'shipment_number', x.shipment_number,
      'pickup_number', x.pickup_number, 'town_name', x.town_name,
      'pincode', x.pincode, 'cod_amount_paise', x.cod_amount_paise
    ) order by x.created_at desc)
    from (
      select 'PICKUP' as task_type, pa.id as assignment_id, ps.display_name as staff_name,
        pa.status, pa.assigned_at as created_at, o.id as order_id, o.order_number,
        s.id as shipment_id, s.shipment_number, pk.pickup_number, o.town_name,
        o.pincode, 0::bigint as cod_amount_paise
      from public.pickup_assignments pa
      join public.partner_staff ps on ps.id = pa.partner_staff_id
      join public.pickup_requests pk on pk.id = pa.pickup_request_id
      join public.orders o on o.id = pk.order_id
      join public.shipments s on s.id = pk.shipment_id
      where pa.partner_id = v_partner
      union all
      select 'DELIVERY', da.id, ps.display_name, da.status, da.assigned_at,
        o.id, o.order_number, s.id, s.shipment_number, null, o.town_name,
        o.pincode, o.cod_amount_paise
      from public.delivery_assignments da
      join public.partner_staff ps on ps.id = da.partner_staff_id
      join public.shipments s on s.id = da.shipment_id
      join public.orders o on o.id = s.order_id
      where da.partner_id = v_partner
    ) x
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Towns, PIN codes and coverage
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_towns()
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
      'id', t.id, 'name', t.name, 'district', t.district, 'state', t.state,
      'latitude', t.latitude, 'longitude', t.longitude, 'is_active', t.is_active,
      'pincodes', coalesce((
        select jsonb_agg(jsonb_build_object('id', sp.id, 'pincode', sp.pincode, 'is_active', sp.is_active) order by sp.pincode)
        from public.serviceable_pincodes sp where sp.town_id = t.id
      ), '[]'::jsonb),
      'own_staff_covered', (
        select count(distinct sa.staff_user_id) from public.staff_service_areas sa where sa.town_id = t.id
      ),
      'partners_covered', (
        select count(distinct psa.partner_id) from public.partner_service_areas psa where psa.town_id = t.id
      )
    ) order by t.state, t.district, t.name)
    from public.towns t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_save_town(
  p_name text,
  p_district text,
  p_state text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_is_active boolean default true,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_id uuid;
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_name, ''))) between 2 and 120, 'Enter a town name.');
  perform app_private.assert_true(char_length(trim(coalesce(p_district, ''))) between 2 and 120, 'Enter a district.');
  perform app_private.assert_true(char_length(trim(coalesce(p_state, ''))) between 2 and 120, 'Enter a state.');
  if p_id is not null then
    select t.id into v_id from public.towns t where t.id = p_id;
    perform app_private.assert_true(v_id is not null, 'Town not found.');
  end if;
  if v_id is null then
    insert into public.towns (name, district, state, latitude, longitude, is_active)
    values (trim(p_name), trim(p_district), trim(p_state), p_latitude, p_longitude, coalesce(p_is_active, true))
    returning id into v_id;
  else
    update public.towns
    set name = trim(p_name), district = trim(p_district), state = trim(p_state),
        latitude = p_latitude, longitude = p_longitude, is_active = coalesce(p_is_active, true)
    where id = v_id;
  end if;
  perform app_private.write_audit(case when p_id is null then 'TOWN_CREATED' else 'TOWN_UPDATED' end,
    'town', v_id, null, jsonb_build_object('name', trim(p_name)), 'SELLER_APP', v_uid);
  return (select jsonb_build_object('id', id, 'name', name, 'district', district, 'state', state, 'is_active', is_active) from public.towns where id = v_id);
end;
$$;

create or replace function public.owner_add_serviceable_pincode(p_town_id uuid, p_pincode text, p_is_active boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_pin text := btrim(coalesce(p_pincode, ''));
  v_id uuid;
begin
  perform app_private.assert_true(public.is_valid_pincode(v_pin), 'Enter a valid 6-digit PIN code.');
  perform app_private.assert_true(exists (select 1 from public.towns t where t.id = p_town_id), 'Town not found.');
  insert into public.serviceable_pincodes (town_id, pincode, is_active)
  values (p_town_id, v_pin, coalesce(p_is_active, true))
  on conflict (town_id, pincode) do update set is_active = excluded.is_active
  returning id into v_id;
  perform app_private.write_audit('PINCODE_SERVICEABILITY_SET', 'serviceable_pincode', v_id, null,
    jsonb_build_object('town_id', p_town_id, 'pincode', v_pin, 'is_active', coalesce(p_is_active, true)), 'SELLER_APP', v_uid);
  return jsonb_build_object('id', v_id, 'pincode', v_pin, 'is_active', coalesce(p_is_active, true));
end;
$$;

create or replace function public.owner_set_pincode_active(p_pincode_id uuid, p_is_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
begin
  update public.serviceable_pincodes set is_active = coalesce(p_is_active, false) where id = p_pincode_id;
  perform app_private.assert_true(found, 'PIN code not found.');
  perform app_private.write_audit('PINCODE_ACTIVE_CHANGED', 'serviceable_pincode', p_pincode_id, null,
    jsonb_build_object('is_active', coalesce(p_is_active, false)), 'SELLER_APP', v_uid);
  return jsonb_build_object('id', p_pincode_id, 'is_active', coalesce(p_is_active, false));
end;
$$;

create or replace function public.owner_set_staff_coverage(p_staff_user_id uuid, p_areas jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_area jsonb;
  v_town uuid;
  v_pin text;
begin
  perform app_private.assert_true(exists (
    select 1 from public.staff_profiles sp where sp.user_id = p_staff_user_id
  ), 'Own delivery staff not found.');
  perform app_private.assert_true(jsonb_typeof(coalesce(p_areas, '[]'::jsonb)) = 'array', 'Coverage must be an array.');
  delete from public.staff_service_areas where staff_user_id = p_staff_user_id;
  for v_area in select * from jsonb_array_elements(coalesce(p_areas, '[]'::jsonb))
  loop
    v_town := (v_area ->> 'town_id')::uuid;
    v_pin := nullif(btrim(coalesce(v_area ->> 'pincode', '')), '');
    perform app_private.assert_true(exists (select 1 from public.towns t where t.id = v_town), 'Invalid town in coverage.');
    if v_pin is not null then
      perform app_private.assert_true(exists (
        select 1 from public.serviceable_pincodes sp
        where sp.town_id = v_town and sp.pincode = v_pin and sp.is_active
      ), 'PIN code is not serviceable for the selected town.');
    end if;
    insert into public.staff_service_areas (staff_user_id, town_id, pincode, created_by)
    values (p_staff_user_id, v_town, v_pin, v_uid)
    on conflict do nothing;
  end loop;
  perform app_private.write_audit('STAFF_COVERAGE_SET', 'staff', p_staff_user_id, null,
    jsonb_build_object('areas', p_areas), 'SELLER_APP', v_uid);
  return jsonb_build_object('staff_user_id', p_staff_user_id, 'area_count', (select count(*) from public.staff_service_areas where staff_user_id = p_staff_user_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create or replace function public.owner_get_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return jsonb_build_object(
    'business', app_private.get_setting('business', '{}'::jsonb),
    'commerce', app_private.get_setting('commerce', '{}'::jsonb),
    'policies', app_private.get_setting('policies', '{}'::jsonb),
    'logistics', app_private.get_setting('logistics', '{}'::jsonb),
    'public', public.get_public_settings(),
    'assignment_policies', coalesce((
      select jsonb_agg(to_jsonb(p) order by (p.town_id is not null), p.created_at)
      from public.assignment_policies p
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.owner_update_settings(p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_business jsonb := app_private.get_setting('business', '{}'::jsonb);
  v_commerce jsonb := app_private.get_setting('commerce', '{}'::jsonb);
  v_policies jsonb := app_private.get_setting('policies', '{}'::jsonb);
  v_logistics jsonb := app_private.get_setting('logistics', '{}'::jsonb);
  v_key text;
  v_value jsonb;
  v_timezone text;
  v_pickup_town uuid;
  v_pickup_pin text;
begin
  perform app_private.assert_true(jsonb_typeof(p_settings) = 'object', 'Settings must be an object.');
  for v_key in select jsonb_object_keys(p_settings) loop
    perform app_private.assert_true(v_key in ('business','commerce','policies','logistics'), 'Unknown settings section: ' || v_key);
  end loop;

  if p_settings ? 'business' then
    perform app_private.assert_true(jsonb_typeof(p_settings -> 'business') = 'object', 'Business settings must be an object.');
    v_business := v_business || (p_settings -> 'business');
    perform app_private.assert_true(
      jsonb_typeof(v_business -> 'legal_name') is null or jsonb_typeof(v_business -> 'legal_name') = 'string',
      'Legal name must be text.'
    );
    v_timezone := nullif(v_business ->> 'timezone', '');
    if v_timezone is not null then
      perform app_private.assert_true(exists (select 1 from pg_timezone_names where name = v_timezone), 'Invalid timezone.');
    end if;
    v_pickup_town := nullif(v_business ->> 'pickup_town_id', '')::uuid;
    v_pickup_pin := nullif(btrim(coalesce(v_business ->> 'pickup_pincode', '')), '');
    if v_pickup_pin is not null then
      perform app_private.assert_true(public.is_valid_pincode(v_pickup_pin), 'Pickup PIN code is invalid.');
    end if;
    if v_pickup_town is not null then
      perform app_private.assert_true(exists (select 1 from public.towns t where t.id = v_pickup_town), 'Pickup town not found.');
    end if;
    v_business := jsonb_build_object(
      'legal_name', coalesce(v_business ->> 'legal_name', ''),
      'display_name', coalesce(nullif(v_business ->> 'display_name', ''), 'IndiaBizz'),
      'address', coalesce(v_business ->> 'address', ''),
      'phone', coalesce(v_business ->> 'phone', ''),
      'email', coalesce(v_business ->> 'email', ''),
      'gstin', coalesce(v_business ->> 'gstin', ''),
      'support_phone', coalesce(v_business ->> 'support_phone', ''),
      'support_email', coalesce(v_business ->> 'support_email', ''),
      'timezone', coalesce(v_timezone, 'Asia/Kolkata'),
      'invoice_terms', coalesce(v_business ->> 'invoice_terms', ''),
      'pickup_town_id', coalesce(v_business ->> 'pickup_town_id', ''),
      'pickup_pincode', coalesce(v_business ->> 'pickup_pincode', '')
    );
  end if;

  if p_settings ? 'commerce' then
    perform app_private.assert_true(jsonb_typeof(p_settings -> 'commerce') = 'object', 'Commerce settings must be an object.');
    v_commerce := v_commerce || (p_settings -> 'commerce');
    perform app_private.assert_true(
      jsonb_typeof(v_commerce -> 'tax_enabled') is null or jsonb_typeof(v_commerce -> 'tax_enabled') = 'boolean',
      'Tax enabled must be boolean.'
    );
    perform app_private.assert_true(
      jsonb_typeof(v_commerce -> 'shipping_fee_paise') is null or jsonb_typeof(v_commerce -> 'shipping_fee_paise') = 'number',
      'Shipping fee must be a number in paise.'
    );
    perform app_private.assert_true(
      jsonb_typeof(v_commerce -> 'free_shipping_threshold_paise') is null or jsonb_typeof(v_commerce -> 'free_shipping_threshold_paise') = 'number',
      'Free shipping threshold must be a number in paise.'
    );
    perform app_private.assert_true(
      jsonb_typeof(v_commerce -> 'default_tax_rate_bps') is null or jsonb_typeof(v_commerce -> 'default_tax_rate_bps') = 'number',
      'Tax rate must be numeric basis points.'
    );
    v_commerce := jsonb_build_object(
      'tax_enabled', coalesce((v_commerce ->> 'tax_enabled')::boolean, false),
      'default_tax_rate_bps', coalesce((v_commerce ->> 'default_tax_rate_bps')::integer, 0),
      'shipping_fee_paise', coalesce((v_commerce ->> 'shipping_fee_paise')::bigint, 0),
      'free_shipping_threshold_paise', coalesce((v_commerce ->> 'free_shipping_threshold_paise')::bigint, 0)
    );
    perform app_private.assert_true((v_commerce ->> 'shipping_fee_paise')::bigint >= 0, 'Shipping fee cannot be negative.');
    perform app_private.assert_true((v_commerce ->> 'free_shipping_threshold_paise')::bigint >= 0, 'Free shipping threshold cannot be negative.');
    perform app_private.assert_true((v_commerce ->> 'default_tax_rate_bps')::integer between 0 and 5000, 'Tax rate must be between 0 and 50%.');
  end if;

  if p_settings ? 'policies' then
    perform app_private.assert_true(jsonb_typeof(p_settings -> 'policies') = 'object', 'Policy settings must be an object.');
    v_policies := v_policies || (p_settings -> 'policies');
    v_policies := jsonb_build_object(
      'cancellation_allowed_before_pickup', coalesce((v_policies ->> 'cancellation_allowed_before_pickup')::boolean, true),
      'return_window_days', coalesce((v_policies ->> 'return_window_days')::integer, 7)
    );
    perform app_private.assert_true((v_policies ->> 'return_window_days')::integer between 0 and 30, 'Return window must be between 0 and 30 days.');
  end if;

  if p_settings ? 'logistics' then
    perform app_private.assert_true(jsonb_typeof(p_settings -> 'logistics') = 'object', 'Logistics settings must be an object.');
    v_logistics := v_logistics || (p_settings -> 'logistics');
    v_logistics := jsonb_build_object(
      'auto_create_delivery_assignment', coalesce((v_logistics ->> 'auto_create_delivery_assignment')::boolean, true),
      'require_photo', coalesce((v_logistics ->> 'require_photo')::boolean, false),
      'max_delivery_attempts', coalesce((v_logistics ->> 'max_delivery_attempts')::integer, 3)
    );
    perform app_private.assert_true((v_logistics ->> 'max_delivery_attempts')::integer between 1 and 10, 'Maximum delivery attempts must be between 1 and 10.');
  end if;

  insert into public.app_settings (key, value, description, is_public, updated_by)
  values
    ('business', v_business, 'Business identity, invoice header and pickup location', true, v_uid),
    ('commerce', v_commerce, 'COD commerce pricing and tax configuration', true, v_uid),
    ('policies', v_policies, 'Cancellation and return policy', true, v_uid),
    ('logistics', v_logistics, 'Delivery proof and attempt configuration', false, v_uid)
  on conflict (key) do update
    set value = excluded.value,
        description = excluded.description,
        updated_by = excluded.updated_by,
        updated_at = now();

  perform app_private.write_audit('SETTINGS_UPDATED', 'app_settings', null, null,
    jsonb_build_object('sections', (select jsonb_agg(k) from jsonb_object_keys(p_settings) k)),
    'SELLER_APP', v_uid);
  return public.owner_get_settings();
end;
$$;

create or replace function public.owner_update_assignment_policy(p_town_id uuid, p_settings jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_id uuid;
begin
  perform app_private.assert_true(p_town_id is null or exists (select 1 from public.towns t where t.id = p_town_id), 'Town not found.');
  perform app_private.assert_true(jsonb_typeof(p_settings) = 'object', 'Policy must be an object.');
  select id into v_id from public.assignment_policies where town_id is not distinct from p_town_id;

  if v_id is null then
    insert into public.assignment_policies (
      town_id, auto_assign_enabled, manual_only, allow_manual_override,
      auto_create_delivery_assignment, offer_timeout_seconds, max_active_tasks_per_staff,
      prefer_own_team, weight_workload, weight_distance, candidate_limit,
      retry_on_rejection, updated_by
    ) values (
      p_town_id,
      coalesce((p_settings ->> 'auto_assign_enabled')::boolean, true),
      coalesce((p_settings ->> 'manual_only')::boolean, false),
      coalesce((p_settings ->> 'allow_manual_override')::boolean, true),
      coalesce((p_settings ->> 'auto_create_delivery_assignment')::boolean, true),
      coalesce((p_settings ->> 'offer_timeout_seconds')::integer, 300),
      coalesce((p_settings ->> 'max_active_tasks_per_staff')::integer, 10),
      coalesce((p_settings ->> 'prefer_own_team')::boolean, true),
      coalesce((p_settings ->> 'weight_workload')::numeric, 10),
      coalesce((p_settings ->> 'weight_distance')::numeric, 1),
      coalesce((p_settings ->> 'candidate_limit')::integer, 20),
      coalesce((p_settings ->> 'retry_on_rejection')::boolean, true),
      v_uid
    ) returning id into v_id;
  else
    update public.assignment_policies
    set auto_assign_enabled = coalesce((p_settings ->> 'auto_assign_enabled')::boolean, auto_assign_enabled),
        manual_only = coalesce((p_settings ->> 'manual_only')::boolean, manual_only),
        allow_manual_override = coalesce((p_settings ->> 'allow_manual_override')::boolean, allow_manual_override),
        auto_create_delivery_assignment = coalesce((p_settings ->> 'auto_create_delivery_assignment')::boolean, auto_create_delivery_assignment),
        offer_timeout_seconds = coalesce((p_settings ->> 'offer_timeout_seconds')::integer, offer_timeout_seconds),
        max_active_tasks_per_staff = coalesce((p_settings ->> 'max_active_tasks_per_staff')::integer, max_active_tasks_per_staff),
        prefer_own_team = coalesce((p_settings ->> 'prefer_own_team')::boolean, prefer_own_team),
        weight_workload = coalesce((p_settings ->> 'weight_workload')::numeric, weight_workload),
        weight_distance = coalesce((p_settings ->> 'weight_distance')::numeric, weight_distance),
        candidate_limit = coalesce((p_settings ->> 'candidate_limit')::integer, candidate_limit),
        retry_on_rejection = coalesce((p_settings ->> 'retry_on_rejection')::boolean, retry_on_rejection),
        updated_by = v_uid,
        updated_at = now()
    where id = v_id;
  end if;

  perform app_private.assert_true((select offer_timeout_seconds from public.assignment_policies where id = v_id) between 30 and 86400, 'Offer timeout must be between 30 and 86400 seconds.');
  perform app_private.assert_true((select max_active_tasks_per_staff from public.assignment_policies where id = v_id) between 1 and 200, 'Maximum active tasks is invalid.');
  perform app_private.assert_true((select candidate_limit from public.assignment_policies where id = v_id) between 1 and 200, 'Candidate limit is invalid.');
  perform app_private.write_audit('ASSIGNMENT_POLICY_UPDATED', 'assignment_policy', v_id, null,
    jsonb_build_object('town_id', p_town_id, 'settings', p_settings), 'SELLER_APP', v_uid);
  return (select to_jsonb(ap) from public.assignment_policies ap where ap.id = v_id);
end;
$$;
