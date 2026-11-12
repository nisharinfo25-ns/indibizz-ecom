"use client";

import Link from "next/link";
import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import {
  ORDER_FLOW,
  canCancelOrder,
  canRequestReturn,
  errorMessage,
  formatDate,
  formatDateTime,
  formatMoney,
  hasErrors,
  isFailureStatus,
  orderNextAction,
  orderProgress,
  orderStageIndex,
  orderStatusLabel,
  paymentStatusLabel,
  returnStatusLabel,
  validateReturn,
  type FieldErrors,
  type OrderDetail,
  type Tracking,
} from "@indibizz/shared";
import {
  getOrder,
  getTracking,
  rpc,
  signedInvoiceUrl,
  uploadReturnEvidence,
} from "@/lib/api";
import { useAuth, useToast } from "@/components/providers";
import { ProductImage } from "@/components/product-image";
import { StatusBadge } from "@/components/product-card";
import { EmptyState, ErrorPanel, LoadingBlock } from "@/components/ui";
import {
  AlertIcon,
  ArrowRightIcon,
  CheckIcon,
  CopyIcon,
  DownloadIcon,
  LockIcon,
  PackageIcon,
  ShieldIcon,
} from "@/components/icons";

function OrderDetailContent() {
  const params = useParams<{ id: string }>();
  const id = params?.id ?? "";
  const searchParams = useSearchParams();
  const placed = searchParams.get("placed") === "1";
  const { user, loading: authLoading } = useAuth();
  const { showToast } = useToast();

  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [tracking, setTracking] = useState<Tracking | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);

  const [cancelOpen, setCancelOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const [cancelling, setCancelling] = useState(false);

  const [returnReason, setReturnReason] = useState("Damaged on arrival");
  const [returnDescription, setReturnDescription] = useState("");
  const [returnFile, setReturnFile] = useState<File | null>(null);
  const [returnErrors, setReturnErrors] = useState<FieldErrors>({});
  const [returning, setReturning] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const load = useCallback(async () => {
    if (!id) return;
    setLoading(true);
    setError(null);
    try {
      const [orderResult, trackingResult] = await Promise.all([getOrder(id), getTracking(id)]);
      setOrder(orderResult);
      setTracking(trackingResult);
    } catch (caught) {
      setError(errorMessage(caught, "This order could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (authLoading) return;
    if (!user) {
      setLoading(false);
      return;
    }
    void load();
  }, [authLoading, load, user]);

  const stageIndex = order ? orderStageIndex(order.status) : 0;
  const failure = order ? isFailureStatus(order.status) : false;

  const stageTimes = useMemo(() => {
    if (!order) return [] as Array<string | null>;
    const events = tracking?.events ?? [];
    const timeFor = (...statuses: string[]) => {
      const event = events.find((item) => statuses.includes(item.new_status));
      return event?.created_at ?? null;
    };
    return [
      order.created_at,
      order.approved_at,
      timeFor("READY_FOR_PICKUP", "PICKUP_REQUESTED", "PICKUP_ASSIGNED"),
      order.shipment?.picked_up_at ?? timeFor("PICKED_UP"),
      timeFor("IN_TRANSIT"),
      timeFor("OUT_FOR_DELIVERY"),
      order.delivered_at ?? timeFor("DELIVERED"),
    ];
  }, [order, tracking]);

  async function copyOtp() {
    if (!tracking?.delivery_otp) return;
    try {
      await navigator.clipboard.writeText(tracking.delivery_otp);
      showToast("Delivery OTP copied.", "success");
    } catch {
      showToast("Could not copy. Select the digits manually.", "error");
    }
  }

  async function downloadInvoice() {
    const path = order?.invoice?.pdf_storage_path;
    if (!path) {
      showToast("The seller has not generated the invoice PDF yet.", "error");
      return;
    }
    setDownloading(true);
    try {
      const url = await signedInvoiceUrl(path);
      if (!url) throw new Error("The invoice file is not available. Ask the seller to regenerate it.");
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.target = "_blank";
      anchor.rel = "noopener noreferrer";
      document.body.appendChild(anchor);
      anchor.click();
      anchor.remove();
    } catch (caught) {
      showToast(errorMessage(caught), "error");
    } finally {
      setDownloading(false);
    }
  }

  async function cancelOrder() {
    if (!order) return;
    if (cancelReason.trim().length < 3) {
      setActionError("Enter a cancellation reason of at least 3 characters.");
      return;
    }
    if (!window.confirm("Cancel this order? Reserved stock will be released.")) return;
    setCancelling(true);
    setActionError(null);
    try {
      await rpc("cancel_order", { p_order_id: order.id, p_reason: cancelReason.trim() });
      showToast("Order cancelled. Reserved stock was released.", "success");
      setCancelOpen(false);
      setCancelReason("");
      await load();
    } catch (caught) {
      setActionError(errorMessage(caught));
    } finally {
      setCancelling(false);
    }
  }

  async function submitReturn(event: React.FormEvent) {
    event.preventDefault();
    if (!order) return;
    const errors = validateReturn(returnReason, returnDescription);
    if (returnFile && returnFile.size > 10 * 1024 * 1024) {
      errors.file = "Evidence must be 10 MB or smaller.";
    }
    setReturnErrors(errors);
    if (hasErrors(errors)) return;

    setReturning(true);
    setActionError(null);
    try {
      let evidencePath: string | null = null;
      if (returnFile) evidencePath = await uploadReturnEvidence(order.id, returnFile);
      await rpc("request_return", {
        p_order_id: order.id,
        p_reason: returnReason,
        p_description: returnDescription.trim() || null,
        p_evidence_path: evidencePath,
      });
      showToast("Return request submitted. The seller will review it.", "success");
      setReturnFile(null);
      setReturnDescription("");
      await load();
    } catch (caught) {
      setActionError(errorMessage(caught));
    } finally {
      setReturning(false);
    }
  }

  if (authLoading) return <div className="page"><div className="container"><LoadingBlock /></div></div>;

  if (!user) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Sign in to view this order"
            description="Order details and the delivery OTP are only available to the verified customer who placed the order."
            action={<Link href={`/login?next=${encodeURIComponent(`/orders/${id}`)}`} className="btn btn-primary btn-sm">Sign in with phone</Link>}
          />
        </div>
      </div>
    );
  }

  if (loading) return <div className="page"><div className="container"><LoadingBlock label="Loading order…" /></div></div>;

  if (error) {
    return <div className="page"><div className="container"><ErrorPanel message={error} retry={load} /></div></div>;
  }

  if (!order) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Order not found"
            description="This order does not exist or does not belong to your account."
            action={<Link href="/orders" className="btn btn-primary btn-sm">Back to orders</Link>}
          />
        </div>
      </div>
    );
  }

  const risk = failure || order.status === "DELIVERY_FAILED";

  return (
    <div className="page">
      <div className="container">
        <nav className="breadcrumbs" aria-label="Breadcrumb">
          <Link href="/">Home</Link>
          <span>/</span>
          <Link href="/orders">Orders</Link>
          <span>/</span>
          <span className="muted">{order.order_number}</span>
        </nav>

        {placed && order.status === "PENDING_APPROVAL" && (
          <div className="alert success" style={{ marginBottom: 18 }} role="status">
            <CheckIcon size={18} />
            <div>
              <strong>Order placed successfully.</strong> No cash was charged. The seller will confirm stock and prepare your parcel.
            </div>
          </div>
        )}

        {actionError && <div style={{ marginBottom: 16 }}><ErrorPanel message={actionError} /></div>}

        <div className="detail-grid">
          <div className="detail-stack">
            <section className="panel">
              <div className="order-summary-head">
                <div>
                  <div className="eyebrow" style={{ marginBottom: 6 }}>Order</div>
                  <h1 style={{ fontSize: "clamp(1.5rem, 3vw, 2rem)" }}>{order.order_number}</h1>
                  <p className="muted small" style={{ marginTop: 5 }}>Placed {formatDateTime(order.created_at)}</p>
                </div>
                <div className="stack-sm" style={{ alignItems: "flex-end" }}>
                  <StatusBadge status={order.status} />
                  <span className="muted small">{orderNextAction(order.status)}</span>
                </div>
              </div>

              <div className="card-pad stack">
                <div>
                  <div className="spread" style={{ marginBottom: 7 }}>
                    <span className="muted small">Delivery progress</span>
                    <span className="small" style={{ fontWeight: 750 }}>{orderProgress(order.status)}%</span>
                  </div>
                  <div className="progress-track">
                    <div className="progress-fill" style={{ width: `${orderProgress(order.status)}%` }} />
                  </div>
                </div>

                {risk && (
                  <div className="alert error">
                    <AlertIcon size={18} />
                    <div>
                      <strong>{orderStatusLabel(order.status)}</strong>
                      <p style={{ marginTop: 3 }}>
                        {order.rejected_reason || orderNextAction(order.status)}
                      </p>
                    </div>
                  </div>
                )}

                <div className="timeline">
                  {ORDER_FLOW.map((stage, index) => {
                    const done = index <= stageIndex && !(failure && index > stageIndex);
                    const current = index === stageIndex && !failure;
                    return (
                      <div key={stage.key} className={`timeline-step ${done ? "done" : ""} ${current ? "current" : ""}`}>
                        <span className="timeline-dot">{done ? <CheckIcon size={13} /> : index + 1}</span>
                        <div>
                          <div className="timeline-title">{stage.label}</div>
                          <div className="timeline-desc">{stage.description}</div>
                          {stageTimes[index] && <div className="timeline-time">{formatDateTime(stageTimes[index])}</div>}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </section>

            <section className="card card-pad">
              <div className="spread" style={{ marginBottom: 8 }}>
                <h2 style={{ fontSize: "1.08rem" }}>Items</h2>
                <span className="muted small">{order.item_count} {order.item_count === 1 ? "item" : "items"}</span>
              </div>
              {order.items.map((item, index) => (
                <div className="item-row" key={`${item.sku}-${index}`}>
                  <div>
                    <div className="item-name">{item.product_name}</div>
                    <div className="item-sub">
                      {item.quantity} × {formatMoney(item.unit_price_paise)} · SKU {item.sku}
                      {item.tax_paise > 0 ? ` · tax ${formatMoney(item.tax_paise)}` : ""}
                    </div>
                  </div>
                  <strong>{formatMoney(item.line_total_paise)}</strong>
                </div>
              ))}
              <div style={{ marginTop: 12 }}>
                <div className="summary-row"><span>Subtotal</span><strong>{formatMoney(order.subtotal_paise)}</strong></div>
                <div className="summary-row"><span>Discount</span><strong>{order.discount_paise > 0 ? `− ${formatMoney(order.discount_paise)}` : formatMoney(0)}</strong></div>
                <div className="summary-row"><span>Tax</span><strong>{formatMoney(order.tax_paise)}</strong></div>
                <div className="summary-row"><span>Shipping</span><strong>{order.shipping_paise > 0 ? formatMoney(order.shipping_paise) : "Free"}</strong></div>
                <div className="summary-total"><span>Total (COD)</span><span className="amount">{formatMoney(order.total_paise)}</span></div>
              </div>
            </section>

            <section className="card card-pad">
              <h2 style={{ fontSize: "1.08rem", marginBottom: 10 }}>Delivery address</h2>
              <p style={{ fontWeight: 700 }}>{order.recipient_name} · {order.phone}</p>
              <p className="muted" style={{ marginTop: 4 }}>
                {[order.line1, order.line2, order.landmark].filter(Boolean).join(", ")}
                <br />
                {order.town_name}, {order.district}, {order.state} — {order.pincode}
              </p>
              {order.customer_note && (
                <div className="alert" style={{ marginTop: 12 }}>
                  <PackageIcon size={17} />
                  <span><strong>Order note:</strong> {order.customer_note}</span>
                </div>
              )}
            </section>

            <section className="card card-pad">
              <div className="spread" style={{ marginBottom: 10 }}>
                <h2 style={{ fontSize: "1.08rem" }}>Recorded events</h2>
                <span className="muted small">Real logistics trail</span>
              </div>
              {tracking?.events && tracking.events.length > 0 ? (
                <div className="stack-sm">
                  {tracking.events.map((event) => (
                    <div key={event.id} className="item-row">
                      <div>
                        <div className="item-name">{event.new_status.replaceAll("_", " ")}</div>
                        <div className="item-sub">
                          {[event.location_text, event.notes].filter(Boolean).join(" · ") || event.source}
                        </div>
                      </div>
                      <span className="muted small" style={{ whiteSpace: "nowrap" }}>{formatDateTime(event.created_at)}</span>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="muted small">
                  No shipment event has been recorded yet. Events appear after the seller packs the parcel and requests pickup.
                </p>
              )}
              {tracking?.packages && tracking.packages.length > 0 && (
                <div className="alert" style={{ marginTop: 12 }}>
                  <PackageIcon size={17} />
                  <span>{tracking.packages.length} sealed {tracking.packages.length === 1 ? "package" : "packages"} recorded for this shipment.</span>
                </div>
              )}
            </section>

            {order.return_request && (
              <section className="card card-pad">
                <div className="spread" style={{ marginBottom: 8 }}>
                  <h2 style={{ fontSize: "1.08rem" }}>Return request</h2>
                  <span className="badge pending">{returnStatusLabel(order.return_request.status)}</span>
                </div>
                <div className="kv-list">
                  <div className="kv"><dt>Return number</dt><dd>{order.return_request.return_number}</dd></div>
                  <div className="kv"><dt>Reason</dt><dd>{order.return_request.reason}</dd></div>
                  <div className="kv"><dt>Requested</dt><dd>{formatDateTime(order.return_request.created_at)}</dd></div>
                  {order.return_request.rejection_reason && <div className="kv"><dt>Seller note</dt><dd>{order.return_request.rejection_reason}</dd></div>}
                  {order.return_request.resolution_note && <div className="kv"><dt>Resolution</dt><dd>{order.return_request.resolution_note}</dd></div>}
                </div>
              </section>
            )}

            {order.status === "DELIVERED" && !order.return_request && (
              <section className="return-box">
                <div className="spread">
                  <div>
                    <h2 style={{ fontSize: "1.05rem" }}>Need to return something?</h2>
                    <p className="muted small" style={{ marginTop: 3 }}>Returns are reviewed by the seller and must be within the published window.</p>
                  </div>
                  <ShieldIcon size={22} />
                </div>
                <form onSubmit={submitReturn} className="stack-sm">
                  <div className={`field ${returnErrors.reason ? "invalid" : ""}`}>
                    <label className="label" htmlFor="return-reason">Reason</label>
                    <select id="return-reason" className="select" value={returnReason} onChange={(event) => setReturnReason(event.target.value)}>
                      {["Damaged on arrival", "Wrong item delivered", "Item missing from parcel", "Quality not as expected", "Other"].map((reason) => (
                        <option key={reason} value={reason}>{reason}</option>
                      ))}
                    </select>
                    {returnErrors.reason && <span className="error-text">{returnErrors.reason}</span>}
                  </div>
                  <div className={`field ${returnErrors.description ? "invalid" : ""}`}>
                    <label className="label" htmlFor="return-description">Description</label>
                    <textarea
                      id="return-description"
                      className="textarea"
                      value={returnDescription}
                      onChange={(event) => setReturnDescription(event.target.value.slice(0, 2000))}
                      placeholder="Describe the issue. Do not include payment details."
                    />
                    {returnErrors.description && <span className="error-text">{returnErrors.description}</span>}
                  </div>
                  <div className="field">
                    <label className="label" htmlFor="return-file">Photo or PDF evidence <span className="muted">(optional, max 10 MB)</span></label>
                    <input
                      id="return-file"
                      className="input"
                      type="file"
                      accept="image/jpeg,image/png,image/webp,application/pdf"
                      onChange={(event) => setReturnFile(event.target.files?.[0] ?? null)}
                    />
                    {returnErrors.file && <span className="error-text">{returnErrors.file}</span>}
                  </div>
                  <button type="submit" className="btn btn-outline" disabled={returning}>
                    {returning ? <span className="spinner" /> : null}
                    {returning ? "Submitting…" : "Request return"}
                  </button>
                </form>
              </section>
            )}

            {canCancelOrder(order.status) && (
              <section className="card card-pad">
                <div className="spread">
                  <div>
                    <h2 style={{ fontSize: "1.05rem" }}>Cancel this order</h2>
                    <p className="muted small" style={{ marginTop: 3 }}>Cancellation is only possible before pickup. Reserved stock is released immediately.</p>
                  </div>
                  {!cancelOpen && <button type="button" className="btn btn-danger btn-sm" onClick={() => setCancelOpen(true)}>Cancel order</button>}
                </div>
                {cancelOpen && (
                  <div className="stack-sm" style={{ marginTop: 12 }}>
                    <textarea
                      className="textarea"
                      value={cancelReason}
                      onChange={(event) => setCancelReason(event.target.value.slice(0, 500))}
                      placeholder="Tell the seller why you need to cancel."
                      maxLength={500}
                    />
                    <div className="row">
                      <button type="button" className="btn btn-danger" onClick={cancelOrder} disabled={cancelling}>
                        {cancelling ? <span className="spinner" /> : null}
                        {cancelling ? "Cancelling…" : "Confirm cancellation"}
                      </button>
                      <button type="button" className="btn btn-ghost" onClick={() => setCancelOpen(false)} disabled={cancelling}>Keep order</button>
                    </div>
                  </div>
                )}
              </section>
            )}
          </div>

          <aside className="detail-stack" style={{ position: "sticky", top: "calc(var(--header-height) + 24px)" }}>
            {order.status === "OUT_FOR_DELIVERY" && tracking?.delivery_otp && (
              <div className="otp-card">
                <div className="row" style={{ gap: 7 }}>
                  <LockIcon size={16} />
                  <h3>Delivery OTP</h3>
                </div>
                <p>Share this code only after checking the parcel and paying {formatMoney(order.cod_amount_paise)} in cash.</p>
                <div className="otp-digits" aria-label={`Delivery OTP ${tracking.delivery_otp}`}>
                  {tracking.delivery_otp.split("").map((digit, index) => (
                    <span className="otp-digit" key={`${digit}-${index}`}>{digit}</span>
                  ))}
                </div>
                <button type="button" className="btn btn-sm" onClick={copyOtp}>
                  <CopyIcon size={15} /> Copy OTP
                </button>
              </div>
            )}

            {order.status === "OUT_FOR_DELIVERY" && !tracking?.delivery_otp && (
              <div className="alert warning">
                <LockIcon size={17} />
                <span>{tracking?.otp_notice || "Your delivery OTP will appear here when the parcel is out for delivery."}</span>
              </div>
            )}

            <section className="card card-pad">
              <h2 style={{ fontSize: "1.02rem", marginBottom: 12 }}>Payment</h2>
              <div className="kv-list">
                <div className="kv"><dt>Method</dt><dd>Cash on delivery</dd></div>
                <div className="kv"><dt>COD amount</dt><dd>{formatMoney(order.cod_amount_paise)}</dd></div>
                <div className="kv"><dt>Payment status</dt><dd>{paymentStatusLabel(order.payment_status)}</dd></div>
              </div>
              <div className="cod-note">
                <ShieldIcon size={17} />
                <span>Pay the exact amount to the assigned delivery person. Do not transfer money to anyone else.</span>
              </div>
            </section>

            <section className="card card-pad">
              <h2 style={{ fontSize: "1.02rem", marginBottom: 12 }}>Invoice</h2>
              {order.invoice ? (
                <>
                  <div className="kv-list">
                    <div className="kv"><dt>Number</dt><dd>{order.invoice.invoice_number}</dd></div>
                    <div className="kv"><dt>Date</dt><dd>{formatDate(order.invoice.invoice_date)}</dd></div>
                    <div className="kv"><dt>Amount</dt><dd>{formatMoney(order.invoice.total_paise)}</dd></div>
                  </div>
                  <button
                    type="button"
                    className="btn btn-outline btn-block"
                    style={{ marginTop: 12 }}
                    onClick={downloadInvoice}
                    disabled={downloading || !order.invoice.pdf_storage_path}
                  >
                    {downloading ? <span className="spinner" /> : <DownloadIcon size={16} />}
                    {order.invoice.pdf_storage_path ? (downloading ? "Preparing…" : "Download invoice PDF") : "PDF not generated yet"}
                  </button>
                  {!order.invoice.pdf_storage_path && (
                    <p className="help" style={{ marginTop: 7 }}>The seller generates the signed PDF from the seller app.</p>
                  )}
                </>
              ) : (
                <p className="muted small">An invoice is issued when the seller confirms the order.</p>
              )}
            </section>

            <section className="card card-pad">
              <h2 style={{ fontSize: "1.02rem", marginBottom: 8 }}>Shipment</h2>
              {order.shipment ? (
                <div className="kv-list">
                  <div className="kv"><dt>Shipment</dt><dd>{order.shipment.shipment_number}</dd></div>
                  <div className="kv"><dt>Status</dt><dd>{order.shipment.status.replaceAll("_", " ")}</dd></div>
                  <div className="kv"><dt>Packages</dt><dd>{order.shipment.package_count}</dd></div>
                </div>
              ) : (
                <p className="muted small">A shipment is created after the seller confirms the order.</p>
              )}
            </section>

            <Link href="/orders" className="btn btn-ghost btn-block">
              Back to all orders <ArrowRightIcon size={16} />
            </Link>
          </aside>
        </div>
      </div>
    </div>
  );
}

export default function OrderDetailPage() {
  return (
    <Suspense fallback={<div className="page"><div className="container"><LoadingBlock label="Loading order…" /></div></div>}>
      <OrderDetailContent />
    </Suspense>
  );
}
