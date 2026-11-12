export * from "./types";
export * from "./format";
export * from "./phone";
export * from "./orders";
export * from "./validation";
export * from "./errors";

export function cx(...values: Array<string | false | null | undefined>): string {
  return values.filter(Boolean).join(" ");
}

export function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return value.slice(0, Math.max(0, max - 1)).trimEnd() + "…";
}

export function initials(name: string | null | undefined): string {
  const parts = String(name ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "IB";
  return parts.slice(0, 2).map((part) => part[0]!.toUpperCase()).join("");
}
