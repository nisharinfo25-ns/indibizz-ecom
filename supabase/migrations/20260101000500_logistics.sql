-- IndiaBizz :: 0006 shipments, packages, pickup verification and delivery.

create table if not exists public.shipments (
  id uuid primary key default gen_random_uuid(),
  shipment_number text not null unique,
  order_id uuid not null unique references public.orders(id) on delete restrict,
  status public.shipment_status not null default 'CREATED',
  expected_cod_paise bigint not null default 0 check (expected_cod_paise >= 0),
  package_count integer not null default 1 check (package_count between 1 and 50),
  weight_grams integer not null default 0 check (weight_grams >= 0),
  picked_up_at timestamptz,
  delivered_at timestamptz,
  returned_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_shipments_status on public.shipments (status, created_at desc);
create index if not exists idx_shipments_delivered on public.shipments (delivered_at) where delivered_at is not null;

create table if not exists public.packages (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  package_number text not null,
  package_code text not null unique,
  status public.package_status not null default 'PACKED',
  weight_grams integer not null default 0 check (weight_grams >= 0),
  is_sealed boolean not null default false,
  sealed_at timestamptz,
  sealed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint packages_number_unique unique (shipment_id, package_number),
  constraint packages_code_opaque check (package_code ~ '^ibpkg_[0-9a-f]{32}$')
);

create index if not exists idx_packages_shipment on public.packages (shipment_id);

create table if not exists public.pickup_requests (
  id uuid primary key default gen_random_uuid(),
  pickup_number text not null unique,
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  status public.pickup_status not null default 'REQUESTED',
  package_count_expected integer not null check (package_count_expected between 1 and 50),
  package_count_verified integer check (package_count_verified is null or package_count_verified between 1 and 50),
  condition public.package_condition not null default 'PENDING',
  failure_reason text,
  requested_by uuid not null references public.profiles(id),
  requested_at timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references public.profiles(id),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_pickup_requests_active_shipment
  on public.pickup_requests (shipment_id)
  where status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED');
create index if not exists idx_pickup_requests_status on public.pickup_requests (status, requested_at desc);
create index if not exists idx_pickup_requests_order on public.pickup_requests (order_id);

create table if not exists public.pickup_otp_challenges (
  id uuid primary key default gen_random_uuid(),
  pickup_request_id uuid not null unique references public.pickup_requests(id) on delete cascade,
  otp_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  last_sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.pickup_assignments (
  id uuid primary key default gen_random_uuid(),
  pickup_request_id uuid not null references public.pickup_requests(id) on delete cascade,
  staff_user_id uuid not null references public.profiles(id) on delete restrict,
  staff_type public.staff_type not null,
  staff_profile_id uuid references public.staff_profiles(id) on delete restrict,
  partner_staff_id uuid references public.partner_staff(id) on delete restrict,
  partner_id uuid references public.delivery_partners(id) on delete restrict,
  status public.assignment_status not null default 'PENDING',
  mode public.assignment_mode not null default 'AUTO',
  score numeric(12,4),
  rejection_reason text,
  assigned_by uuid references public.profiles(id),
  assigned_at timestamptz not null default now(),
  responded_at timestamptz,
  expires_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint pickup_assignment_staff_scope check (
    (staff_type = 'OWN' and staff_profile_id is not null and partner_staff_id is null and partner_id is null)
    or
    (staff_type = 'PARTNER' and staff_profile_id is null and partner_staff_id is not null and partner_id is not null)
  )
);

create unique index if not exists uq_pickup_assignment_active
  on public.pickup_assignments (pickup_request_id)
  where status in ('PENDING','ACCEPTED');
create index if not exists idx_pickup_assignment_staff
  on public.pickup_assignments (staff_user_id, status);
create index if not exists idx_pickup_assignment_partner
  on public.pickup_assignments (partner_id, status) where partner_id is not null;

create table if not exists public.delivery_assignments (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete cascade,
  pickup_assignment_id uuid references public.pickup_assignments(id) on delete set null,
  staff_user_id uuid not null references public.profiles(id) on delete restrict,
  staff_type public.staff_type not null,
  staff_profile_id uuid references public.staff_profiles(id) on delete restrict,
  partner_staff_id uuid references public.partner_staff(id) on delete restrict,
  partner_id uuid references public.delivery_partners(id) on delete restrict,
  status public.assignment_status not null default 'PENDING',
  mode public.assignment_mode not null default 'AUTO',
  rejection_reason text,
  assigned_by uuid references public.profiles(id),
  assigned_at timestamptz not null default now(),
  responded_at timestamptz,
  expires_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint delivery_assignment_staff_scope check (
    (staff_type = 'OWN' and staff_profile_id is not null and partner_staff_id is null and partner_id is null)
    or
    (staff_type = 'PARTNER' and staff_profile_id is null and partner_staff_id is not null and partner_id is not null)
  )
);

create unique index if not exists uq_delivery_assignment_active
  on public.delivery_assignments (shipment_id)
  where status in ('PENDING','ACCEPTED');
create index if not exists idx_delivery_assignment_staff
  on public.delivery_assignments (staff_user_id, status);
create index if not exists idx_delivery_assignment_partner
  on public.delivery_assignments (partner_id, status) where partner_id is not null;

create table if not exists public.delivery_otp_challenges (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null unique references public.shipments(id) on delete cascade,
  otp_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  last_sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.pickup_verifications (
  id uuid primary key default gen_random_uuid(),
  pickup_request_id uuid not null unique references public.pickup_requests(id) on delete restrict,
  assignment_id uuid not null unique references public.pickup_assignments(id) on delete restrict,
  verified_by uuid not null references public.profiles(id),
  package_count integer not null check (package_count between 1 and 50),
  condition public.package_condition not null check (condition = 'GOOD'),
  otp_verified boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  verified_at timestamptz not null default now()
);

create table if not exists public.pickup_manifests (
  id uuid primary key default gen_random_uuid(),
  manifest_number text not null unique,
  pickup_request_id uuid not null references public.pickup_requests(id) on delete restrict,
  package_ids uuid[] not null,
  package_count integer not null check (package_count > 0),
  storage_path text,
  generated_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.barcode_scans (
  id uuid primary key default gen_random_uuid(),
  package_id uuid references public.packages(id) on delete restrict,
  shipment_id uuid references public.shipments(id) on delete restrict,
  pickup_request_id uuid references public.pickup_requests(id) on delete restrict,
  assignment_id uuid references public.pickup_assignments(id) on delete restrict,
  scanned_by uuid not null references public.profiles(id) on delete restrict,
  scan_context public.scan_context not null,
  raw_code text not null,
  result public.scan_result not null,
  message text not null default '',
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  device_id text,
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  scanned_at timestamptz not null default now()
);

create index if not exists idx_barcode_scans_package on public.barcode_scans (package_id, scanned_at desc);
create index if not exists idx_barcode_scans_pickup on public.barcode_scans (pickup_request_id, result);
create index if not exists idx_barcode_scans_shipment on public.barcode_scans (shipment_id, scanned_at desc);

create table if not exists public.shipment_events (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  event_type public.shipment_event_type not null,
  previous_status public.shipment_status,
  new_status public.shipment_status,
  actor_id uuid references public.profiles(id) on delete set null,
  actor_role public.user_role,
  source text not null check (source in ('SYSTEM','SELLER_APP','DELIVERY_APP','CUSTOMER_APP','WEBSITE','ADMIN','CRON')),
  location_text text,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  proof_reference text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_shipment_events_shipment on public.shipment_events (shipment_id, created_at asc);
create index if not exists idx_shipment_events_type on public.shipment_events (event_type, created_at desc);

create table if not exists public.delivery_proofs (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  package_id uuid references public.packages(id) on delete set null,
  proof_type public.delivery_proof_type not null,
  storage_path text,
  otp_verified boolean not null default false,
  recipient_name text not null default '',
  note text not null default '',
  captured_by uuid not null references public.profiles(id) on delete restrict,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  metadata jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default now()
);

create index if not exists idx_delivery_proofs_shipment on public.delivery_proofs (shipment_id);

create table if not exists public.delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  assignment_id uuid not null references public.delivery_assignments(id) on delete restrict,
  attempt_number integer not null check (attempt_number > 0),
  reason public.delivery_failure_reason not null,
  notes text not null default '',
  attempted_by uuid not null references public.profiles(id) on delete restrict,
  attempted_at timestamptz not null default now(),
  next_retry_at timestamptz,
  constraint delivery_attempts_unique_number unique (shipment_id, attempt_number)
);

create index if not exists idx_delivery_attempts_shipment on public.delivery_attempts (shipment_id, attempted_at desc);

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'invoices_shipment_fk'
  ) then
    alter table public.invoices
      add constraint invoices_shipment_fk
      foreign key (shipment_id) references public.shipments(id) on delete set null;
  end if;
end $$;

drop trigger if exists trg_shipments_updated_at on public.shipments;
create trigger trg_shipments_updated_at before update on public.shipments
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_packages_updated_at on public.packages;
create trigger trg_packages_updated_at before update on public.packages
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_pickup_requests_updated_at on public.pickup_requests;
create trigger trg_pickup_requests_updated_at before update on public.pickup_requests
  for each row execute function public.touch_updated_at();
