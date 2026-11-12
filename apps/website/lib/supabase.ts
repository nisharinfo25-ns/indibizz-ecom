"use client";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const url = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").trim();
const anonKey = (process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "").trim();

let client: SupabaseClient | null = null;

export function isSupabaseConfigured(): boolean {
  return url.startsWith("http") && anonKey.length > 20;
}

export function configurationMessage(): string {
  return "The storefront is not connected yet. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY, then restart the website.";
}

export function getSupabase(): SupabaseClient {
  if (!isSupabaseConfigured()) throw new Error(configurationMessage());
  if (!client) {
    client = createClient(url, anonKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        flowType: "pkce",
      },
      global: {
        headers: { "X-Client-Info": "indibizz-website/1.0" },
      },
    });
  }
  return client;
}

export function supabaseUrl(): string {
  if (!isSupabaseConfigured()) throw new Error(configurationMessage());
  return url;
}

export function supabaseAnonKey(): string {
  if (!isSupabaseConfigured()) throw new Error(configurationMessage());
  return anonKey;
}
