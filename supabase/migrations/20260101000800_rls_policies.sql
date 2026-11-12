-- IndiaBizz :: 0009 Row Level Security.
-- Write access is intentionally RPC-only for all business tables. RLS here
-- controls reads; privileged writes are validated inside SECURITY DEFINER
-- functions and audited.

alter table public.towns enable row level security;
alter table public.serviceable_pincodes enable row level security;
alter table public.profiles enable row level security;
alter table public.delivery_partners enable row level security;
alter table public.staff_profiles enable row level security;
alter table public.partner_staff enable row level security;
alter table public.staff_invites enable row level security;
alter table public.staff_service_areas enable row level security;
alter table public.partner_service_areas enable row level security;
alter table public.user_devices enable row level security;
alter table public.otp_request_log enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.inventory enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.addresses enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.invoices enable row level security;
alter table public.shipments enable row level security;
alter table public.packages enable row level security;
alter table public.pickup_requests enable row level security;
alter table public.pickup_otp_challenges enable row level security;
alter table public.pickup_assignments enable row level security;
alter table public.delivery_assignments enable row level security;
alter table public.delivery_otp_challenges enable row level security;
alter table public.pickup_verifications enable row level security;
alter table public.pickup_manifests enable row level security;
alter table public.barcode_scans enable row level security;
alter table public.shipment_events enable row level security;
alter table public.delivery_proofs enable row level security;
alter table public.delivery_attempts enable row level security;
alter table public.cod_settlements enable row level security;
alter table public.cod_transactions enable row level security;
alter table public.cod_settlement_items enable row level security;
alter table public.return_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;
alter table public.assignment_policies enable row level security;

-- Public catalogue -----------------------------------------------------------------
drop policy if exists towns_public_read on public.towns;
create policy towns_public_read on public.towns
  for select to anon, authenticated using (is_active);
drop policy if exists towns_owner_read on public.towns;
create policy towns_owner_read on public.towns
  for select to authenticated using (public.is_owner());

drop policy if exists pincodes_public_read on public.serviceable_pincodes;
create policy pincodes_public_read on public.serviceable_pincodes
  for select to anon, authenticated using (is_active);
drop policy if exists pincodes_owner_read on public.serviceable_pincodes;
create policy pincodes_owner_read on public.serviceable_pincodes
  for select to authenticated using (public.is_owner());

drop policy if exists categories_public_read on public.categories;
create policy categories_public_read on public.categories
  for select to anon, authenticated using (is_active);
drop policy if exists categories_owner_read on public.categories;
create policy categories_owner_read on public.categories
  for select to authenticated using (public.is_owner());

drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products
  for select to anon, authenticated using (status = 'ACTIVE');
drop policy if exists products_owner_read on public.products;
create policy products_owner_read on public.products
  for select to authenticated using (public.is_owner());

drop policy if exists product_images_public_read on public.product_images;
create policy product_images_public_read on public.product_images
  for select to anon, authenticated
  using (
    is_public
    and exists (
      select 1 from public.products p
      where p.id = product_images.product_id and p.status = 'ACTIVE'
    )
  );
drop policy if exists product_images_owner_read on public.product_images;
create policy product_images_owner_read on public.product_images
  for select to authenticated using (public.is_owner());

-- Profiles -------------------------------------------------------------------------
drop policy if exists profiles_self_read on public.profiles;
create policy profiles_self_read on public.profiles
  for select to authenticated using (id = auth.uid());
drop policy if exists profiles_owner_read on public.profiles;
create policy profiles_owner_read on public.profiles
  for select to authenticated using (public.is_owner());

-- Partner / staff reads -------------------------------------------------------------
drop policy if exists delivery_partners_owner_read on public.delivery_partners;
create policy delivery_partners_owner_read on public.delivery_partners
  for select to authenticated using (public.is_owner());
drop policy if exists delivery_partners_self_org_read on public.delivery_partners;
create policy delivery_partners_self_org_read on public.delivery_partners
  for select to authenticated using (id = public.current_partner_id());

drop policy if exists staff_profiles_owner_read on public.staff_profiles;
create policy staff_profiles_owner_read on public.staff_profiles
  for select to authenticated using (public.is_owner());
drop policy if exists staff_profiles_self_read on public.staff_profiles;
create policy staff_profiles_self_read on public.staff_profiles
  for select to authenticated using (user_id = auth.uid());

drop policy if exists partner_staff_owner_read on public.partner_staff;
create policy partner_staff_owner_read on public.partner_staff
  for select to authenticated using (public.is_owner());
drop policy if exists partner_staff_self_read on public.partner_staff;
create policy partner_staff_self_read on public.partner_staff
  for select to authenticated using (user_id = auth.uid());
drop policy if exists partner_staff_admin_read on public.partner_staff;
create policy partner_staff_admin_read on public.partner_staff
  for select to authenticated using (public.is_partner_admin_of(partner_id));

drop policy if exists staff_areas_owner_read on public.staff_service_areas;
create policy staff_areas_owner_read on public.staff_service_areas
  for select to authenticated using (public.is_owner());
drop policy if exists staff_areas_self_read on public.staff_service_areas;
create policy staff_areas_self_read on public.staff_service_areas
  for select to authenticated using (staff_user_id = auth.uid());

drop policy if exists partner_areas_owner_read on public.partner_service_areas;
create policy partner_areas_owner_read on public.partner_service_areas
  for select to authenticated using (public.is_owner());
drop policy if exists partner_areas_self_read on public.partner_service_areas;
create policy partner_areas_self_read on public.partner_service_areas
  for select to authenticated using (partner_id = public.current_partner_id());

drop policy if exists devices_self_read on public.user_devices;
create policy devices_self_read on public.user_devices
  for select to authenticated using (user_id = auth.uid());
drop policy if exists devices_owner_read on public.user_devices;
create policy devices_owner_read on public.user_devices
  for select to authenticated using (public.is_owner());

-- Customer private data -------------------------------------------------------------
drop policy if exists addresses_self_read on public.addresses;
create policy addresses_self_read on public.addresses
  for select to authenticated using (customer_id = auth.uid() and deleted_at is null);
drop policy if exists addresses_owner_read on public.addresses;
create policy addresses_owner_read on public.addresses
  for select to authenticated using (public.is_owner());

drop policy if exists orders_self_read on public.orders;
create policy orders_self_read on public.orders
  for select to authenticated using (customer_id = auth.uid());
drop policy if exists orders_owner_read on public.orders;
create policy orders_owner_read on public.orders
  for select to authenticated using (public.is_owner());

drop policy if exists order_items_self_read on public.order_items;
create policy order_items_self_read on public.order_items
  for select to authenticated using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.customer_id = auth.uid()
    )
  );
drop policy if exists order_items_owner_read on public.order_items;
create policy order_items_owner_read on public.order_items
  for select to authenticated using (public.is_owner());

drop policy if exists invoices_self_read on public.invoices;
create policy invoices_self_read on public.invoices
  for select to authenticated using (
    exists (
      select 1 from public.orders o
      where o.id = invoices.order_id and o.customer_id = auth.uid()
    )
  );
drop policy if exists invoices_owner_read on public.invoices;
create policy invoices_owner_read on public.invoices
  for select to authenticated using (public.is_owner());

drop policy if exists shipments_self_read on public.shipments;
create policy shipments_self_read on public.shipments
  for select to authenticated using (
    exists (
      select 1 from public.orders o
      where o.id = shipments.order_id and o.customer_id = auth.uid()
    )
  );
drop policy if exists shipments_owner_read on public.shipments;
create policy shipments_owner_read on public.shipments
  for select to authenticated using (public.is_owner());

drop policy if exists packages_self_read on public.packages;
create policy packages_self_read on public.packages
  for select to authenticated using (
    exists (
      select 1
      from public.shipments s
      join public.orders o on o.id = s.order_id
      where s.id = packages.shipment_id and o.customer_id = auth.uid()
    )
  );
drop policy if exists packages_owner_read on public.packages;
create policy packages_owner_read on public.packages
  for select to authenticated using (public.is_owner());

drop policy if exists shipment_events_self_read on public.shipment_events;
create policy shipment_events_self_read on public.shipment_events
  for select to authenticated using (
    exists (
      select 1
      from public.shipments s
      join public.orders o on o.id = s.order_id
      where s.id = shipment_events.shipment_id and o.customer_id = auth.uid()
    )
  );
drop policy if exists shipment_events_owner_read on public.shipment_events;
create policy shipment_events_owner_read on public.shipment_events
  for select to authenticated using (public.is_owner());

drop policy if exists returns_self_read on public.return_requests;
create policy returns_self_read on public.return_requests
  for select to authenticated using (customer_id = auth.uid());
drop policy if exists returns_owner_read on public.return_requests;
create policy returns_owner_read on public.return_requests
  for select to authenticated using (public.is_owner());

drop policy if exists notifications_self_read on public.notifications;
create policy notifications_self_read on public.notifications
  for select to authenticated using (recipient_id = auth.uid());

-- Owner operational data ------------------------------------------------------------
drop policy if exists pickup_requests_owner_read on public.pickup_requests;
create policy pickup_requests_owner_read on public.pickup_requests
  for select to authenticated using (public.is_owner());
drop policy if exists pickup_assignments_owner_read on public.pickup_assignments;
create policy pickup_assignments_owner_read on public.pickup_assignments
  for select to authenticated using (public.is_owner());
drop policy if exists delivery_assignments_owner_read on public.delivery_assignments;
create policy delivery_assignments_owner_read on public.delivery_assignments
  for select to authenticated using (public.is_owner());
drop policy if exists pickup_verifications_owner_read on public.pickup_verifications;
create policy pickup_verifications_owner_read on public.pickup_verifications
  for select to authenticated using (public.is_owner());
drop policy if exists pickup_manifests_owner_read on public.pickup_manifests;
create policy pickup_manifests_owner_read on public.pickup_manifests
  for select to authenticated using (public.is_owner());
drop policy if exists barcode_scans_owner_read on public.barcode_scans;
create policy barcode_scans_owner_read on public.barcode_scans
  for select to authenticated using (public.is_owner());
drop policy if exists delivery_proofs_owner_read on public.delivery_proofs;
create policy delivery_proofs_owner_read on public.delivery_proofs
  for select to authenticated using (public.is_owner());
drop policy if exists delivery_attempts_owner_read on public.delivery_attempts;
create policy delivery_attempts_owner_read on public.delivery_attempts
  for select to authenticated using (public.is_owner());
drop policy if exists cod_transactions_owner_read on public.cod_transactions;
create policy cod_transactions_owner_read on public.cod_transactions
  for select to authenticated using (public.is_owner());
drop policy if exists cod_settlements_owner_read on public.cod_settlements;
create policy cod_settlements_owner_read on public.cod_settlements
  for select to authenticated using (public.is_owner());
drop policy if exists cod_settlement_items_owner_read on public.cod_settlement_items;
create policy cod_settlement_items_owner_read on public.cod_settlement_items
  for select to authenticated using (public.is_owner());
drop policy if exists audit_owner_read on public.audit_logs;
create policy audit_owner_read on public.audit_logs
  for select to authenticated using (public.is_owner());
drop policy if exists policies_owner_read on public.assignment_policies;
create policy policies_owner_read on public.assignment_policies
  for select to authenticated using (public.is_owner());

-- Sensitive tables with no client read path at all:
-- app_settings, carts, cart_items, inventory, inventory_movements,
-- pickup_otp_challenges, delivery_otp_challenges, pickup_requests has owner
-- read but never the OTP hash, staff_invites, otp_request_log.
