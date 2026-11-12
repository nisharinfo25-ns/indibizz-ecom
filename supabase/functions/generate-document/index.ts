// Generates immutable PDF documents for the owner:
//   - invoice          (A4 tax invoice)
//   - shipping_label   (4x6in label per package)
//   - pickup_manifest  (A4 pickup checklist)
//
// Files are written to the private Supabase storage buckets created by the
// migrations. The function returns a short-lived signed URL; no bucket is made
// public. Only an active OWNER may call it.
import { PDFDocument, PDFFont, PDFPage, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";
import bwipjs from "npm:bwip-js@4.7.0";
import QRCode from "npm:qrcode@1.5.4";
import {
  anonKey,
  env,
  errorResponse,
  HttpError,
  json,
  preflight,
  readJson,
  requireUser,
  serviceFetch,
  supabaseUrl,
} from "../_shared/http.ts";

type DocumentType = "invoice" | "shipping_label" | "pickup_manifest";
type Json = Record<string, unknown>;

const NAVY = rgb(0.047, 0.118, 0.227);
const INK = rgb(0.12, 0.15, 0.2);
const MUTED = rgb(0.42, 0.46, 0.52);
const LINE = rgb(0.85, 0.87, 0.9);
const ACCENT = rgb(0.91, 0.55, 0.12);
const WHITE = rgb(1, 1, 1);
const SUCCESS = rgb(0.05, 0.45, 0.32);
const DANGER = rgb(0.72, 0.16, 0.16);

function money(paise: number | null | undefined): string {
  const value = Number(paise ?? 0) / 100;
  return "Rs. " + value.toLocaleString("en-IN", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function dateTime(value: string | null | undefined): string {
  if (!value) return "-";
  return new Date(value).toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function dateOnly(value: string | null | undefined): string {
  if (!value) return "-";
  return new Date(value).toLocaleDateString("en-IN", {
    timeZone: "Asia/Kolkata",
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

/** Standard PDF fonts only support WinAnsi. Replace unsupported glyphs instead
 *  of failing an entire document. Names/addresses are expected in Latin script
 *  or transliteration for labels. */
function safeText(value: unknown): string {
  return String(value ?? "")
    .replace(/₹/g, "Rs.")
    .replace(/[–—]/g, "-")
    .replace(/[‘’]/g, "'")
    .replace(/[“”]/g, '"')
    .replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, "?");
}

function wrap(text: string, font: PDFFont, size: number, maxWidth: number): string[] {
  const words = safeText(text).split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(next, size) <= maxWidth) {
      line = next;
    } else {
      if (line) lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines.length > 0 ? lines : [""];
}

function text(
  page: PDFPage,
  font: PDFFont,
  value: string,
  x: number,
  y: number,
  size: number,
  color = INK,
  maxWidth?: number,
): number {
  const lines = maxWidth ? wrap(value, font, size, maxWidth) : [safeText(value)];
  let cursor = y;
  for (const line of lines) {
    page.drawText(line, { x, y: cursor, size, font, color });
    cursor -= size * 1.35;
  }
  return cursor + size * 1.35;
}

function rule(page: PDFPage, y: number, width: number, margin = 40, color = LINE): void {
  page.drawLine({ start: { x: margin, y }, end: { x: width - margin, y }, thickness: 0.7, color });
}

function labelValue(page: PDFPage, label: string, value: string, x: number, y: number, bold: PDFFont, regular: PDFFont, size = 9): void {
  page.drawText(safeText(label.toUpperCase()), { x, y, size: 7, font: bold, color: MUTED });
  text(page, regular, value, x, y - 13, size, INK, 230);
}

async function barcodePng(value: string): Promise<Uint8Array> {
  const buffer = await bwipjs.toBuffer({
    bcid: "code128",
    text: value,
    scale: 3,
    height: 12,
    includetext: false,
    backgroundcolor: "FFFFFF",
  });
  return new Uint8Array(buffer);
}

async function qrPng(value: string): Promise<Uint8Array> {
  const dataUrl = await QRCode.toDataURL(value, { margin: 1, width: 256, errorCorrectionLevel: "M" });
  const base64 = dataUrl.split(",")[1] ?? "";
  const binary = atob(base64);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function fetchJson(path: string): Promise<unknown> {
  const response = await serviceFetch(path);
  const text = await response.text();
  if (!response.ok) {
    console.error("service query failed", path, response.status, text.slice(0, 400));
    throw new HttpError(502, "database_query_failed", "A required record could not be loaded.");
  }
  return text ? JSON.parse(text) : null;
}

async function assertOwner(req: Request): Promise<{ id: string }> {
  const user = await requireUser(req);
  const rows = (await fetchJson(
    `/rest/v1/profiles?id=eq.${encodeURIComponent(user.id)}&select=id,role,status`,
  )) as Array<{ id: string; role: string; status: string }>;
  const profile = rows[0];
  if (!profile || profile.role !== "OWNER" || profile.status !== "ACTIVE") {
    throw new HttpError(403, "owner_only", "Only the active owner can generate documents.");
  }
  return { id: user.id };
}

function orderAddress(order: Json): string {
  return [
    order.recipient_name,
    order.line1,
    order.line2,
    order.landmark,
    `${order.town_name ?? ""}${order.district ? ", " + order.district : ""}`,
    `${order.state ?? ""} ${order.pincode ?? ""}`.trim(),
    `Phone: ${order.phone ?? ""}`,
  ].filter((line) => String(line ?? "").trim()).join("\n");
}

// ---------------------------------------------------------------------------
// Invoice
// ---------------------------------------------------------------------------
async function buildInvoice(orderId: string, ownerId: string): Promise<{ pdf: Uint8Array; path: string; bucket: string }> {
  const invoices = (await fetchJson(
    `/rest/v1/invoices?order_id=eq.${encodeURIComponent(orderId)}&select=*`,
  )) as Json[];
  const invoice = invoices[0];
  if (!invoice) throw new HttpError(404, "invoice_not_found", "No invoice exists for this order.");
  if (invoice.status === "VOID") throw new HttpError(409, "invoice_void", "This invoice has been voided.");

  const items = (await fetchJson(
    `/rest/v1/order_items?order_id=eq.${encodeURIComponent(orderId)}&select=*&order=created_at`,
  )) as Json[];
  const orders = (await fetchJson(
    `/rest/v1/orders?id=eq.${encodeURIComponent(orderId)}&select=*`,
  )) as Json[];
  const order = orders[0];
  if (!order) throw new HttpError(404, "order_not_found", "Order not found.");

  const pdf = await PDFDocument.create();
  pdf.setTitle(`Invoice ${String(invoice.invoice_number)}`);
  pdf.setAuthor(safeText(invoice.seller_name || "IndiaBizz"));
  pdf.setSubject(`Invoice for order ${String(order.order_number)}`);
  pdf.setCreator("IndiaBizz");
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const width = 595.28;
  const height = 841.89;
  const margin = 42;

  const page = pdf.addPage([width, height]);
  let y = height - 45;

  page.drawRectangle({ x: 0, y: height - 96, width, height: 96, color: NAVY });
  page.drawRectangle({ x: 0, y: height - 101, width, height: 5, color: ACCENT });
  page.drawText("INDIABIZZ", { x: margin, y: height - 52, size: 24, font: bold, color: WHITE });
  page.drawText("TAX INVOICE", { x: margin, y: height - 72, size: 9, font: bold, color: rgb(0.78, 0.82, 0.9) });
  text(page, bold, invoice.seller_name || "IndiaBizz", width - margin - 200, height - 48, 13, WHITE, 200);
  text(page, regular, invoice.seller_gstin ? `GSTIN: ${invoice.seller_gstin}` : "", width - margin - 200, height - 66, 8, rgb(0.78, 0.82, 0.9), 200);
  text(page, regular, invoice.seller_phone || "", width - margin - 200, height - 80, 8, rgb(0.78, 0.82, 0.9), 200);

  y = height - 125;
  labelValue(page, "Invoice number", String(invoice.invoice_number), margin, y, bold, regular, 11);
  labelValue(page, "Invoice date", dateOnly(invoice.invoice_date as string), margin + 190, y, bold, regular, 11);
  labelValue(page, "Order number", String(order.order_number), margin + 350, y, bold, regular, 11);

  y -= 58;
  const barcode = await pdf.embedPng(await barcodePng(String(invoice.invoice_number)));
  page.drawImage(barcode, { x: width - margin - 175, y: y + 34, width: 175, height: 38 });

  page.drawText("BILL TO", { x: margin, y, size: 7, font: bold, color: MUTED });
  text(page, regular, `${invoice.buyer_name}\n${invoice.billing_address}\n${invoice.buyer_phone}`, margin, y - 14, 9, INK, width / 2 - margin - 20);

  page.drawText("SHIP TO", { x: width / 2, y, size: 7, font: bold, color: MUTED });
  text(page, regular, `${invoice.buyer_name}\n${invoice.shipping_address}\n${invoice.buyer_phone}`, width / 2, y - 14, 9, INK, width / 2 - margin - 10);

  y = Math.min(y - 95, height - 300);

  const columns = { item: margin, hsn: 300, qty: 360, rate: 400, tax: 465, amount: width - margin };
  page.drawRectangle({ x: margin, y: y - 2, width: width - margin * 2, height: 20, color: rgb(0.94, 0.96, 0.98) });
  page.drawText("ITEM", { x: columns.item + 4, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("HSN", { x: columns.hsn, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("QTY", { x: columns.qty, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("RATE", { x: columns.rate, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("TAX", { x: columns.tax, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("AMOUNT", { x: columns.amount - 68, y: y + 4, size: 7.5, font: bold, color: NAVY });
  y -= 20;

  let currentPage = page;
  for (const item of items) {
    const nameLines = wrap(String(item.product_name ?? ""), regular, 8.5, columns.hsn - columns.item - 12);
    const rowHeight = Math.max(22, 8.5 * 1.3 * nameLines.length + 8);
    if (y - rowHeight < 150) {
      currentPage = pdf.addPage([width, height]);
      currentPage.drawRectangle({ x: 0, y: height - 45, width, height: 45, color: NAVY });
      currentPage.drawText(`INVOICE ${safeText(invoice.invoice_number)} (continued)`, {
        x: margin, y: height - 30, size: 10, font: bold, color: WHITE,
      });
      y = height - 75;
    }
    let nameY = y;
    for (const line of nameLines) {
      currentPage.drawText(line, { x: columns.item + 4, y: nameY, size: 8.5, font: regular, color: INK });
      nameY -= 11;
    }
    currentPage.drawText(safeText(item.sku ?? ""), { x: columns.item + 4, y: nameY, size: 6.5, font: regular, color: MUTED });
    currentPage.drawText(safeText(item.hsn_code ?? "-"), { x: columns.hsn, y: y, size: 8, font: regular, color: INK });
    currentPage.drawText(String(item.quantity ?? ""), { x: columns.qty, y: y, size: 8, font: regular, color: INK });
    currentPage.drawText(money(Number(item.unit_price_paise)), { x: columns.rate, y: y, size: 8, font: regular, color: INK });
    currentPage.drawText(money(Number(item.tax_paise)), { x: columns.tax, y: y, size: 8, font: regular, color: INK });
    currentPage.drawText(money(Number(item.line_total_paise)), { x: columns.amount - 68, y: y, size: 8, font: regular, color: INK });
    y -= rowHeight;
    rule(currentPage, y + 5, width, margin);
  }

  if (y < 230) {
    currentPage = pdf.addPage([width, height]);
    y = height - 70;
  }

  const totalsX = width - margin - 210;
  y -= 8;
  const totalRows: Array<[string, string, boolean]> = [
    ["Subtotal", money(Number(invoice.subtotal_paise)), false],
    ["Discount", "- " + money(Number(invoice.discount_paise)), false],
    ["Tax", money(Number(invoice.tax_paise)), false],
    ["Shipping", money(Number(invoice.shipping_paise)), false],
    ["Invoice total", money(Number(invoice.total_paise)), true],
    ["Cash on Delivery", money(Number(invoice.cod_amount_paise)), false],
  ];
  for (const [name, value, strong] of totalRows) {
    if (strong) {
      currentPage.drawRectangle({ x: totalsX - 8, y: y - 6, width: 220, height: 24, color: rgb(0.94, 0.96, 0.98) });
    }
    currentPage.drawText(name, { x: totalsX, y, size: strong ? 10 : 8.5, font: strong ? bold : regular, color: strong ? NAVY : INK });
    currentPage.drawText(value, { x: totalsX + 130, y, size: strong ? 10 : 8.5, font: strong ? bold : regular, color: strong ? NAVY : INK });
    y -= strong ? 28 : 17;
  }

  const terms = String(invoice.seller_gstin ? "GSTIN shown above. " : "") +
    "This is a computer-generated invoice. Payment method: Cash on Delivery. " +
    "Please retain this invoice for warranty and returns. Returns are accepted within the configured return window in original condition.";
  const qr = await pdf.embedPng(await qrPng(
    JSON.stringify({ invoice: invoice.invoice_number, order: order.order_number, total: invoice.total_paise }),
  ));
  const qrY = Math.min(y - 50, 190);
  currentPage.drawImage(qr, { x: margin, y: qrY, width: 72, height: 72 });
  text(currentPage, regular, terms, margin + 86, qrY + 64, 7.2, MUTED, width - margin * 2 - 96);

  currentPage.drawText(safeText(invoice.seller_address || ""), { x: margin, y: 46, size: 7, font: regular, color: MUTED });
  currentPage.drawText(
    `Generated ${dateTime(new Date().toISOString())}  |  IndiaBizz`,
    { x: width - margin - 190, y: 46, size: 6.5, font: regular, color: MUTED },
  );

  // Storage policies authorize reads by the order UUID prefix.
  const path = `${orderId}/${String(invoice.invoice_number).replace(/[^A-Za-z0-9._-]/g, "_")}.pdf`;
  return { pdf: await pdf.save(), path, bucket: "invoices" };
}

// ---------------------------------------------------------------------------
// Shipping labels (one page per package)
// ---------------------------------------------------------------------------
async function buildShippingLabel(orderId: string | null, shipmentId: string | null): Promise<{ pdf: Uint8Array; path: string; bucket: string }> {
  const filter = orderId ? `order_id=eq.${encodeURIComponent(orderId)}` : `id=eq.${encodeURIComponent(shipmentId ?? "")}`;
  const shipments = (await fetchJson(`/rest/v1/shipments?${filter}&select=*`)) as Json[];
  const shipment = shipments[0];
  if (!shipment) throw new HttpError(404, "shipment_not_found", "Shipment not found.");
  const orders = (await fetchJson(`/rest/v1/orders?id=eq.${encodeURIComponent(String(shipment.order_id))}&select=*`)) as Json[];
  const order = orders[0];
  if (!order) throw new HttpError(404, "order_not_found", "Order not found.");
  const packages = (await fetchJson(
    `/rest/v1/packages?shipment_id=eq.${encodeURIComponent(String(shipment.id))}&select=*&order=package_number`,
  )) as Json[];
  if (packages.length === 0) throw new HttpError(409, "no_packages", "Add and seal at least one package before generating labels.");

  const pdf = await PDFDocument.create();
  pdf.setTitle(`Shipping labels ${String(shipment.shipment_number)}`);
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const width = 288; // 4in
  const height = 432; // 6in
  const margin = 16;

  for (const pkg of packages) {
    const page = pdf.addPage([width, height]);
    page.drawRectangle({ x: 0, y: height - 50, width, height: 50, color: NAVY });
    page.drawRectangle({ x: 0, y: height - 54, width, height: 4, color: ACCENT });
    page.drawText("INDIABIZZ", { x: margin, y: height - 27, size: 15, font: bold, color: WHITE });
    page.drawText(safeText(`Package ${pkg.package_number}`), { x: width - margin - 90, y: height - 25, size: 9, font: bold, color: WHITE });
    page.drawText(safeText(String(shipment.shipment_number)), { x: width - margin - 90, y: height - 38, size: 7, font: regular, color: rgb(0.78, 0.82, 0.9) });

    let y = height - 74;
    page.drawText("DELIVER TO", { x: margin, y, size: 7, font: bold, color: MUTED });
    y = text(page, bold, String(order.recipient_name), margin, y - 16, 12, NAVY, width - margin * 2);
    y = text(page, regular, orderAddress(order), margin, y - 12, 8.6, INK, width - margin * 2) - 18;

    page.drawRectangle({ x: margin, y: y - 2, width: width - margin * 2, height: 24, color: rgb(0.94, 0.96, 0.98) });
    page.drawText("CASH ON DELIVERY", { x: margin + 6, y: y + 5, size: 7.5, font: bold, color: MUTED });
    page.drawText(money(Number(order.cod_amount_paise)), { x: width - margin - 82, y: y + 3, size: 12, font: bold, color: Number(order.cod_amount_paise) > 0 ? DANGER : SUCCESS });
    y -= 36;

    labelValue(page, "Order", String(order.order_number), margin, y, bold, regular, 9);
    labelValue(page, "Weight", `${pkg.weight_grams ?? 0} g`, width / 2, y, bold, regular, 9);
    y -= 44;
    labelValue(page, "Shipment", String(shipment.shipment_number), margin, y, bold, regular, 8);
    labelValue(page, "Package code", String(pkg.package_code), margin, y - 38, bold, regular, 7);

    const barcode = await pdf.embedPng(await barcodePng(String(pkg.package_code)));
    page.drawImage(barcode, { x: margin, y: 82, width: width - margin * 2, height: 54 });
    page.drawText(safeText(String(pkg.package_code)), { x: margin, y: 68, size: 7, font: regular, color: MUTED });

    const qr = await pdf.embedPng(await qrPng(
      JSON.stringify({ package: pkg.package_code, shipment: shipment.shipment_number, order: order.order_number }),
    ));
    page.drawImage(qr, { x: width - margin - 58, y: 22, width: 58, height: 58 });
    page.drawText("Scan package before pickup and delivery.", { x: margin, y: 30, size: 7, font: bold, color: NAVY });
    page.drawText("Do not accept if seal is broken.", { x: margin, y: 19, size: 6.5, font: regular, color: MUTED });
  }

  // Storage policies authorize reads by the shipment UUID prefix.
  const path = `${String(shipment.id)}/${String(shipment.shipment_number).replace(/[^A-Za-z0-9._-]/g, "_")}.pdf`;
  return { pdf: await pdf.save(), path, bucket: "shipping-labels" };
}

// ---------------------------------------------------------------------------
// Pickup manifest
// ---------------------------------------------------------------------------
async function buildPickupManifest(pickupId: string): Promise<{ pdf: Uint8Array; path: string; bucket: string }> {
  const pickups = (await fetchJson(`/rest/v1/pickup_requests?id=eq.${encodeURIComponent(pickupId)}&select=*`)) as Json[];
  const pickup = pickups[0];
  if (!pickup) throw new HttpError(404, "pickup_not_found", "Pickup request not found.");
  const shipments = (await fetchJson(`/rest/v1/shipments?id=eq.${encodeURIComponent(String(pickup.shipment_id))}&select=*`)) as Json[];
  const shipment = shipments[0];
  const orders = (await fetchJson(`/rest/v1/orders?id=eq.${encodeURIComponent(String(pickup.order_id))}&select=*`)) as Json[];
  const order = orders[0];
  if (!shipment || !order) throw new HttpError(404, "pickup_data_missing", "Shipment or order for this pickup is missing.");
  const packages = (await fetchJson(
    `/rest/v1/packages?shipment_id=eq.${encodeURIComponent(String(shipment.id))}&select=*&order=package_number`,
  )) as Json[];
  const settingsRows = (await fetchJson(`/rest/v1/app_settings?key=eq.business&select=value`)) as Array<{ value: Json }>;
  const business = settingsRows[0]?.value ?? {};

  const pdf = await PDFDocument.create();
  pdf.setTitle(`Pickup manifest ${String(pickup.pickup_number)}`);
  const regular = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const width = 595.28;
  const height = 841.89;
  const margin = 42;
  const page = pdf.addPage([width, height]);

  page.drawRectangle({ x: 0, y: height - 92, width, height: 92, color: NAVY });
  page.drawRectangle({ x: 0, y: height - 97, width, height: 5, color: ACCENT });
  page.drawText("INDIABIZZ", { x: margin, y: height - 50, size: 22, font: bold, color: WHITE });
  page.drawText("PICKUP MANIFEST", { x: margin, y: height - 70, size: 9, font: bold, color: rgb(0.78, 0.82, 0.9) });
  page.drawText(safeText(String(pickup.pickup_number)), { x: width - margin - 170, y: height - 55, size: 13, font: bold, color: WHITE });
  page.drawText(safeText(String(pickup.status)), { x: width - margin - 170, y: height - 72, size: 8, font: regular, color: rgb(0.78, 0.82, 0.9) });

  let y = height - 125;
  labelValue(page, "Pickup from", String(business.legal_name || business.display_name || "IndiaBizz"), margin, y, bold, regular, 10);
  text(page, regular, String(business.address || ""), margin, y - 32, 8.5, INK, 300);
  labelValue(page, "Pickup phone", String(business.phone || business.support_phone || "-"), width - margin - 190, y, bold, regular, 10);
  labelValue(page, "Requested", dateTime(pickup.requested_at as string), width - margin - 190, y - 38, bold, regular, 10);

  y -= 108;
  labelValue(page, "Order", String(order.order_number), margin, y, bold, regular, 10);
  labelValue(page, "Shipment", String(shipment.shipment_number), margin + 150, y, bold, regular, 10);
  labelValue(page, "Expected packages", String(pickup.package_count_expected), margin + 320, y, bold, regular, 10);
  labelValue(page, "COD to collect", money(Number(shipment.expected_cod_paise)), margin + 460, y, bold, regular, 10);

  y -= 52;
  page.drawRectangle({ x: margin, y: y - 2, width: width - margin * 2, height: 20, color: rgb(0.94, 0.96, 0.98) });
  page.drawText("#", { x: margin + 5, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("PACKAGE CODE", { x: margin + 35, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("WEIGHT", { x: 330, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("SEALED", { x: 400, y: y + 4, size: 7.5, font: bold, color: NAVY });
  page.drawText("SCAN", { x: 470, y: y + 4, size: 7.5, font: bold, color: NAVY });
  y -= 22;

  for (const pkg of packages) {
    page.drawText(safeText(pkg.package_number), { x: margin + 5, y, size: 8.5, font: regular });
    page.drawText(safeText(pkg.package_code), { x: margin + 35, y, size: 8.5, font: regular });
    page.drawText(`${pkg.weight_grams ?? 0} g`, { x: 330, y, size: 8.5, font: regular });
    page.drawText(pkg.is_sealed ? "YES" : "NO", { x: 400, y, size: 8.5, font: bold, color: pkg.is_sealed ? SUCCESS : DANGER });
    page.drawRectangle({ x: 470, y: y - 3, width: 14, height: 14, borderColor: MUTED, borderWidth: 0.8 });
    y -= 24;
    rule(page, y + 8, width, margin);
  }

  y -= 18;
  page.drawText(`Packages listed: ${packages.length} of ${pickup.package_count_expected} expected`, {
    x: margin, y, size: 9, font: bold, color: packages.length === pickup.package_count_expected ? SUCCESS : DANGER,
  });

  const barcode = await pdf.embedPng(await barcodePng(String(pickup.pickup_number)));
  page.drawImage(barcode, { x: margin, y: y - 75, width: 220, height: 48 });
  page.drawText("Pickup verification checklist", { x: width - margin - 195, y: y - 32, size: 8, font: bold, color: NAVY });
  const checklist = [
    "Count matches expected packages",
    "Every seal is intact",
    "Every package scanned",
    "Condition marked GOOD",
    "Pickup OTP confirmed by owner",
  ];
  checklist.forEach((item, index) => {
    const lineY = y - 46 - index * 13;
    page.drawRectangle({ x: width - margin - 195, y: lineY, width: 9, height: 9, borderColor: MUTED, borderWidth: 0.7 });
    page.drawText(safeText(item), { x: width - margin - 181, y: lineY + 1, size: 7.5, font: regular, color: INK });
  });

  page.drawText(
    "Barcode scanning alone never marks a pickup as verified. The delivery person must verify count, condition and the pickup OTP.",
    { x: margin, y: 48, size: 7, font: regular, color: MUTED, maxWidth: width - margin * 2 },
  );

  // Storage policies authorize reads by the pickup UUID prefix.
  const path = `${String(pickup.id)}/${String(pickup.pickup_number).replace(/[^A-Za-z0-9._-]/g, "_")}.pdf`;
  return { pdf: await pdf.save(), path, bucket: "pickup-manifests" };
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------
async function upload(path: string, bucket: string, bytes: Uint8Array): Promise<boolean> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await serviceFetch(`/storage/v1/object/${bucket}/${encodedPath}`, {
    method: "POST",
    headers: { "Content-Type": "application/pdf", "x-upsert": "false", "Cache-Control": "private, max-age=0" },
    body: bytes,
  });
  if (response.ok) return true;
  const message = await response.text();
  // A duplicate is valid for immutable documents: keep the first generated file.
  if (response.status === 409 || message.toLowerCase().includes("already exists")) return false;
  console.error("storage upload failed", response.status, message.slice(0, 400));
  throw new HttpError(502, "storage_upload_failed", "The PDF could not be stored in the private bucket.");
}

async function signedUrl(bucket: string, path: string): Promise<string> {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await serviceFetch(`/storage/v1/object/sign/${bucket}/${encodedPath}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ expiresIn: 3600 }),
  });
  const text = await response.text();
  if (!response.ok) {
    console.error("storage sign failed", response.status, text.slice(0, 400));
    throw new HttpError(502, "storage_sign_failed", "The document could not be signed for download.");
  }
  const payload = JSON.parse(text) as { signedURL?: string; signedUrl?: string };
  const relative = payload.signedURL ?? payload.signedUrl;
  if (!relative) throw new HttpError(502, "storage_sign_failed", "Storage did not return a signed URL.");
  return relative.startsWith("http") ? relative : `${supabaseUrl()}/storage/v1${relative}`;
}

Deno.serve(async (req) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") {
    return json({ ok: false, error_code: "method_not_allowed", message: "Use POST." }, 405);
  }

  try {
    const owner = await assertOwner(req);
    const body = await readJson(req);
    const type = typeof body.type === "string" ? body.type as DocumentType : null;
    if (!type || !["invoice", "shipping_label", "pickup_manifest"].includes(type)) {
      throw new HttpError(400, "invalid_document_type", "type must be invoice, shipping_label or pickup_manifest.");
    }

    let generated: { pdf: Uint8Array; path: string; bucket: string };
    let existingPath: string | null = null;

    if (type === "invoice") {
      const orderId = typeof body.order_id === "string" ? body.order_id : "";
      if (!orderId) throw new HttpError(400, "order_id_required", "order_id is required.");
      const rows = (await fetchJson(
        `/rest/v1/invoices?order_id=eq.${encodeURIComponent(orderId)}&select=id,invoice_number,pdf_storage_path,status`,
      )) as Json[];
      const invoice = rows[0];
      if (!invoice) throw new HttpError(404, "invoice_not_found", "No invoice exists for this order.");
      if (invoice.status === "VOID") throw new HttpError(409, "invoice_void", "This invoice has been voided.");
      if (typeof invoice.pdf_storage_path === "string" && invoice.pdf_storage_path) {
        return json({
          ok: true,
          type,
          storage_path: invoice.pdf_storage_path,
          signed_url: await signedUrl("invoices", invoice.pdf_storage_path),
          expires_in_seconds: 3600,
          reused: true,
        });
      }
      generated = await buildInvoice(orderId, owner.id);
      existingPath = typeof invoice.pdf_storage_path === "string" ? invoice.pdf_storage_path : null;

      const storedPath = generated.path;
      const fresh = await upload(storedPath, generated.bucket, generated.pdf);
      const update = await serviceFetch(`/rest/v1/invoices?order_id=eq.${encodeURIComponent(orderId)}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pdf_storage_path: storedPath }),
      });
      if (!update.ok) {
        console.error("invoice path update failed", update.status, await update.text());
      }
      return json({
        ok: true,
        type,
        storage_path: storedPath,
        signed_url: await signedUrl(generated.bucket, storedPath),
        expires_in_seconds: 3600,
        created: fresh,
        previous_path: existingPath,
      });
    }

    if (type === "shipping_label") {
      const orderId = typeof body.order_id === "string" ? body.order_id : null;
      const shipmentId = typeof body.shipment_id === "string" ? body.shipment_id : null;
      if (!orderId && !shipmentId) throw new HttpError(400, "identifier_required", "order_id or shipment_id is required.");
      generated = await buildShippingLabel(orderId, shipmentId);
    } else {
      const pickupId = typeof body.pickup_id === "string" ? body.pickup_id : "";
      if (!pickupId) throw new HttpError(400, "pickup_id_required", "pickup_id is required.");
      generated = await buildPickupManifest(pickupId);
    }

    const created = await upload(generated.path, generated.bucket, generated.pdf);
    return json({
      ok: true,
      type,
      storage_path: generated.path,
      signed_url: await signedUrl(generated.bucket, generated.path),
      expires_in_seconds: 3600,
      created,
    });
  } catch (error) {
    return errorResponse(error);
  }
});
