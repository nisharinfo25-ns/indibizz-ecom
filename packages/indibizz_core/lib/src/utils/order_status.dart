import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

enum StatusTone { pending, info, success, danger, muted }

const _labels = <String, String>{
  'PENDING_APPROVAL': 'Awaiting approval',
  'APPROVED': 'Approved',
  'REJECTED': 'Rejected',
  'CANCELLED': 'Cancelled',
  'READY_FOR_PICKUP': 'Ready for pickup',
  'PICKUP_REQUESTED': 'Pickup requested',
  'PICKUP_ASSIGNED': 'Pickup assigned',
  'PICKUP_ACCEPTED': 'Pickup accepted',
  'ARRIVED_AT_PICKUP': 'At pickup',
  'PICKED_UP': 'Picked up',
  'IN_TRANSIT': 'In transit',
  'ARRIVED_AT_DESTINATION': 'Arrived at destination',
  'OUT_FOR_DELIVERY': 'Out for delivery',
  'DELIVERED': 'Delivered',
  'DELIVERY_FAILED': 'Delivery failed',
  'DELIVERY_ATTEMPTED': 'Delivery attempted',
  'CUSTOMER_UNAVAILABLE': 'Customer unavailable',
  'SHIPMENT_DELAYED': 'Delayed',
  'RETURN_REQUESTED': 'Return requested',
  'RETURNED': 'Returned',
  'CLOSED': 'Closed',
  'PENDING': 'Pending',
  'ACCEPTED': 'Accepted',
  'EXPIRED': 'Expired',
  'COMPLETED': 'Completed',
  'REQUESTED': 'Requested',
  'ASSIGNED': 'Assigned',
  'ARRIVED': 'Arrived',
  'VERIFIED': 'Verified',
  'FAILED': 'Failed',
  'VERIFICATION': 'Verification',
  'COLLECTED': 'Collected',
  'SETTLED': 'Settled',
  'VOID': 'Void',
  'PENDING_VERIFICATION': 'Pending verification',
  'DISPUTED': 'Disputed',
  'APPROVED_RETURN': 'Return approved',
  'RECEIVED': 'Received',
  'ACTIVE': 'Active',
  'SUSPENDED': 'Suspended',
  'DEACTIVATED': 'Deactivated',
  'INVITED': 'Invited',
  'DRAFT': 'Draft',
  'ARCHIVED': 'Archived',
  'LOW': 'Low stock',
  'GOOD': 'Good',
  'DAMAGED': 'Damaged',
  'SENT': 'Sent',
  'READ': 'Read',
  'OWN': 'Own team',
  'PARTNER': 'Partner',
};

String statusLabel(Object? status) {
  final key = (status ?? '').toString().toUpperCase();
  return _labels[key] ?? (key.isEmpty ? 'Unknown' : _humanize(key));
}

String _humanize(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

StatusTone statusTone(Object? status) {
  switch ((status ?? '').toString().toUpperCase()) {
    case 'DELIVERED':
    case 'VERIFIED':
    case 'COLLECTED':
    case 'SETTLED':
    case 'ACTIVE':
    case 'APPROVED':
    case 'CLOSED':
    case 'RECEIVED':
    case 'COMPLETED':
      return StatusTone.success;
    case 'REJECTED':
    case 'CANCELLED':
    case 'DELIVERY_FAILED':
    case 'FAILED':
    case 'SUSPENDED':
    case 'DEACTIVATED':
    case 'DISPUTED':
    case 'LOW':
    case 'DAMAGED':
      return StatusTone.danger;
    case 'PENDING_APPROVAL':
    case 'PENDING':
    case 'PENDING_VERIFICATION':
    case 'PICKUP_REQUESTED':
    case 'REQUESTED':
    case 'AWAITING':
      return StatusTone.pending;
    case 'APPROVED_RETURN':
    case 'IN_TRANSIT':
    case 'OUT_FOR_DELIVERY':
    case 'PICKED_UP':
    case 'READY_FOR_PICKUP':
    case 'ASSIGNED':
    case 'ACCEPTED':
    case 'ARRIVED':
      return StatusTone.info;
    default:
      return StatusTone.muted;
  }
}

Color toneColor(StatusTone tone, {bool dark = false}) {
  switch (tone) {
    case StatusTone.success:
      return dark ? const Color(0xFF7FD1A8) : IndiBizzColors.success;
    case StatusTone.danger:
      return dark ? const Color(0xFFFFA69E) : IndiBizzColors.danger;
    case StatusTone.pending:
      return dark ? const Color(0xFFF3C564) : IndiBizzColors.warning;
    case StatusTone.info:
      return dark ? const Color(0xFF9CC0FF) : IndiBizzColors.info;
    case StatusTone.muted:
      return dark ? IndiBizzColors.darkInkMuted : IndiBizzColors.inkMuted;
  }
}

Color toneBackground(StatusTone tone, {bool dark = false}) {
  switch (tone) {
    case StatusTone.success:
      return dark ? const Color(0xFF12372A) : IndiBizzColors.successSoft;
    case StatusTone.danger:
      return dark ? const Color(0xFF3B1714) : IndiBizzColors.dangerSoft;
    case StatusTone.pending:
      return dark ? const Color(0xFF372C10) : IndiBizzColors.warningSoft;
    case StatusTone.info:
      return dark ? const Color(0xFF122A4D) : IndiBizzColors.infoSoft;
    case StatusTone.muted:
      return dark ? const Color(0xFF1A2A3E) : const Color(0xFFF0F2F5);
  }
}

const trackingStages = <String>[
  'PENDING_APPROVAL',
  'APPROVED',
  'READY_FOR_PICKUP',
  'PICKUP_REQUESTED',
  'PICKED_UP',
  'IN_TRANSIT',
  'ARRIVED_AT_DESTINATION',
  'OUT_FOR_DELIVERY',
  'DELIVERED',
];

int trackingStageIndex(String status) {
  switch (status.toUpperCase()) {
    case 'PENDING_APPROVAL':
      return 0;
    case 'APPROVED':
      return 1;
    case 'READY_FOR_PICKUP':
      return 2;
    case 'PICKUP_REQUESTED':
    case 'PICKUP_ASSIGNED':
    case 'PICKUP_ACCEPTED':
    case 'ARRIVED_AT_PICKUP':
      return 3;
    case 'PICKED_UP':
      return 4;
    case 'IN_TRANSIT':
      return 5;
    case 'ARRIVED_AT_DESTINATION':
      return 6;
    case 'OUT_FOR_DELIVERY':
      return 7;
    case 'DELIVERED':
    case 'CLOSED':
      return 8;
    default:
      return 0;
  }
}

bool canCancel(String status) =>
    const {'PENDING_APPROVAL', 'APPROVED', 'READY_FOR_PICKUP'}.contains(status.toUpperCase());

bool canRequestReturn(String status, String? returnStatus) =>
    status.toUpperCase() == 'DELIVERED' && (returnStatus == null || returnStatus == 'REJECTED');

bool canTrack(String? shipmentStatus) => shipmentStatus != null && shipmentStatus.isNotEmpty;

String nextAction(String status) {
  switch (status.toUpperCase()) {
    case 'PENDING_APPROVAL':
      return 'The seller is reviewing your COD order.';
    case 'APPROVED':
      return 'Your order is being packed.';
    case 'READY_FOR_PICKUP':
      return 'Packed and waiting for the delivery partner.';
    case 'PICKUP_REQUESTED':
      return 'A delivery person is being assigned.';
    case 'PICKED_UP':
      return 'Your parcel has been collected.';
    case 'IN_TRANSIT':
      return 'Your parcel is on the way.';
    case 'ARRIVED_AT_DESTINATION':
      return 'Your parcel has reached your town.';
    case 'OUT_FOR_DELIVERY':
      return 'Share the delivery OTP with the delivery person.';
    case 'DELIVERED':
      return 'Delivered. Thank you for shopping with IndiaBizz.';
    case 'DELIVERY_FAILED':
      return 'The delivery attempt failed. The seller will contact you.';
    case 'CANCELLED':
      return 'This order was cancelled.';
    case 'REJECTED':
      return 'The seller could not accept this order.';
    case 'RETURN_REQUESTED':
      return 'Your return request is being reviewed.';
    case 'RETURNED':
      return 'Your return has been received.';
    default:
      return 'We will update this order as it progresses.';
  }
}

String deliveryFailureLabel(String reason) {
  switch (reason) {
    case 'CUSTOMER_UNAVAILABLE':
      return 'Customer unavailable';
    case 'CUSTOMER_REFUSED':
      return 'Customer refused delivery';
    case 'ADDRESS_NOT_FOUND':
      return 'Address not found';
    case 'PAYMENT_NOT_READY':
      return 'Customer not ready with COD payment';
    case 'PACKAGE_DAMAGED':
      return 'Package damaged';
    default:
      return 'Other reason';
  }
}
