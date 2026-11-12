// Rate-limited, real Supabase Phone OTP request proxy.
// It NEVER creates or returns an OTP itself. If the Supabase project has not
// enabled Phone auth / configured an SMS provider it reports that precisely.
import {
  anonKey,
  clientIp,
  errorResponse,
  HttpError,
  json,
  normalizePhone,
  preflight,
  readJson,
  serviceFetch,
  sha256Hex,
  supabaseUrl,
} from "../_shared/http.ts";

const PURPOSE = new Set(["customer", "staff", "seller"]);
const COOLDOWN_SECONDS = 60;
const PHONE_HOURLY_LIMIT = 5;
const IP_HOURLY_LIMIT = 20;

type LogRow = { id: string };

async function insertLog(row: Record<string, unknown>): Promise<string | null> {
  const response = await serviceFetch("/rest/v1/otp_request_log", {
    method: "POST",
    headers: { "Content-Type": "application/json", Prefer: "return=representation" },
    body: JSON.stringify(row),
  });
  if (!response.ok) {
    console.error("otp_request_log insert failed", response.status, await response.text());
    return null;
  }
  const rows = (await response.json()) as LogRow[];
  return rows[0]?.id ?? null;
}

async function updateLog(id: string | null, patch: Record<string, unknown>): Promise<void> {
  if (!id) return;
  const response = await serviceFetch(`/rest/v1/otp_request_log?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  if (!response.ok) console.error("otp_request_log update failed", response.status, await response.text());
}

async function countSince(column: string, hash: string, since: string): Promise<number> {
  const response = await serviceFetch(
    `/rest/v1/otp_request_log?${column}=eq.${encodeURIComponent(hash)}&requested_at=gte.${encodeURIComponent(since)}&select=id`,
    { headers: { Prefer: "count=exact", Range: "0-999" } },
  );
  if (!response.ok) return 0;
  const rows = (await response.json()) as unknown[];
  return rows.length;
}

async function providerEnabled(): Promise<boolean> {
  const response = await fetch(`${supabaseUrl()}/auth/v1/settings`, {
    headers: { apikey: anonKey() },
  });
  if (!response.ok) throw new Error(`Auth settings unavailable (${response.status}).`);
  const settings = (await response.json()) as { phone?: boolean; sms_provider?: string };
  // A provider name alone is not proof that credentials/templates are usable,
  // but phone=false is definitive: GoTrue will refuse every send.
  return settings.phone === true;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ ok: false, error_code: "method_not_allowed", message: "Use POST." }, 405);

  let logId: string | null = null;
  try {
    const body = await readJson(req);
    const phone = normalizePhone(typeof body.phone === "string" ? body.phone : null);
    const purpose = typeof body.purpose === "string" ? body.purpose : "customer";
    if (!PURPOSE.has(purpose)) throw new HttpError(400, "invalid_purpose", "Purpose must be customer, staff or seller.");
    if (!phone) throw new HttpError(400, "invalid_phone", "Enter a valid mobile number in E.164 format.");

    const phoneHash = await sha256Hex(phone);
    const ipHash = await sha256Hex(clientIp(req));
    const now = new Date();
    const hourIso = new Date(now.getTime() - 60 * 60 * 1000).toISOString();
    const cooldownIso = new Date(now.getTime() - COOLDOWN_SECONDS * 1000).toISOString();

    const recent = await serviceFetch(
      `/rest/v1/otp_request_log?phone_hash=eq.${phoneHash}&requested_at=gte.${cooldownIso}&select=requested_at&order=requested_at.desc&limit=1`,
    );
    if (recent.ok) {
      const rows = (await recent.json()) as unknown[];
      if (rows.length > 0) {
        throw new HttpError(429, "otp_cooldown", `Please wait ${COOLDOWN_SECONDS} seconds before requesting another OTP.`);
      }
    }

    const [phoneCount, ipCount] = await Promise.all([
      countSince("phone_hash", phoneHash, hourIso),
      countSince("ip_hash", ipHash, hourIso),
    ]);
    if (phoneCount >= PHONE_HOURLY_LIMIT) {
      throw new HttpError(429, "otp_phone_limit", "Too many OTP requests for this number. Try again after an hour.");
    }
    if (ipCount >= IP_HOURLY_LIMIT) {
      throw new HttpError(429, "otp_ip_limit", "Too many OTP requests from this network. Try again after an hour.");
    }

    logId = await insertLog({
      phone_hash: phoneHash,
      ip_hash: ipHash,
      purpose,
      outcome: "PENDING",
      user_agent: (req.headers.get("user-agent") ?? "").slice(0, 300),
    });

    if (!(await providerEnabled())) {
      await updateLog(logId, { outcome: "DISABLED", error_code: "phone_provider_unavailable" });
      return json({
        ok: false,
        error_code: "phone_provider_unavailable",
        message:
          "Phone authentication is disabled in this Supabase project. The owner must enable Authentication > Providers > Phone and configure an SMS provider (for example Twilio) before OTP can be sent.",
      }, 503);
    }

    const send = await fetch(`${supabaseUrl()}/auth/v1/otp`, {
      method: "POST",
      headers: {
        apikey: anonKey(),
        Authorization: `Bearer ${anonKey()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ phone, create_user: true }),
    });

    const text = await send.text();
    let errorCode: string | undefined;
    let errorMessage = "";
    try {
      const parsed = JSON.parse(text) as Record<string, unknown>;
      errorCode = typeof parsed.error_code === "string" ? parsed.error_code : undefined;
      errorMessage = typeof parsed.msg === "string" ? parsed.msg : typeof parsed.message === "string" ? parsed.message : "";
    } catch { /* non-JSON provider response */ }

    if (!send.ok) {
      const rateLimited = send.status === 429 || errorCode === "over_sms_send_rate_limit" || errorCode === "over_email_send_rate_limit";
      await updateLog(logId, {
        outcome: rateLimited ? "RATE_LIMITED" : "PROVIDER_ERROR",
        error_code: errorCode ?? `provider_http_${send.status}`,
      });
      if (rateLimited) {
        return json({
          ok: false,
          error_code: "otp_provider_rate_limited",
          message: "The SMS provider is rate limiting requests. Wait a minute and try again.",
        }, 429);
      }
      return json({
        ok: false,
        error_code: "otp_provider_error",
        message: errorMessage
          ? `The SMS provider rejected the request: ${errorMessage}`
          : "The SMS provider rejected the request. The owner must verify the Twilio credentials, sender and SMS template in Supabase Auth settings.",
      }, 502);
    }

    await updateLog(logId, { outcome: "SENT" });
    return json({
      ok: true,
      cooldown_seconds: COOLDOWN_SECONDS,
      message: "If the number is valid, an OTP was sent by the configured SMS provider.",
    });
  } catch (error) {
    if (error instanceof HttpError) {
      // Log rate-limit rejections for abuse monitoring after the initial
      // cooldown check; invalid phones are not logged with a hash.
      if (logId) await updateLog(logId, { outcome: "RATE_LIMITED", error_code: error.code });
      return errorResponse(error);
    }
    return errorResponse(error);
  }
});
