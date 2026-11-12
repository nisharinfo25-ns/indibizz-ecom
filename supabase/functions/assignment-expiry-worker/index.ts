// Expires stale pickup/delivery assignment offers and asks the database to
// re-run automatic assignment. Designed for a scheduled invocation (cron).
//
// Authorization: x-worker-secret must match WORKER_SECRET. The database RPC
// additionally requires the service role, so a leaked URL alone is useless.
import {
  env,
  errorResponse,
  HttpError,
  json,
  preflight,
  readJson,
  safeEqual,
  serviceFetch,
} from "../_shared/http.ts";

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") {
    return json({ ok: false, error_code: "method_not_allowed", message: "Use POST." }, 405);
  }

  try {
    const secret = env("WORKER_SECRET");
    if (!secret) {
      return json({
        ok: false,
        error_code: "server_not_configured",
        message: "WORKER_SECRET is not set.",
      }, 503);
    }
    if (!safeEqual(req.headers.get("x-worker-secret") ?? "", secret)) {
      throw new HttpError(401, "invalid_worker_secret", "Invalid worker secret.");
    }

    const body = await readJson(req).catch(() => ({}));
    const limit = typeof body.limit === "number" ? Math.trunc(body.limit) : 100;

    const response = await serviceFetch("/rest/v1/rpc/system_expire_assignments", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ p_limit: limit }),
    });

    const text = await response.text();
    if (!response.ok) {
      console.error("system_expire_assignments failed", response.status, text.slice(0, 500));
      return json({
        ok: false,
        error_code: "worker_failed",
        message: "The assignment expiry job failed.",
      }, 502);
    }

    return json({
      ok: true,
      ran_at: new Date().toISOString(),
      result: text ? JSON.parse(text) : null,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
