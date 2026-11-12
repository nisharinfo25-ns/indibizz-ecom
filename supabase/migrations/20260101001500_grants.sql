-- IndiaBizz :: 0016 API privileges + staff read model.
-- The REST API is deliberately read-only for clients. Every business write is
-- performed by a validated SECURITY DEFINER RPC. This migration narrows the
-- permissive Supabase defaults and adds staff-scoped read policies for live
-- tracking/realtime; it never grants INSERT/UPDATE/DELETE on business tables.

-- ---------------------------------------------------------------------------
-- Staff read model (direct PostgREST reads + Realtime would otherwise be blank)
-- ---------------------------------------------------------------------------
-- Cross-table RLS checks must go through a definer helper, otherwise
-- orders -> shipments -> orders policies recurse.
create or replace function public.staff_can_access_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.delivery_assignments da
    join public.shipments s on s.id = da.shipment_id
    where s.order_id = p_order_id
      and da.staff_user_id = auth.uid()
  )
  or exists (
    select 1
    from public.pickup_assignments pa
    join public.pickup_requests pk on pk.id = pa.pickup_request_id
    where pk.order_id = p_order_id
      and pa.staff_user_id = auth.uid()
  );
$$;

drop policy if exists pickup_assignments_staff_read on public.pickup_assignments;
create policy pickup_assignments_staff_read on public.pickup_assignments
  for select to authenticated using (staff_user_id = auth.uid());

drop policy if exists delivery_assignments_staff_read on public.delivery_assignments;
create policy delivery_assignments_staff_read on public.delivery_assignments
  for select to authenticated using (staff_user_id = auth.uid());

drop policy if exists shipments_staff_read on public.shipments;
create policy shipments_staff_read on public.shipments
  for select to authenticated using (
    exists (select 1 from public.pickup_assignments pa
            join public.pickup_requests pr on pr.id = pa.pickup_request_id
            where pr.shipment_id = shipments.id and pa.staff_user_id = auth.uid())
    or exists (select 1 from public.delivery_assignments da
               where da.shipment_id = shipments.id and da.staff_user_id = auth.uid())
  );

drop policy if exists packages_staff_read on public.packages;
create policy packages_staff_read on public.packages
  for select to authenticated using (
    exists (select 1 from public.pickup_assignments pa
            join public.pickup_requests pr on pr.id = pa.pickup_request_id
            where pr.shipment_id = packages.shipment_id and pa.staff_user_id = auth.uid())
    or exists (select 1 from public.delivery_assignments da
               where da.shipment_id = packages.shipment_id and da.staff_user_id = auth.uid())
  );

drop policy if exists orders_staff_read on public.orders;
create policy orders_staff_read on public.orders
  for select to authenticated using (public.staff_can_access_order(id));

drop policy if exists order_items_staff_read on public.order_items;
create policy order_items_staff_read on public.order_items
  for select to authenticated using (
    exists (select 1 from public.orders o where o.id = order_items.order_id)
  );

drop policy if exists shipment_events_staff_read on public.shipment_events;
create policy shipment_events_staff_read on public.shipment_events
  for select to authenticated using (
    exists (select 1 from public.delivery_assignments da
            where da.shipment_id = shipment_events.shipment_id and da.staff_user_id = auth.uid())
    or exists (select 1 from public.pickup_assignments pa
               join public.pickup_requests pr on pr.id = pa.pickup_request_id
               where pr.shipment_id = shipment_events.shipment_id and pa.staff_user_id = auth.uid())
  );

drop policy if exists cod_transactions_staff_read on public.cod_transactions;
create policy cod_transactions_staff_read on public.cod_transactions
  for select to authenticated using (staff_user_id = auth.uid());

drop policy if exists delivery_proofs_staff_read on public.delivery_proofs;
create policy delivery_proofs_staff_read on public.delivery_proofs
  for select to authenticated using (captured_by = auth.uid());

drop policy if exists delivery_attempts_staff_read on public.delivery_attempts;
create policy delivery_attempts_staff_read on public.delivery_attempts
  for select to authenticated using (attempted_by = auth.uid());

drop policy if exists barcode_scans_staff_read on public.barcode_scans;
create policy barcode_scans_staff_read on public.barcode_scans
  for select to authenticated using (scanned_by = auth.uid());

-- Partner administrators can inspect their own organisation's assignments.
drop policy if exists pickup_assignments_partner_admin_read on public.pickup_assignments;
create policy pickup_assignments_partner_admin_read on public.pickup_assignments
  for select to authenticated using (public.is_partner_admin_of(partner_id));

drop policy if exists delivery_assignments_partner_admin_read on public.delivery_assignments;
create policy delivery_assignments_partner_admin_read on public.delivery_assignments
  for select to authenticated using (public.is_partner_admin_of(partner_id));

drop policy if exists cod_transactions_partner_admin_read on public.cod_transactions;
create policy cod_transactions_partner_admin_read on public.cod_transactions
  for select to authenticated using (public.is_partner_admin_of(partner_id));

-- ---------------------------------------------------------------------------
-- Table privileges: no direct writes. RLS still narrows every row.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;

-- Intentionally public catalogue/geography (RLS limits rows to active records).
grant select on table
  public.towns,
  public.serviceable_pincodes,
  public.categories,
  public.products,
  public.product_images
to anon, authenticated;

-- Authenticated reads. Tables without a matching policy simply return no rows.
grant select on table
  public.profiles,
  public.delivery_partners,
  public.staff_profiles,
  public.partner_staff,
  public.staff_service_areas,
  public.partner_service_areas,
  public.user_devices,
  public.addresses,
  public.carts,
  public.cart_items,
  public.orders,
  public.order_items,
  public.invoices,
  public.shipments,
  public.packages,
  public.pickup_requests,
  public.pickup_assignments,
  public.delivery_assignments,
  public.pickup_verifications,
  public.pickup_manifests,
  public.barcode_scans,
  public.shipment_events,
  public.delivery_proofs,
  public.delivery_attempts,
  public.cod_settlements,
  public.cod_transactions,
  public.cod_settlement_items,
  public.return_requests,
  public.notifications,
  public.audit_logs,
  public.assignment_policies
to authenticated;

-- The service role bypasses RLS and is used only by trusted Edge Functions.
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- ---------------------------------------------------------------------------
-- Function privileges. Start closed, then open the intentional API surface.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;

-- Anonymous storefront API.
grant execute on function public.get_public_settings() to anon, authenticated;
grant execute on function public.list_serviceable_towns() to anon, authenticated;
grant execute on function public.check_serviceability(text, uuid) to anon, authenticated;

-- RLS helper functions must be executable by the role evaluating the policy.
grant execute on function public.is_owner() to authenticated;
grant execute on function public.is_partner_admin_of(uuid) to authenticated;
grant execute on function public.current_partner_id() to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.staff_can_access_order(uuid) to authenticated;

-- Customer application API.
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.update_my_profile(text, text) to authenticated;
grant execute on function public.list_my_addresses() to authenticated;
grant execute on function public.save_my_address(text, text, text, text, text, text, uuid, text, boolean, uuid) to authenticated;
grant execute on function public.delete_my_address(uuid) to authenticated;
grant execute on function public.cart_add_item(uuid, integer) to authenticated;
grant execute on function public.cart_set_quantity(uuid, integer) to authenticated;
grant execute on function public.cart_remove_item(uuid) to authenticated;
grant execute on function public.cart_clear() to authenticated;
grant execute on function public.get_my_cart() to authenticated;
grant execute on function public.quote_my_order(uuid) to authenticated;
grant execute on function public.place_order(uuid, text, text) to authenticated;
grant execute on function public.list_my_orders(integer, timestamptz) to authenticated;
grant execute on function public.get_my_order(uuid) to authenticated;
grant execute on function public.get_order_tracking(uuid) to authenticated;
grant execute on function public.cancel_order(uuid, text) to authenticated;
grant execute on function public.request_return(uuid, text, text, text) to authenticated;
grant execute on function public.list_my_notifications(integer) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
grant execute on function public.register_my_device(text, public.device_platform, text, text, text) to authenticated;
grant execute on function public.revoke_my_device(uuid) to authenticated;

-- Owner (Seller App) API.
grant execute on function public.owner_dashboard() to authenticated;
grant execute on function public.owner_list_categories() to authenticated;
grant execute on function public.owner_save_category(text, text, text, text, integer, boolean, uuid) to authenticated;
grant execute on function public.owner_list_products(text, public.product_status, uuid, boolean) to authenticated;
grant execute on function public.owner_save_product(uuid, text, text, bigint, integer, text, text, bigint, integer, public.product_status, boolean, integer, integer, text, uuid) to authenticated;
grant execute on function public.owner_adjust_stock(uuid, integer, text, text) to authenticated;
grant execute on function public.owner_inventory_movements(uuid, integer) to authenticated;
grant execute on function public.owner_add_product_image(uuid, text, text, boolean, boolean, integer) to authenticated;
grant execute on function public.owner_delete_product_image(uuid) to authenticated;
grant execute on function public.owner_list_orders(public.order_status, text, integer) to authenticated;
grant execute on function public.owner_get_order_admin(uuid) to authenticated;
grant execute on function public.approve_order(uuid, integer) to authenticated;
grant execute on function public.reject_order(uuid, text) to authenticated;
grant execute on function public.owner_add_package(uuid, integer) to authenticated;
grant execute on function public.owner_seal_package(uuid) to authenticated;
grant execute on function public.owner_mark_ready_for_pickup(uuid) to authenticated;
grant execute on function public.owner_request_pickup(uuid) to authenticated;
grant execute on function public.owner_get_pickup_otp(uuid) to authenticated;
grant execute on function public.owner_regenerate_pickup_otp(uuid) to authenticated;
grant execute on function public.owner_list_pickups(public.pickup_status) to authenticated;
grant execute on function public.owner_assign_pickup(uuid, uuid, text) to authenticated;
grant execute on function public.owner_cancel_pickup(uuid, text) to authenticated;
grant execute on function public.owner_reopen_pickup(uuid) to authenticated;
grant execute on function public.owner_list_deliveries(public.shipment_status) to authenticated;
grant execute on function public.owner_assign_delivery(uuid, uuid, text) to authenticated;
grant execute on function public.owner_list_delivery_personnel() to authenticated;
grant execute on function public.owner_set_staff_availability(uuid, boolean) to authenticated;
grant execute on function public.owner_suspend_delivery_person(uuid, text) to authenticated;
grant execute on function public.owner_reactivate_delivery_person(uuid) to authenticated;
grant execute on function public.owner_reset_delivery_otp(uuid) to authenticated;
grant execute on function public.owner_update_staff_profile(uuid, text, integer, text) to authenticated;
grant execute on function public.owner_set_staff_coverage(uuid, jsonb) to authenticated;
grant execute on function public.owner_create_staff_invite(text, public.user_role, text, uuid, boolean) to authenticated;
grant execute on function public.owner_list_staff_invites() to authenticated;
grant execute on function public.owner_revoke_staff_invite(uuid) to authenticated;
grant execute on function public.redeem_staff_invite(text) to authenticated;
grant execute on function public.owner_list_partners() to authenticated;
grant execute on function public.owner_save_partner(text, text, text, text, text, public.partner_status, bigint, integer, text, uuid) to authenticated;
grant execute on function public.owner_set_partner_status(uuid, public.partner_status, text) to authenticated;
grant execute on function public.owner_set_partner_coverage(uuid, jsonb) to authenticated;
grant execute on function public.owner_list_towns() to authenticated;
grant execute on function public.owner_save_town(text, text, text, double precision, double precision, boolean, uuid) to authenticated;
grant execute on function public.owner_add_serviceable_pincode(uuid, text, boolean) to authenticated;
grant execute on function public.owner_set_pincode_active(uuid, boolean) to authenticated;
grant execute on function public.owner_get_settings() to authenticated;
grant execute on function public.owner_update_settings(jsonb) to authenticated;
grant execute on function public.owner_update_assignment_policy(uuid, jsonb) to authenticated;
grant execute on function public.owner_list_cod_overview() to authenticated;
grant execute on function public.owner_list_cod_settlements(public.cod_settlement_status) to authenticated;
grant execute on function public.owner_confirm_cod_settlement(uuid, bigint, text) to authenticated;
grant execute on function public.owner_dispute_cod_settlement(uuid, text) to authenticated;
grant execute on function public.owner_cod_report(timestamptz, timestamptz) to authenticated;
grant execute on function public.owner_list_returns(public.return_status) to authenticated;
grant execute on function public.owner_decide_return(uuid, boolean, text) to authenticated;
grant execute on function public.owner_mark_return_received(uuid, boolean, text) to authenticated;
grant execute on function public.owner_close_return(uuid, text) to authenticated;
grant execute on function public.owner_list_audit_logs(integer, text, text) to authenticated;

-- Delivery staff API.
grant execute on function public.staff_dashboard() to authenticated;
grant execute on function public.staff_list_pickup_assignments(public.assignment_status, integer) to authenticated;
grant execute on function public.staff_get_pickup(uuid) to authenticated;
grant execute on function public.staff_accept_pickup(uuid) to authenticated;
grant execute on function public.staff_reject_pickup(uuid, text) to authenticated;
grant execute on function public.staff_arrive_at_pickup(uuid, double precision, double precision) to authenticated;
grant execute on function public.staff_scan_package(uuid, text, text, double precision, double precision, text) to authenticated;
grant execute on function public.staff_verify_pickup(uuid, text, integer, public.package_condition, text) to authenticated;
grant execute on function public.staff_fail_pickup(uuid, text, boolean) to authenticated;
grant execute on function public.staff_list_delivery_assignments(public.assignment_status, integer) to authenticated;
grant execute on function public.staff_get_delivery(uuid) to authenticated;
grant execute on function public.staff_accept_delivery(uuid) to authenticated;
grant execute on function public.staff_reject_delivery(uuid, text) to authenticated;
grant execute on function public.staff_mark_in_transit(uuid, double precision, double precision) to authenticated;
grant execute on function public.staff_mark_arrived_at_destination(uuid, double precision, double precision) to authenticated;
grant execute on function public.staff_start_out_for_delivery(uuid) to authenticated;
grant execute on function public.staff_complete_delivery(uuid, text, text, text, text, double precision, double precision, bigint) to authenticated;
grant execute on function public.staff_fail_delivery(uuid, public.delivery_failure_reason, text, timestamptz) to authenticated;
grant execute on function public.staff_resend_delivery_otp(uuid) to authenticated;
grant execute on function public.staff_set_availability(boolean) to authenticated;
grant execute on function public.staff_update_location(double precision, double precision) to authenticated;
grant execute on function public.staff_cod_summary() to authenticated;
grant execute on function public.staff_declare_cash_handover(text) to authenticated;

-- Partner administrator API.
grant execute on function public.partner_dashboard() to authenticated;
grant execute on function public.partner_list_tasks() to authenticated;
grant execute on function public.partner_list_staff() to authenticated;
grant execute on function public.partner_create_staff_invite(text, text) to authenticated;
grant execute on function public.partner_list_invites() to authenticated;
grant execute on function public.partner_revoke_invite(uuid) to authenticated;
grant execute on function public.partner_suspend_staff(uuid, text) to authenticated;
grant execute on function public.partner_reactivate_staff(uuid) to authenticated;
grant execute on function public.partner_set_staff_availability(uuid, boolean) to authenticated;

-- Service-role-only worker (also guarded inside the function).
grant execute on function public.system_expire_assignments(integer) to service_role;

-- ---------------------------------------------------------------------------
-- Future objects: no permissive defaults.
-- ---------------------------------------------------------------------------
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
