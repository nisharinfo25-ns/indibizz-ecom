"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Session, User } from "@supabase/supabase-js";
import type { Cart, Profile } from "@indibizz/shared";
import { errorMessage, sleep } from "@indibizz/shared";
import { getCart, getProfile } from "@/lib/api";
import { getSupabase, isSupabaseConfigured } from "@/lib/supabase";

interface AuthContextValue {
  user: User | null;
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
  profileLoading: boolean;
  profileError: string | null;
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [profileLoading, setProfileLoading] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);
  const activeUser = useRef<string | null>(null);

  const loadProfile = useCallback(async (userId: string) => {
    setProfileLoading(true);
    setProfileError(null);
    try {
      // The database trigger creates the profile when auth.users is inserted.
      // A short retry covers the first request immediately after OTP verify.
      let lastError: unknown = null;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        try {
          const result = await getProfile();
          if (result) {
            if (activeUser.current === userId) setProfile(result);
            return;
          }
        } catch (error) {
          lastError = error;
        }
        await sleep(350 * (attempt + 1));
      }
      if (activeUser.current === userId) {
        setProfile(null);
        setProfileError(
          lastError
            ? errorMessage(lastError, "Your profile could not be loaded.")
            : "Your profile is still being created. Refresh in a moment.",
        );
      }
    } finally {
      setProfileLoading(false);
    }
  }, []);

  const applySession = useCallback(
    (next: Session | null) => {
      setSession(next);
      setUser(next?.user ?? null);
      if (!next?.user) {
        activeUser.current = null;
        setProfile(null);
        setProfileError(null);
        return;
      }
      if (activeUser.current === next.user.id) return;
      activeUser.current = next.user.id;
      void loadProfile(next.user.id);
    },
    [loadProfile],
  );

  useEffect(() => {
    if (!isSupabaseConfigured()) {
      setLoading(false);
      return;
    }
    const client = getSupabase();
    let mounted = true;

    client.auth
      .getSession()
      .then(({ data }) => {
        if (!mounted) return;
        applySession(data.session);
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });

    const { data } = client.auth.onAuthStateChange((_event, nextSession) => {
      if (!mounted) return;
      applySession(nextSession);
      setLoading(false);
    });

    return () => {
      mounted = false;
      data.subscription.unsubscribe();
    };
  }, [applySession]);

  const refreshProfile = useCallback(async () => {
    if (!user) return;
    await loadProfile(user.id);
  }, [loadProfile, user]);

  const signOut = useCallback(async () => {
    if (!isSupabaseConfigured()) return;
    await getSupabase().auth.signOut();
    setUser(null);
    setSession(null);
    setProfile(null);
  }, []);

  const value = useMemo(
    () => ({ user, session, profile, loading, profileLoading, profileError, refreshProfile, signOut }),
    [user, session, profile, loading, profileLoading, profileError, refreshProfile, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth must be used inside AuthProvider.");
  return value;
}

interface CartContextValue {
  cart: Cart | null;
  count: number;
  loading: boolean;
  refresh: () => Promise<void>;
  clearLocal: () => void;
}

const CartContext = createContext<CartContextValue | null>(null);

export function CartProvider({ children }: { children: ReactNode }) {
  const { user, loading: authLoading } = useAuth();
  const [cart, setCart] = useState<Cart | null>(null);
  const [loading, setLoading] = useState(false);
  const requestId = useRef(0);

  const refresh = useCallback(async () => {
    if (!user) {
      setCart(null);
      return;
    }
    const current = ++requestId.current;
    setLoading(true);
    try {
      const next = await getCart();
      if (current === requestId.current) setCart(next);
    } finally {
      if (current === requestId.current) setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      setCart(null);
      return;
    }
    void refresh();
  }, [authLoading, refresh, user]);

  const clearLocal = useCallback(() => setCart(null), []);

  const value = useMemo(
    () => ({ cart, count: cart?.item_count ?? 0, loading, refresh, clearLocal }),
    [cart, loading, refresh, clearLocal],
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart(): CartContextValue {
  const value = useContext(CartContext);
  if (!value) throw new Error("useCart must be used inside CartProvider.");
  return value;
}

interface ToastItem {
  id: number;
  message: string;
  tone: "default" | "success" | "error";
}

interface ToastContextValue {
  showToast: (message: string, tone?: ToastItem["tone"]) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastItem[]>([]);
  const idRef = useRef(0);
  const timers = useRef<Map<number, ReturnType<typeof setTimeout>>>(new Map());

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));
    const timer = timers.current.get(id);
    if (timer) clearTimeout(timer);
    timers.current.delete(id);
  }, []);

  const showToast = useCallback(
    (message: string, tone: ToastItem["tone"] = "default") => {
      const id = ++idRef.current;
      setToasts((current) => [...current.slice(-2), { id, message, tone }]);
      const timer = setTimeout(() => dismiss(id), 4200);
      timers.current.set(id, timer);
    },
    [dismiss],
  );

  useEffect(() => () => {
    for (const timer of timers.current.values()) clearTimeout(timer);
  }, []);

  return (
    <ToastContext.Provider value={{ showToast }}>
      {children}
      <div className="toast-stack" role="status" aria-live="polite">
        {toasts.map((toast) => (
          <div key={toast.id} className={`toast ${toast.tone}`} onClick={() => dismiss(toast.id)}>
            {toast.tone === "success" ? <CheckGlyph /> : toast.tone === "error" ? <AlertGlyph /> : <InfoGlyph />}
            <span>{toast.message}</span>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const value = useContext(ToastContext);
  if (!value) throw new Error("useToast must be used inside ToastProvider.");
  return value;
}

function CheckGlyph() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <path d="m5 12 4.5 4.5L19 6.5" />
    </svg>
  );
}

function AlertGlyph() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <path d="M12 3 2.5 20h19L12 3ZM12 9v5M12 17.2v.2" />
    </svg>
  );
}

function InfoGlyph() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v6M12 7.2v.2" />
    </svg>
  );
}
