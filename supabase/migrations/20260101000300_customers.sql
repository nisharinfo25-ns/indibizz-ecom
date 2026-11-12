-- IndiaBizz :: 0004 customer addresses and server-side cart.

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  label text not null default 'Home' check (char_length(trim(label)) between 1 and 40),
  recipient_name text not null check (char_length(trim(recipient_name)) between 2 and 160),
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  line1 text not null check (char_length(trim(line1)) between 3 and 250),
  line2 text not null default '' check (char_length(line2) <= 250),
  landmark text not null default '' check (char_length(landmark) <= 160),
  town_id uuid not null references public.towns(id) on delete restrict,
  pincode text not null check (public.is_valid_pincode(pincode)),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists uq_addresses_default
  on public.addresses (customer_id) where is_default and deleted_at is null;
create index if not exists idx_addresses_customer
  on public.addresses (customer_id) where deleted_at is null;

drop trigger if exists trg_addresses_updated_at on public.addresses;
create trigger trg_addresses_updated_at before update on public.addresses
  for each row execute function public.touch_updated_at();

create table if not exists public.carts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.cart_items (
  id uuid primary key default gen_random_uuid(),
  cart_id uuid not null references public.carts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity integer not null check (quantity between 1 and 99),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cart_items_unique_product unique (cart_id, product_id)
);

create index if not exists idx_cart_items_cart on public.cart_items (cart_id);

drop trigger if exists trg_carts_updated_at on public.carts;
create trigger trg_carts_updated_at before update on public.carts
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_cart_items_updated_at on public.cart_items;
create trigger trg_cart_items_updated_at before update on public.cart_items
  for each row execute function public.touch_updated_at();
