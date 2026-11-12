// Push dispatcher using Firebase Cloud Messaging HTTP v1.
//
// - Claims a batch of PENDING notifications atomically.
// - Sends them to every active device token for the recipient.
// - Marks SENT/FAILED honestly. If FCM is not configured the function
//   returns 503 and never pretends a push was delivered.
//
// Configure FCM_SERVICE_ACCOUNT_JSON (raw JSON or base64-encoded JSON) and
// WORKER_SECRET. Invoke from a scheduler with x-worker-secret.
import { SignJWT, importPKCS8 } from "npm:jose@5.9.6";
import {
  env,
  errorResponse,
  HttpError,
  json,
  preflight,
  safeEqual,
  serviceFetch,
} from "../_shared/http.ts";

type NotificationRow = {
  id: string;
  recipient_id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  created_at: string;
};

type DeviceRow = {
  id: string;
  user_id: string;
  push_token: string;
  app_name: string;
  platform: string;
};

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

let cachedToken: { value: string; expiresAt: number } | null = null;

function loadServiceAccount(): ServiceAccount | null {
  const raw = env("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;
  let text = raw.trim();
  if (!text.startsWith("{")) {
    try {
      text = new TextDecoder().decode(Uint8Array.from(atob(text), (c) => c.charCodeAt(0)));
    } catch {
      throw new HttpError(503, "fcm_config_invalid", "FCM_SERVICE_ACCOUNT_JSON is not valid base64 JSON.");
    }
  }
  let parsed: ServiceAccount;
  try {
    parsed = JSON.parse(text) as ServiceAccount;
  } catch {
    throw new HttpError(503, "fcm_config_invalid", "FCM_SERVICE_ACCOUNT_JSON is not valid JSON.");
  }
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new HttpError(503, "fcm_config_invalid", "FCM service account JSON is missing project_id, client_email or private_key.");
  }
  return parsed;
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 60 > now) return cachedToken.value;

  const key = await importPKCS8(account.private_key.replace(/\\n/g, "\n"), "RS256");
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience(account.token_uri ?? "https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const response = await fetch(account.token_uri ?? "https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const payload = (await response.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error_description?: string };
  if (!response.ok || !payload.access_token) {
    throw new HttpError(502, "fcm_auth_failed", payload.error_description ?? "Could not obtain an FCM access token.");
  }
  cachedToken = { value: payload.access_token, expiresAt: now + (payload.expires_in ?? 3600) };
  return cachedToken.value;
}

function stringData(data: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(data ?? {})) {
    if (value === null || value === undefined) continue;
    out[key] = typeof value === "string" ? value : JSON.stringify(value);
    if (out[key].length > 3500) out[key] = out[key].slice(0, 3500);
  }
  return out;
}

async function sendToToken(
  account: ServiceAccount,
  token: string,
  notification: NotificationRow,
): Promise<{ ok: boolean; messageId?: string; invalidToken: boolean; error?: string }> {
  const access = await accessToken(account);
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: notification.title.slice(0, 200),
            body: notification.body.slice(0, 1000),
          },
          data: {
            ...stringData(notification.data ?? {}),
            notification_id: notification.id,
            notification_type: notification.type,
          },
          android: { priority: "HIGH", notification: { channel_id: "indibizz_orders" } },
          apns: { payload: { aps: { sound: "default" } } },
        },
      }),
    },
  );

  const payload = (await response.json().catch(() => ({}))) as {
    name?: string;
    error?: { status?: string; message?: string; details?: Array<{ errorCode?: string }> };
  };
  if (response.ok && payload.name) {
    return { ok: true, messageId: payload.name, invalidToken: false };
  }
  const errorCode = payload.error?.details?.find((d) => d.errorCode)?.errorCode ?? payload.error?.status ?? "";
  const invalidToken = ["UNREGISTERED", "NOT_FOUND", "INVALID_ARGUMENT"].includes(errorCode);
  return {
    ok: false,
    invalidToken,
    error: payload.error?.message ?? `FCM HTTP ${response.status}`,
  };
}

async function patchNotification(id: string, patch: Record<string, unknown>): Promise<void> {
  const response = await serviceFetch(`/rest/v1/notifications?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  if (!response.ok) console.error("notification patch failed", response.status, await response.text());
}

async function clearToken(deviceId: string): Promise<void> {
  const response = await serviceFetch(`/rest/v1/user_devices?id=eq.${encodeURIComponent(deviceId)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ push_token: null, last_seen_at: new Date().toISOString() }),
  });
  if (!response.ok) console.error("device token clear failed", response.status, await response.text());
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") {
    return json({ ok: false, error_code: "method_not_allowed", message: "Use POST." }, 405);
  }

  try {
    const secret = env("WORKER_SECRET");
    if (!secret) {
      return json({ ok: false, error_code: "server_not_configured", message: "WORKER_SECRET is not set." }, 503);
    }
    if (!safeEqual(req.headers.get("x-worker-secret") ?? "", secret)) {
      throw new HttpError(401, "invalid_worker_secret", "Invalid worker secret.");
    }

    const account = loadServiceAccount();
    if (!account) {
      return json({
        ok: false,
        error_code: "push_provider_unavailable",
        message:
          "FCM_SERVICE_ACCOUNT_JSON is not configured. Push notifications cannot be delivered until a Firebase service account is supplied.",
      }, 503);
    }

    const claimedResponse = await serviceFetch("/rest/v1/rpc/system_claim_pending_push", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ p_limit: 50 }),
    });
    const claimedText = await claimedResponse.text();
    if (!claimedResponse.ok) {
      console.error("claim push failed", claimedResponse.status, claimedText.slice(0, 500));
      return json({ ok: false, error_code: "claim_failed", message: "Could not claim notifications." }, 502);
    }
    const claimed = JSON.parse(claimedText) as { notifications: NotificationRow[] };
    const notifications = claimed.notifications ?? [];
    if (notifications.length === 0) {
      return json({ ok: true, claimed: 0, sent: 0, failed: 0, skipped: 0 });
    }

    const recipientIds = [...new Set(notifications.map((n) => n.recipient_id))];
    const deviceResponse = await serviceFetch(
      `/rest/v1/user_devices?user_id=in.(${recipientIds.map(encodeURIComponent).join(",")})` +
        `&select=id,user_id,push_token,app_name,platform&push_token=not.is.null&revoked_at=is.null`,
    );
    if (!deviceResponse.ok) {
      console.error("device query failed", deviceResponse.status, await deviceResponse.text());
      return json({ ok: false, error_code: "device_query_failed", message: "Could not load device tokens." }, 502);
    }
    const devices = (await deviceResponse.json()) as DeviceRow[];
    const byUser = new Map<string, DeviceRow[]>();
    for (const device of devices) {
      if (!device.push_token) continue;
      const list = byUser.get(device.user_id) ?? [];
      list.push(device);
      byUser.set(device.user_id, list);
    }

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    const errors: string[] = [];

    for (const notification of notifications) {
      const targets = byUser.get(notification.recipient_id) ?? [];
      if (targets.length === 0) {
        skipped += 1;
        await patchNotification(notification.id, {
          delivery_status: "SKIPPED_NO_PROVIDER",
          failure_reason: "No registered push device for this recipient.",
        });
        continue;
      }

      let deviceSuccesses = 0;
      let firstMessageId: string | null = null;
      for (const device of targets) {
        const result = await sendToToken(account, device.push_token, notification);
        if (result.ok) {
          deviceSuccesses += 1;
          firstMessageId = firstMessageId ?? result.messageId ?? null;
          sent += 1;
        } else {
          failed += 1;
          errors.push(result.error ?? "unknown FCM error");
          if (result.invalidToken) await clearToken(device.id);
        }
      }

      if (deviceSuccesses > 0) {
        await patchNotification(notification.id, {
          delivery_status: "SENT",
          provider_message_id: firstMessageId,
          pushed_at: new Date().toISOString(),
          failure_reason: null,
        });
      } else {
        await patchNotification(notification.id, {
          delivery_status: "FAILED",
          failure_reason: errors.slice(0, 3).join(" | ").slice(0, 500) || "FCM rejected the push.",
        });
      }
    }

    return json({
      ok: true,
      claimed: notifications.length,
      sent,
      failed,
      skipped,
      errors: errors.slice(0, 5),
    });
  } catch (error) {
    return errorResponse(error);
  }
});
