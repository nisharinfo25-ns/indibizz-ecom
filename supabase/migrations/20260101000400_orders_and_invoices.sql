-- IndiaBizz :: 0005 orders and invoices.

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  status public.order_status not null default 'PENDING_APPROVAL',
  payment_method text not null default 'COD' check (payment_method = 'COD'),
  payment_status public.payment_status not null default 'PENDING',
  subtotal_paise bigint not null check (subtotal_paise >= 0),
  discount_paise bigint not null default 0 check (discount_paise >= 0),
  tax_paise bigint not null default 0 check (tax_paise >= 0),
  shipping_paise bigint not null default 0 check (shipping_paise >= 0),
  total_paise bigint not null check (total_paise >= 0),
  cod_amount_paise bigint not null default 0 check (cod_amount_paise >= 0),
  item_count integer not null check (item_count > 0),
  address_id uuid references public.addresses(id) on delete set null,
  recipient_name text not null,
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  line1 text not null,
  line2 text not null default '',
  landmark text not null default '',
  town_id uuid not null references public.towns(id) on delete restrict,
  town_name text not null,
  district text not null,
  state text not null,
  pincode text not null check (public.is_valid_pincode(pincode)),
  customer_note text not null default '' check (char_length(customer_note) <= 1000),
  idempotency_key text not null check (char_length(idempotency_key) between 8 and 100),
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejected_reason text,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  delivered_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orders_customer_idempotency unique (customer_id, idempotency_key),
  constraint orders_total_math check (
    total_paise = subtotal_paise - discount_paise + tax_paise + shipping_paise
  ),
  constraint orders_cod_not_above_total check (cod_amount_paise <= total_paise)
);

create index if not exists idx_orders_customer on public.orders (customer_id, created_at desc);
create index if not exists idx_orders_status on public.orders (status, created_at desc);
create index if not exists idx_orders_created on public.orders (created_at desc);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  sku text not null,
  hsn_code text,
  unit_price_paise bigint not null check (unit_price_paise >= 0),
  quantity integer not null check (quantity between 1 and 999),
  discount_paise bigint not null default 0 check (discount_paise >= 0),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 5000),
  tax_paise bigint not null default 0 check (tax_paise >= 0),
  line_total_paise bigint not null check (line_total_paise >= 0),
  created_at timestamptz not null default now(),
  constraint order_items_line_math check (
    line_total_paise = (unit_price_paise * quantity) - discount_paise + tax_paise
  ),
  constraint order_items_discount_valid check (discount_paise <= unit_price_paise * quantity)
);

create index if not exists idx_order_items_order on public.order_items (order_id);
create index if not exists idx_order_items_product on public.order_items (product_id);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  order_id uuid not null unique references public.orders(id) on delete restrict,
  status public.invoice_status not null default 'ISSUED',
  invoice_date date not null default (now() at time zone 'utc')::date,
  seller_name text not null,
  seller_address text not null,
  seller_phone text not null,
  seller_email text not null default '',
  seller_gstin text not null default '',
  buyer_name text not null,
  buyer_phone text not null,
  billing_address text not null,
  shipping_address text not null,
  subtotal_paise bigint not null check (subtotal_paise >= 0),
  discount_paise bigint not null default 0 check (discount_paise >= 0),
  tax_paise bigint not null default 0 check (tax_paise >= 0),
  shipping_paise bigint not null default 0 check (shipping_paise >= 0),
  total_paise bigint not null check (total_paise >= 0),
  cod_amount_paise bigint not null check (cod_amount_paise >= 0),
  payment_method text not null default 'Cash on Delivery',
  shipment_id uuid,
  pdf_storage_path text,
  issued_by uuid references public.profiles(id),
  issued_at timestamptz not null default now(),
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_invoices_date on public.invoices (invoice_date desc);

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.touch_updated_at();
