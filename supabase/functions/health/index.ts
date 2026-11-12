// Configuration and readiness report. Never returns secret values.
// Useful for monitoring and for the owner to see exactly what is missing.
import {
  anonKey,
  env,
  json,
  preflight,
  serviceFetch,
  supabaseUrl,
} from "../_shared/http.ts";

async function authSettings(): Promise<{ ok: boolean; phone: boolean | null; sms_provider: string | null; error?: string }> {
  try {
    const response = await fetch(`${supabaseUrl()}/auth/v1/settings`, { headers: { apikey: anonKey() } });
    if (!response.ok) return { ok: false, phone: null, sms_provider: null, error: `HTTP ${response.status}` };
    const settings = (await response.json()) as { phone?: boolean; sms_provider?: string };
    return { ok: true, phone: settings.phone ?? false, sms_provider: settings.sms_provider ?? null };
  } catch {
    return { ok: false, phone: null, sms_provider: null, error: "Auth settings unreachable." };
  }
}

async function databaseReady(): Promise<{ ok: boolean; error?: string }> {
  try {
    const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/get_public_settings`, {
      method: "POST",
      headers: { apikey: anonKey(), Authorization: `Bearer ${anonKey()}`, "Content-Type": "application/json" },
      body: "{}",
    });
    if (!response.ok) {
      const text = await response.text();
      let message = `HTTP ${response.status}`;
      try {
        const parsed = JSON.parse(text);
        message = parsed.message ?? message;
      } catch { /* generic */ }
      return { ok: false, error: message };
    }
    return { ok: true };
  } catch {
    return { ok: false, error: "Database unreachable." };
  }
}

async function bucketsReady(): Promise<{ ok: boolean; total?: number; error?: string }> {
  if (!env("SUPABASE_SERVICE_ROLE_KEY")) return { ok: false, error: "Service role key not configured." };
  try {
    const response = await serviceFetch("/storage/v1/bucket");
    if (!response.ok) return { ok: false, error: `HTTP ${response.status}` };
    const buckets = (await response.json()) as Array<{ name: string; public?: boolean }>;
    const expected = ["product-images", "invoices", "shipping-labels", "pickup-manifests", "delivery-proofs", "return-evidence"];
    const missing = expected.filter((name) => !buckets.some((bucket) => bucket.name === name));
    if (missing.length > 0) return { ok: false, total: buckets.length, error: `Missing buckets: ${missing.join(", ")}` };
    const publicBuckets = buckets.filter((bucket) => expected.includes(bucket.name) && bucket.public === true);
    if (publicBuckets.length > 0) {
      return { ok: false, total: buckets.length, error: `Buckets must stay private: ${publicBuckets.map((b) => b.name).join(", ")}` };
    }
    return { ok: true, total: buckets.length };
  } catch {
    return { ok: false, error: "Storage API unreachable." };
  }
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ ok: false, error_code: "method_not_allowed", message: "Use GET." }, 405);
  }

  const hasServiceRole = Boolean(env("SUPABASE_SERVICE_ROLE_KEY"));
  const hasAnon = Boolean(env("SUPABASE_ANON_KEY"));
  const hasUrl = Boolean(env("SUPABASE_URL"));
  const fcmConfigured = Boolean(env("FCM_SERVICE_ACCOUNT_JSON"));
  const workerSecret = Boolean(env("WORKER_SECRET"));
  const bootstrapSecret = Boolean(env("BOOTSTRAP_SECRET"));

  const [auth, database, buckets] = await Promise.all([
    hasUrl && hasAnon ? authSettings() : Promise.resolve({ ok: false, phone: null, sms_provider: null, error: "Supabase URL/anon key missing." }),
    hasUrl && hasAnon ? databaseReady() : Promise.resolve({ ok: false, error: "Supabase URL/anon key missing." }),
    bucketsReady(),
  ]);

  const checks = {
    environment: {
      supabase_url: hasUrl,
      anon_key: hasAnon,
      service_role_key: hasServiceRole,
      bootstrap_secret: bootstrapSecret,
      worker_secret: workerSecret,
      fcm_service_account: fcmConfigured,
    },
    auth: {
      reachable: auth.ok,
      phone_otp_enabled: auth.phone === true,
      sms_provider: auth.sms_provider,
      error: auth.error ?? null,
    },
    database: {
      application_schema_ready: database.ok,
      error: database.error ?? null,
    },
    storage: {
      private_buckets_ready: buckets.ok,
      bucket_count: buckets.total ?? null,
      error: buckets.error ?? null,
    },
    push: {
      provider_configured: fcmConfigured,
    },
  };

  const blockers: string[] = [];
  if (!hasUrl || !hasAnon) blockers.push("Supabase environment variables are incomplete.");
  if (!hasServiceRole) blockers.push("SUPABASE_SERVICE_ROLE_KEY is not configured; admin Edge Functions cannot operate.");
  if (!auth.ok) blockers.push(`Auth settings are unreachable: ${auth.error}`);
  else if (auth.phone !== true) {
    blockers.push("Supabase Phone auth is disabled. Enable Authentication > Providers > Phone and configure an SMS provider.");
  }
  if (!database.ok) blockers.push(`Database schema is not ready: ${database.error}`);
  if (!buckets.ok) blockers.push(`Private storage is not ready: ${buckets.error}`);
  if (!bootstrapSecret) blockers.push("BOOTSTRAP_SECRET is not configured; the owner cannot be provisioned.");
  if (!workerSecret) blockers.push("WORKER_SECRET is not configured; scheduled jobs cannot run.");
  if (!fcmConfigured) blockers.push("FCM_SERVICE_ACCOUNT_JSON is not configured; push notifications are disabled (in-app notifications still work).");

  return json({
    ok: blockers.length === 0,
    service: "indibizz-edge",
    time: new Date().toISOString(),
    checks,
    blockers,
  });
});
