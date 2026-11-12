-- IndiaBizz :: 0018 live updates and default configuration.
-- Seeds only neutral defaults; no fake catalogue, orders, staff or metrics.

do $$ begin
  alter publication supabase_realtime add table public.notifications;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.shipments;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.shipment_events;
exception when duplicate_object then null; end $$;

insert into public.app_settings (key, value, description, is_public)
values
  ('business',
   jsonb_build_object(
     'legal_name','', 'display_name','IndiaBizz', 'address','', 'phone','',
     'email','', 'gstin','', 'support_phone','', 'support_email','',
     'timezone','Asia/Kolkata', 'invoice_terms','',
     'pickup_town_id','', 'pickup_pincode',''
   ),
   'Business identity, invoice header and pickup location', true),
  ('commerce',
   jsonb_build_object(
     'tax_enabled', false,
     'default_tax_rate_bps', 0,
     'shipping_fee_paise', 0,
     'free_shipping_threshold_paise', 0
   ),
   'COD commerce pricing and tax configuration', true),
  ('policies',
   jsonb_build_object(
     'cancellation_allowed_before_pickup', true,
     'return_window_days', 7
   ),
   'Cancellation and return policy', true),
  ('logistics',
   jsonb_build_object(
     'auto_create_delivery_assignment', true,
     'require_photo', false,
     'max_delivery_attempts', 3
   ),
   'Delivery proof and attempt configuration', false)
on conflict (key) do nothing;

insert into public.assignment_policies (town_id)
select null::uuid
where not exists (
  select 1 from public.assignment_policies where town_id is null
);
