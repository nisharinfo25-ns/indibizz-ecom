"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import {
  errorMessage,
  formatMoney,
  orderStatusLabel,
  orderStatusTone,
  type CatalogProduct,
  type OrderStatus,
} from "@indibizz/shared";
import { rpc } from "@/lib/api";
import { useAuth, useCart, useToast } from "./providers";
import { ProductImage } from "./product-image";
import { PlusIcon } from "./icons";

export function ProductCard({ product }: { product: CatalogProduct }) {
  const { user } = useAuth();
  const { refresh } = useCart();
  const { showToast } = useToast();
  const router = useRouter();
  const [adding, setAdding] = useState(false);

  const discount =
    product.compare_at_price_paise && product.compare_at_price_paise > product.price_paise
      ? Math.round(((product.compare_at_price_paise - product.price_paise) / product.compare_at_price_paise) * 100)
      : 0;

  async function quickAdd() {
    if (!user) {
      router.push(`/login?next=${encodeURIComponent(`/product/${product.slug}`)}`);
      return;
    }
    setAdding(true);
    try {
      await rpc("cart_add_item", { p_product_id: product.id, p_quantity: 1 });
      await refresh();
      showToast(`${product.name} added to your cart.`, "success");
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      setAdding(false);
    }
  }

  return (
    <article className="product-card">
      <Link href={`/product/${product.slug}`} className="product-media" aria-label={product.name}>
        <ProductImage path={product.primary_image_path} alt={product.name} fallbackName={product.name} />
      </Link>
      <div className="product-body">
        <span className="product-cat">{product.category_name}</span>
        <Link href={`/product/${product.slug}`} className="product-name">
          {product.name}
        </Link>
        <div className="product-meta">
          <div>
            <span className="product-price">{formatMoney(product.price_paise)}</span>
            {discount > 0 && product.compare_at_price_paise && (
              <span className="compare" style={{ marginLeft: 7 }}>
                {formatMoney(product.compare_at_price_paise)}
              </span>
            )}
          </div>
          <span className={`stock-pill ${!product.in_stock ? "out" : product.available_quantity <= 5 ? "low" : ""}`}>
            {!product.in_stock ? "Sold out" : product.available_quantity <= 5 ? "Low stock" : "In stock"}
          </span>
        </div>
      </div>
      {product.in_stock && (
        <button
          type="button"
          className="quick-add"
          onClick={quickAdd}
          disabled={adding}
          aria-label={`Add ${product.name} to cart`}
          title="Add to cart"
        >
          {adding ? <span className="spinner" /> : <PlusIcon size={18} />}
        </button>
      )}
    </article>
  );
}

export function StatusBadge({ status }: { status: OrderStatus | string }) {
  return <span className={`badge ${orderStatusTone(status)}`}>{orderStatusLabel(status)}</span>;
}
