-- IndiaBizz :: 0002 towns, profiles, staff, partners and coverage.

-- ---------------------------------------------------------------------------
-- Serviceable geography
-- ---------------------------------------------------------------------------
create table if not exists public.towns (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  district text not null check (length(trim(district)) between 2 and 120),
  state text not null check (length(trim(state)) between 2 and 120),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint towns_unique_name unique (name, district, state)
);

create table if not exists public.serviceable_pincodes (
  id uuid primary key default gen_random_uuid(),
  town_id uuid not null references public.towns(id) on delete restrict,
  pincode text not null check (public.is_valid_pincode(pincode)),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint serviceable_pincodes_unique unique (town_id, pincode)
);

create index if not exists idx_serviceable_pincodes_pincode
  on public.serviceable_pincodes (pincode) where is_active;
create index if not exists idx_serviceable_pincodes_town
  on public.serviceable_pincodes (town_id);

-- ---------------------------------------------------------------------------
-- Profiles. role/status are authoritative authorization data and are only
-- writable by privileged server-side functions (or the service role).
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  phone text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  full_name text not null default '' check (char_length(full_name) <= 160),
  email text check (email is null or char_length(email) <= 320),
  role public.user_role not null default 'CUSTOMER',
  status public.account_status not null default 'ACTIVE',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_profiles_phone on public.profiles (phone) where phone is not null;
create index if not exists idx_profiles_role on public.profiles (role) where status = 'ACTIVE';

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, phone, full_name, role, status)
  values (
    new.id,
    public.normalize_phone(new.phone),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), ''),
    'CUSTOMER',
    'ACTIVE'
  )
  on conflict (id) do update
    set phone = coalesce(excluded.phone, public.profiles.phone),
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Process-local guard used by trusted DEFINER functions. It prevents direct
-- SQL from changing role/status unless the service role is in use.
create or replace function app_private.guard_profile_privileges()
returns trigger
language plpgsql
as $$
begin
  if (new.role is distinct from old.role or new.status is distinct from old.status) then
    if coalesce(current_setting('indibizz.privileged', true), 'off') <> 'on'
       and coalesce(auth.role(), '') <> 'service_role' then
      raise exception using
        errcode = '42501',
        message = 'Profile role and status can only be changed by an authorized server operation.';
    end if;
  end if;
  if new.phone is distinct from old.phone
     and coalesce(current_setting('indibizz.privileged', true), 'off') <> 'on'
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'The verified phone number cannot be changed directly.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_profile_privileges on public.profiles;
create trigger trg_guard_profile_privileges
  before update on public.profiles
  for each row execute function app_private.guard_profile_privileges();

drop trigger if exists trg_profiles_updated_at on public.profiles;
create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- External delivery partner organizations
-- ---------------------------------------------------------------------------
create table if not exists public.delivery_partners (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 160),
  code text not null unique check (code ~ '^[A-Z0-9][A-Z0-9_-]{2,19}$'),
  contact_name text not null default '',
  phone text check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$'),
  email text,
  status public.partner_status not null default 'PENDING',
  cod_credit_limit_paise bigint not null default 0 check (cod_credit_limit_paise >= 0),
  settlement_cycle_days integer not null default 1 check (settlement_cycle_days between 0 and 30),
  notes text not null default '',
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_delivery_partners_status on public.delivery_partners (status);

-- Own IndiaBizz delivery personnel.
create table if not exists public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  employee_code text unique check (employee_code is null or employee_code ~ '^[A-Za-z0-9_-]{2,24}$'),
  display_name text not null check (char_length(trim(display_name)) between 2 and 160),
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  status public.staff_status not null default 'INVITED',
  capacity_per_day integer not null default 25 check (capacity_per_day between 1 and 500),
  is_available boolean not null default true,
  current_latitude double precision check (current_latitude between -90 and 90),
  current_longitude double precision check (current_longitude between -180 and 180),
  last_location_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_staff_profiles_status on public.staff_profiles (status, is_available);

-- Personnel belonging to an external partner organization.
create table if not exists public.partner_staff (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.delivery_partners(id) on delete cascade,
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 160),
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  status public.staff_status not null default 'INVITED',
  is_admin boolean not null default false,
  can_manage_partner_staff boolean not null default false,
  capacity_per_day integer not null default 25 check (capacity_per_day between 1 and 500),
  is_available boolean not null default true,
  current_latitude double precision check (current_latitude between -90 and 90),
  current_longitude double precision check (current_longitude between -180 and 180),
  last_location_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint partner_staff_unique_phone unique (partner_id, phone)
);

create index if not exists idx_partner_staff_partner on public.partner_staff (partner_id, status, is_available);

-- Private, single-use onboarding invitations. Only a hash of the activation
-- code is stored; the plaintext is returned once to the inviter.
create table if not exists public.staff_invites (
  id uuid primary key default gen_random_uuid(),
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  role public.user_role not null check (role in ('OWN_DELIVERY_STAFF','PARTNER_ADMIN','PARTNER_DELIVERY_STAFF')),
  partner_id uuid references public.delivery_partners(id) on delete restrict,
  display_name text not null check (char_length(trim(display_name)) between 2 and 160),
  can_manage_partner_staff boolean not null default false,
  invite_code_hash text not null,
  expires_at timestamptz not null default (now() + interval '7 days'),
  used_at timestamptz,
  used_by uuid references public.profiles(id),
  revoked_at timestamptz,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  constraint staff_invites_partner_scope check (
    (role = 'OWN_DELIVERY_STAFF' and partner_id is null)
    or (role in ('PARTNER_ADMIN','PARTNER_DELIVERY_STAFF') and partner_id is not null)
  )
);

create unique index if not exists uq_staff_invites_active_phone
  on public.staff_invites (phone)
  where used_at is null and revoked_at is null;
create index if not exists idx_staff_invites_partner on public.staff_invites (partner_id);

-- ---------------------------------------------------------------------------
-- Coverage: which town / PIN codes a person or partner can serve.
-- A NULL pincode means the whole town is covered.
-- ---------------------------------------------------------------------------
create table if not exists public.staff_service_areas (
  id uuid primary key default gen_random_uuid(),
  staff_user_id uuid not null references public.profiles(id) on delete cascade,
  town_id uuid not null references public.towns(id) on delete cascade,
  pincode text check (pincode is null or public.is_valid_pincode(pincode)),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

create unique index if not exists uq_staff_service_area
  on public.staff_service_areas (staff_user_id, town_id, coalesce(pincode, ''));
create index if not exists idx_staff_service_areas_lookup
  on public.staff_service_areas (town_id, pincode);

create table if not exists public.partner_service_areas (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.delivery_partners(id) on delete cascade,
  town_id uuid not null references public.towns(id) on delete cascade,
  pincode text check (pincode is null or public.is_valid_pincode(pincode)),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

create unique index if not exists uq_partner_service_area
  on public.partner_service_areas (partner_id, town_id, coalesce(pincode, ''));
create index if not exists idx_partner_service_areas_lookup
  on public.partner_service_areas (town_id, pincode);

-- ---------------------------------------------------------------------------
-- Device sessions / push token registration
-- ---------------------------------------------------------------------------
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  app_name text not null check (app_name in ('seller','delivery','customer','website')),
  platform public.device_platform not null,
  device_id text not null check (char_length(device_id) between 4 and 200),
  device_name text not null default '',
  push_token text,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists uq_user_devices_device
  on public.user_devices (user_id, app_name, device_id);
create index if not exists idx_user_devices_push_token on public.user_devices (push_token)
  where push_token is not null and revoked_at is null;

-- Service-role-only audit of OTP send requests made through the Edge proxy.
-- Only hashed identifiers are stored.
create table if not exists public.otp_request_log (
  id uuid primary key default gen_random_uuid(),
  phone_hash text not null,
  ip_hash text,
  purpose text not null check (purpose in ('customer','staff','seller')),
  outcome text not null default 'PENDING' check (outcome in ('PENDING','SENT','RATE_LIMITED','PROVIDER_ERROR','DISABLED','INVALID_PHONE')),
  error_code text,
  user_agent text,
  requested_at timestamptz not null default now()
);

create index if not exists idx_otp_request_log_phone on public.otp_request_log (phone_hash, requested_at desc);
create index if not exists idx_otp_request_log_ip on public.otp_request_log (ip_hash, requested_at desc);

drop trigger if exists trg_towns_updated_at on public.towns;
create trigger trg_towns_updated_at before update on public.towns
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_delivery_partners_updated_at on public.delivery_partners;
create trigger trg_delivery_partners_updated_at before update on public.delivery_partners
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_staff_profiles_updated_at on public.staff_profiles;
create trigger trg_staff_profiles_updated_at before update on public.staff_profiles
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_partner_staff_updated_at on public.partner_staff;
create trigger trg_partner_staff_updated_at before update on public.partner_staff
  for each row execute function public.touch_updated_at();
