-- IndiaBizz :: 0003 catalogue, product media and inventory ledger.

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text not null default '',
  image_path text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

create index if not exists idx_categories_active on public.categories (is_active, sort_order);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null check (char_length(trim(name)) between 2 and 200),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text not null default '',
  sku text not null unique check (char_length(trim(sku)) between 2 and 64),
  price_paise bigint not null check (price_paise >= 0),
  compare_at_price_paise bigint check (compare_at_price_paise is null or compare_at_price_paise >= price_paise),
  tax_rate_bps integer not null default 0 check (tax_rate_bps between 0 and 5000),
  hsn_code text check (hsn_code is null or hsn_code ~ '^[0-9]{4,8}$'),
  weight_grams integer not null default 0 check (weight_grams between 0 and 1000000),
  status public.product_status not null default 'DRAFT',
  is_featured boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_products_status on public.products (status, created_at desc);
create index if not exists idx_products_category on public.products (category_id, status);
create index if not exists idx_products_name_search on public.products (lower(name));
create index if not exists idx_products_featured on public.products (is_featured) where status = 'ACTIVE' and is_featured;

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  storage_path text not null check (char_length(storage_path) between 3 and 500),
  alt_text text not null default '',
  sort_order integer not null default 0,
  is_primary boolean not null default false,
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id)
);

create unique index if not exists uq_product_images_primary
  on public.product_images (product_id) where is_primary;
create index if not exists idx_product_images_product on public.product_images (product_id, sort_order);

create table if not exists public.inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null unique references public.products(id) on delete restrict,
  quantity_on_hand integer not null default 0 check (quantity_on_hand >= 0),
  quantity_reserved integer not null default 0 check (quantity_reserved >= 0),
  low_stock_threshold integer not null default 5 check (low_stock_threshold >= 0),
  updated_at timestamptz not null default now(),
  constraint inventory_reserved_not_above_on_hand check (quantity_reserved <= quantity_on_hand)
);

create index if not exists idx_inventory_low_stock
  on public.inventory ((quantity_on_hand - quantity_reserved))
  where quantity_on_hand <= low_stock_threshold;

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type public.stock_movement_type not null,
  quantity_delta integer not null default 0,
  reserved_delta integer not null default 0,
  on_hand_after integer not null check (on_hand_after >= 0),
  reserved_after integer not null check (reserved_after >= 0),
  reference_type text,
  reference_id uuid,
  reason text not null default '',
  actor_id uuid references public.profiles(id),
  idempotency_key text unique,
  created_at timestamptz not null default now(),
  constraint inventory_movement_nonzero check (quantity_delta <> 0 or reserved_delta <> 0)
);

create index if not exists idx_inventory_movements_product
  on public.inventory_movements (product_id, created_at desc);
create index if not exists idx_inventory_movements_reference
  on public.inventory_movements (reference_type, reference_id);

drop trigger if exists trg_categories_updated_at on public.categories;
create trigger trg_categories_updated_at before update on public.categories
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.touch_updated_at();

-- Public catalogue projection. It exposes customer-safe fields plus the
-- sellable availability quantity, but never cost, reservations or internal
-- inventory identifiers.
create or replace view public.catalog_products
with (security_invoker = false)
as
select
  p.id,
  p.name,
  p.slug,
  p.description,
  p.category_id,
  c.name as category_name,
  c.slug as category_slug,
  p.sku,
  p.price_paise,
  p.compare_at_price_paise,
  p.tax_rate_bps,
  p.hsn_code,
  p.weight_grams,
  p.is_featured,
  p.created_at,
  (
    select pi.storage_path
    from public.product_images pi
    where pi.product_id = p.id and pi.is_public
    order by pi.is_primary desc, pi.sort_order asc, pi.created_at asc
    limit 1
  ) as primary_image_path,
  coalesce(i.quantity_on_hand - i.quantity_reserved, 0) as available_quantity,
  coalesce(i.quantity_on_hand - i.quantity_reserved, 0) > 0 as in_stock
from public.products p
join public.categories c on c.id = p.category_id and c.is_active
left join public.inventory i on i.product_id = p.id
where p.status = 'ACTIVE';

comment on view public.catalog_products is
  'Customer-visible active catalogue with sellable quantity and stock flag. Internal inventory, reservations and costs remain protected.';
