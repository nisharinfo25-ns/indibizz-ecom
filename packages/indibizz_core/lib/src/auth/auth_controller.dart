import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

enum AuthStatus { initializing, signedOut, loadingProfile, authenticated, error }

class AuthController extends ChangeNotifier {
  AuthController(this.client) {
    _api = ApiClient(client);
    _subscription = client.auth.onAuthStateChange.listen(_onAuthChange);
  }

  final SupabaseClient client;
  late final ApiClient _api;
  StreamSubscription<AuthState>? _subscription;

  AuthStatus _status = AuthStatus.initializing;
  Session? _session;
  Profile? _profile;
  String? _error;

  AuthStatus get status => _status;
  Session? get session => _session;
  Profile? get profile => _profile;
  String? get error => _error;
  bool get isAuthenticated => _status == AuthStatus.authenticated && _profile != null;
  String get role => _profile?.role ?? '';

  Future<void> initialize() async {
    final current = client.auth.currentSession;
    if (current == null) {
      _setSignedOut();
      return;
    }
    _session = current;
    await _loadProfile();
  }

  void _onAuthChange(AuthState state) {
    final session = state.session;
    if (session == null) {
      _session = null;
      _profile = null;
      _setSignedOut();
      return;
    }
    final changedUser = _session?.user.id != session.user.id;
    _session = session;
    if (changedUser || _profile == null) {
      unawaited(_loadProfile());
    }
  }

  Future<RequestOtpResult> requestOtp(String phone, {String purpose = 'customer'}) async {
    final normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) {
      return const RequestOtpResult(
        ok: false,
        errorCode: 'invalid_phone',
        message: 'Enter a valid 10-digit Indian mobile number.',
      );
    }
    _error = null;
    return _api.requestOtp(normalized, purpose: purpose);
  }

  Future<void> verifyOtp(String phone, String code) async {
    final normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) {
      throw const AuthException('Enter a valid mobile number.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const AuthException('Enter the 6-digit OTP sent to your phone.');
    }
    _status = AuthStatus.loadingProfile;
    _error = null;
    notifyListeners();
    try {
      final response = await client.auth.verifyOTP(
        phone: normalized,
        token: code.trim(),
        type: OtpType.sms,
      );
      _session = response.session;
      await _loadProfile();
    } on AuthException catch (error) {
      _status = AuthStatus.signedOut;
      _error = _friendlyAuthError(error.message);
      notifyListeners();
      rethrow;
    } catch (error) {
      _status = AuthStatus.signedOut;
      _error = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadProfile() async {
    _status = AuthStatus.loadingProfile;
    notifyListeners();
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final data = await _api.rpcMap('get_my_profile');
        if (data.isNotEmpty) {
          _profile = Profile.fromJson(data);
          _status = AuthStatus.authenticated;
          _error = null;
          notifyListeners();
          return;
        }
      } catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
    }
    _profile = null;
    _status = AuthStatus.error;
    _error = lastError == null
        ? 'Your profile could not be loaded. Ask the owner to verify your account.'
        : 'Could not load your profile: $lastError';
    notifyListeners();
  }

  Future<void> refreshProfile() => _loadProfile();

  Future<void> redeemStaffInvite(String code) async {
    await _api.rpc('redeem_staff_invite', {'p_code': code.trim().toUpperCase()});
    await _loadProfile();
  }

  Future<void> signOut() async {
    await client.auth.signOut();
    _profile = null;
    _session = null;
    _setSignedOut();
  }

  void _setSignedOut() {
    _status = AuthStatus.signedOut;
    _error = null;
    notifyListeners();
  }

  String _friendlyAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('otp') && (lower.contains('expired') || lower.contains('invalid'))) {
      return 'That OTP is invalid or has expired. Request a new code.';
    }
    if (lower.contains('rate') || lower.contains('too many')) {
      return 'Too many attempts. Please wait a few minutes before trying again.';
    }
    return message;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
