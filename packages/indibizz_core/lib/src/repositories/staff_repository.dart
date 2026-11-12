import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import 'customer_repository.dart';

class StaffRepository {
  StaffRepository(this.client) : _api = ApiClient(client);

  final SupabaseClient client;
  final ApiClient _api;

  Future<StaffDashboard> dashboard() async => StaffDashboard.fromJson(await _api.rpcMap('staff_dashboard'));

  Future<List<PickupTask>> listPickups({String? status, int limit = 50}) async =>
      (await _api.rpcList('staff_list_pickup_assignments', {'p_status': status, 'p_limit': limit}))
          .map(PickupTask.fromJson)
          .toList(growable: false);

  Future<PickupDetail> getPickup(String assignmentId) async =>
      PickupDetail.fromJson(await _api.rpcMap('staff_get_pickup', {'p_assignment_id': assignmentId}));

  Future<Map<String, dynamic>> acceptPickup(String assignmentId) async =>
      _api.rpcMap('staff_accept_pickup', {'p_assignment_id': assignmentId});

  Future<Map<String, dynamic>> rejectPickup(String assignmentId, String reason) async =>
      _api.rpcMap('staff_reject_pickup', {'p_assignment_id': assignmentId, 'p_reason': reason});

  Future<Map<String, dynamic>> arriveAtPickup(String assignmentId, {double? latitude, double? longitude}) async =>
      _api.rpcMap('staff_arrive_at_pickup', {
        'p_assignment_id': assignmentId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      });

  Future<Map<String, dynamic>> scanPackage({
    required String assignmentId,
    required String rawCode,
    String? idempotencyKey,
    double? latitude,
    double? longitude,
    String? deviceId,
  }) async =>
      _api.rpcMap('staff_scan_package', {
        'p_assignment_id': assignmentId,
        'p_raw_code': rawCode.trim(),
        'p_idempotency_key': idempotencyKey ?? newIdempotencyKey('scan'),
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_device_id': deviceId,
      });

  Future<Map<String, dynamic>> verifyPickup({
    required String assignmentId,
    required String otp,
    required int packageCount,
    String condition = 'GOOD',
    String? notes,
  }) async =>
      _api.rpcMap('staff_verify_pickup', {
        'p_assignment_id': assignmentId,
        'p_otp': otp.trim(),
        'p_package_count': packageCount,
        'p_condition': condition,
        'p_notes': notes,
      });

  Future<Map<String, dynamic>> failPickup({
    required String assignmentId,
    required String reason,
    bool packageDamaged = false,
  }) async =>
      _api.rpcMap('staff_fail_pickup', {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
        'p_package_damaged': packageDamaged,
      });

  Future<List<DeliveryTask>> listDeliveries({String? status, int limit = 50}) async =>
      (await _api.rpcList('staff_list_delivery_assignments', {'p_status': status, 'p_limit': limit}))
          .map(DeliveryTask.fromJson)
          .toList(growable: false);

  Future<DeliveryDetail> getDelivery(String assignmentId) async =>
      DeliveryDetail.fromJson(await _api.rpcMap('staff_get_delivery', {'p_assignment_id': assignmentId}));

  Future<Map<String, dynamic>> acceptDelivery(String assignmentId) async =>
      _api.rpcMap('staff_accept_delivery', {'p_assignment_id': assignmentId});

  Future<Map<String, dynamic>> rejectDelivery(String assignmentId, String reason) async =>
      _api.rpcMap('staff_reject_delivery', {'p_assignment_id': assignmentId, 'p_reason': reason});

  Future<Map<String, dynamic>> markInTransit(String assignmentId, {double? latitude, double? longitude}) async =>
      _api.rpcMap('staff_mark_in_transit', {
        'p_assignment_id': assignmentId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      });

  Future<Map<String, dynamic>> markArrived(String assignmentId, {double? latitude, double? longitude}) async =>
      _api.rpcMap('staff_mark_arrived_at_destination', {
        'p_assignment_id': assignmentId,
        'p_latitude': latitude,
        'p_longitude': longitude,
      });

  Future<Map<String, dynamic>> startOutForDelivery(String assignmentId) async =>
      _api.rpcMap('staff_start_out_for_delivery', {'p_assignment_id': assignmentId});

  Future<Map<String, dynamic>> resendDeliveryOtp(String assignmentId) async =>
      _api.rpcMap('staff_resend_delivery_otp', {'p_assignment_id': assignmentId});

  Future<Map<String, dynamic>> completeDelivery({
    required String assignmentId,
    required String otp,
    String? recipientName,
    String? note,
    String? photoPath,
    double? latitude,
    double? longitude,
    int? codCollectedPaise,
  }) async =>
      _api.rpcMap('staff_complete_delivery', {
        'p_assignment_id': assignmentId,
        'p_otp': otp.trim(),
        'p_recipient_name': recipientName,
        'p_note': note,
        'p_photo_path': photoPath,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_cod_collected_paise': codCollectedPaise,
      });

  Future<Map<String, dynamic>> failDelivery({
    required String assignmentId,
    required String reason,
    String? notes,
    DateTime? nextRetryAt,
  }) async =>
      _api.rpcMap('staff_fail_delivery', {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
        'p_notes': notes,
        'p_next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> updateLocation(double latitude, double longitude) async =>
      _api.rpcMap('staff_update_location', {'p_latitude': latitude, 'p_longitude': longitude});

  Future<Map<String, dynamic>> setAvailability(bool isAvailable) async =>
      _api.rpcMap('staff_set_availability', {'p_is_available': isAvailable});

  Future<StaffCodSummary> codSummary() async =>
      StaffCodSummary.fromJson(await _api.rpcMap('staff_cod_summary'));

  Future<Map<String, dynamic>> declareCashHandover({String? note}) async =>
      _api.rpcMap('staff_declare_cash_handover', {'p_note': note});

  Future<List<NotificationItem>> listNotifications({int limit = 60}) async =>
      (await _api.rpcList('list_my_notifications', {'p_limit': limit}))
          .map(NotificationItem.fromJson)
          .toList(growable: false);

  Future<void> markNotificationRead(String id) async =>
      _api.rpc('mark_notification_read', {'p_notification_id': id});

  Future<String> uploadDeliveryPhoto({
    required String shipmentId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$shipmentId/${DateTime.now().microsecondsSinceEpoch}-$safe';
    await client.storage.from('delivery-proofs').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }
}
