"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { errorMessage, type CatalogProduct } from "@indibizz/shared";
import { fetchCatalog } from "@/lib/api";
import { categoriesFromProducts, filterCatalog, type CatalogSort } from "@/lib/catalog";
import { ProductCard } from "@/components/product-card";
import { EmptyState, ErrorPanel, LoadingBlock, LoadingGrid, PageHead } from "@/components/ui";
import { SearchIcon } from "@/components/icons";

type Sort = CatalogSort;

function ShopContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [products, setProducts] = useState<CatalogProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState(searchParams.get("category") ?? "");
  const [sort, setSort] = useState<Sort>("featured");
  const [inStockOnly, setInStockOnly] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setProducts(await fetchCatalog());
    } catch (caught) {
      setError(errorMessage(caught, "The catalogue could not be loaded."));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    setCategory(searchParams.get("category") ?? "");
  }, [searchParams]);

  const categories = useMemo(() => categoriesFromProducts(products), [products]);

  const filtered = useMemo(
    () => filterCatalog(products, { search, category, inStockOnly, sort }),
    [products, category, inStockOnly, search, sort],
  );

  function chooseCategory(slug: string) {
    setCategory(slug);
    router.replace(slug ? `/shop?category=${encodeURIComponent(slug)}` : "/shop", { scroll: false });
  }

  return (
    <div className="container">
      <PageHead
        eyebrow="Shop"
        title="Everything ready for COD"
        description="Live prices, real stock and sealed-package delivery. Only active products are shown."
      />

      <div className="chip-row" style={{ marginBottom: 14 }}>
        <button type="button" className={`chip ${!category ? "active" : ""}`} onClick={() => chooseCategory("")}>
          All products
        </button>
        {categories.map((item) => (
          <button
            key={item.id}
            type="button"
            className={`chip ${category === item.slug ? "active" : ""}`}
            onClick={() => chooseCategory(item.slug)}
          >
            {item.name} <span className="muted">{item.product_count}</span>
          </button>
        ))}
        <button
          type="button"
          className={`chip ${inStockOnly ? "active" : ""}`}
          onClick={() => setInStockOnly((value) => !value)}
          aria-pressed={inStockOnly}
        >
          In stock only
        </button>
      </div>

      <div className="catalog-toolbar">
        <div className="search">
          <SearchIcon size={18} />
          <input
            className="input"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search products, SKU or category"
            aria-label="Search products"
          />
        </div>
        <select className="select" value={sort} onChange={(event) => setSort(event.target.value as Sort)} aria-label="Sort products">
          <option value="featured">Featured first</option>
          <option value="newest">Newest</option>
          <option value="price_asc">Price: low to high</option>
          <option value="price_desc">Price: high to low</option>
        </select>
        <span className="muted small" style={{ alignSelf: "center", whiteSpace: "nowrap" }}>
          {loading ? "Loading…" : `${filtered.length} ${filtered.length === 1 ? "product" : "products"}`}
        </span>
      </div>

      {error ? (
        <ErrorPanel message={error} retry={load} />
      ) : loading ? (
        <LoadingGrid count={8} />
      ) : filtered.length === 0 ? (
        products.length === 0 ? (
          <EmptyState
            title="No active products yet"
            description="The seller has not published an active catalogue. This page never fills the gap with sample products."
            action={<button className="btn btn-outline btn-sm" onClick={load}>Refresh catalogue</button>}
          />
        ) : (
          <EmptyState
            title="No products match these filters"
            description="Try a different search, category or clear the in-stock filter."
            action={
              <button
                type="button"
                className="btn btn-outline btn-sm"
                onClick={() => {
                  setSearch("");
                  setInStockOnly(false);
                  chooseCategory("");
                }}
              >
                Clear filters
              </button>
            }
          />
        )
      ) : (
        <div className="product-grid">
          {filtered.map((product) => (
            <ProductCard key={product.id} product={product} />
          ))}
        </div>
      )}
    </div>
  );
}

export default function ShopPage() {
  return (
    <div className="page">
      <Suspense fallback={<div className="container"><LoadingBlock label="Loading the catalogue…" /></div>}>
        <ShopContent />
      </Suspense>
    </div>
  );
}
