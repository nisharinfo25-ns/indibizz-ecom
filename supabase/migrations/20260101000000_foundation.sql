-- IndiaBizz :: 0001 foundation
-- Extensions, schemas, enum types and generic helper functions.
-- Target: Supabase PostgreSQL 15+.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists app_private;
revoke all on schema app_private from public;

-- ---------------------------------------------------------------------------
-- Domain enums
-- ---------------------------------------------------------------------------
do $$ begin
  create type public.user_role as enum (
    'OWNER','OWN_DELIVERY_STAFF','PARTNER_ADMIN','PARTNER_DELIVERY_STAFF','CUSTOMER'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.account_status as enum ('ACTIVE','SUSPENDED','DEACTIVATED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.staff_status as enum ('INVITED','ACTIVE','SUSPENDED','DEACTIVATED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.partner_status as enum ('PENDING','APPROVED','SUSPENDED','DEACTIVATED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.product_status as enum ('DRAFT','ACTIVE','ARCHIVED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.stock_movement_type as enum (
    'OPENING','PURCHASE','SALE','RESERVATION','RESERVATION_RELEASE','ADJUSTMENT',
    'CANCELLATION','RETURN','DAMAGE','CORRECTION'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum (
    'PENDING_APPROVAL','APPROVED','REJECTED','CANCELLED','READY_FOR_PICKUP',
    'PICKUP_REQUESTED','PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION',
    'OUT_FOR_DELIVERY','DELIVERED','DELIVERY_FAILED','RETURN_REQUESTED',
    'RETURNED','CLOSED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_status as enum ('PENDING','COLLECTED','SETTLED','VOID');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.invoice_status as enum ('ISSUED','VOID');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.shipment_status as enum (
    'CREATED','PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED',
    'PICKUP_ACCEPTED','ARRIVED_AT_PICKUP','PICKED_UP','IN_TRANSIT',
    'ARRIVED_AT_DESTINATION','OUT_FOR_DELIVERY','DELIVERED','PICKUP_FAILED',
    'SHIPMENT_DELAYED','DELIVERY_ATTEMPTED','CUSTOMER_UNAVAILABLE',
    'DELIVERY_REJECTED','PACKAGE_DAMAGED','RETURN_REQUESTED','RETURN_TO_SELLER',
    'RETURNED_SUCCESSFULLY','CANCELLED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.package_status as enum (
    'PACKED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED','PICKUP_ACCEPTED',
    'PICKED_UP','IN_TRANSIT','OUT_FOR_DELIVERY','DELIVERED','DELIVERY_FAILED',
    'RETURNING','RETURNED','CANCELLED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.assignment_status as enum (
    'PENDING','ACCEPTED','REJECTED','EXPIRED','CANCELLED','COMPLETED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.assignment_mode as enum ('AUTO','MANUAL');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.staff_type as enum ('OWN','PARTNER');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.pickup_status as enum (
    'REQUESTED','ASSIGNED','ACCEPTED','ARRIVED','VERIFIED','FAILED','CANCELLED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.package_condition as enum ('PENDING','GOOD','DAMAGED');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.shipment_event_type as enum (
    'SHIPMENT_CREATED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED',
    'PICKUP_ACCEPTED','PICKUP_REJECTED','ASSIGNMENT_REASSIGNED','ARRIVED_AT_PICKUP',
    'PICKED_UP','IN_TRANSIT','ARRIVED_AT_DESTINATION','OUT_FOR_DELIVERY','DELIVERED',
    'PICKUP_FAILED','SHIPMENT_DELAYED','DELIVERY_ATTEMPTED','CUSTOMER_UNAVAILABLE',
    'DELIVERY_REJECTED','PACKAGE_DAMAGED','RETURN_REQUESTED','RETURN_TO_SELLER',
    'RETURNED_SUCCESSFULLY','CANCELLED','COD_COLLECTED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.scan_context as enum ('PICKUP','DELIVERY','VERIFICATION');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.scan_result as enum (
    'VALID','DUPLICATE','WRONG_PACKAGE','CANCELLED_ORDER','ALREADY_COLLECTED',
    'UNASSIGNED','UNAUTHORIZED','INVALID_CODE','DAMAGED_PACKAGE'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.delivery_proof_type as enum ('DELIVERY_OTP','PHOTO','SIGNATURE');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.delivery_failure_reason as enum (
    'CUSTOMER_UNAVAILABLE','CUSTOMER_REFUSED','ADDRESS_NOT_FOUND',
    'PAYMENT_NOT_READY','PACKAGE_DAMAGED','OTHER'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.cod_entry_type as enum (
    'EXPECTED','COLLECTED','HANDOVER','HANDOVER_REVERSAL','SETTLEMENT_CONFIRMED','ADJUSTMENT'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.cod_settlement_status as enum (
    'PENDING_VERIFICATION','VERIFIED','DISPUTED','CANCELLED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.return_status as enum (
    'REQUESTED','APPROVED','REJECTED','IN_TRANSIT','RECEIVED','CLOSED'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_channel as enum ('IN_APP','PUSH','SMS','EMAIL');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_type as enum (
    'ORDER_PLACED','ORDER_APPROVED','ORDER_REJECTED','ORDER_CANCELLED',
    'INVOICE_GENERATED','READY_FOR_PICKUP','PICKUP_REQUESTED','PICKUP_ASSIGNED',
    'PICKUP_ACCEPTED','PICKUP_REJECTED','PICKUP_OTP','PICKUP_VERIFIED',
    'PICKUP_FAILED','DELIVERY_ASSIGNED','DELIVERY_ACCEPTED','DELIVERY_REJECTED',
    'IN_TRANSIT','OUT_FOR_DELIVERY','DELIVERY_OTP','DELIVERED','DELIVERY_FAILED',
    'RETURN_REQUESTED','RETURN_APPROVED','RETURN_REJECTED','RETURN_UPDATED',
    'COD_COLLECTED','COD_HANDOVER_DECLARED','COD_SETTLEMENT_VERIFIED',
    'COD_SETTLEMENT_DISPUTED','STAFF_ACCOUNT','SYSTEM'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_delivery_status as enum (
    'PENDING','SKIPPED_NO_PROVIDER','SENT','FAILED','READ'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.device_platform as enum ('ANDROID','IOS','WINDOWS','WEB','MACOS');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- Generic helpers
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function app_private.assert_true(p_condition boolean, p_message text)
returns void
language plpgsql
immutable
as $$
begin
  if p_condition is not true then
    raise exception using errcode = 'P0001', message = p_message;
  end if;
end;
$$;

-- Normalize Indian phone numbers to E.164. Accepts optional +91, 91 or leading 0.
create or replace function public.normalize_phone(p_phone text)
returns text
language plpgsql
immutable
as $$
declare
  v_digits text;
begin
  if p_phone is null then
    return null;
  end if;
  v_digits := regexp_replace(p_phone, '[^0-9+]', '', 'g');
  if left(v_digits, 1) = '+' then
    v_digits := '+' || regexp_replace(substr(v_digits, 2), '[^0-9]', '', 'g');
  else
    v_digits := regexp_replace(v_digits, '[^0-9]', '', 'g');
    if length(v_digits) = 10 then
      v_digits := '+91' || v_digits;
    elsif length(v_digits) = 11 and left(v_digits, 1) = '0' then
      v_digits := '+91' || substr(v_digits, 2);
    elsif length(v_digits) = 12 and left(v_digits, 2) = '91' then
      v_digits := '+' || v_digits;
    elsif length(v_digits) = 13 and left(v_digits, 3) = '091' then
      v_digits := '+91' || substr(v_digits, 4);
    else
      v_digits := '+' || v_digits;
    end if;
  end if;
  return v_digits;
end;
$$;

create or replace function public.is_valid_phone(p_phone text)
returns boolean
language sql
immutable
as $$
  select public.normalize_phone(p_phone) ~ '^\+[1-9][0-9]{7,14}$';
$$;

create or replace function public.is_valid_pincode(p_pincode text)
returns boolean
language sql
immutable
as $$
  select p_pincode ~ '^[1-9][0-9]{5}$';
$$;

-- ---------------------------------------------------------------------------
-- Sequence-backed public identifiers
-- ---------------------------------------------------------------------------
create sequence if not exists public.order_number_seq start 1000;
create sequence if not exists public.invoice_number_seq start 1000;
create sequence if not exists public.shipment_number_seq start 1000;
create sequence if not exists public.pickup_number_seq start 1000;
create sequence if not exists public.return_number_seq start 1000;
create sequence if not exists public.settlement_number_seq start 1000;
create sequence if not exists public.manifest_number_seq start 1000;

create or replace function app_private.next_document_number(p_prefix text, p_seq regclass)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_seq bigint := nextval(p_seq);
begin
  return p_prefix || '-' || to_char(now() at time zone 'utc', 'YYYYMMDD') || '-' || lpad(v_seq::text, 6, '0');
end;
$$;
