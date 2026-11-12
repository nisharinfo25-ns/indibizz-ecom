-- Local-only Supabase compatibility shims for plain PostgreSQL validation.
-- Never used against a real Supabase project (which provides these objects).

do $$ begin create role anon nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin noinherit; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin noinherit bypassrls; exception when duplicate_object then null; end $$;

create schema if not exists auth;
create schema if not exists extensions;
create schema if not exists storage;
create schema if not exists realtime;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  phone text,
  email text,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role()
returns text language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('role', true), '')
  );
$$;

create or replace function auth.jwt()
returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$$;

-- pgcrypto shim: format-compatible with crypt()/gen_salt() verification flows.
create or replace function public.gen_random_bytes_compat()
returns bytea language sql volatile as $$
  select decode(md5(random()::text || clock_timestamp()::text), 'hex') || decode(md5(random()::text), 'hex');
$$;

create or replace function extensions.gen_salt(p_type text default 'bf', p_rounds integer default 6)
returns text language sql volatile as $$
  select '$shim$' || encode(public.gen_random_bytes_compat(), 'hex') || '$';
$$;

create or replace function extensions.crypt(p_password text, p_salt text)
returns text language sql immutable as $$
  with parts as (
    select substring(p_salt from '^\$shim\$[0-9a-f]+\$') as salt_prefix
  )
  select case
    when p_salt is null or p_password is null then null
    when (select salt_prefix from parts) is not null then
      (select salt_prefix from parts)
        || encode(sha256(convert_to((select salt_prefix from parts) || p_password, 'UTF8')), 'hex')
    else null
  end;
$$;

-- Storage stub matching the subset of columns used by our policies.
create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  file_size_limit bigint,
  allowed_mime_types text[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  metadata jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function storage.foldername(name text)
returns text[] language sql immutable as $$
  select string_to_array(name, '/');
$$;

alter table storage.objects enable row level security;

-- Supabase grants roles to schemas; mimic the relevant defaults.
grant usage on schema public, auth, storage, extensions to anon, authenticated, service_role;
grant select on auth.users to service_role;
grant all on all tables in schema storage to service_role;

do $$ begin
  create publication supabase_realtime;
exception when duplicate_object then null; end $$;

-- The embedded PostgreSQL build ships without compiled tzdata. Provide the
-- validation view only; actual timestamps in tests use UTC.
create or replace view pg_catalog.pg_timezone_names as
  select 'UTC'::text as name, 'UTC'::text as abbrev, interval '0' as utc_offset, false as is_dst
  union all select 'Etc/UTC', 'UTC', interval '0', false
  union all select 'Asia/Kolkata', 'IST', interval '5:30', false
  union all select 'Asia/Calcutta', 'IST', interval '5:30', false
  union all select 'Asia/Dubai', 'GST', interval '4:00', false
  union all select 'Asia/Singapore', 'SGT', interval '8:00', false
  union all select 'Europe/London', 'GMT', interval '0', false
  union all select 'America/New_York', 'EST', interval '-5:00', false;
