import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../models/models.dart';

class PartnerRepository {
  PartnerRepository(this.client) : _api = ApiClient(client);

  final SupabaseClient client;
  final ApiClient _api;

  Future<PartnerDashboard> dashboard() async => PartnerDashboard.fromJson(await _api.rpcMap('partner_dashboard'));

  Future<List<PartnerStaff>> listStaff() async =>
      (await _api.rpcList('partner_list_staff')).map(PartnerStaff.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> setStaffAvailability(String staffUserId, bool isAvailable) async =>
      _api.rpcMap('partner_set_staff_availability', {
        'p_staff_user_id': staffUserId,
        'p_is_available': isAvailable,
      });

  Future<StaffInvite> createStaffInvite({required String phone, required String displayName}) async =>
      StaffInvite.fromJson(await _api.rpcMap('partner_create_staff_invite', {
        'p_phone': phone,
        'p_display_name': displayName,
      }));

  Future<List<StaffInvite>> listInvites() async =>
      (await _api.rpcList('partner_list_invites')).map(StaffInvite.fromJson).toList(growable: false);

  Future<void> revokeInvite(String inviteId) async =>
      _api.rpc('partner_revoke_invite', {'p_invite_id': inviteId});

  Future<List<PartnerTask>> listTasks() async =>
      (await _api.rpcList('partner_list_tasks')).map(PartnerTask.fromJson).toList(growable: false);

  Future<Map<String, dynamic>> suspendStaff(String staffUserId, String reason) async =>
      _api.rpcMap('partner_suspend_staff', {'p_staff_user_id': staffUserId, 'p_reason': reason});

  Future<Map<String, dynamic>> reactivateStaff(String staffUserId) async =>
      _api.rpcMap('partner_reactivate_staff', {'p_staff_user_id': staffUserId});
}
