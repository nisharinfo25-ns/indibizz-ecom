-- IndiaBizz :: 0007 COD accounting, returns, notifications, audit and settings.

-- ---------------------------------------------------------------------------
-- COD settlement headers (declared by delivery staff, verified by OWNER only)
-- ---------------------------------------------------------------------------
create table if not exists public.cod_settlements (
  id uuid primary key default gen_random_uuid(),
  settlement_number text not null unique,
  staff_user_id uuid not null references public.profiles(id) on delete restrict,
  staff_type public.staff_type not null,
  staff_profile_id uuid references public.staff_profiles(id) on delete restrict,
  partner_staff_id uuid references public.partner_staff(id) on delete restrict,
  partner_id uuid references public.delivery_partners(id) on delete restrict,
  period_start timestamptz not null,
  period_end timestamptz not null,
  expected_paise bigint not null default 0 check (expected_paise >= 0),
  collected_paise bigint not null default 0 check (collected_paise >= 0),
  handed_over_paise bigint not null default 0 check (handed_over_paise >= 0),
  counted_paise bigint check (counted_paise is null or counted_paise >= 0),
  shortage_paise bigint not null default 0 check (shortage_paise >= 0),
  excess_paise bigint not null default 0 check (excess_paise >= 0),
  status public.cod_settlement_status not null default 'PENDING_VERIFICATION',
  note text not null default '',
  rejection_reason text,
  declared_at timestamptz not null default now(),
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  constraint cod_settlement_period check (period_end >= period_start),
  constraint cod_settlement_staff_scope check (
    (staff_type = 'OWN' and staff_profile_id is not null and partner_staff_id is null and partner_id is null)
    or
    (staff_type = 'PARTNER' and staff_profile_id is null and partner_staff_id is not null and partner_id is not null)
  ),
  constraint cod_settlement_variance_math check (
    shortage_paise = greatest(handed_over_paise - coalesce(counted_paise, handed_over_paise), 0)
    and excess_paise = greatest(coalesce(counted_paise, handed_over_paise) - handed_over_paise, 0)
  )
);

create index if not exists idx_cod_settlements_staff on public.cod_settlements (staff_user_id, status, declared_at desc);
create index if not exists idx_cod_settlements_status on public.cod_settlements (status, declared_at desc);

create table if not exists public.cod_transactions (
  id uuid primary key default gen_random_uuid(),
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  staff_user_id uuid references public.profiles(id) on delete restrict,
  partner_id uuid references public.delivery_partners(id) on delete restrict,
  settlement_id uuid references public.cod_settlements(id) on delete restrict,
  entry_type public.cod_entry_type not null,
  amount_paise bigint not null,
  description text not null default '',
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  idempotency_key text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint cod_transactions_sign check (
    (entry_type in ('EXPECTED','COLLECTED','HANDOVER_REVERSAL') and amount_paise >= 0)
    or (entry_type = 'HANDOVER' and amount_paise <= 0)
    or (entry_type = 'SETTLEMENT_CONFIRMED' and amount_paise = 0)
    or (entry_type = 'ADJUSTMENT')
  )
);

create index if not exists idx_cod_transactions_shipment on public.cod_transactions (shipment_id, created_at asc);
create index if not exists idx_cod_transactions_staff on public.cod_transactions (staff_user_id, entry_type);
create index if not exists idx_cod_transactions_settlement on public.cod_transactions (settlement_id);
create index if not exists idx_cod_transactions_created on public.cod_transactions (created_at desc);

create table if not exists public.cod_settlement_items (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid not null references public.cod_settlements(id) on delete cascade,
  shipment_id uuid not null references public.shipments(id) on delete restrict,
  expected_paise bigint not null check (expected_paise >= 0),
  collected_paise bigint not null check (collected_paise >= 0),
  created_at timestamptz not null default now(),
  constraint cod_settlement_items_unique unique (settlement_id, shipment_id)
);

create index if not exists idx_cod_settlement_items_shipment on public.cod_settlement_items (shipment_id);

-- ---------------------------------------------------------------------------
-- Customer return requests
-- ---------------------------------------------------------------------------
create table if not exists public.return_requests (
  id uuid primary key default gen_random_uuid(),
  return_number text not null unique,
  order_id uuid not null references public.orders(id) on delete restrict,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  shipment_id uuid references public.shipments(id) on delete set null,
  reason text not null check (char_length(trim(reason)) between 3 and 160),
  description text not null default '' check (char_length(description) <= 2000),
  evidence_path text,
  status public.return_status not null default 'REQUESTED',
  decided_by uuid references public.profiles(id),
  decided_at timestamptz,
  rejection_reason text,
  received_at timestamptz,
  resolution_note text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_return_requests_active_order
  on public.return_requests (order_id)
  where status in ('REQUESTED','APPROVED','IN_TRANSIT','RECEIVED');
create index if not exists idx_return_requests_customer on public.return_requests (customer_id, created_at desc);
create index if not exists idx_return_requests_status on public.return_requests (status, created_at desc);

-- ---------------------------------------------------------------------------
-- Notifications (in-app is authoritative; push is best-effort and tracked)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  type public.notification_type not null,
  title text not null check (char_length(title) between 1 and 200),
  body text not null default '' check (char_length(body) <= 2000),
  data jsonb not null default '{}'::jsonb,
  channel public.notification_channel not null default 'IN_APP',
  delivery_status public.notification_delivery_status not null default 'PENDING',
  provider_message_id text,
  failure_reason text,
  dedupe_key text unique,
  read_at timestamptz,
  pushed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_notifications_recipient
  on public.notifications (recipient_id, created_at desc);
create index if not exists idx_notifications_unread
  on public.notifications (recipient_id) where read_at is null;
create index if not exists idx_notifications_pending_push
  on public.notifications (created_at) where delivery_status = 'PENDING';

-- ---------------------------------------------------------------------------
-- Immutable audit trail
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  actor_role public.user_role,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  source text not null default 'SERVER',
  request_id text,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_created on public.audit_logs (created_at desc);
create index if not exists idx_audit_logs_entity on public.audit_logs (entity_type, entity_id, created_at desc);
create index if not exists idx_audit_logs_actor on public.audit_logs (actor_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key check (key ~ '^[a-z0-9_.]+$'),
  value jsonb not null,
  description text not null default '',
  is_public boolean not null default false,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.assignment_policies (
  id uuid primary key default gen_random_uuid(),
  town_id uuid references public.towns(id) on delete cascade,
  auto_assign_enabled boolean not null default true,
  manual_only boolean not null default false,
  allow_manual_override boolean not null default true,
  auto_create_delivery_assignment boolean not null default true,
  offer_timeout_seconds integer not null default 300 check (offer_timeout_seconds between 30 and 86400),
  max_active_tasks_per_staff integer not null default 10 check (max_active_tasks_per_staff between 1 and 200),
  prefer_own_team boolean not null default true,
  weight_workload numeric(6,2) not null default 10 check (weight_workload >= 0),
  weight_distance numeric(6,2) not null default 1 check (weight_distance >= 0),
  candidate_limit integer not null default 20 check (candidate_limit between 1 and 200),
  retry_on_rejection boolean not null default true,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create unique index if not exists uq_assignment_policy_town
  on public.assignment_policies (coalesce(town_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- ---------------------------------------------------------------------------
-- Immutability guards for financial/operational history
-- ---------------------------------------------------------------------------
create or replace function app_private.reject_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception using
    errcode = '42501',
    message = 'This record is immutable operational or financial history.';
end;
$$;

drop trigger if exists trg_inventory_movements_immutable on public.inventory_movements;
create trigger trg_inventory_movements_immutable
  before update or delete on public.inventory_movements
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_shipment_events_immutable on public.shipment_events;
create trigger trg_shipment_events_immutable
  before update or delete on public.shipment_events
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_barcode_scans_immutable on public.barcode_scans;
create trigger trg_barcode_scans_immutable
  before update or delete on public.barcode_scans
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_cod_transactions_immutable on public.cod_transactions;
create trigger trg_cod_transactions_immutable
  before update or delete on public.cod_transactions
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_pickup_verifications_immutable on public.pickup_verifications;
create trigger trg_pickup_verifications_immutable
  before update or delete on public.pickup_verifications
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_audit_logs_immutable on public.audit_logs;
create trigger trg_audit_logs_immutable
  before update or delete on public.audit_logs
  for each row execute function app_private.reject_mutation();

drop trigger if exists trg_return_requests_updated_at on public.return_requests;
create trigger trg_return_requests_updated_at before update on public.return_requests
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_assignment_policies_updated_at on public.assignment_policies;
create trigger trg_assignment_policies_updated_at before update on public.assignment_policies
  for each row execute function public.touch_updated_at();
