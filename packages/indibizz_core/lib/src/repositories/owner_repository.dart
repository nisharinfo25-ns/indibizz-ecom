import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../json.dart';
import '../models/models.dart';

class OwnerSettings {
  const OwnerSettings({
    required this.business,
    required this.commerce,
    required this.policies,
    required this.logistics,
    required this.publicSettings,
    required this.assignmentPolicies,
  });

  final Map<String, dynamic> business;
  final Map<String, dynamic> commerce;
  final Map<String, dynamic> policies;
  final Map<String, dynamic> logistics;
  final Map<String, dynamic> publicSettings;
  final List<Map<String, dynamic>> assignmentPolicies;

  factory OwnerSettings.fromJson(Map<String, dynamic> json) => OwnerSettings(
        business: jsonMap(json['business']),
        commerce: jsonMap(json['commerce']),
        policies: jsonMap(json['policies']),
        logistics: jsonMap(json['logistics']),
        publicSettings: jsonMap(json['public']),
        assignmentPolicies: jsonList(json['assignment_policies']),
      );
}

class OwnerRepository {
  OwnerRepository(this.client) : _api = ApiClient(client);

  final SupabaseClient client;
  final ApiClient _api;

  Future<OwnerDashboard> dashboard() async => OwnerDashboard.fromJson(await _api.rpcMap('owner_dashboard'));

  // Catalogue -----------------------------------------------------------------
  Future<List<CategoryInfo>> listCategories() async =>
      (await _api.rpcList('owner_list_categories')).map(CategoryInfo.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> saveCategory({
    required String name,
    String? slug,
    String description = '',
    String? imagePath,
    int sortOrder = 0,
    bool isActive = true,
    String? id,
  }) async =>
      _api.rpcMap('owner_save_category', {
        'p_name': name,
        'p_slug': slug,
        'p_description': description,
        'p_image_path': imagePath,
        'p_sort_order': sortOrder,
        'p_is_active': isActive,
        'p_id': id,
      });

  Future<List<AdminProduct>> listProducts({String? search, String? status, String? categoryId, bool lowStockOnly = false}) async =>
      (await _api.rpcList('owner_list_products', {
        'p_search': search,
        'p_status': status,
        'p_category_id': categoryId,
        'p_low_stock_only': lowStockOnly,
      }))
          .map(AdminProduct.fromJson)
          .toList(growable: false);

  Future<Map<String, dynamic>> saveProduct({
    required String categoryId,
    required String name,
    required String sku,
    required int pricePaise,
    int taxRateBps = 0,
    String? hsnCode,
    String description = '',
    int? compareAtPricePaise,
    int weightGrams = 0,
    String status = 'DRAFT',
    bool isFeatured = false,
    int lowStockThreshold = 5,
    int openingStock = 0,
    String? slug,
    String? id,
  }) async =>
      _api.rpcMap('owner_save_product', {
        'p_category_id': categoryId,
        'p_name': name,
        'p_sku': sku,
        'p_price_paise': pricePaise,
        'p_tax_rate_bps': taxRateBps,
        'p_hsn_code': hsnCode,
        'p_description': description,
        'p_compare_at_price_paise': compareAtPricePaise,
        'p_weight_grams': weightGrams,
        'p_status': status,
        'p_is_featured': isFeatured,
        'p_low_stock_threshold': lowStockThreshold,
        'p_opening_stock': openingStock,
        'p_slug': slug,
        'p_id': id,
      });

  Future<Map<String, dynamic>> addProductImage({
    required String productId,
    required String storagePath,
    String altText = '',
    bool isPrimary = false,
    bool isPublic = true,
    int sortOrder = 0,
  }) async =>
      _api.rpcMap('owner_add_product_image', {
        'p_product_id': productId,
        'p_storage_path': storagePath,
        'p_alt_text': altText,
        'p_is_primary': isPrimary,
        'p_is_public': isPublic,
        'p_sort_order': sortOrder,
      });

  Future<void> deleteProductImage(String imageId) async =>
      _api.rpc('owner_delete_product_image', {'p_image_id': imageId});

  Future<Map<String, dynamic>> adjustStock({
    required String productId,
    required int quantityDelta,
    required String reason,
    required String idempotencyKey,
  }) async =>
      _api.rpcMap('owner_adjust_stock', {
        'p_product_id': productId,
        'p_quantity_delta': quantityDelta,
        'p_reason': reason,
        'p_idempotency_key': idempotencyKey,
      });

  Future<List<Map<String, dynamic>>> inventoryMovements(String productId, {int limit = 50}) async =>
      _api.rpcList('owner_inventory_movements', {'p_product_id': productId, 'p_limit': limit});

  // Orders --------------------------------------------------------------------
  Future<List<AdminOrderSummary>> listOrders({String? status, String? search, int limit = 50}) async =>
      (await _api.rpcList('owner_list_orders', {
        'p_status': status,
        'p_search': search,
        'p_limit': limit,
      }))
          .map(AdminOrderSummary.fromJson)
          .toList(growable: false);

  Future<AdminOrderDetail> getOrderAdmin(String orderId) async =>
      AdminOrderDetail.fromJson(await _api.rpcMap('owner_get_order_admin', {'p_order_id': orderId}));

  Future<Map<String, dynamic>> approveOrder(String orderId, {int packageCount = 1}) async =>
      _api.rpcMap('approve_order', {'p_order_id': orderId, 'p_package_count': packageCount});

  Future<Map<String, dynamic>> rejectOrder(String orderId, String reason) async =>
      _api.rpcMap('reject_order', {'p_order_id': orderId, 'p_reason': reason});

  Future<Map<String, dynamic>> addPackage(String orderId, {int weightGrams = 0}) async =>
      _api.rpcMap('owner_add_package', {'p_order_id': orderId, 'p_weight_grams': weightGrams});

  Future<Map<String, dynamic>> sealPackage(String packageId) async =>
      _api.rpcMap('owner_seal_package', {'p_package_id': packageId});

  Future<Map<String, dynamic>> markReadyForPickup(String orderId) async =>
      _api.rpcMap('owner_mark_ready_for_pickup', {'p_order_id': orderId});

  Future<Map<String, dynamic>> requestPickup(String orderId) async =>
      _api.rpcMap('owner_request_pickup', {'p_order_id': orderId});

  Future<Map<String, dynamic>> getPickupOtp(String pickupId) async =>
      _api.rpcMap('owner_get_pickup_otp', {'p_pickup_id': pickupId});

  Future<Map<String, dynamic>> regeneratePickupOtp(String pickupId) async =>
      _api.rpcMap('owner_regenerate_pickup_otp', {'p_pickup_id': pickupId});

  // Logistics -----------------------------------------------------------------
  Future<List<PickupListItem>> listPickups({String? status}) async =>
      (await _api.rpcList('owner_list_pickups', {'p_status': status}))
          .map(PickupListItem.fromJson)
          .toList(growable: false);

  Future<List<DeliveryListItem>> listDeliveries({String? status}) async =>
      (await _api.rpcList('owner_list_deliveries', {'p_status': status}))
          .map(DeliveryListItem.fromJson)
          .toList(growable: false);

  Future<List<Personnel>> listDeliveryPersonnel() async =>
      (await _api.rpcList('owner_list_delivery_personnel')).map(Personnel.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> assignPickup({required String pickupId, required String staffUserId, String? reason}) async =>
      _api.rpcMap('owner_assign_pickup', {
        'p_pickup_id': pickupId,
        'p_staff_user_id': staffUserId,
        'p_reason': reason,
      });

  Future<Map<String, dynamic>> assignDelivery({required String shipmentId, required String staffUserId, String? reason}) async =>
      _api.rpcMap('owner_assign_delivery', {
        'p_shipment_id': shipmentId,
        'p_staff_user_id': staffUserId,
        'p_reason': reason,
      });

  Future<Map<String, dynamic>> cancelPickup(String pickupId, String reason) async =>
      _api.rpcMap('owner_cancel_pickup', {'p_pickup_id': pickupId, 'p_reason': reason});

  Future<Map<String, dynamic>> reopenPickup(String orderId) async =>
      _api.rpcMap('owner_reopen_pickup', {'p_order_id': orderId});

  Future<Map<String, dynamic>> resetDeliveryOtp(String shipmentId) async =>
      _api.rpcMap('owner_reset_delivery_otp', {'p_shipment_id': shipmentId});

  Future<Map<String, dynamic>> setStaffAvailability(String staffUserId, bool isAvailable) async =>
      _api.rpcMap('owner_set_staff_availability', {
        'p_staff_user_id': staffUserId,
        'p_is_available': isAvailable,
      });

  Future<Map<String, dynamic>> updateStaffProfile({
    required String staffUserId,
    required String displayName,
    int capacityPerDay = 25,
    String? employeeCode,
  }) async =>
      _api.rpcMap('owner_update_staff_profile', {
        'p_staff_user_id': staffUserId,
        'p_display_name': displayName,
        'p_capacity_per_day': capacityPerDay,
        'p_employee_code': employeeCode,
      });

  Future<Map<String, dynamic>> suspendDeliveryPerson(String staffUserId, String reason) async =>
      _api.rpcMap('owner_suspend_delivery_person', {'p_staff_user_id': staffUserId, 'p_reason': reason});

  Future<Map<String, dynamic>> reactivateDeliveryPerson(String staffUserId) async =>
      _api.rpcMap('owner_reactivate_delivery_person', {'p_staff_user_id': staffUserId});

  // Staff invitations ---------------------------------------------------------
  Future<StaffInvite> createStaffInvite({
    required String phone,
    required String role,
    required String displayName,
    String? partnerId,
    bool canManagePartnerStaff = false,
  }) async =>
      StaffInvite.fromJson(await _api.rpcMap('owner_create_staff_invite', {
        'p_phone': phone,
        'p_role': role,
        'p_display_name': displayName,
        'p_partner_id': partnerId,
        'p_can_manage_partner_staff': canManagePartnerStaff,
      }));

  Future<List<StaffInvite>> listStaffInvites() async =>
      (await _api.rpcList('owner_list_staff_invites')).map(StaffInvite.fromJson).toList(growable: false);

  Future<void> revokeStaffInvite(String inviteId) async =>
      _api.rpc('owner_revoke_staff_invite', {'p_invite_id': inviteId});

  // Partners ------------------------------------------------------------------
  Future<List<Partner>> listPartners() async =>
      (await _api.rpcList('owner_list_partners')).map(Partner.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> savePartner({
    required String name,
    required String code,
    String contactName = '',
    String? phone,
    String? email,
    String status = 'PENDING',
    int codCreditLimitPaise = 0,
    int settlementCycleDays = 1,
    String notes = '',
    String? id,
  }) async =>
      _api.rpcMap('owner_save_partner', {
        'p_name': name,
        'p_code': code,
        'p_contact_name': contactName,
        'p_phone': phone,
        'p_email': email,
        'p_status': status,
        'p_cod_credit_limit_paise': codCreditLimitPaise,
        'p_settlement_cycle_days': settlementCycleDays,
        'p_notes': notes,
        'p_id': id,
      });

  Future<Map<String, dynamic>> setPartnerStatus(String partnerId, String status, {String? reason}) async =>
      _api.rpcMap('owner_set_partner_status', {
        'p_partner_id': partnerId,
        'p_status': status,
        'p_reason': reason,
      });

  Future<Map<String, dynamic>> setPartnerCoverage(String partnerId, List<Map<String, dynamic>> areas) async =>
      _api.rpcMap('owner_set_partner_coverage', {'p_partner_id': partnerId, 'p_areas': areas});

  // Towns and settings --------------------------------------------------------
  Future<List<AdminTown>> listTowns() async =>
      (await _api.rpcList('owner_list_towns')).map(AdminTown.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> saveTown({
    required String name,
    required String district,
    required String state,
    double? latitude,
    double? longitude,
    bool isActive = true,
    String? id,
  }) async =>
      _api.rpcMap('owner_save_town', {
        'p_name': name,
        'p_district': district,
        'p_state': state,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_is_active': isActive,
        'p_id': id,
      });

  Future<Map<String, dynamic>> addPincode(String townId, String pincode, {bool isActive = true}) async =>
      _api.rpcMap('owner_add_serviceable_pincode', {
        'p_town_id': townId,
        'p_pincode': pincode,
        'p_is_active': isActive,
      });

  Future<Map<String, dynamic>> setPincodeActive(String pincodeId, bool isActive) async =>
      _api.rpcMap('owner_set_pincode_active', {'p_pincode_id': pincodeId, 'p_is_active': isActive});

  Future<Map<String, dynamic>> setStaffCoverage(String staffUserId, List<Map<String, dynamic>> areas) async =>
      _api.rpcMap('owner_set_staff_coverage', {'p_staff_user_id': staffUserId, 'p_areas': areas});

  Future<OwnerSettings> getSettings() async => OwnerSettings.fromJson(await _api.rpcMap('owner_get_settings'));

  Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> settings) async =>
      _api.rpcMap('owner_update_settings', {'p_settings': settings});

  Future<Map<String, dynamic>> updateAssignmentPolicy(String? townId, Map<String, dynamic> settings) async =>
      _api.rpcMap('owner_update_assignment_policy', {'p_town_id': townId, 'p_settings': settings});

  // COD and returns -----------------------------------------------------------
  Future<CodOverview> codOverview() async => CodOverview.fromJson(await _api.rpcMap('owner_list_cod_overview'));

  Future<List<CodSettlement>> listCodSettlements({String? status}) async =>
      (await _api.rpcList('owner_list_cod_settlements', {'p_status': status}))
          .map(CodSettlement.fromJson)
          .toList(growable: false);

  Future<Map<String, dynamic>> confirmCodSettlement({
    required String settlementId,
    required int countedPaise,
    String? note,
  }) async =>
      _api.rpcMap('owner_confirm_cod_settlement', {
        'p_settlement_id': settlementId,
        'p_counted_paise': countedPaise,
        'p_note': note,
      });

  Future<Map<String, dynamic>> disputeCodSettlement(String settlementId, String reason) async =>
      _api.rpcMap('owner_dispute_cod_settlement', {'p_settlement_id': settlementId, 'p_reason': reason});

  Future<List<ReturnAdmin>> listReturns({String? status}) async =>
      (await _api.rpcList('owner_list_returns', {'p_status': status}))
          .map(ReturnAdmin.fromJson)
          .toList(growable: false);

  Future<Map<String, dynamic>> decideReturn({required String returnId, required bool approve, String? note}) async =>
      _api.rpcMap('owner_decide_return', {'p_return_id': returnId, 'p_approve': approve, 'p_note': note});

  Future<Map<String, dynamic>> markReturnReceived(String returnId) async =>
      _api.rpcMap('owner_mark_return_received', {'p_return_id': returnId});

  Future<Map<String, dynamic>> closeReturn(String returnId, {String? note}) async =>
      _api.rpcMap('owner_close_return', {'p_return_id': returnId, 'p_note': note});

  // Audit and notifications ---------------------------------------------------
  Future<List<AuditLog>> listAuditLogs({int limit = 100, String? entityType, String? search}) async =>
      (await _api.rpcList('owner_list_audit_logs', {
        'p_limit': limit,
        'p_entity_type': entityType,
        'p_search': search,
      }))
          .map(AuditLog.fromJson)
          .toList(growable: false);

  Future<List<NotificationItem>> listNotifications({int limit = 60}) async =>
      (await _api.rpcList('list_my_notifications', {'p_limit': limit}))
          .map(NotificationItem.fromJson)
          .toList(growable: false);

  Future<void> markNotificationRead(String id) async =>
      _api.rpc('mark_notification_read', {'p_notification_id': id});

  Future<String?> signedProductImage(String? path) => _api.storageSignedUrl('product-images', path);

  Future<String?> signedReturnEvidence(String? path) => _api.storageSignedUrl('return-evidence', path);

  /// Calls the owner-only Edge Function that renders immutable PDFs. The
  /// response includes a short-lived signed URL; no storage bucket is public.
  Future<Map<String, dynamic>> generateDocument({
    required String type,
    String? orderId,
    String? shipmentId,
    String? pickupId,
  }) async {
    final response = await client.functions.invoke('generate-document', body: {
      'type': type,
      'order_id': ?orderId,
      'shipment_id': ?shipmentId,
      'pickup_id': ?pickupId,
    });
    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      final message = data is Map ? data['message'] ?? data['error'] : null;
      throw Exception(message?.toString() ?? 'Document generation failed (${response.status}).');
    }
    if (data is! Map) throw Exception('Document generation returned an unexpected response.');
    return Map<String, dynamic>.from(data);
  }
}
