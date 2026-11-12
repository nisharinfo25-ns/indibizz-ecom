// One-time owner bootstrap.
//
// Security model:
//  1. The caller must sign in with real Supabase Phone OTP first (JWT).
//  2. The caller must present the private BOOTSTRAP_SECRET header.
//  3. No active OWNER may exist. The SQL function enforces this under an
//     advisory lock, so two concurrent calls cannot create two owners.
//
// The secret is only compared server-side and is never returned. The function
// does not create users or bypass OTP verification.
import {
  env,
  errorResponse,
  HttpError,
  json,
  preflight,
  readJson,
  requireUser,
  safeEqual,
  serviceFetch,
} from "../_shared/http.ts";

type BootstrapResult = {
  ok: boolean;
  already_owner?: boolean;
  owner_id?: string;
  error_code?: string;
  message?: string;
};

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") {
    return json({ ok: false, error_code: "method_not_allowed", message: "Use POST." }, 405);
  }

  try {
    const secret = env("BOOTSTRAP_SECRET");
    if (!secret) {
      return json({
        ok: false,
        error_code: "server_not_configured",
        message: "BOOTSTRAP_SECRET is not set. Configure it before bootstrapping the owner.",
      }, 503);
    }

    const supplied = req.headers.get("x-bootstrap-secret") ?? "";
    if (!supplied || !safeEqual(supplied, secret)) {
      throw new HttpError(401, "invalid_bootstrap_secret", "Invalid bootstrap secret.");
    }

    const user = await requireUser(req);
    if (!user.phone || !user.phone_confirmed_at) {
      throw new HttpError(403, "phone_not_verified", "Sign in with a verified phone OTP before bootstrapping the owner.");
    }

    const body = await readJson(req);
    const fullName = typeof body.full_name === "string" ? body.full_name.trim().slice(0, 160) : "";

    const response = await serviceFetch("/rest/v1/rpc/system_bootstrap_owner", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ p_user_id: user.id, p_full_name: fullName || null }),
    });

    const text = await response.text();
    let result: BootstrapResult;
    try {
      result = text ? (JSON.parse(text) as BootstrapResult) : { ok: false, error_code: "empty_response" };
    } catch {
      return json({
        ok: false,
        error_code: "bootstrap_failed",
        message: "The database returned an unexpected response.",
      }, 502);
    }

    if (!response.ok) {
      console.error("bootstrap rpc failed", response.status, text.slice(0, 500));
      return json({
        ok: false,
        error_code: result.error_code ?? "bootstrap_failed",
        message: result.message ?? "Owner bootstrap failed.",
      }, response.status === 409 ? 409 : 500);
    }

    if (result.ok === false) {
      const status = result.error_code === "OWNER_EXISTS" ? 409 : 400;
      return json(result, status);
    }

    return json({
      ok: true,
      already_owner: result.already_owner ?? false,
      owner_id: result.owner_id ?? user.id,
      message: result.message ?? "Owner account activated.",
    });
  } catch (error) {
    return errorResponse(error);
  }
});
