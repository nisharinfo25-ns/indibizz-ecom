import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../models/models.dart';

String newIdempotencyKey(String prefix) {
  final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$random';
}

class CustomerRepository {
  CustomerRepository(this.client) : _api = ApiClient(client);

  final SupabaseClient client;
  final ApiClient _api;

  Future<Profile> getProfile() async => Profile.fromJson(await _api.rpcMap('get_my_profile'));

  Future<Profile> updateProfile({required String fullName, String? email}) async {
    await _api.rpc('update_my_profile', {'p_full_name': fullName, 'p_email': email});
    return getProfile();
  }

  Future<List<CatalogProduct>> fetchCatalog({int limit = 500}) async {
    final rows = await _api.select(
      'catalog_products',
      order: 'created_at',
      ascending: false,
      limit: limit,
    );
    return rows.map(CatalogProduct.fromJson).toList(growable: false);
  }

  Future<CatalogProduct?> fetchProductBySlug(String slug) async {
    final row = await _api.selectSingle('catalog_products', 'slug', slug);
    return row == null ? null : CatalogProduct.fromJson(row);
  }

  Future<List<ProductImage>> fetchProductImages(String productId) async {
    final rows = await _api.select(
      'product_images',
      eq: {'product_id': productId},
      order: 'sort_order',
      ascending: true,
    );
    return rows.map(ProductImage.fromJson).toList(growable: false);
  }

  Future<String?> signedProductImage(String? path) => _api.storageSignedUrl('product-images', path);

  Future<String?> signedInvoice(String? path) => _api.storageSignedUrl('invoices', path);

  Future<Cart> getCart() async => Cart.fromJson(await _api.rpcMap('get_my_cart'));

  Future<Cart> addToCart(String productId, {int quantity = 1}) async =>
      Cart.fromJson(await _api.rpcMap('cart_add_item', {'p_product_id': productId, 'p_quantity': quantity}));

  Future<Cart> setQuantity(String productId, int quantity) async =>
      Cart.fromJson(await _api.rpcMap('cart_set_quantity', {'p_product_id': productId, 'p_quantity': quantity}));

  Future<Cart> removeFromCart(String productId) async =>
      Cart.fromJson(await _api.rpcMap('cart_remove_item', {'p_product_id': productId}));

  Future<Cart> clearCart() async => Cart.fromJson(await _api.rpcMap('cart_clear'));

  Future<List<Address>> getAddresses() async =>
      (await _api.rpcList('list_my_addresses')).map(Address.fromJson).toList(growable: false);

  Future<List<Town>> getTowns() async =>
      (await _api.rpcList('list_serviceable_towns')).map(Town.fromJson).toList(growable: false);

  Future<Serviceability> checkServiceability(String pincode, {String? townId}) async =>
      Serviceability.fromJson(await _api.rpcMap('check_serviceability', {
        'p_pincode': pincode.trim(),
        'p_town_id': townId,
      }));

  Future<Quote> quote(String addressId) async =>
      Quote.fromJson(await _api.rpcMap('quote_my_order', {'p_address_id': addressId}));

  Future<Map<String, dynamic>> placeOrder({
    required String addressId,
    String? note,
    String? idempotencyKey,
  }) async =>
      _api.rpcMap('place_order', {
        'p_address_id': addressId,
        'p_idempotency_key': idempotencyKey ?? newIdempotencyKey('order'),
        'p_customer_note': note,
      });

  Future<List<OrderSummary>> listOrders({int limit = 30, DateTime? before}) async =>
      (await _api.rpcList('list_my_orders', {'p_limit': limit, 'p_before': before?.toUtc().toIso8601String()}))
          .map(OrderSummary.fromJson)
          .toList(growable: false);

  Future<OrderDetail> getOrder(String orderId) async =>
      OrderDetail.fromJson(await _api.rpcMap('get_my_order', {'p_order_id': orderId}));

  Future<Tracking> getTracking(String orderId) async =>
      Tracking.fromJson(await _api.rpcMap('get_order_tracking', {'p_order_id': orderId}));

  Future<Map<String, dynamic>> cancelOrder(String orderId, String reason) async =>
      _api.rpcMap('cancel_order', {'p_order_id': orderId, 'p_reason': reason});

  Future<Map<String, dynamic>> requestReturn({
    required String orderId,
    required String reason,
    String? description,
    String? evidencePath,
  }) async =>
      _api.rpcMap('request_return', {
        'p_order_id': orderId,
        'p_reason': reason,
        'p_description': description,
        'p_evidence_path': evidencePath,
      });

  Future<Address> saveAddress({
    required String label,
    required String recipientName,
    required String phone,
    required String line1,
    required String line2,
    required String landmark,
    required String townId,
    required String pincode,
    required bool isDefault,
    String? id,
  }) async =>
      Address.fromJson(await _api.rpcMap('save_my_address', {
        'p_label': label,
        'p_recipient_name': recipientName,
        'p_phone': phone,
        'p_line1': line1,
        'p_line2': line2,
        'p_landmark': landmark,
        'p_town_id': townId,
        'p_pincode': pincode,
        'p_is_default': isDefault,
        'p_id': id,
      }));

  Future<void> deleteAddress(String id) async => _api.rpc('delete_my_address', {'p_id': id});

  Future<List<NotificationItem>> listNotifications({int limit = 60}) async =>
      (await _api.rpcList('list_my_notifications', {'p_limit': limit}))
          .map(NotificationItem.fromJson)
          .toList(growable: false);

  Future<void> markNotificationRead(String id) async =>
      _api.rpc('mark_notification_read', {'p_notification_id': id});

  Future<void> markAllNotificationsRead() async => _api.rpc('mark_all_notifications_read');

  Future<String> uploadReturnEvidence({
    required String orderId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$orderId/${DateTime.now().microsecondsSinceEpoch}-$safe';
    await client.storage.from('return-evidence').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }
}
