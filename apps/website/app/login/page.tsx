"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import {
  errorMessage,
  formatPhoneDisplay,
  isIndianMobile,
  normalizePhone,
} from "@indibizz/shared";
import { requestOtp } from "@/lib/api";
import { safeNextPath } from "@/lib/catalog";
import { useAuth, useToast } from "@/components/providers";
import { getSupabase } from "@/lib/supabase";
import { LoadingBlock } from "@/components/ui";
import { ArrowRightIcon, LockIcon, PhoneIcon, ShieldIcon } from "@/components/icons";

function LoginContent() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const { user, loading: authLoading, profile } = useAuth();
  const { showToast } = useToast();

  const [step, setStep] = useState<"phone" | "otp">("phone");
  const [phone, setPhone] = useState("");
  const [otp, setOtp] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sending, setSending] = useState(false);
  const [verifying, setVerifying] = useState(false);
  const [cooldown, setCooldown] = useState(0);

  const next = safeNextPath(searchParams.get("next"));

  useEffect(() => {
    if (cooldown <= 0) return;
    const timer = setInterval(() => setCooldown((value) => Math.max(0, value - 1)), 1000);
    return () => clearInterval(timer);
  }, [cooldown]);

  useEffect(() => {
    if (!authLoading && user) {
      const timer = setTimeout(() => router.replace(next), 900);
      return () => clearTimeout(timer);
    }
  }, [authLoading, next, router, user]);

  async function sendOtp(event?: React.FormEvent) {
    event?.preventDefault();
    setError(null);
    if (!isIndianMobile(phone)) {
      setError("Enter a valid 10-digit Indian mobile number.");
      return;
    }
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Enter a valid mobile number.");
      return;
    }
    setSending(true);
    try {
      const result = await requestOtp(normalized);
      if (!result.ok) {
        setError(result.message ?? "The OTP could not be sent.");
        return;
      }
      setStep("otp");
      setCooldown(result.cooldown_seconds ?? 60);
      setOtp("");
      showToast("If the number is valid, an OTP was sent by SMS.", "success");
    } catch (caught) {
      setError(errorMessage(caught, "The OTP service could not be reached."));
    } finally {
      setSending(false);
    }
  }

  async function verify(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    if (otp.length !== 6) {
      setError("Enter the 6-digit OTP.");
      return;
    }
    const normalized = normalizePhone(phone);
    if (!normalized) {
      setError("Go back and enter a valid phone number.");
      return;
    }
    setVerifying(true);
    try {
      const { error: verifyError } = await getSupabase().auth.verifyOtp({
        phone: normalized,
        token: otp,
        type: "sms",
      });
      if (verifyError) {
        setError(
          /expired/i.test(verifyError.message)
            ? "That OTP has expired. Request a new code."
            : /invalid|incorrect/i.test(verifyError.message)
              ? "The OTP is incorrect. Check the SMS and try again."
              : errorMessage(verifyError),
        );
        return;
      }
      showToast("Signed in successfully.", "success");
      router.replace(next);
    } catch (caught) {
      setError(errorMessage(caught, "Verification failed. Please try again."));
    } finally {
      setVerifying(false);
    }
  }

  if (authLoading) return <div className="page"><div className="container"><LoadingBlock /></div></div>;

  if (user) {
    return (
      <div className="auth-shell">
        <div className="auth-card">
          <div className="auth-mark"><ShieldIcon size={23} /></div>
          <h1>You&apos;re signed in</h1>
          <p className="lead">
            {profile ? `${profile.full_name || "Welcome back"} · ${formatPhoneDisplay(profile.phone)}` : "Your session is active."}
          </p>
          <div className="stack" style={{ marginTop: 22 }}>
            <Link href={next} className="btn btn-primary btn-block">Continue <ArrowRightIcon size={17} /></Link>
            <Link href="/account" className="btn btn-outline btn-block">Your account</Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <div className="auth-card">
        <div className="auth-mark">{step === "phone" ? <PhoneIcon size={22} /> : <LockIcon size={22} />}</div>
        <h1>{step === "phone" ? "Sign in with your phone" : "Enter the OTP"}</h1>
        <p className="lead">
          {step === "phone"
            ? "We send a one-time code by SMS. No password, no prepayment."
            : `Enter the 6-digit code sent to ${formatPhoneDisplay(phone)}.`}
        </p>

        {error && (
          <div className="alert error" style={{ marginTop: 18 }} role="alert">
            <span>{error}</span>
          </div>
        )}

        {step === "phone" ? (
          <form onSubmit={sendOtp} noValidate>
            <div className="field">
              <label className="label" htmlFor="login-phone">Mobile number</label>
              <input
                id="login-phone"
                className="input"
                inputMode="tel"
                autoComplete="tel"
                placeholder="98765 43210"
                value={phone}
                onChange={(event) => setPhone(event.target.value)}
                autoFocus
              />
              <span className="help">Indian mobile number. Standard SMS rates may apply.</span>
            </div>
            <button type="submit" className="btn btn-primary btn-block" disabled={sending}>
              {sending ? <span className="spinner" /> : <PhoneIcon size={17} />}
              {sending ? "Sending OTP…" : "Send OTP"}
            </button>
            <p className="help" style={{ textAlign: "center" }}>
              OTP delivery depends on the seller&apos;s SMS provider. If it is not configured, you will see an exact configuration error — never a fake code.
            </p>
          </form>
        ) : (
          <form onSubmit={verify} noValidate>
            <div className="field">
              <label className="label" htmlFor="login-otp">One-time code</label>
              <input
                id="login-otp"
                className="input otp-input"
                inputMode="numeric"
                autoComplete="one-time-code"
                pattern="[0-9]*"
                maxLength={6}
                value={otp}
                onChange={(event) => setOtp(event.target.value.replace(/\D/g, "").slice(0, 6))}
                autoFocus
              />
            </div>
            <button type="submit" className="btn btn-primary btn-block" disabled={verifying || otp.length !== 6}>
              {verifying ? <span className="spinner" /> : <LockIcon size={17} />}
              {verifying ? "Verifying…" : "Verify and sign in"}
            </button>
            <div className="auth-meta">
              <button
                type="button"
                className="link-btn"
                onClick={() => {
                  setStep("phone");
                  setOtp("");
                  setError(null);
                }}
              >
                Change number
              </button>
              <button
                type="button"
                className="link-btn"
                disabled={cooldown > 0 || sending}
                onClick={() => void sendOtp()}
              >
                {cooldown > 0 ? `Resend in ${cooldown}s` : sending ? "Sending…" : "Resend OTP"}
              </button>
            </div>
          </form>
        )}

        <div className="alert" style={{ marginTop: 20 }}>
          <ShieldIcon size={17} />
          <span>IndiaBizz will never call and ask for your OTP. Share it only with the assigned delivery person at handover.</span>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense fallback={<div className="page"><div className="container"><LoadingBlock /></div></div>}>
      <LoginContent />
    </Suspense>
  );
}
