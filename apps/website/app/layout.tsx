import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { AuthProvider, CartProvider, ToastProvider } from "@/components/providers";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "IndiaBizz — Everyday essentials, delivered with proof",
    template: "%s | IndiaBizz",
  },
  description:
    "Shop everyday essentials with cash on delivery, OTP-verified handover and clear order tracking. No prepayment.",
  applicationName: "IndiaBizz",
  robots: { index: true, follow: true },
  openGraph: {
    title: "IndiaBizz — Cash on delivery, delivered with proof",
    description: "Browse the catalogue, order with COD and follow every step until delivery.",
    type: "website",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f8fc" },
    { media: "(prefers-color-scheme: dark)", color: "#070d17" },
  ],
};

const themeScript = `
(() => {
  try {
    const saved = localStorage.getItem('indibizz-theme');
    const theme = saved === 'light' || saved === 'dark'
      ? saved
      : (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    document.documentElement.dataset.theme = theme;
  } catch (_) {
    document.documentElement.dataset.theme = 'light';
  }
})();
`;

export default function RootLayout({ children }: { children: ReactNode }) {
  const configured = Boolean(
    (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").trim() &&
      (process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "").trim(),
  );

  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeScript }} />
      </head>
      <body>
        {!configured && (
          <div className="config-banner" role="alert">
            Storefront configuration missing: set <code>NEXT_PUBLIC_SUPABASE_URL</code> and{" "}
            <code>NEXT_PUBLIC_SUPABASE_ANON_KEY</code> in <code>.env.local</code>, then restart.
          </div>
        )}
        <ToastProvider>
          <AuthProvider>
            <CartProvider>
              <SiteHeader />
              <main>{children}</main>
              <SiteFooter />
            </CartProvider>
          </AuthProvider>
        </ToastProvider>
      </body>
    </html>
  );
}
