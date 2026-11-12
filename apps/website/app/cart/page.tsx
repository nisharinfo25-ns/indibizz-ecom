"use client";

import Link from "next/link";
import { useState } from "react";
import { errorMessage, formatMoney, pluralize } from "@indibizz/shared";
import { rpc } from "@/lib/api";
import { useAuth, useCart, useToast } from "@/components/providers";
import { ProductImage } from "@/components/product-image";
import { EmptyState, ErrorPanel, LoadingBlock, PageHead } from "@/components/ui";
import { ArrowRightIcon, LockIcon, MinusIcon, PlusIcon, TrashIcon } from "@/components/icons";

export default function CartPage() {
  const { user, loading: authLoading } = useAuth();
  const { cart, loading, refresh } = useCart();
  const { showToast } = useToast();
  const [pending, setPending] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function setQuantity(productId: string, quantity: number) {
    setPending(productId);
    setError(null);
    try {
      await rpc("cart_set_quantity", { p_product_id: productId, p_quantity: quantity });
      await refresh();
    } catch (caught) {
      const message = errorMessage(caught);
      setError(message);
      showToast(message, "error");
    } finally {
      setPending(null);
    }
  }

  async function remove(productId: string, name: string) {
    if (!window.confirm(`Remove ${name} from your cart?`)) return;
    setPending(productId);
    setError(null);
    try {
      await rpc("cart_remove_item", { p_product_id: productId });
      await refresh();
      showToast("Item removed from cart.");
    } catch (caught) {
      const message = errorMessage(caught);
      setError(message);
      showToast(message, "error");
    } finally {
      setPending(null);
    }
  }

  if (authLoading) {
    return <div className="page"><div className="container"><LoadingBlock /></div></div>;
  }

  if (!user) {
    return (
      <div className="page">
        <div className="container">
          <PageHead eyebrow="Cart" title="Your cart" />
          <EmptyState
            title="Sign in to see your cart"
            description="Your cart is stored securely against your verified phone number, so it follows you across devices."
            action={<Link href="/login?next=/cart" className="btn btn-primary btn-sm">Sign in with phone</Link>}
          />
        </div>
      </div>
    );
  }

  if (loading && !cart) {
    return <div className="page"><div className="container"><LoadingBlock label="Loading your cart…" /></div></div>;
  }

  const items = cart?.items ?? [];
  const unavailable = items.filter((item) => !item.is_available);

  return (
    <div className="page">
      <div className="container">
        <PageHead
          eyebrow="Cart"
          title="Your cart"
          description={items.length > 0 ? `${cart?.item_count} ${pluralize(cart?.item_count ?? 0, "item")} ready for a COD checkout.` : undefined}
          action={<Link href="/shop" className="btn btn-ghost btn-sm">Continue shopping</Link>}
        />

        {error && <div style={{ marginBottom: 16 }}><ErrorPanel message={error} /></div>}

        {items.length === 0 ? (
          <EmptyState
            title="Your cart is empty"
            description="Add something from the live catalogue. Prices and stock are checked again when you place the order."
            action={<Link href="/shop" className="btn btn-primary btn-sm">Browse products</Link>}
          />
        ) : (
          <div className="cart-layout">
            <div className="card">
              {items.map((item) => {
                const busy = pending === item.product_id;
                return (
                  <div className="line-item" key={item.product_id}>
                    <Link href={`/product/${item.slug}`} className="line-thumb" aria-label={item.name}>
                      <ProductImage path={item.primary_image_path} alt={item.name} fallbackName={item.name} />
                    </Link>
                    <div className="line-main">
                      <Link href={`/product/${item.slug}`} className="line-title">{item.name}</Link>
                      <span className="muted small">SKU {item.sku}</span>
                      {!item.is_available && <span className="error-text">Only {item.available_quantity} available — reduce the quantity or remove this item.</span>}
                      <div className="line-actions">
                        <div className="qty">
                          <button
                            type="button"
                            className="qty-btn"
                            disabled={busy || item.quantity <= 1}
                            onClick={() => setQuantity(item.product_id, item.quantity - 1)}
                            aria-label={`Decrease ${item.name} quantity`}
                          >
                            <MinusIcon size={15} />
                          </button>
                          <span className="qty-value">{item.quantity}</span>
                          <button
                            type="button"
                            className="qty-btn"
                            disabled={busy || item.quantity >= Math.min(item.available_quantity, 99)}
                            onClick={() => setQuantity(item.product_id, item.quantity + 1)}
                            aria-label={`Increase ${item.name} quantity`}
                          >
                            <PlusIcon size={15} />
                          </button>
                        </div>
                        <button
                          type="button"
                          className="btn btn-ghost btn-sm"
                          disabled={busy}
                          onClick={() => remove(item.product_id, item.name)}
                        >
                          <TrashIcon size={15} /> Remove
                        </button>
                        {busy && <span className="spinner" />}
                      </div>
                    </div>
                    <div className="line-price">
                      <div>{formatMoney(item.line_subtotal_paise)}</div>
                      <div className="muted small">{formatMoney(item.unit_price_paise)} each</div>
                    </div>
                  </div>
                );
              })}
            </div>

            <aside className="card summary">
              <h2>Order summary</h2>
              <div className="summary-row">
                <span>Subtotal ({cart?.item_count} {pluralize(cart?.item_count ?? 0, "item")})</span>
                <strong>{formatMoney(cart?.subtotal_paise)}</strong>
              </div>
              <div className="summary-row">
                <span>Shipping</span>
                <span>Calculated at checkout</span>
              </div>
              <div className="summary-row">
                <span>Tax</span>
                <span>Based on seller settings</span>
              </div>
              <div className="summary-total">
                <span>Subtotal</span>
                <span className="amount">{formatMoney(cart?.subtotal_paise)}</span>
              </div>

              {unavailable.length > 0 && (
                <div className="alert warning" style={{ marginTop: 14 }}>
                  Some items changed stock. Adjust them before checkout.
                </div>
              )}

              <Link
                href="/checkout"
                className={`btn btn-primary btn-block ${unavailable.length > 0 ? "disabled" : ""}`}
                aria-disabled={unavailable.length > 0}
                onClick={(event) => {
                  if (unavailable.length > 0) event.preventDefault();
                }}
                style={{ marginTop: 16 }}
              >
                Checkout with COD <ArrowRightIcon size={17} />
              </Link>

              <div className="cod-note">
                <LockIcon size={17} />
                <span>
                  Cash on delivery only. The final COD amount is locked when you place the order and is shown again on the delivery OTP screen.
                </span>
              </div>
            </aside>
          </div>
        )}
      </div>
    </div>
  );
}
