"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { errorMessage, type CatalogProduct } from "@indibizz/shared";
import { categoriesFromProducts, fetchCatalog, publicSettings, type PublicSettings } from "@/lib/api";
import { ProductCard } from "@/components/product-card";
import { EmptyState, ErrorPanel, LoadingGrid } from "@/components/ui";
import {
  ArrowRightIcon,
  CheckIcon,
  LockIcon,
  PackageIcon,
  RupeeIcon,
  ShieldIcon,
  TruckIcon,
} from "@/components/icons";

export default function HomePage() {
  const [products, setProducts] = useState<CatalogProduct[]>([]);
  const [settings, setSettings] = useState<PublicSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [catalogue, configuration] = await Promise.all([
        fetchCatalog(),
        publicSettings().catch(() => null),
      ]);
      setProducts(catalogue);
      setSettings(configuration);
    } catch (caught) {
      setError(errorMessage(caught, "The catalogue could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const categories = useMemo(() => categoriesFromProducts(products).slice(0, 8), [products]);
  const featured = useMemo(() => {
    const flagged = products.filter((product) => product.is_featured && product.in_stock);
    return (flagged.length > 0 ? flagged : products.filter((product) => product.in_stock)).slice(0, 8);
  }, [products]);
  const returnDays = Number(settings?.policies?.return_window_days ?? 0);

  return (
    <>
      <div className="container">
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">Cash on delivery • OTP verified</div>
            <h1 className="hero-title">
              Everyday essentials, <em>delivered with proof.</em>
            </h1>
            <p className="lead">
              Browse a real catalogue, pay cash at your door, and follow every step from
              confirmation to handover. No prepayment. No guessed tracking.
            </p>
            <div className="hero-actions">
              <Link href="/shop" className="btn btn-accent">
                Start shopping <ArrowRightIcon size={18} />
              </Link>
              <Link href="/orders" className="btn btn-outline">
                Track an order
              </Link>
            </div>
            <div className="hero-notes">
              <span><CheckIcon size={15} /> No card needed</span>
              <span><CheckIcon size={15} /> Check the parcel first</span>
              <span><CheckIcon size={15} /> Pay the exact COD amount</span>
            </div>
          </div>

          <aside className="promise-card" aria-label="How IndiaBizz delivery works">
            <div className="row" style={{ marginBottom: 14 }}>
              <span className="badge" style={{ background: "rgba(242,163,58,0.18)", color: "#ffd18c" }}>
                The COD promise
              </span>
            </div>
            <h3>Pay only when the parcel is in your hands.</h3>
            <p>Every handover is verified. Every parcel is scanned. Your cash stays yours until delivery.</p>

            <div className="promise-row">
              <span className="promise-icon"><ShieldIcon size={18} /></span>
              <div>
                <strong>Check before you pay</strong>
                <span>Confirm the package, count and condition at your door.</span>
              </div>
            </div>
            <div className="promise-row">
              <span className="promise-icon"><LockIcon size={18} /></span>
              <div>
                <strong>Share the delivery OTP</strong>
                <span>The assigned delivery person verifies the handover with your one-time code.</span>
              </div>
            </div>
            <div className="promise-row">
              <span className="promise-icon"><PackageIcon size={18} /></span>
              <div>
                <strong>Sealed and accounted for</strong>
                <span>Packages are sealed and scanned at pickup — never marked from a barcode alone.</span>
              </div>
            </div>
          </aside>
        </section>

        <div className="trust-strip">
          <div className="trust-item"><RupeeIcon size={18} /> Cash on delivery only</div>
          <div className="trust-item"><LockIcon size={18} /> One-time delivery OTP</div>
          <div className="trust-item"><PackageIcon size={18} /> Sealed package evidence</div>
          <div className="trust-item"><TruckIcon size={18} /> Tracked delivery trail</div>
        </div>
      </div>

      <section className="section">
        <div className="container">
          <div className="section-head">
            <div>
              <div className="eyebrow" style={{ marginBottom: 8 }}>The catalogue</div>
              <h2>Ready to deliver</h2>
              <p>Products currently active and in stock with the seller.</p>
            </div>
            <Link href="/shop" className="btn btn-ghost btn-sm">
              View all <ArrowRightIcon size={16} />
            </Link>
          </div>

          {categories.length > 0 && (
            <div className="chip-row" style={{ marginBottom: 20 }}>
              <Link href="/shop" className="chip active">All products</Link>
              {categories.map((category) => (
                <Link key={category.id} href={`/shop?category=${encodeURIComponent(category.slug)}`} className="chip">
                  {category.name} <span className="muted">{category.product_count}</span>
                </Link>
              ))}
            </div>
          )}

          {error ? (
            <ErrorPanel message={error} retry={load} />
          ) : loading ? (
            <LoadingGrid count={8} />
          ) : featured.length === 0 ? (
            <EmptyState
              title="The catalogue is being prepared"
              description="No active products are published yet. This storefront never shows sample products or invented stock — check back after the seller adds the first items."
              action={<Link href="/account" className="btn btn-outline btn-sm">Go to your account</Link>}
            />
          ) : (
            <div className="product-grid">
              {featured.map((product) => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          )}
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="section-head">
            <div>
              <div className="eyebrow" style={{ marginBottom: 8 }}>No surprises</div>
              <h2>How your COD order moves</h2>
            </div>
          </div>
          <div className="steps-grid">
            <article className="card step-card">
              <span className="step-num">01</span>
              <h3>Place your order</h3>
              <p>Choose a serviceable address, review the live stock and confirm the COD total. The seller approves and packs your parcel.</p>
            </article>
            <article className="card step-card">
              <span className="step-num">02</span>
              <h3>Track the handover</h3>
              <p>Every scan, pickup and transit event is recorded. When the parcel is out for delivery, your one-time OTP appears here.</p>
            </article>
            <article className="card step-card">
              <span className="step-num">03</span>
              <h3>Check, then pay</h3>
              <p>Inspect the sealed parcel, pay the exact cash amount and share the delivery OTP only after you are satisfied.</p>
            </article>
          </div>
        </div>
      </section>

      <section className="section">
        <div className="container">
          <div className="panel" style={{ padding: 28 }}>
            <div className="spread" style={{ alignItems: "flex-start" }}>
              <div>
                <div className="eyebrow" style={{ marginBottom: 8 }}>Buy with confidence</div>
                <h2>COD, without the guesswork.</h2>
                <p className="lead" style={{ marginTop: 8 }}>
                  {returnDays > 0
                    ? `Returns are accepted within ${returnDays} days of delivery, in original condition.`
                    : "Return eligibility follows the seller's published policy and is shown on your delivered order."}
                </p>
              </div>
              <Link href="/shop" className="btn btn-primary">
                Browse products <ArrowRightIcon size={17} />
              </Link>
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
