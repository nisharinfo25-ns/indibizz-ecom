import assert from "node:assert/strict";
import test from "node:test";
import type { CatalogProduct } from "@indibizz/shared";
import { categoriesFromProducts, filterCatalog, safeNextPath } from "../lib/catalog";

function product(overrides: Partial<CatalogProduct> & Pick<CatalogProduct, "id" | "name">): CatalogProduct {
  return {
    slug: overrides.name.toLowerCase().replace(/\s+/g, "-"),
    description: null,
    category_id: "cat-1",
    category_name: "Kitchen",
    category_slug: "kitchen",
    sku: "SKU-1",
    price_paise: 10000,
    compare_at_price_paise: null,
    tax_rate_bps: 500,
    hsn_code: null,
    weight_grams: 500,
    is_featured: false,
    available_quantity: 5,
    in_stock: true,
    primary_image_path: null,
    created_at: "2026-01-01T00:00:00Z",
    ...overrides,
  };
}

const products: CatalogProduct[] = [
  product({ id: "p1", name: "Steel Tumbler", sku: "TUM-1", price_paise: 25000, is_featured: true }),
  product({
    id: "p2",
    name: "Copper Bottle",
    sku: "BOT-2",
    price_paise: 79900,
    category_id: "cat-2",
    category_name: "Drinkware",
    category_slug: "drinkware",
    in_stock: false,
    created_at: "2026-02-01T00:00:00Z",
  }),
  product({
    id: "p3",
    name: "Masala Box",
    sku: "BOX-3",
    price_paise: 45000,
    category_id: "cat-2",
    category_name: "Drinkware",
    category_slug: "drinkware",
    created_at: "2025-12-01T00:00:00Z",
  }),
];

test("categoriesFromProducts groups and counts by category", () => {
  const categories = categoriesFromProducts(products);
  assert.deepEqual(
    categories.map((c) => [c.slug, c.product_count]),
    [
      ["drinkware", 2],
      ["kitchen", 1],
    ],
  );
  const first = categories[0];
  assert.ok(first);
  assert.equal(first.name, "Drinkware");
  assert.equal(first.description, null);
});

test("categoriesFromProducts is stable for an empty catalogue", () => {
  assert.deepEqual(categoriesFromProducts([]), []);
});

test("filterCatalog matches name, SKU and category case-insensitively", () => {
  assert.deepEqual(filterCatalog(products, { search: "copper" }).map((p) => p.id), ["p2"]);
  assert.deepEqual(filterCatalog(products, { search: "box-3" }).map((p) => p.id), ["p3"]);
  assert.deepEqual(filterCatalog(products, { search: "kitchen" }).map((p) => p.id), ["p1"]);
  assert.deepEqual(filterCatalog(products, { search: "  " }).map((p) => p.id), ["p1", "p3", "p2"]);
});

test("filterCatalog filters by category and stock", () => {
  assert.deepEqual(filterCatalog(products, { category: "drinkware" }).map((p) => p.id), ["p3", "p2"]);
  assert.deepEqual(filterCatalog(products, { inStockOnly: true }).map((p) => p.id), ["p1", "p3"]);
  assert.deepEqual(
    filterCatalog(products, { category: "drinkware", inStockOnly: true }).map((p) => p.id),
    ["p3"],
  );
});

test("filterCatalog sorts without mutating the source", () => {
  const snapshot = products.map((p) => p.id);
  assert.deepEqual(filterCatalog(products, { sort: "price_asc" }).map((p) => p.id), ["p1", "p3", "p2"]);
  assert.deepEqual(filterCatalog(products, { sort: "price_desc" }).map((p) => p.id), ["p2", "p3", "p1"]);
  assert.deepEqual(filterCatalog(products, { sort: "newest" }).map((p) => p.id), ["p2", "p1", "p3"]);
  assert.deepEqual(products.map((p) => p.id), snapshot);
});

test("featured sort puts featured and in-stock products first", () => {
  assert.deepEqual(filterCatalog(products, {}).map((p) => p.id), ["p1", "p3", "p2"]);
});

test("safeNextPath only allows same-site absolute paths", () => {
  assert.equal(safeNextPath("/orders/123"), "/orders/123");
  assert.equal(safeNextPath("/shop?category=kitchen"), "/shop?category=kitchen");
  assert.equal(safeNextPath(null), "/account");
  assert.equal(safeNextPath(undefined), "/account");
  assert.equal(safeNextPath(""), "/account");
  assert.equal(safeNextPath("//evil.example"), "/account");
  assert.equal(safeNextPath("https://evil.example"), "/account");
  assert.equal(safeNextPath("orders"), "/account");
});
