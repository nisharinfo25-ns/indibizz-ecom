"use client";

import type {
  Address,
  Cart,
  CatalogProduct,
  NotificationItem,
  OrderDetail,
  OrderSummary,
  Profile,
  Quote,
  Serviceability,
  Town,
  Tracking,
} from "@indibizz/shared";
import { getSupabase, supabaseAnonKey, supabaseUrl } from "./supabase";

export { categoriesFromProducts } from "./catalog";

export async function rpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await getSupabase().rpc(fn, args);
  if (error) throw error;
  return data as T;
}

export async function fetchCatalog(): Promise<CatalogProduct[]> {
  const { data, error } = await getSupabase()
    .from("catalog_products")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(500);
  if (error) throw error;
  return (data ?? []) as CatalogProduct[];
}

export async function fetchProductBySlug(slug: string): Promise<CatalogProduct | null> {
  const { data, error } = await getSupabase()
    .from("catalog_products")
    .select("*")
    .eq("slug", slug)
    .maybeSingle();
  if (error) throw error;
  return (data as CatalogProduct | null) ?? null;
}

export async function fetchProductImages(productId: string): Promise<Array<{ id: string; storage_path: string; alt_text: string }>> {
  const { data, error } = await getSupabase()
    .from("product_images")
    .select("id,storage_path,alt_text")
    .eq("product_id", productId)
    .order("is_primary", { ascending: false })
    .order("sort_order", { ascending: true });
  if (error) throw error;
  return (data ?? []) as Array<{ id: string; storage_path: string; alt_text: string }>;
}

export async function getProfile(): Promise<Profile> {
  return rpc<Profile>("get_my_profile");
}

export async function updateProfile(fullName: string, email: string): Promise<Profile> {
  await rpc("update_my_profile", { p_full_name: fullName, p_email: email || null });
  return getProfile();
}

export async function getCart(): Promise<Cart> {
  return rpc<Cart>("get_my_cart");
}

export async function getAddresses(): Promise<Address[]> {
  return rpc<Address[]>("list_my_addresses");
}

export async function getTowns(): Promise<Town[]> {
  return rpc<Town[]>("list_serviceable_towns");
}

export async function checkServiceability(pincode: string, townId?: string | null): Promise<Serviceability> {
  return rpc<Serviceability>("check_serviceability", {
    p_pincode: pincode.trim(),
    p_town_id: townId || null,
  });
}

export async function getQuote(addressId: string): Promise<Quote> {
  return rpc<Quote>("quote_my_order", { p_address_id: addressId });
}

export async function listOrders(): Promise<OrderSummary[]> {
  return rpc<OrderSummary[]>("list_my_orders", { p_limit: 50 });
}

export async function getOrder(id: string): Promise<OrderDetail> {
  return rpc<OrderDetail>("get_my_order", { p_order_id: id });
}

export async function getTracking(id: string): Promise<Tracking> {
  return rpc<Tracking>("get_order_tracking", { p_order_id: id });
}

export async function listNotifications(): Promise<NotificationItem[]> {
  return rpc<NotificationItem[]>("list_my_notifications", { p_limit: 60 });
}

export async function markNotificationRead(id: string): Promise<void> {
  await rpc("mark_notification_read", { p_notification_id: id });
}

export async function markAllNotificationsRead(): Promise<void> {
  await rpc("mark_all_notifications_read");
}

export interface PublicSettings {
  business?: Record<string, unknown>;
  commerce?: Record<string, unknown>;
  policies?: Record<string, unknown>;
}

export async function publicSettings(): Promise<PublicSettings> {
  return rpc<PublicSettings>("get_public_settings");
}

interface ImageCacheEntry {
  url: string | null;
  expiresAt: number;
}

const imageCache = new Map<string, ImageCacheEntry>();

export async function signedBucketUrl(bucket: string, path: string): Promise<string | null> {
  const key = `${bucket}:${path}`;
  const cached = imageCache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.url;
  try {
    const { data, error } = await getSupabase().storage.from(bucket).createSignedUrl(path, 3600);
    if (error || !data?.signedUrl) {
      imageCache.set(key, { url: null, expiresAt: Date.now() + 60_000 });
      return null;
    }
    imageCache.set(key, { url: data.signedUrl, expiresAt: Date.now() + 55 * 60_000 });
    return data.signedUrl;
  } catch {
    return null;
  }
}

export async function signedProductImage(path: string | null | undefined): Promise<string | null> {
  if (!path) return null;
  return signedBucketUrl("product-images", path);
}

export async function signedInvoiceUrl(path: string): Promise<string | null> {
  return signedBucketUrl("invoices", path);
}

export interface RequestOtpResult {
  ok: boolean;
  error_code?: string;
  message?: string;
  cooldown_seconds?: number;
}

export async function requestOtp(phone: string): Promise<RequestOtpResult> {
  const response = await fetch(`${supabaseUrl()}/functions/v1/request-otp`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseAnonKey(),
      Authorization: `Bearer ${supabaseAnonKey()}`,
    },
    body: JSON.stringify({ phone, purpose: "customer" }),
  });
  const payload = (await response.json().catch(() => ({}))) as RequestOtpResult;
  if (!response.ok && !payload.message) {
    payload.ok = false;
    payload.message = `The OTP service returned HTTP ${response.status}.`;
  }
  return payload;
}

const MAX_EVIDENCE_BYTES = 10 * 1024 * 1024;
const ALLOWED_EVIDENCE = new Set(["image/jpeg", "image/png", "image/webp", "application/pdf"]);

export async function uploadReturnEvidence(orderId: string, file: File): Promise<string> {
  if (file.size > MAX_EVIDENCE_BYTES) throw new Error("Evidence must be 10 MB or smaller.");
  if (!ALLOWED_EVIDENCE.has(file.type)) throw new Error("Upload a JPEG, PNG, WebP or PDF file.");
  const safeName = file.name.replace(/[^A-Za-z0-9._-]/g, "_").slice(-80);
  const path = `${orderId}/${crypto.randomUUID()}-${safeName}`;
  const { error } = await getSupabase().storage.from("return-evidence").upload(path, file, {
    contentType: file.type,
    upsert: false,
  });
  if (error) throw error;
  return path;
}

export async function createAddress(input: {
  label: string;
  recipient_name: string;
  phone: string;
  line1: string;
  line2: string;
  landmark: string;
  town_id: string;
  pincode: string;
  is_default: boolean;
  id?: string | null;
}): Promise<Address> {
  return rpc<Address>("save_my_address", {
    p_label: input.label,
    p_recipient_name: input.recipient_name,
    p_phone: input.phone,
    p_line1: input.line1,
    p_line2: input.line2,
    p_landmark: input.landmark,
    p_town_id: input.town_id,
    p_pincode: input.pincode,
    p_is_default: input.is_default,
    p_id: input.id ?? null,
  });
}

export async function deleteAddress(id: string): Promise<void> {
  await rpc("delete_my_address", { p_id: id });
}
