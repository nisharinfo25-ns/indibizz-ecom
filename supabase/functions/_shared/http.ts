// Shared helpers for IndiaBizz Edge Functions. No secrets are ever returned
// to clients; configuration errors are reported precisely.

export const corsHeaders = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_ORIGIN") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-worker-secret, x-bootstrap-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Vary": "Origin",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return null;
}

export function env(name: string): string | null {
  const value = Deno.env.get(name);
  return value && value.trim().length > 0 ? value.trim() : null;
}

export function requireEnv(name: string): string {
  const value = env(name);
  if (!value) throw new ConfigurationError(`Missing required environment variable ${name}.`);
  return value;
}

export class ConfigurationError extends Error {}

export function supabaseUrl(): string {
  const raw = requireEnv("SUPABASE_URL").replace(/\/+$/, "");
  return raw;
}

export function serviceRoleKey(): string {
  return requireEnv("SUPABASE_SERVICE_ROLE_KEY");
}

export function anonKey(): string {
  return requireEnv("SUPABASE_ANON_KEY");
}

/** Normalize an Indian phone number to E.164, matching the SQL helper. */
export function normalizePhone(input: string | null | undefined): string | null {
  if (!input) return null;
  let digits = String(input).replace(/[^0-9+]/g, "");
  if (digits.startsWith("+")) {
    digits = "+" + digits.slice(1).replace(/[^0-9]/g, "");
  } else {
    digits = digits.replace(/[^0-9]/g, "");
    if (digits.length === 10) digits = "+91" + digits;
    else if (digits.length === 11 && digits.startsWith("0")) digits = "+91" + digits.slice(1);
    else if (digits.length === 12 && digits.startsWith("91")) digits = "+" + digits;
    else if (digits.length === 13 && digits.startsWith("091")) digits = "+91" + digits.slice(3);
    else digits = "+" + digits;
  }
  return /^\+[1-9][0-9]{7,14}$/.test(digits) ? digits : null;
}

export async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function clientIp(req: Request): string {
  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return req.headers.get("cf-connecting-ip") ?? req.headers.get("x-real-ip") ?? "unknown";
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    throw new HttpError(415, "unsupported_media_type", "Send a JSON body.");
  }
  try {
    const value = await req.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("not an object");
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "invalid_json", "The request body is not valid JSON.");
  }
}

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) return json({ ok: false, error_code: error.code, message: error.message }, error.status);
  if (error instanceof ConfigurationError) {
    return json({ ok: false, error_code: "server_not_configured", message: error.message }, 503);
  }
  console.error(error);
  return json({ ok: false, error_code: "internal_error", message: "An unexpected server error occurred." }, 500);
}

/** Constant-time string comparison for shared secrets. */
export function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const left = enc.encode(a);
  const right = enc.encode(b);
  let diff = left.length ^ right.length;
  const max = Math.max(left.length, right.length);
  for (let i = 0; i < max; i++) diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  return diff === 0;
}

export async function requireUser(req: Request): Promise<{ id: string; phone?: string; phone_confirmed_at?: string }> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new HttpError(401, "not_authenticated", "Sign in with phone OTP first.");
  }
  const response = await fetch(`${supabaseUrl()}/auth/v1/user`, {
    headers: { Authorization: authorization, apikey: anonKey() },
  });
  if (!response.ok) throw new HttpError(401, "invalid_session", "Your session is invalid or expired.");
  return await response.json();
}

export function bearer(req: Request): string {
  const authorization = req.headers.get("authorization") ?? "";
  return authorization.toLowerCase().startsWith("bearer ") ? authorization.slice(7) : "";
}

/** Call a PostgREST RPC using the caller's JWT (RLS/RPC role checks apply). */
export async function rpcAsUser(req: Request, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`${supabaseUrl()}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${bearer(req)}`,
      apikey: anonKey(),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) {
    let message = `RPC ${fn} failed (${response.status}).`;
    try {
      const parsed = JSON.parse(text);
      message = parsed.message ?? parsed.hint ?? message;
    } catch { /* keep generic */ }
    throw new HttpError(response.status === 401 || response.status === 403 ? 403 : 400, "operation_failed", message);
  }
  return text ? JSON.parse(text) : null;
}

export async function serviceFetch(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${supabaseUrl()}${path}`, {
    ...init,
    headers: {
      apikey: serviceRoleKey(),
      Authorization: `Bearer ${serviceRoleKey()}`,
      ...(init.headers ?? {}),
    },
  });
}
