export function newIdempotencyKey(prefix = "web"): string {
  const cryptoApi = globalThis.crypto;
  if (cryptoApi && typeof cryptoApi.randomUUID === "function") {
    return `${prefix}_${cryptoApi.randomUUID()}`;
  }
  const random = Math.random().toString(36).slice(2) + Date.now().toString(36);
  return `${prefix}_${random}`.slice(0, 100);
}

/** Supabase/PostgREST errors can be objects, FunctionsHttpError bodies or strings. */
export function errorMessage(error: unknown, fallback = "Something went wrong. Please try again."): string {
  if (!error) return fallback;
  if (typeof error === "string") return error.trim() || fallback;
  if (error instanceof Error && error.message) {
    return cleanMessage(error.message) || fallback;
  }
  if (typeof error === "object") {
    const record = error as Record<string, unknown>;
    if (typeof record.message === "string" && record.message.trim()) return cleanMessage(record.message);
    if (typeof record.error_description === "string") return cleanMessage(record.error_description);
    if (typeof record.error === "string") return cleanMessage(record.error);
    if (typeof record.msg === "string") return cleanMessage(record.msg);
    if (record.error && typeof record.error === "object") {
      return errorMessage(record.error, fallback);
    }
  }
  return fallback;
}

function cleanMessage(message: string): string {
  return message
    .replace(/^Error:\s*/i, "")
    .replace(/^PostgrestException\(message:\s*/i, "")
    .replace(/,\s*code:.*$/, "")
    .replace(/\)$/, "")
    .trim();
}

export function errorCode(error: unknown): string | null {
  if (!error || typeof error !== "object") return null;
  const record = error as Record<string, unknown>;
  if (typeof record.error_code === "string") return record.error_code;
  if (typeof record.code === "string") return record.code;
  if (record.context && typeof record.context === "object") {
    const context = record.context as Record<string, unknown>;
    if (typeof context.error_code === "string") return context.error_code;
  }
  return null;
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
