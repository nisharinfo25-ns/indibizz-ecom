export const APP_NAME = "IndiaBizz";
export const SUPPORT_EMAIL = "support@indibizz.in";

export type OrderStatus =
  | "PENDING_APPROVAL"
  | "APPROVED"
  | "REJECTED"
  | "CANCELLED"
  | "READY_FOR_PICKUP"
  | "PICKUP_REQUESTED"
  | "PICKED_UP"
  | "IN_TRANSIT"
  | "ARRIVED_AT_DESTINATION"
  | "OUT_FOR_DELIVERY"
  | "DELIVERED"
  | "DELIVERY_FAILED"
  | "RETURN_REQUESTED"
  | "RETURNED"
  | "CLOSED";

export type PaymentStatus = "PENDING" | "COLLECTED" | "SETTLED" | "VOID";

export type ReturnStatus = "REQUESTED" | "APPROVED" | "REJECTED" | "RECEIVED" | "CLOSED";

export type StatusTone = "pending" | "info" | "success" | "danger" | "muted";

export interface CatalogProduct {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  category_id: string;
  category_name: string;
  category_slug: string;
  sku: string;
  price_paise: number;
  compare_at_price_paise: number | null;
  tax_rate_bps: number;
  hsn_code: string | null;
  weight_grams: number | null;
  is_featured: boolean;
  available_quantity: number;
  in_stock: boolean;
  primary_image_path: string | null;
  created_at: string;
}

export interface CatalogCategory {
  id: string;
  name: string;
  slug: string;
  description: string | null;
  product_count: number;
}

export interface Town {
  id: string;
  name: string;
  district: string;
  state: string;
  pincodes: string[];
}

export interface Address {
  id: string;
  label: string;
  recipient_name: string;
  phone: string;
  line1: string;
  line2: string;
  landmark: string;
  town_id: string;
  town_name: string;
  district: string;
  state: string;
  pincode: string;
  is_default: boolean;
}

export interface AddressInput {
  label: string;
  recipient_name: string;
  phone: string;
  line1: string;
  line2: string;
  landmark: string;
  town_id: string;
  pincode: string;
  is_default: boolean;
  id?: string | null;
}

export interface CartItem {
  product_id: string;
  name: string;
  slug: string;
  sku: string;
  quantity: number;
  unit_price_paise: number;
  line_subtotal_paise: number;
  tax_rate_bps: number;
  available_quantity: number;
  is_available: boolean;
  primary_image_path: string | null;
}

export interface Cart {
  items: CartItem[];
  subtotal_paise: number;
  item_count: number;
}

export interface QuoteLine {
  product_id: string;
  name: string;
  sku: string;
  hsn_code: string | null;
  quantity: number;
  unit_price_paise: number;
  discount_paise: number;
  tax_rate_bps: number;
  tax_paise: number;
  line_total_paise: number;
  available_quantity: number;
  is_active: boolean;
  is_available: boolean;
}

export interface Quote {
  items: QuoteLine[];
  item_count: number;
  subtotal_paise: number;
  discount_paise: number;
  tax_paise: number;
  shipping_paise: number;
  total_paise: number;
  cod_amount_paise: number;
}

export interface OrderSummary {
  id: string;
  order_number: string;
  status: OrderStatus;
  payment_status: PaymentStatus;
  total_paise: number;
  cod_amount_paise: number;
  item_count: number;
  created_at: string;
  delivered_at: string | null;
  town_name: string;
  pincode: string;
  shipment_id: string | null;
  shipment_status: string | null;
  invoice_number: string | null;
  first_item_name: string | null;
  return_status: ReturnStatus | null;
}

export interface OrderItem {
  product_id: string | null;
  product_name: string;
  sku: string;
  hsn_code: string | null;
  unit_price_paise: number;
  quantity: number;
  discount_paise: number;
  tax_rate_bps: number;
  tax_paise: number;
  line_total_paise: number;
}

export interface OrderDetail {
  id: string;
  order_number: string;
  status: OrderStatus;
  payment_method: "COD";
  payment_status: PaymentStatus;
  subtotal_paise: number;
  discount_paise: number;
  tax_paise: number;
  shipping_paise: number;
  total_paise: number;
  cod_amount_paise: number;
  item_count: number;
  recipient_name: string;
  phone: string;
  line1: string;
  line2: string;
  landmark: string;
  town_name: string;
  district: string;
  state: string;
  pincode: string;
  customer_note: string;
  created_at: string;
  approved_at: string | null;
  delivered_at: string | null;
  cancelled_at: string | null;
  rejected_reason: string | null;
  items: OrderItem[];
  invoice: {
    id: string;
    invoice_number: string;
    invoice_date: string;
    status: "ISSUED" | "VOID";
    total_paise: number;
    pdf_storage_path: string | null;
  } | null;
  shipment: {
    id: string;
    shipment_number: string;
    status: string;
    package_count: number;
    expected_cod_paise: number;
    picked_up_at: string | null;
    delivered_at: string | null;
  } | null;
  return_request: {
    id: string;
    return_number: string;
    status: ReturnStatus;
    reason: string;
    created_at: string;
    rejection_reason: string | null;
    resolution_note: string | null;
  } | null;
}

export interface TrackingEvent {
  id: string;
  event_type: string;
  previous_status: string | null;
  new_status: string;
  source: string;
  notes: string | null;
  location_text: string | null;
  created_at: string;
}

export interface Tracking {
  order_id: string;
  order_number: string;
  order_status: OrderStatus;
  shipment_status: string | null;
  events: TrackingEvent[];
  packages: Array<{ package_number: string; status: string }>;
  delivery_otp: string | null;
  otp_notice: string | null;
  estimated_delivery: string | null;
}

export interface Profile {
  id: string;
  phone: string | null;
  full_name: string;
  email: string | null;
  role: string;
  status: string;
  created_at: string;
}

export interface NotificationItem {
  id: string;
  type: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  read_at: string | null;
  created_at: string;
}

export interface Serviceability {
  serviceable: boolean;
  town_id: string | null;
  town_name: string | null;
  district: string | null;
  state: string | null;
  message: string;
  available_towns?: Array<{ id: string; name: string; district: string; state: string }>;
}
