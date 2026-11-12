import 'package:supabase_flutter/supabase_flutter.dart';

import '../json.dart';

class RequestOtpResult {
  const RequestOtpResult({required this.ok, this.errorCode, this.message, this.cooldownSeconds = 0});
  final bool ok;
  final String? errorCode;
  final String? message;
  final int cooldownSeconds;
}

/// Thin typed wrapper around Supabase. All catalogue reads go through RLS;
/// every commerce write goes through a SECURITY DEFINER RPC.
class ApiClient {
  ApiClient(this.client);

  final SupabaseClient client;

  Future<dynamic> rpc(String function, [Map<String, dynamic> params = const {}]) async {
    return client.rpc(function, params: params);
  }

  Future<Map<String, dynamic>> rpcMap(String function, [Map<String, dynamic> params = const {}]) async {
    final data = await rpc(function, params);
    return jsonMap(data);
  }

  Future<List<Map<String, dynamic>>> rpcList(String function, [Map<String, dynamic> params = const {}]) async {
    final data = await rpc(function, params);
    return jsonList(data);
  }

  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, dynamic>? eq,
    String? order,
    bool ascending = false,
    int? limit,
  }) async {
    dynamic query = client.from(table).select(columns);
    if (eq != null) {
      for (final entry in eq.entries) {
        query = query.eq(entry.key, entry.value);
      }
    }
    if (order != null) {
      query = query.order(order, ascending: ascending);
    }
    if (limit != null) {
      query = query.limit(limit);
    }
    final rows = await query;
    return jsonList(rows);
  }

  Future<Map<String, dynamic>?> selectSingle(String table, String column, Object value, {String columns = '*'}) async {
    final row = await client.from(table).select(columns).eq(column, value).maybeSingle();
    if (row == null) return null;
    return jsonMap(row);
  }

  Future<String?> storageSignedUrl(String bucket, String? path, {int seconds = 3600}) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await client.storage.from(bucket).createSignedUrl(path, seconds);
    } catch (_) {
      return null;
    }
  }

  /// Requests a real SMS OTP through the rate-limited Edge Function. It never
  /// simulates success: when the provider is unavailable the precise error is
  /// returned to the caller for display.
  Future<RequestOtpResult> requestOtp(String phone, {String purpose = 'customer'}) async {
    try {
      final response = await client.functions.invoke(
        'request-otp',
        body: {'phone': phone, 'purpose': purpose},
      );
      final data = jsonMap(response.data);
      return RequestOtpResult(
        ok: asBool(data['ok']),
        errorCode: asNullableString(data['error_code']),
        message: asNullableString(data['message']),
        cooldownSeconds: asInt(data['cooldown_seconds']),
      );
    } on FunctionException catch (error) {
      final details = error.details;
      final data = jsonMap(details);
      return RequestOtpResult(
        ok: false,
        errorCode: asNullableString(data['error_code']) ?? 'otp_request_failed',
        message: asNullableString(data['message']) ??
            _functionErrorMessage(error),
        cooldownSeconds: asInt(data['cooldown_seconds']),
      );
    } catch (error) {
      return RequestOtpResult(
        ok: false,
        errorCode: 'network_error',
        message: 'Could not reach the OTP service. Check your internet connection and try again. ($error)',
      );
    }
  }

  String _functionErrorMessage(FunctionException error) {
    switch (error.status) {
      case 400:
        return 'Enter a valid mobile number.';
      case 429:
        return 'Too many OTP requests. Please wait before trying again.';
      case 503:
        return 'SMS OTP is not configured on the server yet. Ask the owner to enable Phone auth and an SMS provider.';
      default:
        return 'The OTP service returned HTTP ${error.status}.';
    }
  }
}
