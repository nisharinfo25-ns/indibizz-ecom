-- IndiaBizz :: 0011 owner dashboard, catalogue, inventory, approvals, invoices,
-- packages and pickup request creation.

create or replace function app_private.slugify(p_text text)
returns text
language sql
immutable
as $$
  select trim(both '-' from regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function app_private.generate_otp_code()
returns text
language sql
volatile
as $$
  select lpad((floor(random() * 900000) + 100000)::integer::text, 6, '0');
$$;

create or replace function public.owner_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_business jsonb := app_private.get_setting('business', '{}'::jsonb);
  v_tz text := coalesce(nullif(btrim(v_business ->> 'timezone'), ''), 'Asia/Kolkata');
  v_day_start timestamptz;
begin
  if not exists (select 1 from pg_timezone_names where name = v_tz) then
    v_tz := 'Asia/Kolkata';
  end if;
  v_day_start := date_trunc('day', now() at time zone v_tz) at time zone v_tz;
  return jsonb_build_object(
    'generated_at', now(),
    'timezone', v_tz,
    'orders_today', (select count(*) from public.orders o where o.created_at >= v_day_start),
    'pending_approval', (select count(*) from public.orders o where o.status = 'PENDING_APPROVAL'),
    'ready_for_pickup', (select count(*) from public.orders o where o.status = 'READY_FOR_PICKUP'),
    'pickups_in_progress', (select count(*) from public.pickup_requests p where p.status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED')),
    'packages_waiting_pickup', (
      select count(*) from public.packages pk
      join public.shipments s on s.id = pk.shipment_id
      where pk.status in ('PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED')
        and s.status not in ('CANCELLED','RETURNED_SUCCESSFULLY')
    ),
    'out_for_delivery', (select count(*) from public.shipments s where s.status = 'OUT_FOR_DELIVERY'),
    'delivered_today', (
      select count(*) from public.shipments s
      where s.delivered_at is not null and s.delivered_at >= v_day_start
    ),
    'delivered_value_today_paise', coalesce((
      select sum(o.total_paise) from public.shipments s
      join public.orders o on o.id = s.order_id
      where s.delivered_at is not null and s.delivered_at >= v_day_start
    ), 0),
    'cod_pending_verification_paise', coalesce((
      select sum(cs.handed_over_paise) from public.cod_settlements cs
      where cs.status = 'PENDING_VERIFICATION'
    ), 0),
    'low_stock_products', (
      select count(*) from public.inventory i
      join public.products p on p.id = i.product_id
      where p.status = 'ACTIVE' and i.quantity_on_hand <= i.low_stock_threshold
    ),
    'active_products', (select count(*) from public.products p where p.status = 'ACTIVE'),
    'pending_returns', (select count(*) from public.return_requests r where r.status = 'REQUESTED'),
    'unread_notifications', (
      select count(*) from public.notifications n
      where n.recipient_id = v_uid and n.read_at is null
    ),
    'recent_orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'order_number', o.order_number, 'status', o.status,
        'created_at', o.created_at, 'total_paise', o.total_paise,
        'item_count', o.item_count, 'customer_name', pr.full_name,
        'customer_phone', pr.phone, 'town_name', o.town_name
      ) order by o.created_at desc)
      from (
        select * from public.orders order by created_at desc limit 8
      ) o
      join public.profiles pr on pr.id = o.customer_id
    ), '[]'::jsonb),
    'recent_activity', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_type', e.event_type, 'shipment_id', e.shipment_id,
        'created_at', e.created_at, 'order_number', o.order_number,
        'shipment_number', s.shipment_number
      ) order by e.created_at desc)
      from (
        select * from public.shipment_events order by created_at desc limit 10
      ) e
      join public.shipments s on s.id = e.shipment_id
      join public.orders o on o.id = s.order_id
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_categories()
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
      'id', c.id, 'name', c.name, 'slug', c.slug, 'description', c.description,
      'image_path', c.image_path, 'sort_order', c.sort_order,
      'is_active', c.is_active, 'product_count', (
        select count(*) from public.products p where p.category_id = c.id
      )
    ) order by c.sort_order, c.name)
    from public.categories c
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_save_category(
  p_name text,
  p_slug text default null,
  p_description text default '',
  p_image_path text default null,
  p_sort_order integer default 0,
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
  v_slug text := coalesce(nullif(btrim(p_slug), ''), app_private.slugify(p_name));
  v_id uuid;
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_name, ''))) between 2 and 120, 'Enter a category name.');
  perform app_private.assert_true(v_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$', 'Enter a valid category slug.');
  if p_id is not null then
    select c.id into v_id from public.categories c where c.id = p_id;
    perform app_private.assert_true(v_id is not null, 'Category not found.');
  end if;

  if v_id is null then
    insert into public.categories (name, slug, description, image_path, sort_order, is_active, created_by)
    values (trim(p_name), v_slug, coalesce(p_description, ''), p_image_path, coalesce(p_sort_order, 0), coalesce(p_is_active, true), v_uid)
    returning id into v_id;
  else
    update public.categories
    set name = trim(p_name), slug = v_slug, description = coalesce(p_description, ''),
        image_path = p_image_path, sort_order = coalesce(p_sort_order, 0),
        is_active = coalesce(p_is_active, true)
    where id = v_id;
  end if;
  perform app_private.write_audit(
    case when p_id is null then 'CATEGORY_CREATED' else 'CATEGORY_UPDATED' end,
    'category', v_id, null, jsonb_build_object('name', trim(p_name), 'slug', v_slug),
    'SELLER_APP', v_uid
  );
  return (select jsonb_build_object(
    'id', c.id, 'name', c.name, 'slug', c.slug, 'description', c.description,
    'image_path', c.image_path, 'sort_order', c.sort_order, 'is_active', c.is_active
  ) from public.categories c where c.id = v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Products & images
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_products(
  p_search text default null,
  p_status public.product_status default null,
  p_category_id uuid default null,
  p_low_stock_only boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform app_private.require_owner();
  return coalesce((
    select jsonb_agg(row_data order by name)
    from (
      select p.name, jsonb_build_object(
        'id', p.id,
        'name', p.name,
        'slug', p.slug,
        'sku', p.sku,
        'description', p.description,
        'category_id', p.category_id,
        'category_name', c.name,
        'price_paise', p.price_paise,
        'compare_at_price_paise', p.compare_at_price_paise,
        'tax_rate_bps', p.tax_rate_bps,
        'hsn_code', p.hsn_code,
        'weight_grams', p.weight_grams,
        'status', p.status,
        'is_featured', p.is_featured,
        'created_at', p.created_at,
        'updated_at', p.updated_at,
        'quantity_on_hand', coalesce(i.quantity_on_hand, 0),
        'quantity_reserved', coalesce(i.quantity_reserved, 0),
        'available_quantity', greatest(coalesce(i.quantity_on_hand - i.quantity_reserved, 0), 0),
        'low_stock_threshold', coalesce(i.low_stock_threshold, 5),
        'is_low_stock', coalesce(i.quantity_on_hand, 0) <= coalesce(i.low_stock_threshold, 5),
        'images', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', pi.id, 'storage_path', pi.storage_path, 'alt_text', pi.alt_text,
            'is_primary', pi.is_primary, 'is_public', pi.is_public, 'sort_order', pi.sort_order
          ) order by pi.is_primary desc, pi.sort_order)
          from public.product_images pi where pi.product_id = p.id
        ), '[]'::jsonb)
      ) as row_data
      from public.products p
      join public.categories c on c.id = p.category_id
      left join public.inventory i on i.product_id = p.id
      where (p_status is null or p.status = p_status)
        and (p_category_id is null or p.category_id = p_category_id)
        and (p_search is null or p_search = '' or p.name ilike '%' || p_search || '%' or p.sku ilike '%' || p_search || '%')
        and (not coalesce(p_low_stock_only, false) or (p.status = 'ACTIVE' and coalesce(i.quantity_on_hand, 0) <= coalesce(i.low_stock_threshold, 5)))
    ) q
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_save_product(
  p_category_id uuid,
  p_name text,
  p_sku text,
  p_price_paise bigint,
  p_tax_rate_bps integer default 0,
  p_hsn_code text default null,
  p_description text default '',
  p_compare_at_price_paise bigint default null,
  p_weight_grams integer default 0,
  p_status public.product_status default 'DRAFT',
  p_is_featured boolean default false,
  p_low_stock_threshold integer default 5,
  p_opening_stock integer default 0,
  p_slug text default null,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_slug text := coalesce(nullif(btrim(p_slug), ''), app_private.slugify(p_name));
  v_id uuid;
  v_inventory_id uuid;
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_name, ''))) between 2 and 200, 'Enter a product name.');
  perform app_private.assert_true(char_length(trim(coalesce(p_sku, ''))) between 2 and 64, 'Enter a valid SKU.');
  perform app_private.assert_true(v_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$', 'Enter a valid product slug.');
  perform app_private.assert_true(coalesce(p_price_paise, -1) >= 0, 'Price cannot be negative.');
  perform app_private.assert_true(coalesce(p_tax_rate_bps, 0) between 0 and 5000, 'Tax rate is invalid.');
  perform app_private.assert_true(p_hsn_code is null or p_hsn_code = '' or p_hsn_code ~ '^[0-9]{4,8}$', 'HSN code must be 4 to 8 digits.');
  perform app_private.assert_true(coalesce(p_weight_grams, 0) between 0 and 1000000, 'Weight is invalid.');
  perform app_private.assert_true(coalesce(p_low_stock_threshold, 5) >= 0, 'Low-stock threshold cannot be negative.');
  perform app_private.assert_true(coalesce(p_opening_stock, 0) >= 0, 'Opening stock cannot be negative.');
  perform app_private.assert_true(exists (select 1 from public.categories c where c.id = p_category_id), 'Select a valid category.');
  perform app_private.assert_true(
    p_compare_at_price_paise is null or p_compare_at_price_paise >= p_price_paise,
    'Compare-at price must be at least the selling price.'
  );

  if p_id is not null then
    select p.id into v_id from public.products p where p.id = p_id;
    perform app_private.assert_true(v_id is not null, 'Product not found.');
  end if;

  if v_id is null then
    insert into public.products (
      category_id, name, slug, description, sku, price_paise,
      compare_at_price_paise, tax_rate_bps, hsn_code, weight_grams, status,
      is_featured, created_by
    ) values (
      p_category_id, trim(p_name), v_slug, coalesce(p_description, ''),
      upper(trim(p_sku)), p_price_paise, p_compare_at_price_paise,
      coalesce(p_tax_rate_bps, 0), nullif(trim(coalesce(p_hsn_code, '')), ''),
      coalesce(p_weight_grams, 0), coalesce(p_status, 'DRAFT'), coalesce(p_is_featured, false), v_uid
    ) returning id into v_id;

    insert into public.inventory (product_id, quantity_on_hand, quantity_reserved, low_stock_threshold)
    values (v_id, coalesce(p_opening_stock, 0), 0, coalesce(p_low_stock_threshold, 5))
    returning id into v_inventory_id;

    if coalesce(p_opening_stock, 0) > 0 then
      insert into public.inventory_movements (
        product_id, movement_type, quantity_delta, reserved_delta,
        on_hand_after, reserved_after, reference_type, reference_id, reason,
        actor_id, idempotency_key
      ) values (
        v_id, 'OPENING', p_opening_stock, 0, p_opening_stock, 0,
        'PRODUCT', v_id, 'Opening stock', v_uid,
        'product:' || v_id::text || ':opening'
      );
    end if;
  else
    update public.products
    set category_id = p_category_id, name = trim(p_name), slug = v_slug,
        description = coalesce(p_description, ''), sku = upper(trim(p_sku)),
        price_paise = p_price_paise, compare_at_price_paise = p_compare_at_price_paise,
        tax_rate_bps = coalesce(p_tax_rate_bps, 0),
        hsn_code = nullif(trim(coalesce(p_hsn_code, '')), ''),
        weight_grams = coalesce(p_weight_grams, 0),
        status = coalesce(p_status, 'DRAFT'), is_featured = coalesce(p_is_featured, false)
    where id = v_id;
    update public.inventory
    set low_stock_threshold = coalesce(p_low_stock_threshold, 5), updated_at = now()
    where product_id = v_id;
  end if;

  perform app_private.write_audit(
    case when p_id is null then 'PRODUCT_CREATED' else 'PRODUCT_UPDATED' end,
    'product', v_id, null,
    jsonb_build_object('name', trim(p_name), 'sku', upper(trim(p_sku)), 'price_paise', p_price_paise, 'status', coalesce(p_status, 'DRAFT')),
    'SELLER_APP', v_uid
  );

  return (
    select jsonb_build_object(
      'id', p.id, 'name', p.name, 'slug', p.slug, 'sku', p.sku,
      'status', p.status, 'price_paise', p.price_paise,
      'quantity_on_hand', i.quantity_on_hand, 'quantity_reserved', i.quantity_reserved,
      'low_stock_threshold', i.low_stock_threshold
    )
    from public.products p join public.inventory i on i.product_id = p.id
    where p.id = v_id
  );
end;
$$;

create or replace function public.owner_add_product_image(
  p_product_id uuid,
  p_storage_path text,
  p_alt_text text default '',
  p_is_primary boolean default false,
  p_is_public boolean default true,
  p_sort_order integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_id uuid;
  v_count integer;
begin
  perform app_private.assert_true(exists (select 1 from public.products p where p.id = p_product_id), 'Product not found.');
  perform app_private.assert_true(char_length(coalesce(p_storage_path, '')) between 3 and 500, 'Invalid image path.');
  perform app_private.assert_true(
    p_storage_path like p_product_id::text || '/%',
    'Image path must be inside the product folder.'
  );
  select count(*) into v_count from public.product_images where product_id = p_product_id;
  perform app_private.assert_true(v_count < 10, 'A product can have at most 10 images.');
  if p_is_primary then
    update public.product_images set is_primary = false where product_id = p_product_id;
  end if;
  insert into public.product_images (product_id, storage_path, alt_text, is_primary, is_public, sort_order, created_by)
  values (p_product_id, p_storage_path, coalesce(p_alt_text, ''), coalesce(p_is_primary, false), coalesce(p_is_public, true), coalesce(p_sort_order, 0), v_uid)
  returning id into v_id;
  perform app_private.write_audit('PRODUCT_IMAGE_ADDED', 'product', p_product_id, null, jsonb_build_object('image_id', v_id), 'SELLER_APP', v_uid);
  return (select jsonb_build_object('id', id, 'storage_path', storage_path, 'is_primary', is_primary) from public.product_images where id = v_id);
end;
$$;

create or replace function public.owner_delete_product_image(p_image_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_product uuid;
begin
  select product_id into v_product from public.product_images where id = p_image_id;
  perform app_private.assert_true(v_product is not null, 'Image not found.');
  delete from public.product_images where id = p_image_id;
  perform app_private.write_audit('PRODUCT_IMAGE_REMOVED', 'product', v_product, jsonb_build_object('image_id', p_image_id), null, 'SELLER_APP', v_uid);
  return jsonb_build_object('deleted', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- Inventory
-- ---------------------------------------------------------------------------
create or replace function public.owner_adjust_stock(
  p_product_id uuid,
  p_quantity_delta integer,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_inv public.inventory%rowtype;
  v_existing public.inventory_movements%rowtype;
begin
  perform app_private.assert_true(coalesce(p_quantity_delta, 0) <> 0, 'Enter a non-zero stock adjustment.');
  perform app_private.assert_true(char_length(trim(coalesce(p_reason, ''))) between 3 and 500, 'Enter a reason for the stock adjustment.');
  perform app_private.assert_true(char_length(coalesce(p_idempotency_key, '')) between 8 and 100, 'A valid idempotency key is required.');

  select * into v_existing from public.inventory_movements where idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return jsonb_build_object(
      'product_id', p_product_id, 'quantity_on_hand', v_existing.on_hand_after,
      'quantity_reserved', v_existing.reserved_after, 'idempotent_replay', true
    );
  end if;

  select * into v_inv from public.inventory where product_id = p_product_id for update;
  perform app_private.assert_true(v_inv.id is not null, 'Inventory record not found.');
  perform app_private.assert_true(
    v_inv.quantity_on_hand + p_quantity_delta >= v_inv.quantity_reserved,
    'Adjustment would make on-hand stock lower than reserved stock.'
  );
  perform app_private.assert_true(
    v_inv.quantity_on_hand + p_quantity_delta >= 0,
    'On-hand stock cannot be negative.'
  );

  update public.inventory
  set quantity_on_hand = quantity_on_hand + p_quantity_delta, updated_at = now()
  where id = v_inv.id;

  insert into public.inventory_movements (
    product_id, movement_type, quantity_delta, reserved_delta,
    on_hand_after, reserved_after, reference_type, reference_id, reason,
    actor_id, idempotency_key
  ) values (
    p_product_id, 'ADJUSTMENT', p_quantity_delta, 0,
    v_inv.quantity_on_hand + p_quantity_delta, v_inv.quantity_reserved,
    'MANUAL', null, trim(p_reason), v_uid, p_idempotency_key
  );

  perform app_private.write_audit(
    'STOCK_ADJUSTED', 'inventory', v_inv.id,
    jsonb_build_object('on_hand', v_inv.quantity_on_hand),
    jsonb_build_object('on_hand', v_inv.quantity_on_hand + p_quantity_delta, 'reason', trim(p_reason)),
    'SELLER_APP', v_uid
  );

  return jsonb_build_object(
    'product_id', p_product_id,
    'quantity_on_hand', v_inv.quantity_on_hand + p_quantity_delta,
    'quantity_reserved', v_inv.quantity_reserved,
    'idempotent_replay', false
  );
end;
$$;

create or replace function public.owner_inventory_movements(p_product_id uuid, p_limit integer default 50)
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
      'id', m.id, 'movement_type', m.movement_type,
      'quantity_delta', m.quantity_delta, 'reserved_delta', m.reserved_delta,
      'on_hand_after', m.on_hand_after, 'reserved_after', m.reserved_after,
      'reference_type', m.reference_type, 'reference_id', m.reference_id,
      'reason', m.reason, 'created_at', m.created_at
    ) order by m.created_at desc)
    from (
      select * from public.inventory_movements
      where product_id = p_product_id
      order by created_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) m
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Orders
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_orders(
  p_status public.order_status default null,
  p_search text default null,
  p_limit integer default 50
)
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
      'id', o.id, 'order_number', o.order_number, 'status', o.status,
      'payment_status', o.payment_status, 'total_paise', o.total_paise,
      'cod_amount_paise', o.cod_amount_paise, 'item_count', o.item_count,
      'created_at', o.created_at, 'customer_name', pr.full_name,
      'customer_phone', pr.phone, 'town_name', o.town_name, 'pincode', o.pincode,
      'shipment_status', (select s.status from public.shipments s where s.order_id = o.id),
      'payment_collected_at', (
        select s.delivered_at from public.shipments s where s.order_id = o.id and s.status = 'DELIVERED'
      )
    ) order by o.created_at desc)
    from (
      select o.* from public.orders o
      where (p_status is null or o.status = p_status)
        and (
          p_search is null or p_search = ''
          or o.order_number ilike '%' || p_search || '%'
          or o.phone ilike '%' || p_search || '%'
          or o.recipient_name ilike '%' || p_search || '%'
        )
      order by o.created_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) o
    join public.profiles pr on pr.id = o.customer_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_get_order_admin(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_base jsonb;
begin
  perform app_private.require_owner();
  select public.get_my_order(p_order_id) into v_base;
  perform app_private.assert_true(v_base is not null, 'Order not found.');
  return v_base || jsonb_build_object(
    'customer', (
      select jsonb_build_object('id', pr.id, 'name', pr.full_name, 'phone', pr.phone, 'email', pr.email)
      from public.orders o join public.profiles pr on pr.id = o.customer_id where o.id = p_order_id
    ),
    'pickup', (
      select jsonb_build_object(
        'id', pk.id, 'pickup_number', pk.pickup_number, 'status', pk.status,
        'condition', pk.condition, 'requested_at', pk.requested_at,
        'package_count_expected', pk.package_count_expected,
        'package_count_verified', pk.package_count_verified,
        'otp', (
          select n.data ->> 'otp' from public.notifications n
          where n.type = 'PICKUP_OTP' and n.data ->> 'pickup_id' = pk.id::text
          order by n.created_at desc limit 1
        ),
        'assignment', (
          select jsonb_build_object(
            'id', pa.id, 'staff_user_id', pa.staff_user_id, 'status', pa.status,
            'mode', pa.mode, 'staff_type', pa.staff_type,
            'assigned_at', pa.assigned_at, 'expires_at', pa.expires_at
          ) from public.pickup_assignments pa
          where pa.pickup_request_id = pk.id and pa.status in ('PENDING','ACCEPTED')
          limit 1
        ),
        'scanned_packages', (
          select count(distinct bs.package_id) from public.barcode_scans bs
          where bs.pickup_request_id = pk.id and bs.result = 'VALID'
        )
      )
      from public.pickup_requests pk
      where pk.order_id = p_order_id
      order by pk.created_at desc limit 1
    ),
    'delivery_assignment', (
      select jsonb_build_object(
        'id', da.id, 'staff_user_id', da.staff_user_id, 'status', da.status,
        'staff_type', da.staff_type, 'assigned_at', da.assigned_at
      )
      from public.delivery_assignments da
      join public.shipments s on s.id = da.shipment_id
      where s.order_id = p_order_id and da.status in ('PENDING','ACCEPTED')
      limit 1
    ),
    'packages_detail', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pk.id, 'package_number', pk.package_number, 'package_code', pk.package_code,
        'status', pk.status, 'is_sealed', pk.is_sealed, 'weight_grams', pk.weight_grams
      ) order by pk.package_number)
      from public.packages pk
      join public.shipments s on s.id = pk.shipment_id
      where s.order_id = p_order_id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.approve_order(
  p_order_id uuid,
  p_package_count integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_item record;
  v_business jsonb;
  v_invoice_id uuid;
  v_invoice_number text;
  v_shipment_id uuid;
  v_shipment_number text;
  v_package_id uuid;
  v_i integer;
  v_weight integer := 0;
  v_address text;
  v_tz text;
  v_existing_invoice public.invoices%rowtype;
  v_existing_shipment public.shipments%rowtype;
begin
  perform app_private.assert_true(coalesce(p_package_count, 1) between 1 and 20, 'Package count must be between 1 and 20.');
  v_business := app_private.business_invoice_details();
  v_tz := coalesce(v_business ->> 'timezone', 'Asia/Kolkata');

  select * into v_order from public.orders o where o.id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  if v_order.status = 'APPROVED' then
    select * into v_existing_invoice from public.invoices where order_id = v_order.id;
    select * into v_existing_shipment from public.shipments where order_id = v_order.id;
    return jsonb_build_object(
      'order_id', v_order.id, 'status', 'APPROVED',
      'invoice_id', v_existing_invoice.id, 'invoice_number', v_existing_invoice.invoice_number,
      'shipment_id', v_existing_shipment.id, 'shipment_number', v_existing_shipment.shipment_number,
      'idempotent_replay', true
    );
  end if;
  perform app_private.assert_true(v_order.status = 'PENDING_APPROVAL', 'This order cannot be approved in its current status.');

  for v_item in
    select oi.*, p.weight_grams
    from public.order_items oi
    left join public.products p on p.id = oi.product_id
    where oi.order_id = v_order.id
    order by oi.product_id nulls last
  loop
    if v_item.product_id is null then
      raise exception using errcode = 'P0001', message = 'A product in this order no longer exists. Reject the order.';
    end if;
    update public.inventory
    set quantity_on_hand = quantity_on_hand - v_item.quantity,
        quantity_reserved = quantity_reserved - v_item.quantity,
        updated_at = now()
    where product_id = v_item.product_id
      and quantity_reserved >= v_item.quantity
      and quantity_on_hand >= v_item.quantity;
    perform app_private.assert_true(found, 'Reserved stock is inconsistent for this order. Reject the order and investigate.');
    insert into public.inventory_movements (
      product_id, movement_type, quantity_delta, reserved_delta,
      on_hand_after, reserved_after, reference_type, reference_id, reason,
      actor_id, idempotency_key
    )
    select i.product_id, 'SALE', -v_item.quantity, -v_item.quantity,
      i.quantity_on_hand, i.quantity_reserved, 'ORDER', v_order.id,
      'Order approved', v_uid,
      'order:' || v_order.id::text || ':sale:' || v_item.product_id::text
    from public.inventory i where i.product_id = v_item.product_id
    on conflict (idempotency_key) do nothing;
    v_weight := v_weight + coalesce(v_item.weight_grams, 0) * v_item.quantity;
  end loop;

  v_address := concat_ws(E'\n',
    v_order.line1,
    nullif(v_order.line2, ''),
    nullif(v_order.landmark, ''),
    v_order.town_name || ', ' || v_order.district,
    v_order.state || ' - ' || v_order.pincode,
    'Phone: ' || v_order.phone
  );

  v_invoice_number := app_private.next_document_number('INV', 'public.invoice_number_seq'::regclass);
  insert into public.invoices (
    invoice_number, order_id, status, invoice_date,
    seller_name, seller_address, seller_phone, seller_email, seller_gstin,
    buyer_name, buyer_phone, billing_address, shipping_address,
    subtotal_paise, discount_paise, tax_paise, shipping_paise, total_paise,
    cod_amount_paise, payment_method, issued_by
  ) values (
    v_invoice_number, v_order.id, 'ISSUED', (now() at time zone v_tz)::date,
    v_business ->> 'legal_name', v_business ->> 'address',
    v_business ->> 'phone', coalesce(v_business ->> 'email', ''),
    coalesce(v_business ->> 'gstin', ''),
    v_order.recipient_name, v_order.phone, v_address, v_address,
    v_order.subtotal_paise, v_order.discount_paise, v_order.tax_paise,
    v_order.shipping_paise, v_order.total_paise, v_order.cod_amount_paise,
    'Cash on Delivery', v_uid
  ) returning id into v_invoice_id;

  v_shipment_number := app_private.next_document_number('SHP', 'public.shipment_number_seq'::regclass);
  insert into public.shipments (
    shipment_number, order_id, status, expected_cod_paise, package_count, weight_grams
  ) values (
    v_shipment_number, v_order.id, 'CREATED', v_order.cod_amount_paise, p_package_count, v_weight
  ) returning id into v_shipment_id;

  for v_i in 1..p_package_count loop
    insert into public.packages (shipment_id, package_number, package_code, status, weight_grams)
    values (
      v_shipment_id,
      v_shipment_number || '-P' || lpad(v_i::text, 2, '0'),
      'ibpkg_' || replace(gen_random_uuid()::text, '-', ''),
      'PACKED',
      v_weight
    ) returning id into v_package_id;
  end loop;

  update public.invoices set shipment_id = v_shipment_id where id = v_invoice_id;
  update public.orders
  set status = 'APPROVED', approved_by = v_uid, approved_at = now(), payment_status = 'PENDING'
  where id = v_order.id;

  perform app_private.log_shipment_event(
    v_shipment_id, 'SHIPMENT_CREATED', null, 'CREATED', 'SELLER_APP', v_uid,
    null, null, null, null,
    jsonb_build_object('invoice_id', v_invoice_id, 'invoice_number', v_invoice_number, 'package_count', p_package_count)
  );
  perform app_private.notify_user(
    v_order.customer_id, 'ORDER_APPROVED', 'Order ' || v_order.order_number || ' approved',
    'Your order has been approved and an invoice was generated. We will notify you when it is ready for pickup.',
    jsonb_build_object('order_id', v_order.id, 'invoice_number', v_invoice_number),
    'order-approved:' || v_order.id::text
  );
  perform app_private.notify_user(
    v_order.customer_id, 'INVOICE_GENERATED', 'Invoice ' || v_invoice_number || ' ready',
    'Your invoice is available in order details.',
    jsonb_build_object('order_id', v_order.id, 'invoice_id', v_invoice_id),
    'invoice-generated:' || v_invoice_id::text
  );
  perform app_private.write_audit(
    'ORDER_APPROVED', 'order', v_order.id,
    jsonb_build_object('status', 'PENDING_APPROVAL'),
    jsonb_build_object('status', 'APPROVED', 'invoice_number', v_invoice_number, 'shipment_number', v_shipment_number),
    'SELLER_APP', v_uid
  );

  return jsonb_build_object(
    'order_id', v_order.id, 'status', 'APPROVED',
    'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
    'shipment_id', v_shipment_id, 'shipment_number', v_shipment_number,
    'package_count', p_package_count, 'idempotent_replay', false
  );
end;
$$;

create or replace function public.reject_order(p_order_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_item record;
  v_reason text := trim(coalesce(p_reason, ''));
begin
  perform app_private.assert_true(char_length(v_reason) between 3 and 500, 'Enter a reason for rejecting the order.');
  select * into v_order from public.orders o where o.id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  if v_order.status = 'REJECTED' then
    return jsonb_build_object('order_id', v_order.id, 'status', 'REJECTED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(v_order.status = 'PENDING_APPROVAL', 'Only orders awaiting approval can be rejected.');

  for v_item in
    select * from public.order_items where order_id = v_order.id order by product_id
  loop
    if v_item.product_id is not null then
      update public.inventory
      set quantity_reserved = quantity_reserved - v_item.quantity, updated_at = now()
      where product_id = v_item.product_id and quantity_reserved >= v_item.quantity;
      perform app_private.assert_true(found, 'Reserved stock is inconsistent for this order.');
      insert into public.inventory_movements (
        product_id, movement_type, quantity_delta, reserved_delta,
        on_hand_after, reserved_after, reference_type, reference_id, reason,
        actor_id, idempotency_key
      )
      select i.product_id, 'RESERVATION_RELEASE', 0, -v_item.quantity,
        i.quantity_on_hand, i.quantity_reserved, 'ORDER', v_order.id,
        'Order rejected', v_uid,
        'order:' || v_order.id::text || ':reject-release:' || v_item.product_id::text
      from public.inventory i where i.product_id = v_item.product_id
      on conflict (idempotency_key) do nothing;
    end if;
  end loop;

  update public.orders
  set status = 'REJECTED', rejected_reason = v_reason, rejected_at = now(), payment_status = 'VOID'
  where id = v_order.id;

  perform app_private.notify_user(
    v_order.customer_id, 'ORDER_REJECTED', 'Order ' || v_order.order_number || ' could not be accepted',
    v_reason, jsonb_build_object('order_id', v_order.id),
    'order-rejected:' || v_order.id::text
  );
  perform app_private.write_audit(
    'ORDER_REJECTED', 'order', v_order.id,
    jsonb_build_object('status', 'PENDING_APPROVAL'),
    jsonb_build_object('status', 'REJECTED', 'reason', v_reason),
    'SELLER_APP', v_uid
  );
  return jsonb_build_object('order_id', v_order.id, 'status', 'REJECTED', 'idempotent_replay', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Packaging / pickup request
-- ---------------------------------------------------------------------------
create or replace function public.owner_add_package(p_order_id uuid, p_weight_grams integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_count integer;
  v_package_id uuid;
  v_package_code text;
  v_number text;
begin
  perform app_private.assert_true(coalesce(p_weight_grams, 0) >= 0, 'Weight cannot be negative.');
  select * into v_order from public.orders where id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  perform app_private.assert_true(v_order.status in ('APPROVED','READY_FOR_PICKUP'), 'Packages can only be added before pickup is requested.');
  select * into v_shipment from public.shipments where order_id = p_order_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');
  perform app_private.assert_true(v_shipment.status in ('CREATED','PACKED','READY_FOR_PICKUP'), 'Packages cannot be added after pickup started.');
  select count(*) into v_count from public.packages where shipment_id = v_shipment.id;
  perform app_private.assert_true(v_count < 20, 'Maximum 20 packages per shipment.');
  v_number := v_shipment.shipment_number || '-P' || lpad((v_count + 1)::text, 2, '0');
  v_package_code := 'ibpkg_' || replace(gen_random_uuid()::text, '-', '');
  insert into public.packages (shipment_id, package_number, package_code, status, weight_grams)
  values (v_shipment.id, v_number, v_package_code, 'PACKED', coalesce(p_weight_grams, 0))
  returning id into v_package_id;
  update public.shipments set package_count = v_count + 1 where id = v_shipment.id;
  perform app_private.write_audit('PACKAGE_ADDED', 'package', v_package_id, null, jsonb_build_object('order_id', p_order_id), 'SELLER_APP', v_uid);
  return jsonb_build_object('package_id', v_package_id, 'package_number', v_number, 'package_code', v_package_code, 'package_count', v_count + 1);
end;
$$;

create or replace function public.owner_seal_package(p_package_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_pkg public.packages%rowtype;
  v_shipment public.shipments%rowtype;
begin
  select * into v_pkg from public.packages where id = p_package_id for update;
  perform app_private.assert_true(v_pkg.id is not null, 'Package not found.');
  select * into v_shipment from public.shipments where id = v_pkg.shipment_id;
  perform app_private.assert_true(v_shipment.status in ('CREATED','PACKED','READY_FOR_PICKUP'), 'This package can no longer be sealed.');
  if v_pkg.is_sealed then
    return jsonb_build_object('package_id', v_pkg.id, 'is_sealed', true, 'idempotent_replay', true);
  end if;
  update public.packages
  set is_sealed = true, sealed_at = now(), sealed_by = v_uid
  where id = v_pkg.id;
  perform app_private.write_audit('PACKAGE_SEALED', 'package', v_pkg.id, jsonb_build_object('is_sealed', false), jsonb_build_object('is_sealed', true), 'SELLER_APP', v_uid);
  return jsonb_build_object('package_id', v_pkg.id, 'is_sealed', true, 'idempotent_replay', false);
end;
$$;

create or replace function public.owner_mark_ready_for_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_pending integer;
  v_count integer;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  select * into v_shipment from public.shipments where order_id = p_order_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');
  if v_order.status in ('READY_FOR_PICKUP','PICKUP_REQUESTED') then
    return jsonb_build_object('order_id', v_order.id, 'status', v_order.status, 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(v_order.status = 'APPROVED', 'Only approved orders can be marked ready for pickup.');
  select count(*), count(*) filter (where not is_sealed) into v_count, v_pending
  from public.packages where shipment_id = v_shipment.id;
  perform app_private.assert_true(v_count > 0, 'Add at least one package before marking ready.');
  perform app_private.assert_true(v_pending = 0, 'Seal every package before marking ready for pickup.');

  update public.packages set status = 'READY_FOR_PICKUP'
  where shipment_id = v_shipment.id and status = 'PACKED';
  update public.shipments set status = 'READY_FOR_PICKUP' where id = v_shipment.id;
  update public.orders set status = 'READY_FOR_PICKUP' where id = v_order.id;
  perform app_private.log_shipment_event(
    v_shipment.id, 'READY_FOR_PICKUP', v_shipment.status, 'READY_FOR_PICKUP',
    'SELLER_APP', v_uid, null, null, null, null,
    jsonb_build_object('package_count', v_count)
  );
  perform app_private.notify_user(
    v_order.customer_id, 'READY_FOR_PICKUP', 'Order ' || v_order.order_number || ' packed',
    'Your order is packed and waiting for pickup.',
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id),
    'ready-for-pickup:' || v_order.id::text
  );
  perform app_private.write_audit('ORDER_READY_FOR_PICKUP', 'order', v_order.id, jsonb_build_object('status', 'APPROVED'), jsonb_build_object('status', 'READY_FOR_PICKUP'), 'SELLER_APP', v_uid);
  return jsonb_build_object('order_id', v_order.id, 'status', 'READY_FOR_PICKUP', 'package_count', v_count, 'idempotent_replay', false);
end;
$$;

create or replace function public.owner_request_pickup(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_pickup public.pickup_requests%rowtype;
  v_count integer;
  v_otp text;
  v_id uuid;
  v_number text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  perform app_private.assert_true(v_order.id is not null, 'Order not found.');
  select * into v_shipment from public.shipments where order_id = p_order_id for update;
  perform app_private.assert_true(v_shipment.id is not null, 'Shipment not found.');

  select * into v_pickup from public.pickup_requests
  where shipment_id = v_shipment.id and status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED')
  order by requested_at desc limit 1;
  if v_pickup.id is not null then
    select n.data ->> 'otp' into v_otp
    from public.notifications n
    where n.type = 'PICKUP_OTP' and n.data ->> 'pickup_id' = v_pickup.id::text
    order by n.created_at desc limit 1;
    return jsonb_build_object(
      'pickup_id', v_pickup.id, 'pickup_number', v_pickup.pickup_number,
      'status', v_pickup.status, 'otp', v_otp, 'idempotent_replay', true
    );
  end if;

  perform app_private.assert_true(v_order.status = 'READY_FOR_PICKUP', 'Mark all packages ready before requesting pickup.');
  select count(*) into v_count from public.packages where shipment_id = v_shipment.id and is_sealed;
  perform app_private.assert_true(v_count > 0, 'No sealed packages are available for pickup.');

  v_number := app_private.next_document_number('PICK', 'public.pickup_number_seq'::regclass);
  insert into public.pickup_requests (
    pickup_number, shipment_id, order_id, status, package_count_expected, requested_by
  ) values (
    v_number, v_shipment.id, v_order.id, 'REQUESTED', v_count, v_uid
  ) returning id into v_id;

  v_otp := app_private.generate_otp_code();
  insert into public.pickup_otp_challenges (pickup_request_id, otp_hash, expires_at)
  values (v_id, extensions.crypt(v_otp, extensions.gen_salt('bf', 8)), now() + interval '30 minutes');

  update public.pickup_requests set status = 'REQUESTED' where id = v_id;
  update public.shipments set status = 'PICKUP_REQUESTED' where id = v_shipment.id;
  update public.packages set status = 'PICKUP_REQUESTED' where shipment_id = v_shipment.id and status = 'READY_FOR_PICKUP';
  update public.orders set status = 'PICKUP_REQUESTED' where id = v_order.id;

  perform app_private.log_shipment_event(
    v_shipment.id, 'PICKUP_REQUESTED', v_shipment.status, 'PICKUP_REQUESTED',
    'SELLER_APP', v_uid, null, null, null, null,
    jsonb_build_object('pickup_id', v_id, 'pickup_number', v_number, 'package_count', v_count)
  );
  perform app_private.notify_owner(
    'PICKUP_REQUESTED', 'Pickup ' || v_number || ' requested',
    'Share the pickup OTP with the delivery person only after verifying the packages at handover.',
    jsonb_build_object('pickup_id', v_id, 'order_id', v_order.id, 'otp', v_otp, 'shipment_id', v_shipment.id),
    null
  );
  perform app_private.notify_owner(
    'PICKUP_OTP', 'Pickup OTP for ' || v_number,
    'Pickup OTP: ' || v_otp || ' (valid for 30 minutes). Share it at physical handover.',
    jsonb_build_object('pickup_id', v_id, 'otp', v_otp, 'shipment_id', v_shipment.id),
    null
  );

  -- Automatic assignment is best-effort inside this transaction. If no
  -- eligible person exists, the request remains available for manual assignment.
  perform app_private.try_auto_assign_pickup(v_id);

  perform app_private.write_audit(
    'PICKUP_REQUESTED', 'pickup_request', v_id, null,
    jsonb_build_object('order_id', v_order.id, 'shipment_id', v_shipment.id, 'package_count', v_count),
    'SELLER_APP', v_uid
  );

  return jsonb_build_object(
    'pickup_id', v_id, 'pickup_number', v_number, 'status', 'REQUESTED',
    'otp', v_otp, 'package_count', v_count, 'idempotent_replay', false
  );
end;
$$;

create or replace function public.owner_get_pickup_otp(p_pickup_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_otp text;
  v_expires timestamptz;
begin
  perform app_private.require_owner();
  select n.data ->> 'otp' into v_otp
  from public.notifications n
  where n.type = 'PICKUP_OTP' and n.data ->> 'pickup_id' = p_pickup_id::text
  order by n.created_at desc limit 1;
  select expires_at into v_expires from public.pickup_otp_challenges where pickup_request_id = p_pickup_id;
  return jsonb_build_object('pickup_id', p_pickup_id, 'otp', v_otp, 'expires_at', v_expires);
end;
$$;

create or replace function public.owner_regenerate_pickup_otp(p_pickup_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_pickup public.pickup_requests%rowtype;
  v_otp text;
begin
  select * into v_pickup from public.pickup_requests where id = p_pickup_id for update;
  perform app_private.assert_true(v_pickup.id is not null, 'Pickup request not found.');
  perform app_private.assert_true(v_pickup.status in ('REQUESTED','ASSIGNED','ACCEPTED','ARRIVED'), 'This pickup can no longer receive an OTP.');
  v_otp := app_private.generate_otp_code();
  update public.pickup_otp_challenges
  set otp_hash = extensions.crypt(v_otp, extensions.gen_salt('bf', 8)),
      expires_at = now() + interval '30 minutes',
      attempts = 0,
      last_sent_at = now()
  where pickup_request_id = p_pickup_id;
  perform app_private.assert_true(found, 'Pickup OTP challenge not found.');
  perform app_private.notify_owner(
    'PICKUP_OTP', 'New pickup OTP for ' || v_pickup.pickup_number,
    'Pickup OTP: ' || v_otp || ' (valid for 30 minutes).',
    jsonb_build_object('pickup_id', p_pickup_id, 'otp', v_otp),
    null
  );
  perform app_private.write_audit('PICKUP_OTP_REGENERATED', 'pickup_request', p_pickup_id, null, null, 'SELLER_APP', v_uid);
  return jsonb_build_object('pickup_id', p_pickup_id, 'otp', v_otp);
end;
$$;
