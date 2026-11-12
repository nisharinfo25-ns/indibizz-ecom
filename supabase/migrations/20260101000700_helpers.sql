-- IndiaBizz :: 0008 authorization, settings, notification and audit helpers.

-- ---------------------------------------------------------------------------
-- Trusted role resolution. Never read a role from JWT metadata.
-- ---------------------------------------------------------------------------
create or replace function app_private.current_profile_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid()
    and p.status = 'ACTIVE';
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select app_private.current_profile_role();
$$;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(app_private.current_profile_role() = 'OWNER', false);
$$;

create or replace function public.is_partner_admin_of(p_partner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.partner_staff ps
    join public.profiles p on p.id = ps.user_id
    where ps.user_id = auth.uid()
      and ps.partner_id = p_partner_id
      and ps.status = 'ACTIVE'
      and p.status = 'ACTIVE'
      and p.role = 'PARTNER_ADMIN'
  );
$$;

create or replace function public.current_partner_id()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select ps.partner_id
  from public.partner_staff ps
  join public.profiles p on p.id = ps.user_id
  where ps.user_id = auth.uid()
    and ps.status = 'ACTIVE'
    and p.status = 'ACTIVE'
    and p.role in ('PARTNER_ADMIN','PARTNER_DELIVERY_STAFF')
  limit 1;
$$;

create or replace function app_private.require_authenticated()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = v_uid and p.status = 'ACTIVE'
  ) then
    raise exception using errcode = '42501', message = 'This account is not active.';
  end if;
  return v_uid;
end;
$$;

create or replace function app_private.require_owner()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
begin
  v_uid := app_private.require_authenticated();
  if app_private.current_profile_role() is distinct from 'OWNER' then
    raise exception using errcode = '42501', message = 'Owner authorization required.';
  end if;
  return v_uid;
end;
$$;

create or replace function app_private.require_partner_admin()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid;
begin
  v_uid := app_private.require_authenticated();
  if app_private.current_profile_role() is distinct from 'PARTNER_ADMIN' then
    raise exception using errcode = '42501', message = 'Partner administrator authorization required.';
  end if;
  return v_uid;
end;
$$;

create or replace function app_private.staff_identity(p_user_id uuid)
returns table (
  staff_type public.staff_type,
  staff_profile_id uuid,
  partner_staff_id uuid,
  partner_id uuid,
  capacity_per_day integer,
  is_available boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    'OWN'::public.staff_type,
    sp.id,
    null::uuid,
    null::uuid,
    sp.capacity_per_day,
    sp.is_available
  from public.staff_profiles sp
  join public.profiles p on p.id = sp.user_id
  where sp.user_id = p_user_id
    and sp.status = 'ACTIVE'
    and p.status = 'ACTIVE'
    and p.role = 'OWN_DELIVERY_STAFF'
  union all
  select
    'PARTNER'::public.staff_type,
    null::uuid,
    ps.id,
    ps.partner_id,
    ps.capacity_per_day,
    ps.is_available
  from public.partner_staff ps
  join public.delivery_partners dp on dp.id = ps.partner_id and dp.status = 'APPROVED'
  join public.profiles p on p.id = ps.user_id
  where ps.user_id = p_user_id
    and ps.status = 'ACTIVE'
    and p.status = 'ACTIVE'
    and p.role in ('PARTNER_ADMIN','PARTNER_DELIVERY_STAFF');
$$;

create or replace function app_private.require_staff_identity()
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
declare
  v_uid uuid;
begin
  v_uid := app_private.require_authenticated();
  if not exists (select 1 from app_private.staff_identity(v_uid)) then
    raise exception using errcode = '42501', message = 'Active delivery staff authorization required.';
  end if;
  return query select * from app_private.staff_identity(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
create or replace function app_private.get_setting(p_key text, p_default jsonb default 'null'::jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select s.value from public.app_settings s where s.key = p_key), p_default);
$$;

create or replace function app_private.get_bool_setting(p_key text, p_default boolean)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((app_private.get_setting(p_key, to_jsonb(p_default)))::text::boolean, p_default);
$$;

create or replace function app_private.get_int_setting(p_key text, p_default bigint)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((app_private.get_setting(p_key, to_jsonb(p_default)))::text::bigint, p_default);
$$;

create or replace function public.get_public_settings()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb)
  from public.app_settings s
  where s.is_public;
$$;

-- ---------------------------------------------------------------------------
-- Audit trail writer
-- ---------------------------------------------------------------------------
create or replace function app_private.write_audit(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_before jsonb default null,
  p_after jsonb default null,
  p_source text default 'SERVER',
  p_actor uuid default auth.uid()
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.audit_logs (
    actor_id, actor_role, action, entity_type, entity_id, before_data, after_data, source
  )
  values (
    p_actor,
    (select p.role from public.profiles p where p.id = p_actor),
    p_action,
    p_entity_type,
    p_entity_id,
    p_before,
    p_after,
    p_source
  );
$$;

-- ---------------------------------------------------------------------------
-- Notification writer. In-app rows are always written. Push is a separate
-- best-effort dispatch step; no code marks a push as delivered without a
-- provider confirmation.
-- ---------------------------------------------------------------------------
create or replace function app_private.notify_user(
  p_recipient uuid,
  p_type public.notification_type,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  if p_recipient is null then
    return null;
  end if;
  insert into public.notifications (
    recipient_id, type, title, body, data, channel, delivery_status, dedupe_key
  )
  values (
    p_recipient, p_type, p_title, coalesce(p_body, ''), coalesce(p_data, '{}'::jsonb),
    'IN_APP', 'PENDING', p_dedupe_key
  )
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function app_private.notify_owner(
  p_type public.notification_type,
  p_title text,
  p_body text,
  p_data jsonb default '{}'::jsonb,
  p_dedupe_key text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_owner record;
begin
  for v_owner in
    select p.id from public.profiles p
    where p.role = 'OWNER' and p.status = 'ACTIVE'
  loop
    perform app_private.notify_user(
      v_owner.id,
      p_type,
      p_title,
      p_body,
      p_data,
      case when p_dedupe_key is null then null else p_dedupe_key || ':' || v_owner.id::text end
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- Shipment event writer
-- ---------------------------------------------------------------------------
create or replace function app_private.log_shipment_event(
  p_shipment_id uuid,
  p_event_type public.shipment_event_type,
  p_previous public.shipment_status,
  p_new public.shipment_status,
  p_source text default 'SYSTEM',
  p_actor uuid default auth.uid(),
  p_proof_reference text default null,
  p_location_text text default null,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  insert into public.shipment_events (
    shipment_id, event_type, previous_status, new_status, actor_id, actor_role,
    source, proof_reference, location_text, latitude, longitude, metadata
  )
  values (
    p_shipment_id, p_event_type, p_previous, p_new, p_actor,
    (select p.role from public.profiles p where p.id = p_actor),
    p_source, p_proof_reference, p_location_text, p_latitude, p_longitude,
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end;
$$;

-- Resolve the configured business invoice header. Raises if the owner has not
-- completed mandatory legal details, instead of inventing them.
create or replace function app_private.business_invoice_details()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_business jsonb := app_private.get_setting('business', '{}'::jsonb);
begin
  if coalesce(trim(v_business ->> 'legal_name'), '') = ''
     or coalesce(trim(v_business ->> 'address'), '') = ''
     or coalesce(trim(v_business ->> 'phone'), '') = '' then
    raise exception using
      errcode = 'P0001',
      message = 'Configure the legal business name, address and phone in Settings before approving orders or issuing invoices.';
  end if;
  return v_business;
end;
$$;
