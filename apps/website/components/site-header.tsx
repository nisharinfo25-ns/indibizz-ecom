"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useAuth, useCart } from "./providers";
import { CartIcon, CloseIcon, MenuIcon, MoonIcon, SunIcon, UserIcon } from "./icons";

const links = [
  { href: "/shop", label: "Shop" },
  { href: "/orders", label: "Orders" },
  { href: "/account", label: "Account" },
];

export function SiteHeader() {
  const pathname = usePathname();
  const { user, loading } = useAuth();
  const { count } = useCart();
  const [open, setOpen] = useState(false);

  useEffect(() => {
    setOpen(false);
  }, [pathname]);

  useEffect(() => {
    if (!open) return;
    const close = () => setOpen(false);
    window.addEventListener("resize", close);
    return () => window.removeEventListener("resize", close);
  }, [open]);

  return (
    <header className="site-header">
      <div className="container header-inner">
        <Link href="/" className="brand" aria-label="IndiaBizz home">
          <span className="brand-mark">IB</span>
          <span>
            IndiaBizz
            <small>Cash on delivery</small>
          </span>
        </Link>

        <nav className="nav" aria-label="Main navigation">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={`nav-link ${pathname === link.href || pathname.startsWith(link.href + "/") ? "active" : ""}`}
            >
              {link.label}
            </Link>
          ))}
        </nav>

        <div className="header-actions">
          <ThemeToggle />
          <Link href="/cart" className="icon-btn" aria-label={`Cart${count ? `, ${count} items` : ""}`}>
            <CartIcon />
            {count > 0 && <span className="cart-count">{count > 99 ? "99+" : count}</span>}
          </Link>
          {!loading && (
            <Link href={user ? "/account" : "/login"} className="icon-btn" aria-label={user ? "Your account" : "Sign in"}>
              <UserIcon />
            </Link>
          )}
          <button
            type="button"
            className="icon-btn mobile-toggle"
            aria-label={open ? "Close menu" : "Open menu"}
            aria-expanded={open}
            onClick={() => setOpen((value) => !value)}
          >
            {open ? <CloseIcon /> : <MenuIcon />}
          </button>
        </div>
      </div>

      {open && (
        <nav className="mobile-nav" aria-label="Mobile navigation">
          {links.map((link) => (
            <Link key={link.href} href={link.href} className="nav-link">
              {link.label}
            </Link>
          ))}
          <Link href="/cart" className="nav-link">
            Cart {count > 0 ? `(${count})` : ""}
          </Link>
          <Link href={user ? "/account" : "/login"} className="nav-link">
            {user ? "Your account" : "Sign in"}
          </Link>
        </nav>
      )}
    </header>
  );
}

export function ThemeToggle() {
  const [theme, setTheme] = useState<"light" | "dark" | null>(null);

  useEffect(() => {
    const stored = document.documentElement.dataset.theme;
    setTheme(stored === "dark" ? "dark" : "light");
  }, []);

  function toggle() {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    document.documentElement.dataset.theme = next;
    try {
      localStorage.setItem("indibizz-theme", next);
    } catch {
      /* storage can be blocked; the visual change still applies */
    }
  }

  return (
    <button type="button" className="icon-btn" onClick={toggle} aria-label={theme === "dark" ? "Switch to light theme" : "Switch to dark theme"}>
      {theme === null ? <SunIcon /> : theme === "dark" ? <SunIcon /> : <MoonIcon />}
    </button>
  );
}
