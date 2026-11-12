"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  errorMessage,
  formatMoney,
  type CatalogProduct,
  type Serviceability,
} from "@indibizz/shared";
import {
  checkServiceability,
  fetchCatalog,
  fetchProductBySlug,
  fetchProductImages,
  rpc,
} from "@/lib/api";
import { useAuth, useCart, useToast } from "@/components/providers";
import { ProductImage } from "@/components/product-image";
import { ProductCard } from "@/components/product-card";
import { EmptyState, ErrorPanel, LoadingBlock } from "@/components/ui";
import {
  ArrowRightIcon,
  CheckIcon,
  LockIcon,
  MapPinIcon,
  MinusIcon,
  PackageIcon,
  PlusIcon,
  ShieldIcon,
} from "@/components/icons";

export default function ProductPage() {
  const params = useParams<{ slug: string }>();
  const slug = params?.slug ?? "";
  const router = useRouter();
  const { user } = useAuth();
  const { refresh } = useCart();
  const { showToast } = useToast();

  const [product, setProduct] = useState<CatalogProduct | null>(null);
  const [images, setImages] = useState<Array<{ id: string; storage_path: string; alt_text: string }>>([]);
  const [related, setRelated] = useState<CatalogProduct[]>([]);
  const [activeImage, setActiveImage] = useState<string | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [added, setAdded] = useState(false);
  const [pin, setPin] = useState("");
  const [serviceability, setServiceability] = useState<Serviceability | null>(null);
  const [checkingPin, setCheckingPin] = useState(false);

  const load = useCallback(async () => {
    if (!slug) return;
    setLoading(true);
    setError(null);
    try {
      const found = await fetchProductBySlug(slug);
      setProduct(found);
      if (found) {
        const [imageRows, catalogue] = await Promise.all([
          fetchProductImages(found.id).catch(() => []),
          fetchCatalog().catch(() => []),
        ]);
        setImages(imageRows);
        setActiveImage(imageRows[0]?.storage_path ?? found.primary_image_path ?? null);
        setRelated(
          catalogue
            .filter((item) => item.category_id === found.category_id && item.id !== found.id && item.in_stock)
            .slice(0, 4),
        );
      }
    } catch (caught) {
      setError(errorMessage(caught, "This product could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, [slug]);

  useEffect(() => {
    void load();
  }, [load]);

  const discount = useMemo(() => {
    if (!product?.compare_at_price_paise || product.compare_at_price_paise <= product.price_paise) return 0;
    return Math.round(((product.compare_at_price_paise - product.price_paise) / product.compare_at_price_paise) * 100);
  }, [product]);

  async function addToCart() {
    if (!product) return;
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/product/${product.slug}`)}`);
      return;
    }
    setAdding(true);
    try {
      await rpc("cart_add_item", { p_product_id: product.id, p_quantity: quantity });
      await refresh();
      setAdded(true);
      showToast(`${quantity} × ${product.name} added to your cart.`, "success");
    } catch (caught) {
      showToast(errorMessage(caught), "error");
    } finally {
      setAdding(false);
    }
  }

  async function checkPin() {
    if (pin.trim().length !== 6) {
      setServiceability({
        serviceable: false,
        town_id: null,
        town_name: null,
        district: null,
        state: null,
        message: "Enter a 6-digit PIN code.",
      });
      return;
    }
    setCheckingPin(true);
    setServiceability(null);
    try {
      setServiceability(await checkServiceability(pin.trim()));
    } catch (caught) {
      setServiceability({
        serviceable: false,
        town_id: null,
        town_name: null,
        district: null,
        state: null,
        message: errorMessage(caught),
      });
    } finally {
      setCheckingPin(false);
    }
  }

  if (loading) {
    return <div className="page"><div className="container"><LoadingBlock label="Loading product…" /></div></div>;
  }

  if (error) {
    return (
      <div className="page">
        <div className="container">
          <ErrorPanel message={error} retry={load} />
        </div>
      </div>
    );
  }

  if (!product) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Product not found"
            description="This product may have been archived or is no longer active. Browse the current catalogue instead."
            action={<Link href="/shop" className="btn btn-primary btn-sm">Browse the catalogue</Link>}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <div className="container">
        <nav className="breadcrumbs" aria-label="Breadcrumb">
          <Link href="/">Home</Link>
          <span>/</span>
          <Link href="/shop">Shop</Link>
          <span>/</span>
          <Link href={`/shop?category=${encodeURIComponent(product.category_slug)}`}>{product.category_name}</Link>
          <span>/</span>
          <span className="muted">{product.name}</span>
        </nav>

        <div className="product-detail">
          <div className="gallery">
            <div className="gallery-main">
              <ProductImage path={activeImage} alt={product.name} fallbackName={product.name} eager />
            </div>
            {images.length > 1 && (
              <div className="gallery-thumbs" aria-label="Product images">
                {images.map((image) => (
                  <button
                    key={image.id}
                    type="button"
                    className={`gallery-thumb ${activeImage === image.storage_path ? "active" : ""}`}
                    onClick={() => setActiveImage(image.storage_path)}
                    aria-label={image.alt_text || product.name}
                  >
                    <ProductImage path={image.storage_path} alt={image.alt_text || product.name} fallbackName={product.name} />
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="product-info">
            <div>
              <div className="eyebrow">{product.category_name}</div>
              <h1 style={{ fontSize: "clamp(1.7rem, 3.4vw, 2.6rem)", marginTop: 8 }}>{product.name}</h1>
            </div>

            <div className="price-row">
              <span className="price-lg">{formatMoney(product.price_paise)}</span>
              {product.compare_at_price_paise && product.compare_at_price_paise > product.price_paise && (
                <>
                  <span className="compare" style={{ fontSize: "0.95rem" }}>{formatMoney(product.compare_at_price_paise)}</span>
                  <span className="badge success">{discount}% off</span>
                </>
              )}
            </div>

            <div className="row">
              <span className={`stock-pill ${!product.in_stock ? "out" : product.available_quantity <= 5 ? "low" : ""}`}>
                {product.in_stock
                  ? product.available_quantity <= 5
                    ? `Only ${product.available_quantity} left`
                    : "In stock"
                  : "Sold out"}
              </span>
              <span className="muted small">SKU {product.sku}</span>
            </div>

            {product.description && <p className="muted" style={{ lineHeight: 1.65 }}>{product.description}</p>}

            <ul className="detail-list">
              <li><ShieldIcon size={17} /> Cash on delivery — pay after checking the parcel.</li>
              <li><LockIcon size={17} /> Handover verified with a one-time delivery OTP.</li>
              <li><PackageIcon size={17} /> Sealed and scanned package with a recorded pickup trail.</li>
              <li><CheckIcon size={17} /> Taxes, if configured, are shown transparently in your cart and checkout.</li>
            </ul>

            <div className="buy-row">
              <div className="qty" aria-label="Quantity">
                <button type="button" className="qty-btn" onClick={() => setQuantity((value) => Math.max(1, value - 1))} disabled={quantity <= 1} aria-label="Decrease quantity">
                  <MinusIcon size={16} />
                </button>
                <span className="qty-value" aria-live="polite">{quantity}</span>
                <button
                  type="button"
                  className="qty-btn"
                  onClick={() => setQuantity((value) => Math.min(product.available_quantity || 99, value + 1))}
                  disabled={quantity >= Math.min(product.available_quantity || 99, 99)}
                  aria-label="Increase quantity"
                >
                  <PlusIcon size={16} />
                </button>
              </div>
              <button
                type="button"
                className="btn btn-primary"
                onClick={addToCart}
                disabled={!product.in_stock || adding || quantity > product.available_quantity}
              >
                {adding ? <span className="spinner" /> : null}
                {!product.in_stock ? "Sold out" : adding ? "Adding…" : "Add to cart"}
              </button>
              {added && (
                <Link href="/cart" className="btn btn-outline">
                  View cart <ArrowRightIcon size={16} />
                </Link>
              )}
            </div>
            {!user && <span className="help">You will be asked to sign in with a phone OTP before adding items.</span>}

            <hr className="divider" />

            <div className="card card-pad stack-sm" style={{ boxShadow: "none" }}>
              <div className="row" style={{ gap: 8 }}>
                <MapPinIcon size={17} />
                <strong style={{ fontSize: "0.9rem" }}>Check delivery</strong>
              </div>
              <div className="serviceability">
                <input
                  className="input"
                  inputMode="numeric"
                  placeholder="Enter 6-digit PIN"
                  value={pin}
                  onChange={(event) => setPin(event.target.value.replace(/\D/g, "").slice(0, 6))}
                  aria-label="Delivery PIN code"
                  onKeyDown={(event) => {
                    if (event.key === "Enter") {
                      event.preventDefault();
                      void checkPin();
                    }
                  }}
                />
                <button type="button" className="btn btn-outline" onClick={checkPin} disabled={checkingPin}>
                  {checkingPin ? <span className="spinner" /> : "Check"}
                </button>
              </div>
              {serviceability && (
                <div className={`alert ${serviceability.serviceable ? "success" : "warning"}`} role="status">
                  <div>
                    <strong>{serviceability.serviceable ? "Deliverable" : "Not serviceable"}</strong>
                    <p style={{ marginTop: 2 }}>{serviceability.message}</p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {related.length > 0 && (
          <section className="section">
            <div className="section-head">
              <div>
                <div className="eyebrow" style={{ marginBottom: 8 }}>More from {product.category_name}</div>
                <h2>You may also like</h2>
              </div>
            </div>
            <div className="product-grid">
              {related.map((item) => (
                <ProductCard key={item.id} product={item} />
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
