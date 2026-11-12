import type { OrderStatus, PaymentStatus, ReturnStatus, StatusTone } from "./types";

export const ORDER_FLOW = [
  { key: "placed", label: "Order placed", description: "We received your COD order." },
  { key: "approved", label: "Confirmed", description: "The seller confirmed your order." },
  { key: "packed", label: "Packed", description: "Your parcel is sealed and ready." },
  { key: "picked_up", label: "Picked up", description: "The delivery partner collected your parcel." },
  { key: "transit", label: "In transit", description: "Your parcel is on the way." },
  { key: "out_for_delivery", label: "Out for delivery", description: "Keep your delivery OTP ready." },
  { key: "delivered", label: "Delivered", description: "Cash paid and parcel handed over." },
] as const;

const STATUS_INDEX: Record<OrderStatus, number> = {
  PENDING_APPROVAL: 0,
  APPROVED: 1,
  READY_FOR_PICKUP: 2,
  PICKUP_REQUESTED: 2,
  PICKED_UP: 3,
  IN_TRANSIT: 4,
  ARRIVED_AT_DESTINATION: 4,
  OUT_FOR_DELIVERY: 5,
  DELIVERED: 6,
  CLOSED: 6,
  RETURN_REQUESTED: 6,
  RETURNED: 6,
  REJECTED: 0,
  CANCELLED: 0,
  DELIVERY_FAILED: 5,
};

const LABELS: Record<OrderStatus, string> = {
  PENDING_APPROVAL: "Awaiting confirmation",
  APPROVED: "Confirmed",
  REJECTED: "Rejected",
  CANCELLED: "Cancelled",
  READY_FOR_PICKUP: "Packed",
  PICKUP_REQUESTED: "Pickup scheduled",
  PICKED_UP: "Picked up",
  IN_TRANSIT: "In transit",
  ARRIVED_AT_DESTINATION: "Arrived in your town",
  OUT_FOR_DELIVERY: "Out for delivery",
  DELIVERED: "Delivered",
  DELIVERY_FAILED: "Delivery failed",
  RETURN_REQUESTED: "Return requested",
  RETURNED: "Returned",
  CLOSED: "Closed",
};

const TONES: Record<OrderStatus, StatusTone> = {
  PENDING_APPROVAL: "pending",
  APPROVED: "info",
  REJECTED: "danger",
  CANCELLED: "muted",
  READY_FOR_PICKUP: "info",
  PICKUP_REQUESTED: "info",
  PICKED_UP: "info",
  IN_TRANSIT: "info",
  ARRIVED_AT_DESTINATION: "info",
  OUT_FOR_DELIVERY: "pending",
  DELIVERED: "success",
  DELIVERY_FAILED: "danger",
  RETURN_REQUESTED: "pending",
  RETURNED: "muted",
  CLOSED: "success",
};

const PAYMENT_LABELS: Record<PaymentStatus, string> = {
  PENDING: "Cash due on delivery",
  COLLECTED: "Cash collected",
  SETTLED: "Settled with seller",
  VOID: "Void",
};

const RETURN_LABELS: Record<ReturnStatus, string> = {
  REQUESTED: "Return requested",
  APPROVED: "Return approved",
  REJECTED: "Return rejected",
  RECEIVED: "Return received",
  CLOSED: "Return closed",
};

export function orderStatusLabel(status: OrderStatus | string | null | undefined): string {
  if (!status) return "Unknown";
  return LABELS[status as OrderStatus] ?? String(status).replaceAll("_", " ").toLowerCase();
}

export function orderStatusTone(status: OrderStatus | string | null | undefined): StatusTone {
  if (!status) return "muted";
  return TONES[status as OrderStatus] ?? "muted";
}

export function paymentStatusLabel(status: PaymentStatus | string | null | undefined): string {
  if (!status) return "—";
  return PAYMENT_LABELS[status as PaymentStatus] ?? String(status).replaceAll("_", " ").toLowerCase();
}

export function returnStatusLabel(status: ReturnStatus | string | null | undefined): string {
  if (!status) return "—";
  return RETURN_LABELS[status as ReturnStatus] ?? String(status).replaceAll("_", " ").toLowerCase();
}

export function orderStageIndex(status: OrderStatus | string | null | undefined): number {
  if (!status) return 0;
  return STATUS_INDEX[status as OrderStatus] ?? 0;
}

export function orderProgress(status: OrderStatus | string | null | undefined): number {
  if (status === "DELIVERED" || status === "CLOSED" || status === "RETURN_REQUESTED" || status === "RETURNED") return 100;
  if (status === "CANCELLED" || status === "REJECTED") return 100;
  const index = orderStageIndex(status);
  return Math.round((index / (ORDER_FLOW.length - 1)) * 100);
}

export function isOrderTerminal(status: OrderStatus | string | null | undefined): boolean {
  return ["DELIVERED", "CLOSED", "CANCELLED", "REJECTED", "RETURNED"].includes(String(status));
}

export function canCancelOrder(status: OrderStatus | string | null | undefined): boolean {
  return ["PENDING_APPROVAL", "APPROVED", "READY_FOR_PICKUP", "PICKUP_REQUESTED"].includes(String(status));
}

export function canRequestReturn(
  status: OrderStatus | string | null | undefined,
  returnStatus?: ReturnStatus | string | null,
): boolean {
  return status === "DELIVERED" && (!returnStatus || returnStatus === "REJECTED");
}

export function isFailureStatus(status: OrderStatus | string | null | undefined): boolean {
  return ["REJECTED", "CANCELLED", "DELIVERY_FAILED", "RETURNED"].includes(String(status));
}

export function orderNextAction(status: OrderStatus | string | null | undefined): string {
  switch (status) {
    case "PENDING_APPROVAL":
      return "The seller is reviewing stock and your address.";
    case "APPROVED":
      return "Your order is being packed and sealed.";
    case "READY_FOR_PICKUP":
    case "PICKUP_REQUESTED":
      return "A delivery partner will collect your parcel.";
    case "PICKED_UP":
    case "IN_TRANSIT":
    case "ARRIVED_AT_DESTINATION":
      return "Your parcel is moving towards your address.";
    case "OUT_FOR_DELIVERY":
      return "Share the delivery OTP only after checking your parcel and paying the exact COD amount.";
    case "DELIVERED":
      return "Thank you. You can request a return within the return window.";
    case "DELIVERY_FAILED":
      return "The delivery could not be completed. The seller will contact you.";
    case "REJECTED":
      return "The order was rejected. No cash was collected.";
    case "CANCELLED":
      return "This order was cancelled. Reserved stock was released.";
    case "RETURN_REQUESTED":
      return "The seller is reviewing your return request.";
    case "RETURNED":
      return "The return has been completed.";
    default:
      return "";
  }
}

export const RETURN_REASONS = [
  "Damaged on arrival",
  "Wrong item delivered",
  "Item missing from parcel",
  "Quality not as expected",
  "Other",
] as const;
