import 'package:flutter_test/flutter_test.dart';
import 'package:indibizz_core/indibizz_core.dart';

void main() {
  group('money', () {
    test('formats paise using Indian grouping', () {
      expect(formatMoney(0), '\u20B90');
      expect(formatMoney(100), '\u20B91');
      expect(formatMoney(12345), '\u20B9123.45');
      expect(formatMoney(123456789), '\u20B912,34,567.89');
      expect(formatMoney(-15000), '-\u20B9150');
    });

    test('parses rupees without floating point drift', () {
      expect(parseRupeesToPaise('123.45'), 12345);
      expect(parseRupeesToPaise('1,234'), 123400);
      expect(parseRupeesToPaise('\u20B999.9'), 9990);
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
    });
  });

  group('phone', () {
    test('normalizes Indian numbers', () {
      expect(normalizePhone('98765 43210'), '+919876543210');
      expect(normalizePhone('+91 98765 43210'), '+919876543210');
      expect(normalizePhone('09876543210'), '+919876543210');
      expect(isValidPhone('9876543210'), isTrue);
      expect(isValidPhone('12345'), isFalse);
    });

    test('masks middle digits', () {
      expect(maskPhone('+919876543210'), '+919876******');
    });
  });

  group('order status', () {
    test('labels and tones are stable', () {
      expect(statusLabel('PENDING_APPROVAL'), 'Awaiting approval');
      expect(statusLabel('OUT_FOR_DELIVERY'), 'Out for delivery');
      expect(statusTone('DELIVERED'), StatusTone.success);
      expect(statusTone('REJECTED'), StatusTone.danger);
      expect(statusTone('PENDING_APPROVAL'), StatusTone.pending);
    });

    test('tracking stage progresses to the end', () {
      expect(trackingStageIndex('PENDING_APPROVAL'), 0);
      expect(trackingStageIndex('OUT_FOR_DELIVERY'), 7);
      expect(trackingStageIndex('DELIVERED'), 8);
    });

    test('customer actions respect workflow boundaries', () {
      expect(canCancel('APPROVED'), isTrue);
      expect(canCancel('OUT_FOR_DELIVERY'), isFalse);
      expect(canRequestReturn('DELIVERED', null), isTrue);
      expect(canRequestReturn('DELIVERED', 'REQUESTED'), isFalse);
      expect(canRequestReturn('OUT_FOR_DELIVERY', null), isFalse);
    });
  });

  group('models', () {
    test('OrderDetail parses nested payloads', () {
      final detail = OrderDetail.fromJson({
        'id': 'o1',
        'order_number': 'IB-1001',
        'status': 'DELIVERED',
        'payment_status': 'COLLECTED',
        'subtotal_paise': 10000,
        'discount_paise': 0,
        'tax_paise': 500,
        'shipping_paise': 0,
        'total_paise': 10500,
        'cod_amount_paise': 10500,
        'item_count': 2,
        'recipient_name': 'Asha',
        'phone': '+919876543210',
        'line1': '1 Main Road',
        'town_name': 'Chennai',
        'district': 'Chennai',
        'state': 'Tamil Nadu',
        'pincode': '600001',
        'created_at': '2026-01-01T00:00:00Z',
        'items': [
          {'product_name': 'Bottle', 'sku': 'B1', 'quantity': 2, 'unit_price_paise': 5000, 'tax_paise': 500, 'line_total_paise': 10500}
        ],
        'invoice': {'id': 'i1', 'invoice_number': 'INV-1', 'status': 'ISSUED', 'total_paise': 10500},
        'return_request': {'id': 'r1', 'return_number': 'RET-1', 'status': 'REQUESTED', 'reason': 'Damaged', 'created_at': '2026-01-02T00:00:00Z'},
      });
      expect(detail.orderNumber, 'IB-1001');
      expect(detail.items.single.productName, 'Bottle');
      expect(detail.invoice?.invoiceNumber, 'INV-1');
      expect(detail.returnRequest?.status, 'REQUESTED');
      expect(detail.addressLine, contains('600001'));
    });

    test('OwnerDashboard reads metrics and recent orders', () {
      final dashboard = OwnerDashboard.fromJson({
        'orders_today': 3,
        'pending_approval': 1,
        'ready_for_pickup': 2,
        'cod_pending_verification_paise': 45000,
        'recent_orders': [
          {'id': 'o1', 'order_number': 'IB-1', 'status': 'PENDING_APPROVAL', 'total_paise': 45000, 'item_count': 1, 'created_at': '2026-01-01T00:00:00Z'}
        ],
      });
      expect(dashboard.ordersToday, 3);
      expect(dashboard.codPendingVerificationPaise, 45000);
      expect(dashboard.recentOrders.single.orderNumber, 'IB-1');
    });

    test('PickupDetail separates physical verification from scans', () {
      final detail = PickupDetail.fromJson({
        'assignment': {'id': 'a1', 'status': 'ACCEPTED'},
        'pickup': {'id': 'p1', 'pickup_number': 'PU-1', 'status': 'ARRIVED', 'package_count_expected': 2, 'scanned_packages': 2},
        'shipment': {'id': 's1', 'shipment_number': 'SH-1', 'status': 'ARRIVED_AT_PICKUP', 'package_count': 2},
        'order': {'id': 'o1', 'order_number': 'IB-1', 'status': 'READY_FOR_PICKUP'},
        'seller': {'name': 'IndiaBizz'},
        'packages': [
          {'id': 'k1', 'package_number': 'PKG-1', 'status': 'ARRIVED_AT_PICKUP', 'is_sealed': true, 'scanned': true}
        ],
        'can_verify': true,
      });
      expect(detail.pickup.scannedPackages, 2);
      expect(detail.canVerify, isTrue);
      expect(detail.packages.single.scanned, isTrue);
      expect(detail.isVerified, isFalse);
    });
  });
}
