-- IndiaBizz :: 0017 private storage buckets and access policies.
-- All buckets are private. Catalogue images are readable by the storefront;
-- invoices are readable only by the owning customer and the owner; operational
-- evidence is readable only by the owner/assigned staff. Object keys follow
--   product-images  : catalogue/<product_id>/<file>
--   invoices        : <order_id>/<file>
--   shipping-labels : <shipment_id>/<file>
--   pickup-manifests: <pickup_id>/<file>
--   delivery-proofs : <shipment_id>/<file>
--   return-evidence : <order_id>/<file>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images',  'product-images',  false, 10485760, array['image/jpeg','image/png','image/webp']),
  ('invoices',        'invoices',        false, 5242880,  array['application/pdf']),
  ('shipping-labels', 'shipping-labels', false, 5242880,  array['application/pdf']),
  ('pickup-manifests','pickup-manifests',false, 5242880,  array['application/pdf']),
  ('delivery-proofs', 'delivery-proofs', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf']),
  ('return-evidence', 'return-evidence', false, 10485760, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types,
      updated_at = now();

-- Catalogue images: public to read, owner to write.
drop policy if exists ib_product_images_read on storage.objects;
create policy ib_product_images_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'product-images');

drop policy if exists ib_product_images_owner_insert on storage.objects;
create policy ib_product_images_owner_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-images' and public.is_owner());

drop policy if exists ib_product_images_owner_update on storage.objects;
create policy ib_product_images_owner_update on storage.objects
  for update to authenticated
  using (bucket_id = 'product-images' and public.is_owner())
  with check (bucket_id = 'product-images' and public.is_owner());

drop policy if exists ib_product_images_owner_delete on storage.objects;
create policy ib_product_images_owner_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-images' and public.is_owner());

-- Invoices: owner and the customer whose order id prefixes the object key.
drop policy if exists ib_invoices_read on storage.objects;
create policy ib_invoices_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'invoices'
    and (
      public.is_owner()
      or exists (
        select 1 from public.orders o
        where o.id = case
          when name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
            then substring(name from 1 for 36)::uuid
          else null
        end
        and o.customer_id = auth.uid()
      )
    )
  );

-- Shipping labels and pickup manifests: owner operations only.
drop policy if exists ib_labels_read on storage.objects;
create policy ib_labels_read on storage.objects
  for select to authenticated
  using (bucket_id in ('shipping-labels','pickup-manifests') and public.is_owner());

-- Delivery proofs: owner and the staff member assigned to the shipment.
drop policy if exists ib_proofs_read on storage.objects;
create policy ib_proofs_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'delivery-proofs'
    and (
      public.is_owner()
      or exists (
        select 1 from public.delivery_assignments da
        where da.staff_user_id = auth.uid()
          and da.shipment_id = case
            when name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
              then substring(name from 1 for 36)::uuid
            else null
          end
      )
    )
  );

drop policy if exists ib_proofs_staff_insert on storage.objects;
create policy ib_proofs_staff_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'delivery-proofs'
    and exists (
      select 1 from public.delivery_assignments da
      where da.staff_user_id = auth.uid()
        and da.shipment_id = case
          when name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
            then substring(name from 1 for 36)::uuid
          else null
        end
    )
  );

-- Return evidence: customer uploads/reads for their own order, owner reads.
drop policy if exists ib_return_evidence_read on storage.objects;
create policy ib_return_evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'return-evidence'
    and (
      public.is_owner()
      or exists (
        select 1 from public.orders o
        where o.id = case
          when name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
            then substring(name from 1 for 36)::uuid
          else null
        end
        and o.customer_id = auth.uid()
      )
    )
  );

drop policy if exists ib_return_evidence_insert on storage.objects;
create policy ib_return_evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'return-evidence'
    and exists (
      select 1 from public.orders o
      where o.id = case
        when name ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/'
          then substring(name from 1 for 36)::uuid
        else null
      end
      and o.customer_id = auth.uid()
    )
  );
