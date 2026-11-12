"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  errorMessage,
  formatMoney,
  newIdempotencyKey,
  pluralize,
  type Address,
  type Cart,
  type Quote,
  type Town,
} from "@indibizz/shared";
import {
  createAddress,
  getAddresses,
  getCart,
  getQuote,
  getTowns,
  rpc,
} from "@/lib/api";
import { useAuth, useCart, useToast } from "@/components/providers";
import { AddressForm } from "@/components/address-form";
import { ProductImage } from "@/components/product-image";
import { EmptyState, ErrorPanel, LoadingBlock, PageHead } from "@/components/ui";
import { CheckIcon, LockIcon, MapPinIcon, PlusIcon, ShieldIcon } from "@/components/icons";

interface PlaceOrderResult {
  order_id: string;
  order_number: string;
  status: string;
  total_paise: number;
  cod_amount_paise: number;
  idempotent_replay: boolean;
}

export default function CheckoutPage() {
  const router = useRouter();
  const { user, profile, loading: authLoading } = useAuth();
  const { refresh } = useCart();
  const { showToast } = useToast();

  const [cart, setCart] = useState<Cart | null>(null);
  const [addresses, setAddresses] = useState<Address[]>([]);
  const [towns, setTowns] = useState<Town[]>([]);
  const [selectedAddress, setSelectedAddress] = useState<string>("");
  const [quote, setQuote] = useState<Quote | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingQuote, setLoadingQuote] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [quoteError, setQuoteError] = useState<string | null>(null);
  const [showAddressForm, setShowAddressForm] = useState(false);
  const [note, setNote] = useState("");
  const [consent, setConsent] = useState(false);
  const [placing, setPlacing] = useState(false);
  const [placeError, setPlaceError] = useState<string | null>(null);
  const [idempotencyKey] = useState(() => newIdempotencyKey("checkout"));

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [cartResult, addressResult, townResult] = await Promise.all([
        getCart(),
        getAddresses(),
        getTowns(),
      ]);
      setCart(cartResult);
      setAddresses(addressResult);
      setTowns(townResult);
      const preferred = addressResult.find((address) => address.is_default) ?? addressResult[0];
      setSelectedAddress((current) => current || preferred?.id || "");
      if (addressResult.length === 0) setShowAddressForm(true);
    } catch (caught) {
      setError(errorMessage(caught, "Checkout could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      setLoading(false);
      return;
    }
    void load();
  }, [authLoading, load, user]);

  const loadQuote = useCallback(async (addressId: string) => {
    if (!addressId) {
      setQuote(null);
      return;
    }
    setLoadingQuote(true);
    setQuoteError(null);
    try {
      const result = await getQuote(addressId);
      setQuote(result);
    } catch (caught) {
      setQuote(null);
      setQuoteError(errorMessage(caught, "The final COD amount could not be calculated."));
    } finally {
      setLoadingQuote(false);
    }
  }, []);

  useEffect(() => {
    if (!selectedAddress) {
      setQuote(null);
      return;
    }
    void loadQuote(selectedAddress);
  }, [loadQuote, selectedAddress]);

  const cartImages = useMemo(() => {
    const map = new Map<string, string | null>();
    for (const item of cart?.items ?? []) map.set(item.product_id, item.primary_image_path);
    return map;
  }, [cart]);

  async function onAddressSaved(address: Address) {
    const updated = await getAddresses();
    setAddresses(updated);
    setSelectedAddress(address.id);
    setShowAddressForm(false);
    showToast("Delivery address saved.", "success");
  }

  async function placeOrder() {
    if (!selectedAddress) {
      setPlaceError("Select a delivery address first.");
      return;
    }
    if (!quote) {
      setPlaceError("Wait for the COD total to load before placing the order.");
      return;
    }
    if (!consent) {
      setPlaceError("Confirm that you will pay the exact cash amount on delivery.");
      return;
    }
    setPlacing(true);
    setPlaceError(null);
    try {
      const result = await rpc<PlaceOrderResult>("place_order", {
        p_address_id: selectedAddress,
        p_idempotency_key: idempotencyKey,
        p_customer_note: note.trim() || null,
      });
      await refresh();
      showToast("Order placed. The seller will confirm it shortly.", "success");
      router.replace(`/orders/${result.order_id}?placed=1`);
    } catch (caught) {
      const message = errorMessage(caught, "The order could not be placed.");
      setPlaceError(message);
      showToast(message, "error");
      // Stock or pricing may have changed; refresh the quote for a safe retry.
      void loadQuote(selectedAddress);
    } finally {
      setPlacing(false);
    }
  }

  if (authLoading) return <div className="page"><div className="container"><LoadingBlock /></div></div>;

  if (!user) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Sign in to check out"
            description="Your verified phone number protects the order, the delivery OTP and your address book."
            action={<Link href="/login?next=/checkout" className="btn btn-primary btn-sm">Sign in with phone</Link>}
          />
        </div>
      </div>
    );
  }

  if (loading) return <div className="page"><div className="container"><LoadingBlock label="Preparing checkout…" /></div></div>;

  if (error) {
    return <div className="page"><div className="container"><ErrorPanel message={error} retry={load} /></div></div>;
  }

  if (!cart || cart.items.length === 0) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Nothing to check out"
            description="Your cart is empty. Add a product before placing a COD order."
            action={<Link href="/shop" className="btn btn-primary btn-sm">Browse products</Link>}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <div className="container">
        <PageHead
          eyebrow="Checkout"
          title="Confirm your COD order"
          description="Choose the delivery address, review the final amount and place the order. Nothing is charged now."
        />

        <div className="checkout-layout">
          <div className="stack">
            <section className="card card-pad">
              <div className="spread" style={{ marginBottom: 14 }}>
                <div>
                  <h2 style={{ fontSize: "1.12rem" }}>Delivery address</h2>
                  <p className="muted small" style={{ marginTop: 3 }}>Only serviceable towns and PIN codes can be saved.</p>
                </div>
                {!showAddressForm && (
                  <button type="button" className="btn btn-outline btn-sm" onClick={() => setShowAddressForm(true)}>
                    <PlusIcon size={15} /> Add address
                  </button>
                )}
              </div>

              {showAddressForm ? (
                <AddressForm
                  key="new-address"
                  towns={towns}
                  defaultPhone={profile?.phone ?? ""}
                  onSaved={onAddressSaved}
                  onCancel={addresses.length > 0 ? () => setShowAddressForm(false) : undefined}
                />
              ) : addresses.length === 0 ? (
                <EmptyState
                  title="No delivery address yet"
                  description="Add a serviceable address to continue."
                  action={<button type="button" className="btn btn-primary btn-sm" onClick={() => setShowAddressForm(true)}>Add address</button>}
                />
              ) : (
                <div className="stack-sm">
                  {addresses.map((address) => (
                    <label
                      key={address.id}
                      className={`address-option ${selectedAddress === address.id ? "selected" : ""}`}
                      style={{ cursor: "pointer" }}
                    >
                      <input
                        type="radio"
                        name="delivery-address"
                        value={address.id}
                        checked={selectedAddress === address.id}
                        onChange={() => setSelectedAddress(address.id)}
                      />
                      <span style={{ flex: 1 }}>
                        <span className="address-title">
                          <MapPinIcon size={15} /> {address.label}
                          {address.is_default && <span className="address-tag">Default</span>}
                        </span>
                        <span className="address-text" style={{ display: "block" }}>
                          {address.recipient_name} · {address.phone}
                          <br />
                          {[address.line1, address.line2, address.landmark].filter(Boolean).join(", ")}
                          <br />
                          {address.town_name}, {address.district}, {address.state} — {address.pincode}
                        </span>
                      </span>
                    </label>
                  ))}
                </div>
              )}
            </section>

            <section className="card card-pad">
              <h2 style={{ fontSize: "1.12rem", marginBottom: 6 }}>Order note <span className="muted small">(optional)</span></h2>
              <p className="muted small" style={{ marginBottom: 10 }}>Delivery instructions for the seller and delivery person.</p>
              <textarea
                className="textarea"
                value={note}
                onChange={(event) => setNote(event.target.value.slice(0, 1000))}
                placeholder="For example: call before reaching the gate."
                maxLength={1000}
                aria-label="Order note"
              />
              <div className="help" style={{ marginTop: 5 }}>{note.length}/1000</div>
            </section>

            <section className="card">
              <div className="card-pad" style={{ paddingBottom: 8 }}>
                <h2 style={{ fontSize: "1.12rem" }}>Items in this order</h2>
              </div>
              {loadingQuote ? (
                <LoadingBlock label="Calculating the final amount…" />
              ) : quoteError ? (
                <div className="card-pad"><ErrorPanel message={quoteError} retry={() => loadQuote(selectedAddress)} /></div>
              ) : quote ? (
                <div className="card-pad" style={{ paddingTop: 8 }}>
                  {quote.items.map((item) => (
                    <div className="item-row" key={item.product_id}>
                      <div className="row" style={{ gap: 12, flexWrap: "nowrap" }}>
                        <div className="line-thumb" style={{ width: 52, height: 52, flex: "0 0 auto" }}>
                          <ProductImage path={cartImages.get(item.product_id) ?? null} alt={item.name} fallbackName={item.name} />
                        </div>
                        <div>
                          <div className="item-name">{item.name}</div>
                          <div className="item-sub">{item.quantity} × {formatMoney(item.unit_price_paise)} · SKU {item.sku}</div>
                          {!item.is_available && <div className="error-text">Stock is no longer sufficient.</div>}
                        </div>
                      </div>
                      <strong>{formatMoney(item.line_total_paise)}</strong>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="card-pad"><span className="muted small">Select a delivery address to see the final COD amount.</span></div>
              )}
            </section>
          </div>

          <aside className="card summary">
            <h2>Cash on delivery</h2>
            {quote ? (
              <>
                <div className="summary-row">
                  <span>Subtotal ({quote.item_count} {pluralize(quote.item_count, "item")})</span>
                  <strong>{formatMoney(quote.subtotal_paise)}</strong>
                </div>
                <div className="summary-row">
                  <span>Discount</span>
                  <strong>{quote.discount_paise > 0 ? `− ${formatMoney(quote.discount_paise)}` : formatMoney(0)}</strong>
                </div>
                <div className="summary-row">
                  <span>Tax</span>
                  <strong>{formatMoney(quote.tax_paise)}</strong>
                </div>
                <div className="summary-row">
                  <span>Shipping</span>
                  <strong>{quote.shipping_paise > 0 ? formatMoney(quote.shipping_paise) : "Free"}</strong>
                </div>
                <div className="summary-total">
                  <span>Pay on delivery</span>
                  <span className="amount">{formatMoney(quote.total_paise)}</span>
                </div>
              </>
            ) : (
              <div className="stack-sm">
                <div className="skeleton skeleton-line" />
                <div className="skeleton skeleton-line short" />
                <div className="skeleton skeleton-line" />
              </div>
            )}

            <div className="cod-note">
              <ShieldIcon size={17} />
              <span>Inspect the sealed parcel, pay the exact amount above, then share your delivery OTP with the assigned person.</span>
            </div>

            <label className="checkbox-row" style={{ marginTop: 15 }}>
              <input type="checkbox" checked={consent} onChange={(event) => setConsent(event.target.checked)} />
              I will pay this exact cash amount on delivery.
            </label>

            {placeError && <div className="alert error" style={{ marginTop: 12 }}>{placeError}</div>}

            <button
              type="button"
              className="btn btn-primary btn-block"
              style={{ marginTop: 14 }}
              onClick={placeOrder}
              disabled={placing || !quote || !consent || Boolean(quoteError) || quote?.items.some((item) => !item.is_available)}
            >
              {placing ? <span className="spinner" /> : <LockIcon size={17} />}
              {placing ? "Placing order…" : "Place COD order"}
            </button>

            <div className="row" style={{ marginTop: 12, color: "var(--muted)", fontSize: "0.75rem" }}>
              <CheckIcon size={14} /> No payment now
              <CheckIcon size={14} /> OTP-verified handover
            </div>
          </aside>
        </div>
      </div>
    </div>
  );
}
