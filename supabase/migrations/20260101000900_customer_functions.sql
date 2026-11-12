-- IndiaBizz :: 0010 customer profile, address, cart, checkout, orders, returns.

-- ---------------------------------------------------------------------------
-- Profile and serviceability
-- ---------------------------------------------------------------------------
create or replace function public.get_my_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  return (
    select jsonb_build_object(
      'id', p.id,
      'phone', p.phone,
      'full_name', p.full_name,
      'email', p.email,
      'role', p.role,
      'status', p.status,
      'created_at', p.created_at
    )
    from public.profiles p
    where p.id = v_uid
  );
end;
$$;

create or replace function public.update_my_profile(
  p_full_name text,
  p_email text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  perform app_private.assert_true(
    p_full_name is not null and char_length(trim(p_full_name)) between 2 and 160,
    'Enter a valid full name.'
  );
  perform app_private.assert_true(
    p_email is null or p_email = '' or p_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$',
    'Enter a valid email address.'
  );
  update public.profiles
  set full_name = trim(p_full_name),
      email = nullif(trim(coalesce(p_email, '')), '')
  where id = v_uid;
  perform app_private.write_audit('PROFILE_UPDATED', 'profile', v_uid, null,
    jsonb_build_object('full_name', trim(p_full_name)), 'CUSTOMER_APP');
  return public.get_my_profile();
end;
$$;

create or replace function public.check_serviceability(
  p_pincode text,
  p_town_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_pin text := btrim(coalesce(p_pincode, ''));
  v_towns jsonb;
begin
  if not public.is_valid_pincode(v_pin) then
    return jsonb_build_object('serviceable', false, 'towns', '[]'::jsonb, 'message', 'Enter a valid 6-digit PIN code.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'town_id', t.id,
    'town_name', t.name,
    'district', t.district,
    'state', t.state,
    'pincode', sp.pincode
  )), '[]'::jsonb)
  into v_towns
  from public.serviceable_pincodes sp
  join public.towns t on t.id = sp.town_id
  where sp.pincode = v_pin
    and sp.is_active
    and t.is_active
    and (p_town_id is null or t.id = p_town_id);

  return jsonb_build_object(
    'serviceable', jsonb_array_length(v_towns) > 0,
    'towns', v_towns,
    'message', case when jsonb_array_length(v_towns) > 0
      then 'Delivery is available for this PIN code.'
      else 'We do not deliver to this PIN code yet.' end
  );
end;
$$;

create or replace function public.list_serviceable_towns()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(row_json order by town_name), '[]'::jsonb)
  from (
    select
      t.name as town_name,
      jsonb_build_object(
        'id', t.id,
        'name', t.name,
        'district', t.district,
        'state', t.state,
        'pincodes', coalesce((
          select jsonb_agg(sp.pincode order by sp.pincode)
          from public.serviceable_pincodes sp
          where sp.town_id = t.id and sp.is_active
        ), '[]'::jsonb)
      ) as row_json
    from public.towns t
    where t.is_active
  ) x;
$$;

-- ---------------------------------------------------------------------------
-- Addresses
-- ---------------------------------------------------------------------------
create or replace function app_private.validate_address_town(p_town_id uuid, p_pincode text)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.assert_true(public.is_valid_pincode(p_pincode), 'Enter a valid 6-digit PIN code.');
  perform app_private.assert_true(exists (
    select 1 from public.towns t where t.id = p_town_id and t.is_active
  ), 'Select a valid delivery town.');
  perform app_private.assert_true(exists (
    select 1 from public.serviceable_pincodes sp
    where sp.town_id = p_town_id and sp.pincode = p_pincode and sp.is_active
  ), 'This town and PIN code combination is not serviceable.');
end;
$$;

create or replace function public.list_my_addresses()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id,
      'label', a.label,
      'recipient_name', a.recipient_name,
      'phone', a.phone,
      'line1', a.line1,
      'line2', a.line2,
      'landmark', a.landmark,
      'town_id', a.town_id,
      'town_name', t.name,
      'district', t.district,
      'state', t.state,
      'pincode', a.pincode,
      'is_default', a.is_default
    ) order by a.is_default desc, a.created_at desc)
    from public.addresses a
    join public.towns t on t.id = a.town_id
    where a.customer_id = v_uid and a.deleted_at is null
  ), '[]'::jsonb);
end;
$$;

create or replace function public.save_my_address(
  p_label text,
  p_recipient_name text,
  p_phone text,
  p_line1 text,
  p_line2 text,
  p_landmark text,
  p_town_id uuid,
  p_pincode text,
  p_is_default boolean default false,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_phone text := public.normalize_phone(p_phone);
  v_has_addresses boolean;
  v_id uuid;
  v_default boolean := coalesce(p_is_default, false);
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_label, ''))) between 1 and 40, 'Enter an address label.');
  perform app_private.assert_true(char_length(trim(coalesce(p_recipient_name, ''))) between 2 and 160, 'Enter the recipient name.');
  perform app_private.assert_true(public.is_valid_phone(v_phone), 'Enter a valid mobile number.');
  perform app_private.assert_true(char_length(trim(coalesce(p_line1, ''))) between 3 and 250, 'Enter the delivery address.');
  perform app_private.assert_true(char_length(coalesce(p_line2, '')) <= 250, 'Address line 2 is too long.');
  perform app_private.assert_true(char_length(coalesce(p_landmark, '')) <= 160, 'Landmark is too long.');
  perform app_private.validate_address_town(p_town_id, btrim(p_pincode));

  select exists (
    select 1 from public.addresses a
    where a.customer_id = v_uid and a.deleted_at is null
  ) into v_has_addresses;

  if p_id is not null then
    select a.id into v_id
    from public.addresses a
    where a.id = p_id and a.customer_id = v_uid and a.deleted_at is null
    for update;
    perform app_private.assert_true(v_id is not null, 'Address not found.');
  end if;

  if v_default then
    update public.addresses
    set is_default = false
    where customer_id = v_uid and is_default and deleted_at is null;
  end if;

  if v_id is null then
    insert into public.addresses (
      customer_id, label, recipient_name, phone, line1, line2, landmark,
      town_id, pincode, is_default
    ) values (
      v_uid, trim(p_label), trim(p_recipient_name), v_phone, trim(p_line1),
      trim(coalesce(p_line2, '')), trim(coalesce(p_landmark, '')), p_town_id,
      btrim(p_pincode), v_default or not v_has_addresses
    )
    returning id into v_id;
  else
    update public.addresses
    set label = trim(p_label),
        recipient_name = trim(p_recipient_name),
        phone = v_phone,
        line1 = trim(p_line1),
        line2 = trim(coalesce(p_line2, '')),
        landmark = trim(coalesce(p_landmark, '')),
        town_id = p_town_id,
        pincode = btrim(p_pincode),
        is_default = case when v_default then true else is_default end
    where id = v_id;
  end if;

  perform app_private.write_audit(
    case when p_id is null then 'ADDRESS_CREATED' else 'ADDRESS_UPDATED' end,
    'address', v_id, null, jsonb_build_object('pincode', btrim(p_pincode)),
    'CUSTOMER_APP', v_uid
  );

  return (
    select jsonb_build_object(
      'id', a.id, 'label', a.label, 'recipient_name', a.recipient_name,
      'phone', a.phone, 'line1', a.line1, 'line2', a.line2,
      'landmark', a.landmark, 'town_id', a.town_id, 'town_name', t.name,
      'district', t.district, 'state', t.state, 'pincode', a.pincode,
      'is_default', a.is_default
    )
    from public.addresses a
    join public.towns t on t.id = a.town_id
    where a.id = v_id
  );
end;
$$;

create or replace function public.delete_my_address(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_was_default boolean;
begin
  select is_default into v_was_default
  from public.addresses
  where id = p_id and customer_id = v_uid and deleted_at is null
  for update;
  perform app_private.assert_true(v_was_default is not null, 'Address not found.');

  update public.addresses set deleted_at = now(), is_default = false where id = p_id;

  if v_was_default then
    update public.addresses
    set is_default = true
    where id = (
      select a.id from public.addresses a
      where a.customer_id = v_uid and a.deleted_at is null
      order by a.created_at desc limit 1
    );
  end if;

  perform app_private.write_audit('ADDRESS_DELETED', 'address', p_id, null, null, 'CUSTOMER_APP', v_uid);
  return jsonb_build_object('deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Cart
-- ---------------------------------------------------------------------------
create or replace function app_private.ensure_cart(p_customer uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
begin
  insert into public.carts (customer_id) values (p_customer)
  on conflict (customer_id) do nothing;
  select c.id into v_id from public.carts c where c.customer_id = p_customer;
  return v_id;
end;
$$;

create or replace function app_private.cart_payload(p_customer uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_items jsonb;
  v_subtotal bigint;
  v_count integer;
begin
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'product_id', ci.product_id,
      'name', p.name,
      'slug', p.slug,
      'sku', p.sku,
      'quantity', ci.quantity,
      'unit_price_paise', p.price_paise,
      'line_subtotal_paise', p.price_paise * ci.quantity,
      'tax_rate_bps', p.tax_rate_bps,
      'available_quantity', greatest(coalesce(i.quantity_on_hand - i.quantity_reserved, 0), 0),
      'is_available', p.status = 'ACTIVE' and coalesce(i.quantity_on_hand - i.quantity_reserved, 0) >= ci.quantity,
      'primary_image_path', (
        select pi.storage_path from public.product_images pi
        where pi.product_id = p.id and pi.is_public
        order by pi.is_primary desc, pi.sort_order asc limit 1
      )
    ) order by ci.created_at), '[]'::jsonb),
    coalesce(sum(p.price_paise * ci.quantity), 0)::bigint,
    coalesce(sum(ci.quantity), 0)::integer
  into v_items, v_subtotal, v_count
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  left join public.inventory i on i.product_id = p.id
  where ci.cart_id = (select c.id from public.carts c where c.customer_id = p_customer);

  return jsonb_build_object(
    'items', coalesce(v_items, '[]'::jsonb),
    'subtotal_paise', v_subtotal,
    'item_count', v_count
  );
end;
$$;

create or replace function public.get_my_cart()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  return app_private.cart_payload(v_uid);
end;
$$;

create or replace function public.cart_add_item(p_product_id uuid, p_quantity integer default 1)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_cart uuid;
  v_available integer;
  v_existing integer;
  v_qty integer;
begin
  perform app_private.assert_true(p_quantity between 1 and 99, 'Quantity must be between 1 and 99.');
  select coalesce(i.quantity_on_hand - i.quantity_reserved, 0)
  into v_available
  from public.inventory i
  where i.product_id = p_product_id;
  perform app_private.assert_true(exists (
    select 1 from public.products p where p.id = p_product_id and p.status = 'ACTIVE'
  ), 'This product is not available.');
  perform app_private.assert_true(coalesce(v_available, 0) > 0, 'This product is out of stock.');

  v_cart := app_private.ensure_cart(v_uid);

  select ci.quantity into v_existing
  from public.cart_items ci
  where ci.cart_id = v_cart and ci.product_id = p_product_id
  for update;
  v_qty := coalesce(v_existing, 0) + p_quantity;
  perform app_private.assert_true(v_qty <= 99, 'Maximum quantity per product is 99.');
  perform app_private.assert_true(v_qty <= v_available, 'Requested quantity is not in stock.');

  insert into public.cart_items (cart_id, product_id, quantity)
  values (v_cart, p_product_id, v_qty)
  on conflict (cart_id, product_id) do update set quantity = excluded.quantity;

  return app_private.cart_payload(v_uid);
end;
$$;

create or replace function public.cart_set_quantity(p_product_id uuid, p_quantity integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_cart uuid := app_private.ensure_cart(v_uid);
  v_available integer;
begin
  perform app_private.assert_true(p_quantity between 0 and 99, 'Quantity must be between 0 and 99.');
  if p_quantity = 0 then
    delete from public.cart_items where cart_id = v_cart and product_id = p_product_id;
    return app_private.cart_payload(v_uid);
  end if;
  select coalesce(i.quantity_on_hand - i.quantity_reserved, 0)
  into v_available from public.inventory i where i.product_id = p_product_id;
  perform app_private.assert_true(p_quantity <= coalesce(v_available, 0), 'Requested quantity is not in stock.');
  insert into public.cart_items (cart_id, product_id, quantity)
  values (v_cart, p_product_id, p_quantity)
  on conflict (cart_id, product_id) do update set quantity = excluded.quantity;
  return app_private.cart_payload(v_uid);
end;
$$;

create or replace function public.cart_remove_item(p_product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  delete from public.cart_items
  where cart_id = (select c.id from public.carts c where c.customer_id = v_uid)
    and product_id = p_product_id;
  return app_private.cart_payload(v_uid);
end;
$$;

create or replace function public.cart_clear()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  delete from public.cart_items
  where cart_id = (select c.id from public.carts c where c.customer_id = v_uid);
  return app_private.cart_payload(v_uid);
end;
$$;

-- ---------------------------------------------------------------------------
-- Pricing quote
-- ---------------------------------------------------------------------------
create or replace function app_private.compute_order_pricing(p_customer uuid, p_address_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_address public.addresses%rowtype;
  v_items jsonb;
  v_subtotal bigint := 0;
  v_tax bigint := 0;
  v_discount bigint := 0;
  v_shipping bigint := 0;
  v_total bigint := 0;
  v_count integer := 0;
  v_tax_enabled boolean := app_private.get_bool_setting('commerce.tax_enabled', false);
  v_fee bigint := app_private.get_int_setting('commerce.shipping_fee_paise', 0);
  v_free_threshold bigint := app_private.get_int_setting('commerce.free_shipping_threshold_paise', 0);
  v_line record;
begin
  select * into v_address
  from public.addresses a
  where a.id = p_address_id and a.customer_id = p_customer and a.deleted_at is null;
  perform app_private.assert_true(v_address.id is not null, 'Select a valid delivery address.');
  perform app_private.validate_address_town(v_address.town_id, v_address.pincode);
  perform app_private.assert_true(exists (
    select 1 from public.carts c where c.customer_id = p_customer
  ), 'Your cart is empty.');

  for v_line in
    select
      ci.product_id,
      ci.quantity,
      p.name,
      p.sku,
      p.status,
      p.price_paise,
      p.tax_rate_bps,
      p.hsn_code,
      coalesce(i.quantity_on_hand - i.quantity_reserved, 0) as available_quantity
    from public.cart_items ci
    join public.carts c on c.id = ci.cart_id and c.customer_id = p_customer
    join public.products p on p.id = ci.product_id
    left join public.inventory i on i.product_id = ci.product_id
    order by ci.created_at
  loop
    declare
      v_line_subtotal bigint := v_line.price_paise * v_line.quantity;
      v_line_tax bigint := case
        when v_tax_enabled then round((v_line_subtotal * v_line.tax_rate_bps)::numeric / 10000.0)::bigint
        else 0
      end;
    begin
      v_subtotal := v_subtotal + v_line_subtotal;
      v_tax := v_tax + v_line_tax;
      v_count := v_count + v_line.quantity;
      v_items := coalesce(v_items, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
        'product_id', v_line.product_id,
        'name', v_line.name,
        'sku', v_line.sku,
        'hsn_code', v_line.hsn_code,
        'quantity', v_line.quantity,
        'unit_price_paise', v_line.price_paise,
        'discount_paise', 0,
        'tax_rate_bps', case when v_tax_enabled then v_line.tax_rate_bps else 0 end,
        'tax_paise', v_line_tax,
        'line_total_paise', v_line_subtotal + v_line_tax,
        'available_quantity', v_line.available_quantity,
        'is_active', v_line.status = 'ACTIVE',
        'is_available', v_line.status = 'ACTIVE' and v_line.available_quantity >= v_line.quantity
      ));
    end;
  end loop;

  perform app_private.assert_true(v_count > 0, 'Your cart is empty.');
  if v_fee > 0 and v_free_threshold > 0 and v_subtotal >= v_free_threshold then
    v_shipping := 0;
  else
    v_shipping := v_fee;
  end if;
  v_total := v_subtotal - v_discount + v_tax + v_shipping;

  return jsonb_build_object(
    'items', coalesce(v_items, '[]'::jsonb),
    'item_count', v_count,
    'subtotal_paise', v_subtotal,
    'discount_paise', v_discount,
    'tax_paise', v_tax,
    'shipping_paise', v_shipping,
    'total_paise', v_total,
    'cod_amount_paise', v_total,
    'payment_method', 'COD',
    'address', jsonb_build_object(
      'id', v_address.id,
      'label', v_address.label,
      'recipient_name', v_address.recipient_name,
      'phone', v_address.phone,
      'line1', v_address.line1,
      'line2', v_address.line2,
      'landmark', v_address.landmark,
      'town_id', v_address.town_id,
      'pincode', v_address.pincode
    )
  );
end;
$$;

create or replace function public.quote_my_order(p_address_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
begin
  return app_private.compute_order_pricing(v_uid, p_address_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Idempotent COD checkout
-- ---------------------------------------------------------------------------
create or replace function public.place_order(
  p_address_id uuid,
  p_idempotency_key text,
  p_customer_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_existing public.orders%rowtype;
  v_address public.addresses%rowtype;
  v_cart_id uuid;
  v_pricing jsonb;
  v_items jsonb;
  v_order_id uuid;
  v_order_number text;
  v_line record;
  v_movement record;
  v_note text := trim(coalesce(p_customer_note, ''));
begin
  perform app_private.assert_true(
    p_idempotency_key is not null and char_length(p_idempotency_key) between 8 and 100,
    'A valid idempotency key is required.'
  );
  perform app_private.assert_true(char_length(v_note) <= 1000, 'Order note is too long.');

  select * into v_existing
  from public.orders o
  where o.customer_id = v_uid and o.idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'order_id', v_existing.id, 'order_number', v_existing.order_number,
      'status', v_existing.status, 'total_paise', v_existing.total_paise,
      'cod_amount_paise', v_existing.cod_amount_paise, 'idempotent_replay', true
    );
  end if;

  -- Serialize cart mutations for this customer. This also protects against
  -- double-order retries with different idempotency keys.
  select c.id into v_cart_id
  from public.carts c
  where c.customer_id = v_uid
  for update;
  perform app_private.assert_true(v_cart_id is not null, 'Your cart is empty.');

  select * into v_existing
  from public.orders o
  where o.customer_id = v_uid and o.idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'order_id', v_existing.id, 'order_number', v_existing.order_number,
      'status', v_existing.status, 'total_paise', v_existing.total_paise,
      'cod_amount_paise', v_existing.cod_amount_paise, 'idempotent_replay', true
    );
  end if;

  -- Lock products and inventory rows in a deterministic order before pricing.
  perform 1
  from public.products p
  where p.id in (select ci.product_id from public.cart_items ci where ci.cart_id = v_cart_id)
  order by p.id
  for share;
  perform 1
  from public.inventory i
  where i.product_id in (select ci.product_id from public.cart_items ci where ci.cart_id = v_cart_id)
  order by i.product_id
  for update;

  select * into v_address
  from public.addresses a
  where a.id = p_address_id and a.customer_id = v_uid and a.deleted_at is null;
  perform app_private.assert_true(v_address.id is not null, 'Select a valid delivery address.');
  perform app_private.validate_address_town(v_address.town_id, v_address.pincode);

  v_pricing := app_private.compute_order_pricing(v_uid, p_address_id);
  v_items := v_pricing -> 'items';

  for v_line in
    select
      (x ->> 'product_id')::uuid as product_id,
      (x ->> 'quantity')::integer as quantity,
      (x ->> 'is_active')::boolean as is_active,
      (x ->> 'is_available')::boolean as is_available
    from jsonb_array_elements(v_items) x
  loop
    perform app_private.assert_true(v_line.is_active, 'A product in your cart is no longer available.');
    perform app_private.assert_true(v_line.is_available, 'Insufficient stock for a product in your cart.');
    update public.inventory
    set quantity_reserved = quantity_reserved + v_line.quantity,
        updated_at = now()
    where product_id = v_line.product_id
      and quantity_on_hand - quantity_reserved >= v_line.quantity;
    perform app_private.assert_true(
      found,
      'Stock changed while placing the order. Please review your cart.'
    );
  end loop;

  v_order_number := app_private.next_document_number('IB', 'public.order_number_seq'::regclass);
  insert into public.orders (
    order_number, customer_id, status, payment_method, payment_status,
    subtotal_paise, discount_paise, tax_paise, shipping_paise, total_paise,
    cod_amount_paise, item_count, address_id, recipient_name, phone, line1, line2,
    landmark, town_id, town_name, district, state, pincode, customer_note,
    idempotency_key
  )
  select
    v_order_number, v_uid, 'PENDING_APPROVAL', 'COD', 'PENDING',
    (v_pricing ->> 'subtotal_paise')::bigint,
    (v_pricing ->> 'discount_paise')::bigint,
    (v_pricing ->> 'tax_paise')::bigint,
    (v_pricing ->> 'shipping_paise')::bigint,
    (v_pricing ->> 'total_paise')::bigint,
    (v_pricing ->> 'total_paise')::bigint,
    (v_pricing ->> 'item_count')::integer,
    v_address.id, v_address.recipient_name, v_address.phone, v_address.line1,
    v_address.line2, v_address.landmark, v_address.town_id, t.name, t.district,
    t.state, v_address.pincode, v_note, p_idempotency_key
  from public.towns t
  where t.id = v_address.town_id
  returning id into v_order_id;

  insert into public.order_items (
    order_id, product_id, product_name, sku, hsn_code, unit_price_paise,
    quantity, discount_paise, tax_rate_bps, tax_paise, line_total_paise
  )
  select
    v_order_id,
    (x ->> 'product_id')::uuid,
    x ->> 'name',
    x ->> 'sku',
    nullif(x ->> 'hsn_code', ''),
    (x ->> 'unit_price_paise')::bigint,
    (x ->> 'quantity')::integer,
    (x ->> 'discount_paise')::bigint,
    (x ->> 'tax_rate_bps')::integer,
    (x ->> 'tax_paise')::bigint,
    (x ->> 'line_total_paise')::bigint
  from jsonb_array_elements(v_items) x;

  for v_line in
    select
      (x ->> 'product_id')::uuid as product_id,
      (x ->> 'quantity')::integer as quantity
    from jsonb_array_elements(v_items) x
  loop
    insert into public.inventory_movements (
      product_id, movement_type, quantity_delta, reserved_delta,
      on_hand_after, reserved_after, reference_type, reference_id, reason,
      actor_id, idempotency_key
    )
    select
      i.product_id, 'RESERVATION', 0, v_line.quantity,
      i.quantity_on_hand, i.quantity_reserved, 'ORDER', v_order_id,
      'Stock reserved for order', v_uid,
      'order:' || v_order_id::text || ':reserve:' || v_line.product_id::text
    from public.inventory i
    where i.product_id = v_line.product_id;
  end loop;

  delete from public.cart_items where cart_id = v_cart_id;

  perform app_private.notify_owner(
    'ORDER_PLACED',
    'New order ' || v_order_number,
    'A new COD order was placed for ₹' || to_char(((v_pricing ->> 'total_paise')::bigint / 100.0), 'FM999999990.00') || '. Review and approve it.',
    jsonb_build_object('order_id', v_order_id, 'order_number', v_order_number, 'total_paise', (v_pricing ->> 'total_paise')::bigint),
    'order-placed:' || v_order_id::text
  );
  perform app_private.notify_user(
    v_uid, 'ORDER_PLACED', 'Order ' || v_order_number || ' received',
    'Your COD order has been received and is awaiting confirmation.',
    jsonb_build_object('order_id', v_order_id, 'order_number', v_order_number),
    'customer-order-placed:' || v_order_id::text
  );
  perform app_private.write_audit(
    'ORDER_PLACED', 'order', v_order_id, null,
    jsonb_build_object('order_number', v_order_number, 'total_paise', (v_pricing ->> 'total_paise')::bigint),
    'WEBSITE', v_uid
  );

  return jsonb_build_object(
    'order_id', v_order_id,
    'order_number', v_order_number,
    'status', 'PENDING_APPROVAL',
    'total_paise', (v_pricing ->> 'total_paise')::bigint,
    'cod_amount_paise', (v_pricing ->> 'total_paise')::bigint,
    'idempotent_replay', false
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Customer order reads and tracking
-- ---------------------------------------------------------------------------
create or replace function app_private.assert_can_view_order(p_order_id uuid, p_uid uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.assert_true(exists (
    select 1 from public.orders o
    where o.id = p_order_id and (o.customer_id = p_uid or public.is_owner())
  ), 'Order not found.');
end;
$$;

create or replace function public.list_my_orders(p_limit integer default 20, p_before timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', o.id,
      'order_number', o.order_number,
      'status', o.status,
      'payment_status', o.payment_status,
      'total_paise', o.total_paise,
      'cod_amount_paise', o.cod_amount_paise,
      'item_count', o.item_count,
      'created_at', o.created_at,
      'delivered_at', o.delivered_at,
      'town_name', o.town_name,
      'pincode', o.pincode,
      'shipment_id', (select s.id from public.shipments s where s.order_id = o.id),
      'shipment_status', (select s.status from public.shipments s where s.order_id = o.id),
      'invoice_number', (select inv.invoice_number from public.invoices inv where inv.order_id = o.id and inv.status = 'ISSUED'),
      'first_item_name', (
        select oi.product_name from public.order_items oi
        where oi.order_id = o.id order by oi.created_at asc limit 1
      ),
      'return_status', (
        select r.status from public.return_requests r
        where r.order_id = o.id order by r.created_at desc limit 1
      )
    ) order by o.created_at desc)
    from (
      select * from public.orders o
      where o.customer_id = v_uid
        and (p_before is null or o.created_at < p_before)
      order by o.created_at desc
      limit v_limit
    ) o
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_my_order(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_order public.orders%rowtype;
  v_result jsonb;
begin
  select * into v_order from public.orders o where o.id = p_order_id;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  perform app_private.assert_true(v_order.customer_id = v_uid or public.is_owner(), 'Order not found.');

  select jsonb_build_object(
    'id', v_order.id,
    'order_number', v_order.order_number,
    'status', v_order.status,
    'payment_method', v_order.payment_method,
    'payment_status', v_order.payment_status,
    'subtotal_paise', v_order.subtotal_paise,
    'discount_paise', v_order.discount_paise,
    'tax_paise', v_order.tax_paise,
    'shipping_paise', v_order.shipping_paise,
    'total_paise', v_order.total_paise,
    'cod_amount_paise', v_order.cod_amount_paise,
    'item_count', v_order.item_count,
    'recipient_name', v_order.recipient_name,
    'phone', v_order.phone,
    'line1', v_order.line1,
    'line2', v_order.line2,
    'landmark', v_order.landmark,
    'town_name', v_order.town_name,
    'district', v_order.district,
    'state', v_order.state,
    'pincode', v_order.pincode,
    'customer_note', v_order.customer_note,
    'created_at', v_order.created_at,
    'approved_at', v_order.approved_at,
    'delivered_at', v_order.delivered_at,
    'cancelled_at', v_order.cancelled_at,
    'rejected_reason', v_order.rejected_reason,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_id', oi.product_id, 'product_name', oi.product_name,
        'sku', oi.sku, 'hsn_code', oi.hsn_code,
        'unit_price_paise', oi.unit_price_paise, 'quantity', oi.quantity,
        'discount_paise', oi.discount_paise, 'tax_rate_bps', oi.tax_rate_bps,
        'tax_paise', oi.tax_paise, 'line_total_paise', oi.line_total_paise
      ) order by oi.created_at)
      from public.order_items oi where oi.order_id = v_order.id
    ), '[]'::jsonb),
    'invoice', (
      select jsonb_build_object(
        'id', inv.id, 'invoice_number', inv.invoice_number,
        'invoice_date', inv.invoice_date, 'status', inv.status,
        'total_paise', inv.total_paise, 'pdf_storage_path', inv.pdf_storage_path
      ) from public.invoices inv where inv.order_id = v_order.id
    ),
    'shipment', (
      select jsonb_build_object(
        'id', s.id, 'shipment_number', s.shipment_number, 'status', s.status,
        'package_count', s.package_count, 'expected_cod_paise', s.expected_cod_paise,
        'picked_up_at', s.picked_up_at, 'delivered_at', s.delivered_at
      ) from public.shipments s where s.order_id = v_order.id
    ),
    'return_request', (
      select jsonb_build_object(
        'id', r.id, 'return_number', r.return_number, 'status', r.status,
        'reason', r.reason, 'created_at', r.created_at,
        'rejection_reason', r.rejection_reason, 'resolution_note', r.resolution_note
      ) from public.return_requests r where r.order_id = v_order.id
      order by r.created_at desc limit 1
    )
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.get_order_tracking(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_events jsonb;
  v_packages jsonb;
  v_otp_notice text;
  v_delivery_otp text;
begin
  select * into v_order from public.orders o where o.id = p_order_id;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  perform app_private.assert_true(v_order.customer_id = v_uid or public.is_owner(), 'Order not found.');
  select * into v_shipment from public.shipments s where s.order_id = p_order_id;

  if v_shipment.id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'event_type', e.event_type, 'previous_status', e.previous_status,
      'new_status', e.new_status, 'source', e.source, 'location_text', e.location_text,
      'created_at', e.created_at
    ) order by e.created_at asc), '[]'::jsonb)
    into v_events
    from public.shipment_events e
    where e.shipment_id = v_shipment.id;

    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'package_number', p.package_number, 'status', p.status,
      'is_sealed', p.is_sealed
    ) order by p.package_number), '[]'::jsonb)
    into v_packages
    from public.packages p where p.shipment_id = v_shipment.id;

    if v_shipment.status = 'OUT_FOR_DELIVERY' then
      select n.body, n.data ->> 'otp'
      into v_otp_notice, v_delivery_otp
      from public.notifications n
      where n.recipient_id = v_uid
        and n.type = 'DELIVERY_OTP'
        and n.data ->> 'shipment_id' = v_shipment.id::text
      order by n.created_at desc limit 1;
    end if;
  else
    v_events := '[]'::jsonb;
    v_packages := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_number', v_order.order_number,
    'order_status', v_order.status,
    'payment_status', v_order.payment_status,
    'shipment_id', v_shipment.id,
    'shipment_number', v_shipment.shipment_number,
    'shipment_status', v_shipment.status,
    'package_count', v_shipment.package_count,
    'events', v_events,
    'packages', v_packages,
    'delivery_otp_notice', v_otp_notice,
    'delivery_otp', v_delivery_otp,
    'updated_at', greatest(v_order.updated_at, coalesce(v_shipment.updated_at, v_order.updated_at))
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Cancellation (policy controlled, stock safe, idempotent)
-- ---------------------------------------------------------------------------
create or replace function public.cancel_order(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_order public.orders%rowtype;
  v_line record;
  v_movement_id uuid;
  v_shipment public.shipments%rowtype;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a cancellation reason.');
  perform app_private.assert_true(
    app_private.get_bool_setting('policies.cancellation_allowed_before_pickup', true),
    'Cancellation is currently disabled. Please contact support.'
  );

  select * into v_order from public.orders o where o.id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  perform app_private.assert_true(v_order.customer_id = v_uid, 'Order not found.');
  if v_order.status = 'CANCELLED' then
    return jsonb_build_object('order_id', v_order.id, 'status', 'CANCELLED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(
    v_order.status in ('PENDING_APPROVAL','APPROVED','READY_FOR_PICKUP'),
    'This order can no longer be cancelled. Please use the return process once delivered.'
  );

  select * into v_shipment from public.shipments s where s.order_id = v_order.id for update;
  if v_shipment.id is not null then
    perform app_private.assert_true(
      v_shipment.status not in ('PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','OUT_FOR_DELIVERY','DELIVERED'),
      'This order has already been picked up and cannot be cancelled.'
    );
  end if;

  for v_line in
    select * from public.order_items oi where oi.order_id = v_order.id order by oi.product_id
  loop
    if v_order.status = 'PENDING_APPROVAL' then
      update public.inventory
      set quantity_reserved = greatest(quantity_reserved - v_line.quantity, 0), updated_at = now()
      where product_id = v_line.product_id and quantity_reserved >= v_line.quantity;
      perform app_private.assert_true(found, 'Reserved stock could not be released safely.');
      insert into public.inventory_movements (
        product_id, movement_type, quantity_delta, reserved_delta,
        on_hand_after, reserved_after, reference_type, reference_id, reason,
        actor_id, idempotency_key
      )
      select i.product_id, 'RESERVATION_RELEASE', 0, -v_line.quantity,
        i.quantity_on_hand, i.quantity_reserved, 'ORDER', v_order.id,
        'Order cancelled before approval', v_uid,
        'order:' || v_order.id::text || ':cancel-release:' || v_line.product_id::text
      from public.inventory i where i.product_id = v_line.product_id
      on conflict (idempotency_key) do nothing;
    else
      update public.inventory
      set quantity_on_hand = quantity_on_hand + v_line.quantity, updated_at = now()
      where product_id = v_line.product_id;
      insert into public.inventory_movements (
        product_id, movement_type, quantity_delta, reserved_delta,
        on_hand_after, reserved_after, reference_type, reference_id, reason,
        actor_id, idempotency_key
      )
      select i.product_id, 'CANCELLATION', v_line.quantity, 0,
        i.quantity_on_hand, i.quantity_reserved, 'ORDER', v_order.id,
        'Order cancelled after approval', v_uid,
        'order:' || v_order.id::text || ':cancel-restock:' || v_line.product_id::text
      from public.inventory i where i.product_id = v_line.product_id
      on conflict (idempotency_key) do nothing;
    end if;
  end loop;

  update public.orders
  set status = 'CANCELLED', cancelled_at = now(), cancellation_reason = v_reason,
      payment_status = 'VOID'
  where id = v_order.id;

  update public.invoices
  set status = 'VOID', voided_at = now(), void_reason = 'Order cancelled: ' || v_reason
  where order_id = v_order.id and status = 'ISSUED';

  if v_shipment.id is not null then
    update public.shipments set status = 'CANCELLED' where id = v_shipment.id;
    update public.packages set status = 'CANCELLED'
    where shipment_id = v_shipment.id and status not in ('DELIVERED','RETURNED');
    update public.pickup_requests
    set status = 'CANCELLED', cancelled_at = now()
    where shipment_id = v_shipment.id and status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED');
    update public.pickup_assignments
    set status = 'CANCELLED', responded_at = now()
    where pickup_request_id in (select id from public.pickup_requests where shipment_id = v_shipment.id)
      and status in ('PENDING','ACCEPTED');
    update public.delivery_assignments
    set status = 'CANCELLED', responded_at = now()
    where shipment_id = v_shipment.id and status in ('PENDING','ACCEPTED');
    perform app_private.log_shipment_event(
      v_shipment.id, 'CANCELLED', v_shipment.status, 'CANCELLED', 'CUSTOMER_APP', v_uid,
      null, null, null, null, jsonb_build_object('reason', v_reason)
    );
  end if;

  perform app_private.notify_owner(
    'ORDER_CANCELLED', 'Order ' || v_order.order_number || ' cancelled',
    'Customer cancelled the order. Reason: ' || v_reason,
    jsonb_build_object('order_id', v_order.id, 'order_number', v_order.order_number),
    'order-cancelled-owner:' || v_order.id::text
  );
  perform app_private.notify_user(
    v_uid, 'ORDER_CANCELLED', 'Order ' || v_order.order_number || ' cancelled',
    'Your order has been cancelled.',
    jsonb_build_object('order_id', v_order.id, 'order_number', v_order.order_number),
    'order-cancelled-customer:' || v_order.id::text
  );
  perform app_private.write_audit(
    'ORDER_CANCELLED', 'order', v_order.id,
    jsonb_build_object('status', v_order.status),
    jsonb_build_object('status', 'CANCELLED', 'reason', v_reason),
    'CUSTOMER_APP', v_uid
  );

  return jsonb_build_object('order_id', v_order.id, 'status', 'CANCELLED', 'idempotent_replay', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Return requests
-- ---------------------------------------------------------------------------
create or replace function public.request_return(
  p_order_id uuid,
  p_reason text,
  p_description text default null,
  p_evidence_path text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_window integer := app_private.get_int_setting('policies.return_window_days', 7)::integer;
  v_id uuid;
  v_number text;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.assert_true(char_length(v_reason) between 3 and 160, 'Enter a return reason.');
  perform app_private.assert_true(char_length(coalesce(p_description, '')) <= 2000, 'Description is too long.');

  select * into v_order from public.orders o where o.id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null and v_order.customer_id = v_uid, 'Order not found.');
  perform app_private.assert_true(v_order.status = 'DELIVERED', 'Only delivered orders can be returned.');
  perform app_private.assert_true(
    v_order.delivered_at is not null and v_order.delivered_at >= now() - make_interval(days => greatest(v_window, 0)),
    'The return window for this order has closed.'
  );
  perform app_private.assert_true(not exists (
    select 1 from public.return_requests r
    where r.order_id = v_order.id
      and r.status in ('REQUESTED','APPROVED','IN_TRANSIT','RECEIVED')
  ), 'A return request is already open for this order.');

  select * into v_shipment from public.shipments s where s.order_id = v_order.id;

  v_number := app_private.next_document_number('RET', 'public.return_number_seq'::regclass);
  insert into public.return_requests (
    return_number, order_id, customer_id, shipment_id, reason, description,
    evidence_path, status
  ) values (
    v_number, v_order.id, v_uid, v_shipment.id, v_reason,
    trim(coalesce(p_description, '')), nullif(trim(coalesce(p_evidence_path, '')), ''), 'REQUESTED'
  ) returning id into v_id;

  update public.orders set status = 'RETURN_REQUESTED' where id = v_order.id;
  if v_shipment.id is not null then
    perform app_private.log_shipment_event(
      v_shipment.id, 'RETURN_REQUESTED', v_shipment.status, v_shipment.status,
      'CUSTOMER_APP', v_uid, nullif(trim(coalesce(p_evidence_path, '')), ''),
      null, null, null, jsonb_build_object('return_id', v_id, 'reason', v_reason)
    );
  end if;

  perform app_private.notify_owner(
    'RETURN_REQUESTED', 'Return request ' || v_number,
    'Customer requested a return for order ' || v_order.order_number || '. Reason: ' || v_reason,
    jsonb_build_object('return_id', v_id, 'order_id', v_order.id),
    'return-requested:' || v_id::text
  );
  perform app_private.notify_user(
    v_uid, 'RETURN_REQUESTED', 'Return request received',
    'We received your return request for order ' || v_order.order_number || '.',
    jsonb_build_object('return_id', v_id, 'order_id', v_order.id),
    'return-requested-customer:' || v_id::text
  );
  perform app_private.write_audit(
    'RETURN_REQUESTED', 'return_request', v_id, null,
    jsonb_build_object('order_id', v_order.id, 'reason', v_reason),
    'CUSTOMER_APP', v_uid
  );

  return jsonb_build_object('return_id', v_id, 'return_number', v_number, 'status', 'REQUESTED');
end;
$$;

-- ---------------------------------------------------------------------------
-- Notifications and devices
-- ---------------------------------------------------------------------------
create or replace function public.list_my_notifications(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', n.id, 'type', n.type, 'title', n.title, 'body', n.body,
      'data', n.data, 'read_at', n.read_at, 'created_at', n.created_at
    ) order by n.created_at desc)
    from (
      select * from public.notifications
      where recipient_id = v_uid
      order by created_at desc
      limit v_limit
    ) n
  ), '[]'::jsonb);
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.notifications
  set read_at = coalesce(read_at, now())
  where id = p_notification_id and recipient_id = auth.uid()
  returning jsonb_build_object('id', id, 'read_at', read_at);
$$;

create or replace function public.mark_all_notifications_read()
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  with updated as (
    update public.notifications
    set read_at = now()
    where recipient_id = auth.uid() and read_at is null
    returning id
  )
  select jsonb_build_object('updated', count(*)) from updated;
$$;

create or replace function public.register_my_device(
  p_app_name text,
  p_platform public.device_platform,
  p_device_id text,
  p_device_name text default '',
  p_push_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_authenticated();
  v_id uuid;
begin
  perform app_private.assert_true(p_app_name in ('seller','delivery','customer','website'), 'Invalid app name.');
  perform app_private.assert_true(char_length(coalesce(p_device_id, '')) between 4 and 200, 'Invalid device id.');
  insert into public.user_devices (
    user_id, app_name, platform, device_id, device_name, push_token
  ) values (
    v_uid, p_app_name, p_platform, p_device_id, coalesce(p_device_name, ''), nullif(trim(coalesce(p_push_token, '')), '')
  )
  on conflict (user_id, app_name, device_id) do update
    set platform = excluded.platform,
        device_name = excluded.device_name,
        push_token = coalesce(excluded.push_token, public.user_devices.push_token),
        last_seen_at = now(),
        revoked_at = null
  returning id into v_id;
  return jsonb_build_object('device_id', v_id);
end;
$$;

create or replace function public.revoke_my_device(p_device_id uuid)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.user_devices
  set revoked_at = now(), push_token = null
  where id = p_device_id and user_id = auth.uid()
  returning jsonb_build_object('revoked', true);
$$;
