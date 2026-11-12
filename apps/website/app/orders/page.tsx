"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  errorMessage,
  formatDate,
  formatMoney,
  isOrderTerminal,
  pluralize,
  type OrderSummary,
} from "@indibizz/shared";
import { listOrders } from "@/lib/api";
import { useAuth } from "@/components/providers";
import { StatusBadge } from "@/components/product-card";
import { EmptyState, ErrorPanel, LoadingBlock, PageHead } from "@/components/ui";
import { ArrowRightIcon, PackageIcon } from "@/components/icons";

type Filter = "all" | "active" | "delivered" | "closed";

export default function OrdersPage() {
  const { user, loading: authLoading } = useAuth();
  const [orders, setOrders] = useState<OrderSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>("all");

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setOrders(await listOrders());
    } catch (caught) {
      setError(errorMessage(caught, "Your orders could not be loaded."));
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

  const filtered = useMemo(() => {
    switch (filter) {
      case "active":
        return orders.filter((order) => !isOrderTerminal(order.status) && order.status !== "DELIVERY_FAILED");
      case "delivered":
        return orders.filter((order) => order.status === "DELIVERED" || order.status === "CLOSED");
      case "closed":
        return orders.filter((order) => ["CANCELLED", "REJECTED", "RETURNED", "RETURN_REQUESTED"].includes(order.status));
      default:
        return orders;
    }
  }, [orders, filter]);

  if (authLoading) return <div className="page"><div className="container"><LoadingBlock /></div></div>;

  if (!user) {
    return (
      <div className="page">
        <div className="container">
          <EmptyState
            title="Sign in to see your orders"
            description="Orders are tied to your verified phone number. Sign in with a one-time code to view the live status and delivery OTP."
            action={<Link href="/login?next=/orders" className="btn btn-primary btn-sm">Sign in with phone</Link>}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      <div className="container">
        <PageHead
          eyebrow="Orders"
          title="Your orders"
          description="Every order below is real: live status, recorded events and the exact COD amount."
          action={<Link href="/shop" className="btn btn-outline btn-sm">Shop again</Link>}
        />

        <div className="filter-tabs" role="tablist" aria-label="Filter orders">
          {([
            ["all", "All"],
            ["active", "In progress"],
            ["delivered", "Delivered"],
            ["closed", "Cancelled / returned"],
          ] as Array<[Filter, string]>).map(([value, label]) => (
            <button
              key={value}
              type="button"
              role="tab"
              aria-selected={filter === value}
              className={`filter-tab ${filter === value ? "active" : ""}`}
              onClick={() => setFilter(value)}
            >
              {label}
            </button>
          ))}
        </div>

        {error ? (
          <ErrorPanel message={error} retry={load} />
        ) : loading ? (
          <div className="stack">
            {Array.from({ length: 3 }, (_, index) => (
              <div key={index} className="card card-pad">
                <div className="skeleton skeleton-line short" />
                <div className="skeleton skeleton-line" />
                <div className="skeleton skeleton-line short" />
              </div>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<PackageIcon size={26} />}
            title={orders.length === 0 ? "No orders yet" : "No orders in this view"}
            description={
              orders.length === 0
                ? "Place your first cash-on-delivery order and it will appear here with its full status trail."
                : "Choose another filter to see the rest of your orders."
            }
            action={orders.length === 0 ? <Link href="/shop" className="btn btn-primary btn-sm">Browse products</Link> : undefined}
          />
        ) : (
          <div className="order-list">
            {filtered.map((order) => (
              <article key={order.id} className="card order-card">
                <div className="order-head">
                  <div>
                    <div className="order-number">{order.order_number}</div>
                    <div className="order-date">Placed {formatDate(order.created_at, { hour: "2-digit", minute: "2-digit" })}</div>
                  </div>
                  <StatusBadge status={order.status} />
                </div>

                <div className="order-body">
                  <div className="order-meta">
                    <div>
                      <span className="meta-label">Items</span>
                      <span className="meta-value">
                        {order.first_item_name ?? `${order.item_count} ${pluralize(order.item_count, "item")}`}
                        {order.item_count > 1 ? ` +${order.item_count - 1}` : ""}
                      </span>
                    </div>
                    <div>
                      <span className="meta-label">COD amount</span>
                      <span className="meta-value">{formatMoney(order.cod_amount_paise)}</span>
                    </div>
                    <div>
                      <span className="meta-label">Deliver to</span>
                      <span className="meta-value">{order.town_name} — {order.pincode}</span>
                    </div>
                    {order.invoice_number && (
                      <div>
                        <span className="meta-label">Invoice</span>
                        <span className="meta-value">{order.invoice_number}</span>
                      </div>
                    )}
                  </div>

                  <div className="order-actions">
                    {order.shipment_status && <span className="muted small">{order.shipment_status.replaceAll("_", " ").toLowerCase()}</span>}
                    <Link href={`/orders/${order.id}`} className="btn btn-outline btn-sm">
                      View order <ArrowRightIcon size={15} />
                    </Link>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
