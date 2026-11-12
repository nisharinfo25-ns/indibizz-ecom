-- IndiaBizz :: 0019 server-only support for Edge Functions.
-- These functions are never callable by normal clients: they require the
-- service role (or the explicit local worker flag used by the test harness).

-- ---------------------------------------------------------------------------
-- Push dispatch claim column. Notifications are created as PENDING by the
-- database. The push worker atomically claims a batch before calling FCM so
-- concurrent workers never send the same notification twice.
-- ---------------------------------------------------------------------------
alter table public.notifications
  add column if not exists push_claimed_at timestamptz;

create index if not exists idx_notifications_push_claim
  on public.notifications (created_at)
  where delivery_status = 'PENDING';

-- ---------------------------------------------------------------------------
-- One-time owner bootstrap.
--
-- The owner signs in with real phone OTP first. The bootstrap Edge Function
-- then calls this function with the service role. The advisory lock makes the
-- "only one OWNER" rule race-free.
-- ---------------------------------------------------------------------------
create or replace function public.system_bootstrap_owner(
  p_user_id uuid,
  p_full_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_existing uuid;
  v_profile public.profiles%rowtype;
  v_name text;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and coalesce(current_setting('indibizz.worker', true), 'off') <> 'on' then
    raise exception using errcode = '42501', message = 'Service role authorization required.';
  end if;

  perform pg_advisory_xact_lock(hashtext('indibizz.bootstrap_owner'));

  select p.id into v_existing
  from public.profiles p
  where p.role = 'OWNER' and p.status = 'ACTIVE'
  order by p.created_at
  limit 1;

  select * into v_profile from public.profiles p where p.id = p_user_id;
  if v_profile.id is null then
    return jsonb_build_object(
      'ok', false, 'error_code', 'PROFILE_NOT_FOUND',
      'message', 'No profile exists for this authenticated user.'
    );
  end if;

  if v_existing is not null then
    if v_existing = p_user_id then
      return jsonb_build_object(
        'ok', true, 'already_owner', true, 'owner_id', p_user_id,
        'message', 'This account is already the owner.'
      );
    end if;
    return jsonb_build_object(
      'ok', false, 'error_code', 'OWNER_EXISTS',
      'message', 'An active owner already exists. Owner bootstrap is single-use.'
    );
  end if;

  v_name := coalesce(nullif(trim(p_full_name), ''), nullif(trim(v_profile.full_name), ''), 'Owner');

  update public.profiles
  set role = 'OWNER',
      status = 'ACTIVE',
      full_name = left(v_name, 160),
      updated_at = now()
  where id = p_user_id;

  insert into public.audit_logs (
    actor_id, actor_role, action, entity_type, entity_id, after_data, source
  ) values (
    p_user_id, 'OWNER', 'OWNER_BOOTSTRAPPED', 'profile', p_user_id,
    jsonb_build_object('role', 'OWNER', 'status', 'ACTIVE'), 'BOOTSTRAP'
  );

  return jsonb_build_object(
    'ok', true, 'already_owner', false, 'owner_id', p_user_id,
    'message', 'Owner account activated. Sign in again to refresh the session role.'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Atomically claim a batch of pending notifications for push delivery.
-- A claim older than 10 minutes is considered abandoned and can be retried.
-- ---------------------------------------------------------------------------
create or replace function public.system_claim_pending_push(p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_rows jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role'
     and coalesce(current_setting('indibizz.worker', true), 'off') <> 'on' then
    raise exception using errcode = '42501', message = 'Service role authorization required.';
  end if;

  with claimed as (
    update public.notifications n
    set push_claimed_at = now()
    where n.id in (
      select n2.id
      from public.notifications n2
      where n2.delivery_status = 'PENDING'
        and (n2.push_claimed_at is null or n2.push_claimed_at < now() - interval '10 minutes')
      order by n2.created_at
      limit v_limit
      for update of n2 skip locked
    )
    returning n.id, n.recipient_id, n.type, n.title, n.body, n.data,
              n.dedupe_key, n.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'recipient_id', c.recipient_id,
    'type', c.type,
    'title', c.title,
    'body', c.body,
    'data', c.data,
    'dedupe_key', c.dedupe_key,
    'created_at', c.created_at
  ) order by c.created_at), '[]'::jsonb)
  into v_rows
  from claimed c;

  return jsonb_build_object('ok', true, 'claimed', jsonb_array_length(v_rows), 'notifications', v_rows);
end;
$$;

-- ---------------------------------------------------------------------------
-- Explicit grants: service role only.
-- ---------------------------------------------------------------------------
revoke all on function public.system_bootstrap_owner(uuid, text) from public, anon, authenticated;
revoke all on function public.system_claim_pending_push(integer) from public, anon, authenticated;
grant execute on function public.system_bootstrap_owner(uuid, text) to service_role;
grant execute on function public.system_claim_pending_push(integer) to service_role;
