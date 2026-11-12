import type { CatalogCategory, CatalogProduct } from "@indibizz/shared";

export type CatalogSort = "featured" | "newest" | "price_asc" | "price_desc";

export function categoriesFromProducts(products: CatalogProduct[]): CatalogCategory[] {
  const map = new Map<string, CatalogCategory>();
  for (const product of products) {
    const existing = map.get(product.category_id);
    if (existing) {
      existing.product_count += 1;
    } else {
      map.set(product.category_id, {
        id: product.category_id,
        name: product.category_name,
        slug: product.category_slug,
        description: null,
        product_count: 1,
      });
    }
  }
  return [...map.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function filterCatalog(
  products: CatalogProduct[],
  options: { search?: string; category?: string; inStockOnly?: boolean; sort?: CatalogSort },
): CatalogProduct[] {
  const term = (options.search ?? "").trim().toLowerCase();
  const category = options.category ?? "";
  const list = products.filter((product) => {
    if (category && product.category_slug !== category) return false;
    if (options.inStockOnly && !product.in_stock) return false;
    if (!term) return true;
    return (
      product.name.toLowerCase().includes(term) ||
      product.sku.toLowerCase().includes(term) ||
      product.category_name.toLowerCase().includes(term)
    );
  });
  const sort = options.sort ?? "featured";
  return [...list].sort((a, b) => {
    switch (sort) {
      case "price_asc":
        return a.price_paise - b.price_paise;
      case "price_desc":
        return b.price_paise - a.price_paise;
      case "newest":
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
      default:
        return Number(b.is_featured) - Number(a.is_featured) || Number(b.in_stock) - Number(a.in_stock);
    }
  });
}

export function safeNextPath(value: string | null | undefined): string {
  if (!value || !value.startsWith("/") || value.startsWith("//")) return "/account";
  return value;
}
