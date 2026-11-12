-- IndiaBizz :: 0014 COD reconciliation, returns administration and audit access.

create or replace function public.owner_list_cod_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
begin
  return jsonb_build_object(
    'summary', jsonb_build_object(
      'expected_paise', coalesce((select sum(amount_paise) from public.cod_transactions where entry_type = 'EXPECTED'), 0),
      'collected_paise', coalesce((select sum(amount_paise) from public.cod_transactions where entry_type = 'COLLECTED'), 0),
      'handed_over_paise', coalesce((select -sum(amount_paise) from public.cod_transactions where entry_type = 'HANDOVER'), 0),
      'handover_reversed_paise', coalesce((select sum(amount_paise) from public.cod_transactions where entry_type = 'HANDOVER_REVERSAL'), 0),
      'cash_with_staff_paise', coalesce((
        select sum(amount_paise) from public.cod_transactions
        where entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL')
      ), 0),
      'pending_verification_paise', coalesce((
        select sum(handed_over_paise) from public.cod_settlements where status = 'PENDING_VERIFICATION'
      ), 0),
      'verified_paise', coalesce((
        select sum(counted_paise) from public.cod_settlements where status = 'VERIFIED'
      ), 0),
      'shortage_paise', coalesce((
        select sum(shortage_paise) from public.cod_settlements where status = 'VERIFIED'
      ), 0),
      'excess_paise', coalesce((
        select sum(excess_paise) from public.cod_settlements where status = 'VERIFIED'
      ), 0),
      'open_settlements', (select count(*) from public.cod_settlements where status = 'PENDING_VERIFICATION')
    ),
    'staff_balances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'staff_user_id', b.staff_user_id,
        'staff_name', coalesce(sp.display_name, ps.display_name, pr.full_name),
        'staff_phone', coalesce(sp.phone, ps.phone, pr.phone),
        'staff_type', case when sp.id is not null then 'OWN' when ps.id is not null then 'PARTNER' else 'UNKNOWN' end,
        'partner_name', dp.name,
        'collected_paise', b.collected_paise,
        'declared_handover_paise', b.declared_handover_paise,
        'reversed_handover_paise', b.reversed_handover_paise,
        'cash_in_custody_paise', b.cash_in_custody_paise,
        'last_collection_at', b.last_collection_at
      ) order by b.cash_in_custody_paise desc, staff_name)
      from (
        select
          ct.staff_user_id,
          sum(case when ct.entry_type = 'COLLECTED' then ct.amount_paise else 0 end)::bigint as collected_paise,
          (-sum(case when ct.entry_type = 'HANDOVER' then ct.amount_paise else 0 end))::bigint as declared_handover_paise,
          sum(case when ct.entry_type = 'HANDOVER_REVERSAL' then ct.amount_paise else 0 end)::bigint as reversed_handover_paise,
          sum(case when ct.entry_type in ('COLLECTED','HANDOVER','HANDOVER_REVERSAL') then ct.amount_paise else 0 end)::bigint as cash_in_custody_paise,
          max(case when ct.entry_type = 'COLLECTED' then ct.created_at end) as last_collection_at
        from public.cod_transactions ct
        where ct.staff_user_id is not null
        group by ct.staff_user_id
      ) b
      join public.profiles pr on pr.id = b.staff_user_id
      left join public.staff_profiles sp on sp.user_id = b.staff_user_id
      left join public.partner_staff ps on ps.user_id = b.staff_user_id
      left join public.delivery_partners dp on dp.id = ps.partner_id
    ), '[]'::jsonb),
    'settlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id, 'settlement_number', cs.settlement_number,
        'staff_user_id', cs.staff_user_id,
        'staff_name', coalesce(sp.display_name, ps.display_name, pr.full_name),
        'staff_type', cs.staff_type, 'partner_name', dp.name,
        'expected_paise', cs.expected_paise, 'collected_paise', cs.collected_paise,
        'handed_over_paise', cs.handed_over_paise, 'counted_paise', cs.counted_paise,
        'shortage_paise', cs.shortage_paise, 'excess_paise', cs.excess_paise,
        'status', cs.status, 'declared_at', cs.declared_at, 'verified_at', cs.verified_at,
        'note', cs.note, 'rejection_reason', cs.rejection_reason,
        'item_count', (select count(*) from public.cod_settlement_items csi where csi.settlement_id = cs.id)
      ) order by cs.declared_at desc)
      from (
        select * from public.cod_settlements order by declared_at desc limit 50
      ) cs
      join public.profiles pr on pr.id = cs.staff_user_id
      left join public.staff_profiles sp on sp.user_id = cs.staff_user_id
      left join public.partner_staff ps on ps.user_id = cs.staff_user_id
      left join public.delivery_partners dp on dp.id = cs.partner_id
    ), '[]'::jsonb),
    'recent_transactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'entry_type', t.entry_type, 'amount_paise', t.amount_paise,
        'shipment_id', t.shipment_id, 'order_id', t.order_id,
        'staff_user_id', t.staff_user_id, 'settlement_id', t.settlement_id,
        'description', t.description, 'created_at', t.created_at
      ) order by t.created_at desc)
      from (
        select * from public.cod_transactions order by created_at desc limit 50
      ) t
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.owner_list_cod_settlements(p_status public.cod_settlement_status default null)
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
      'id', cs.id, 'settlement_number', cs.settlement_number,
      'staff_user_id', cs.staff_user_id,
      'staff_name', coalesce(sp.display_name, ps.display_name, pr.full_name),
      'staff_phone', coalesce(sp.phone, ps.phone, pr.phone),
      'staff_type', cs.staff_type, 'partner_name', dp.name,
      'period_start', cs.period_start, 'period_end', cs.period_end,
      'expected_paise', cs.expected_paise, 'collected_paise', cs.collected_paise,
      'handed_over_paise', cs.handed_over_paise, 'counted_paise', cs.counted_paise,
      'shortage_paise', cs.shortage_paise, 'excess_paise', cs.excess_paise,
      'status', cs.status, 'note', cs.note, 'rejection_reason', cs.rejection_reason,
      'declared_at', cs.declared_at, 'verified_at', cs.verified_at,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'shipment_id', csi.shipment_id,
          'shipment_number', s.shipment_number,
          'order_number', o.order_number,
          'expected_paise', csi.expected_paise,
          'collected_paise', csi.collected_paise
        ) order by csi.created_at)
        from public.cod_settlement_items csi
        join public.shipments s on s.id = csi.shipment_id
        join public.orders o on o.id = s.order_id
        where csi.settlement_id = cs.id
      ), '[]'::jsonb)
    ) order by cs.declared_at desc)
    from public.cod_settlements cs
    join public.profiles pr on pr.id = cs.staff_user_id
    left join public.staff_profiles sp on sp.user_id = cs.staff_user_id
    left join public.partner_staff ps on ps.user_id = cs.staff_user_id
    left join public.delivery_partners dp on dp.id = cs.partner_id
    where p_status is null or cs.status = p_status
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_confirm_cod_settlement(
  p_settlement_id uuid,
  p_counted_paise bigint,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_cs public.cod_settlements%rowtype;
  v_shortage bigint;
  v_excess bigint;
begin
  perform app_private.assert_true(coalesce(p_counted_paise, -1) >= 0, 'Counted cash cannot be negative.');
  select * into v_cs from public.cod_settlements where id = p_settlement_id for update;
  perform app_private.assert_true(v_cs.id is not null, 'Settlement not found.');
  if v_cs.status = 'VERIFIED' then
    return jsonb_build_object('settlement_id', v_cs.id, 'status', 'VERIFIED', 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(v_cs.status = 'PENDING_VERIFICATION', 'Only pending settlements can be verified.');
  v_shortage := greatest(v_cs.handed_over_paise - p_counted_paise, 0);
  v_excess := greatest(p_counted_paise - v_cs.handed_over_paise, 0);

  update public.cod_settlements
  set counted_paise = p_counted_paise,
      shortage_paise = v_shortage,
      excess_paise = v_excess,
      status = 'VERIFIED',
      verified_by = v_uid,
      verified_at = now(),
      note = case when p_note is null or p_note = '' then note else note || E'\nVerification: ' || p_note end
  where id = p_settlement_id;

  insert into public.cod_transactions (
    shipment_id, order_id, customer_id, staff_user_id, partner_id, settlement_id,
    entry_type, amount_paise, description, recorded_by, idempotency_key
  )
  select
    (select csi.shipment_id from public.cod_settlement_items csi where csi.settlement_id = p_settlement_id order by csi.created_at limit 1),
    s.order_id, o.customer_id, v_cs.staff_user_id, v_cs.partner_id, p_settlement_id,
    'SETTLEMENT_CONFIRMED', 0,
    'Cash settlement verified by owner',
    v_uid, 'settlement:' || p_settlement_id::text || ':confirmed'
  from public.cod_settlements cs
  join public.cod_settlement_items csi on csi.settlement_id = cs.id
  join public.shipments s on s.id = csi.shipment_id
  join public.orders o on o.id = s.order_id
  where cs.id = p_settlement_id
  limit 1
  on conflict (idempotency_key) do nothing;

  if p_counted_paise <> v_cs.handed_over_paise then
    insert into public.cod_transactions (
      shipment_id, order_id, customer_id, staff_user_id, partner_id, settlement_id,
      entry_type, amount_paise, description, recorded_by, idempotency_key, metadata
    )
    select
      (select csi.shipment_id from public.cod_settlement_items csi where csi.settlement_id = p_settlement_id order by csi.created_at limit 1),
      s.order_id, o.customer_id, v_cs.staff_user_id, v_cs.partner_id, p_settlement_id,
      'ADJUSTMENT', p_counted_paise - v_cs.handed_over_paise,
      case when v_shortage > 0 then 'Cash shortage at settlement' else 'Cash excess at settlement' end,
      v_uid, 'settlement:' || p_settlement_id::text || ':adjustment',
      jsonb_build_object('shortage_paise', v_shortage, 'excess_paise', v_excess)
    from public.cod_settlements cs
    join public.cod_settlement_items csi on csi.settlement_id = cs.id
    join public.shipments s on s.id = csi.shipment_id
    join public.orders o on o.id = s.order_id
    where cs.id = p_settlement_id
    limit 1
    on conflict (idempotency_key) do nothing;
  end if;

  -- Cash is only fully settled after the owner verifies the counted amount.
  update public.orders o
  set payment_status = 'SETTLED'
  where o.id in (
    select s.order_id
    from public.cod_settlement_items csi
    join public.shipments s on s.id = csi.shipment_id
    where csi.settlement_id = p_settlement_id
  )
    and o.payment_status = 'COLLECTED';

  perform app_private.notify_user(
    v_cs.staff_user_id, 'COD_SETTLEMENT_VERIFIED', 'Cash settlement verified',
    'Settlement ' || v_cs.settlement_number || ' verified. Counted: ₹' ||
      to_char(p_counted_paise / 100.0, 'FM999999990.00') ||
      case when v_shortage > 0 then '. Shortage: ₹' || to_char(v_shortage / 100.0, 'FM999999990.00')
           when v_excess > 0 then '. Excess: ₹' || to_char(v_excess / 100.0, 'FM999999990.00')
           else '. Amount matched.' end,
    jsonb_build_object('settlement_id', p_settlement_id, 'shortage_paise', v_shortage, 'excess_paise', v_excess),
    'cod-settlement-verified:' || p_settlement_id::text
  );
  perform app_private.write_audit('COD_SETTLEMENT_VERIFIED', 'cod_settlement', p_settlement_id,
    jsonb_build_object('status', 'PENDING_VERIFICATION', 'handed_over_paise', v_cs.handed_over_paise),
    jsonb_build_object('status', 'VERIFIED', 'counted_paise', p_counted_paise, 'shortage_paise', v_shortage, 'excess_paise', v_excess),
    'SELLER_APP', v_uid);
  return jsonb_build_object(
    'settlement_id', p_settlement_id, 'status', 'VERIFIED',
    'counted_paise', p_counted_paise, 'shortage_paise', v_shortage,
    'excess_paise', v_excess, 'idempotent_replay', false
  );
end;
$$;

create or replace function public.owner_dispute_cod_settlement(p_settlement_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_cs public.cod_settlements%rowtype;
  v_item record;
begin
  perform app_private.assert_true(char_length(trim(coalesce(p_reason, ''))) between 3 and 500, 'Enter a dispute reason.');
  select * into v_cs from public.cod_settlements where id = p_settlement_id for update;
  perform app_private.assert_true(v_cs.id is not null, 'Settlement not found.');
  perform app_private.assert_true(v_cs.status = 'PENDING_VERIFICATION', 'Only pending settlements can be disputed.');

  update public.cod_settlements
  set status = 'DISPUTED', rejection_reason = trim(p_reason)
  where id = p_settlement_id;

  for v_item in
    select csi.*, s.order_id, o.customer_id
    from public.cod_settlement_items csi
    join public.shipments s on s.id = csi.shipment_id
    join public.orders o on o.id = s.order_id
    where csi.settlement_id = p_settlement_id
  loop
    insert into public.cod_transactions (
      shipment_id, order_id, customer_id, staff_user_id, partner_id, settlement_id,
      entry_type, amount_paise, description, recorded_by, idempotency_key
    ) values (
      v_item.shipment_id, v_item.order_id, v_item.customer_id, v_cs.staff_user_id,
      v_cs.partner_id, p_settlement_id, 'HANDOVER_REVERSAL', v_item.collected_paise,
      'Handover disputed: cash returned to staff custody', v_uid,
      'settlement:' || p_settlement_id::text || ':reversal:' || v_item.shipment_id::text
    ) on conflict (idempotency_key) do nothing;
  end loop;

  perform app_private.notify_user(
    v_cs.staff_user_id, 'COD_SETTLEMENT_DISPUTED', 'Cash settlement disputed',
    'Settlement ' || v_cs.settlement_number || ' was disputed. Reason: ' || trim(p_reason),
    jsonb_build_object('settlement_id', p_settlement_id, 'reason', trim(p_reason)),
    'cod-settlement-disputed:' || p_settlement_id::text
  );
  perform app_private.write_audit('COD_SETTLEMENT_DISPUTED', 'cod_settlement', p_settlement_id,
    jsonb_build_object('status', 'PENDING_VERIFICATION'),
    jsonb_build_object('status', 'DISPUTED', 'reason', trim(p_reason)), 'SELLER_APP', v_uid);
  return jsonb_build_object('settlement_id', p_settlement_id, 'status', 'DISPUTED');
end;
$$;

create or replace function public.owner_cod_report(p_from timestamptz default null, p_to timestamptz default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_from timestamptz := coalesce(p_from, now() - interval '30 days');
  v_to timestamptz := coalesce(p_to, now());
begin
  perform app_private.require_owner();
  return jsonb_build_object(
    'from', v_from,
    'to', v_to,
    'totals', jsonb_build_object(
      'delivered_shipments', (
        select count(*) from public.shipments s
        where s.delivered_at between v_from and v_to
      ),
      'expected_paise', coalesce((
        select sum(amount_paise) from public.cod_transactions
        where entry_type = 'EXPECTED' and created_at between v_from and v_to
      ), 0),
      'collected_paise', coalesce((
        select sum(amount_paise) from public.cod_transactions
        where entry_type = 'COLLECTED' and created_at between v_from and v_to
      ), 0),
      'handed_over_paise', coalesce((
        select -sum(amount_paise) from public.cod_transactions
        where entry_type = 'HANDOVER' and created_at between v_from and v_to
      ), 0),
      'verified_paise', coalesce((
        select sum(counted_paise) from public.cod_settlements
        where status = 'VERIFIED' and verified_at between v_from and v_to
      ), 0),
      'shortage_paise', coalesce((
        select sum(shortage_paise) from public.cod_settlements
        where status = 'VERIFIED' and verified_at between v_from and v_to
      ), 0),
      'excess_paise', coalesce((
        select sum(excess_paise) from public.cod_settlements
        where status = 'VERIFIED' and verified_at between v_from and v_to
      ), 0)
    ),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', d.day,
        'expected_paise', d.expected_paise,
        'collected_paise', d.collected_paise
      ) order by d.day)
      from (
        select
          (ct.created_at at time zone 'Asia/Kolkata')::date as day,
          sum(case when ct.entry_type = 'EXPECTED' then ct.amount_paise else 0 end)::bigint as expected_paise,
          sum(case when ct.entry_type = 'COLLECTED' then ct.amount_paise else 0 end)::bigint as collected_paise
        from public.cod_transactions ct
        where ct.created_at between v_from and v_to
        group by 1
      ) d
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Returns administration
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_returns(p_status public.return_status default null)
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
      'id', r.id, 'return_number', r.return_number, 'status', r.status,
      'reason', r.reason, 'description', r.description,
      'evidence_path', r.evidence_path,
      'order_id', o.id, 'order_number', o.order_number,
      'customer_name', pr.full_name, 'customer_phone', pr.phone,
      'order_total_paise', o.total_paise, 'delivered_at', o.delivered_at,
      'created_at', r.created_at, 'decided_at', r.decided_at,
      'rejection_reason', r.rejection_reason, 'received_at', r.received_at,
      'resolution_note', r.resolution_note, 'closed_at', r.closed_at,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
          'product_name', oi.product_name, 'sku', oi.sku,
          'quantity', oi.quantity, 'line_total_paise', oi.line_total_paise
        ) order by oi.created_at)
        from public.order_items oi where oi.order_id = o.id
      ), '[]'::jsonb)
    ) order by r.created_at desc)
    from public.return_requests r
    join public.orders o on o.id = r.order_id
    join public.profiles pr on pr.id = r.customer_id
    where p_status is null or r.status = p_status
  ), '[]'::jsonb);
end;
$$;

create or replace function public.owner_decide_return(
  p_return_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_return public.return_requests%rowtype;
  v_note text := trim(coalesce(p_note, ''));
begin
  select * into v_return from public.return_requests where id = p_return_id for update;
  perform app_private.assert_true(v_return.id is not null, 'Return request not found.');
  if v_return.status = 'APPROVED' or v_return.status = 'REJECTED' then
    return jsonb_build_object('return_id', v_return.id, 'status', v_return.status, 'idempotent_replay', true);
  end if;
  perform app_private.assert_true(v_return.status = 'REQUESTED', 'This return request has already been processed.');

  if p_approve then
    update public.return_requests
    set status = 'APPROVED', decided_by = v_uid, decided_at = now(),
        resolution_note = nullif(v_note, '')
    where id = p_return_id;
    update public.orders set status = 'RETURN_REQUESTED' where id = v_return.order_id;
    perform app_private.notify_user(
      v_return.customer_id, 'RETURN_APPROVED', 'Return request approved',
      'Your return request ' || v_return.return_number || ' has been approved. Please keep the items ready for collection.',
      jsonb_build_object('return_id', v_return.id),
      'return-approved:' || v_return.id::text
    );
  else
    perform app_private.assert_true(char_length(v_note) between 3 and 500, 'Enter a reason for rejecting the return.');
    update public.return_requests
    set status = 'REJECTED', decided_by = v_uid, decided_at = now(),
        rejection_reason = v_note, closed_at = now()
    where id = p_return_id;
    update public.orders set status = 'DELIVERED' where id = v_return.order_id and status = 'RETURN_REQUESTED';
    perform app_private.notify_user(
      v_return.customer_id, 'RETURN_REJECTED', 'Return request rejected',
      'Your return request ' || v_return.return_number || ' was rejected. Reason: ' || v_note,
      jsonb_build_object('return_id', v_return.id),
      'return-rejected:' || v_return.id::text
    );
  end if;

  perform app_private.write_audit(
    case when p_approve then 'RETURN_APPROVED' else 'RETURN_REJECTED' end,
    'return_request', p_return_id,
    jsonb_build_object('status', 'REQUESTED'),
    jsonb_build_object('status', case when p_approve then 'APPROVED' else 'REJECTED' end, 'note', v_note),
    'SELLER_APP', v_uid);
  return jsonb_build_object('return_id', p_return_id, 'status', case when p_approve then 'APPROVED' else 'REJECTED' end, 'idempotent_replay', false);
end;
$$;

create or replace function public.owner_mark_return_received(
  p_return_id uuid,
  p_restock boolean default false,
  p_resolution_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
  v_return public.return_requests%rowtype;
  v_order public.orders%rowtype;
  v_shipment public.shipments%rowtype;
  v_item record;
begin
  select * into v_return from public.return_requests where id = p_return_id for update;
  perform app_private.assert_true(v_return.id is not null, 'Return request not found.');
  perform app_private.assert_true(v_return.status in ('APPROVED','IN_TRANSIT','RECEIVED'), 'Only approved or in-transit returns can be received.');
  select * into v_order from public.orders where id = v_return.order_id for update;
  select * into v_shipment from public.shipments where order_id = v_return.order_id;

  if v_return.status = 'RECEIVED' then
    return jsonb_build_object('return_id', p_return_id, 'status', 'RECEIVED', 'idempotent_replay', true);
  end if;

  update public.return_requests
  set status = 'RECEIVED', received_at = now(),
      resolution_note = coalesce(nullif(trim(coalesce(p_resolution_note, '')), ''), resolution_note)
  where id = p_return_id;

  if p_restock then
    for v_item in
      select * from public.order_items where order_id = v_order.id and product_id is not null
    loop
      insert into public.inventory_movements (
        product_id, movement_type, quantity_delta, reserved_delta,
        on_hand_after, reserved_after, reference_type, reference_id, reason,
        actor_id, idempotency_key
      )
      select i.product_id, 'RETURN', v_item.quantity, 0,
        i.quantity_on_hand + v_item.quantity, i.quantity_reserved,
        'RETURN', p_return_id, 'Return received and restocked', v_uid,
        'return:' || p_return_id::text || ':restock:' || v_item.product_id::text
      from public.inventory i
      where i.product_id = v_item.product_id
      on conflict (idempotency_key) do nothing;

      -- Only increment when the movement row was actually created. The
      -- idempotency key and the inventory increment therefore stay atomic.
      if found then
        update public.inventory i
        set quantity_on_hand = i.quantity_on_hand + v_item.quantity, updated_at = now()
        where i.product_id = v_item.product_id;
      end if;
    end loop;
  end if;

  update public.orders set status = 'RETURNED', closed_at = now() where id = v_order.id;
  if v_shipment.id is not null then
    update public.shipments set status = 'RETURNED_SUCCESSFULLY', returned_at = now() where id = v_shipment.id;
    update public.packages set status = 'RETURNED' where shipment_id = v_shipment.id and status not in ('CANCELLED');
    perform app_private.log_shipment_event(
      v_shipment.id, 'RETURNED_SUCCESSFULLY', v_shipment.status, 'RETURNED_SUCCESSFULLY',
      'SELLER_APP', v_uid, null, null, null, null,
      jsonb_build_object('return_id', p_return_id)
    );
  end if;
  perform app_private.notify_user(
    v_return.customer_id, 'RETURN_UPDATED', 'Return received',
    'We received your return. The seller will contact you if a COD refund or adjustment is due.',
    jsonb_build_object('return_id', p_return_id),
    'return-received:' || p_return_id::text
  );
  perform app_private.write_audit('RETURN_RECEIVED', 'return_request', p_return_id,
    jsonb_build_object('status', v_return.status),
    jsonb_build_object('status', 'RECEIVED', 'restock', p_restock),
    'SELLER_APP', v_uid);
  return jsonb_build_object('return_id', p_return_id, 'status', 'RECEIVED', 'restocked', p_restock);
end;
$$;

create or replace function public.owner_close_return(p_return_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := app_private.require_owner();
begin
  update public.return_requests
  set status = 'CLOSED', closed_at = now(),
      resolution_note = coalesce(nullif(trim(coalesce(p_note, '')), ''), resolution_note)
  where id = p_return_id and status in ('RECEIVED','APPROVED','IN_TRANSIT');
  perform app_private.assert_true(found, 'Return request cannot be closed.');
  perform app_private.write_audit('RETURN_CLOSED', 'return_request', p_return_id, null, jsonb_build_object('note', p_note), 'SELLER_APP', v_uid);
  return jsonb_build_object('return_id', p_return_id, 'status', 'CLOSED');
end;
$$;

-- ---------------------------------------------------------------------------
-- Audit access
-- ---------------------------------------------------------------------------
create or replace function public.owner_list_audit_logs(
  p_limit integer default 100,
  p_entity_type text default null,
  p_search text default null
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
      'id', a.id, 'actor_id', a.actor_id, 'actor_name', pr.full_name,
      'actor_role', a.actor_role, 'action', a.action,
      'entity_type', a.entity_type, 'entity_id', a.entity_id,
      'before_data', a.before_data, 'after_data', a.after_data,
      'source', a.source, 'created_at', a.created_at
    ) order by a.created_at desc)
    from (
      select * from public.audit_logs
      where (p_entity_type is null or entity_type = p_entity_type)
        and (p_search is null or p_search = '' or action ilike '%' || p_search || '%' or entity_type ilike '%' || p_search || '%')
      order by created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) a
    left join public.profiles pr on pr.id = a.actor_id
  ), '[]'::jsonb);
end;
$$;
