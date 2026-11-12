import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/order_status.dart';
import 'common.dart';

typedef AuthenticatedBuilder = Widget Function(BuildContext context, Profile profile);

class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.allowedRoles,
    required this.builder,
    required this.tagline,
    required this.purpose,
    this.allowActivation = false,
    this.accent,
  });

  final AuthController controller;
  final Set<String> allowedRoles;
  final AuthenticatedBuilder builder;
  final String tagline;
  final String purpose;
  final bool allowActivation;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        switch (controller.status) {
          case AuthStatus.initializing:
          case AuthStatus.loadingProfile:
            return _AuthScaffold(
              tagline: tagline,
              accent: accent,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: LoadingView(label: 'Signing you in…'),
              ),
            );
          case AuthStatus.signedOut:
            return OtpLoginView(controller: controller, tagline: tagline, purpose: purpose, accent: accent);
          case AuthStatus.error:
            return _AuthScaffold(
              tagline: tagline,
              accent: accent,
              child: SurfaceCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_off_outlined, size: 32, color: IndiBizzColors.danger),
                    const SizedBox(height: 12),
                    Text('Account unavailable', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      controller.error ?? 'Your profile could not be loaded.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: controller.signOut, child: const Text('Sign out')),
                  ],
                ),
              ),
            );
          case AuthStatus.authenticated:
            final profile = controller.profile;
            if (profile == null) {
              return const _AuthScaffold(tagline: '', child: LoadingView());
            }
            if (!profile.isActive) {
              return _AccessDenied(
                title: 'Account suspended',
                message: 'This account is ${profile.status.toLowerCase()}. Contact the IndiaBizz owner to restore access.',
                onSignOut: controller.signOut,
                role: profile.role,
              );
            }
            if (!allowedRoles.contains(profile.role)) {
              if (allowActivation && profile.role == 'CUSTOMER') {
                return _ActivateStaff(
                  controller: controller,
                  tagline: tagline,
                  accent: accent,
                  profile: profile,
                );
              }
              return _AccessDenied(
                title: 'Not available for this account',
                message: 'This app is for ${allowedRoles.map(_roleLabel).join(' and ')} accounts. '
                    'Your account role is ${_roleLabel(profile.role)}.',
                onSignOut: controller.signOut,
                role: profile.role,
              );
            }
            return builder(context, profile);
        }
      },
    );
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'OWNER':
        return 'owner';
      case 'OWN_DELIVERY_STAFF':
        return 'own delivery staff';
      case 'PARTNER_ADMIN':
        return 'partner administrator';
      case 'PARTNER_DELIVERY_STAFF':
        return 'partner delivery staff';
      case 'CUSTOMER':
        return 'customer';
      default:
        return role.toLowerCase();
    }
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.tagline, required this.child, this.accent});
  final String tagline;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            if (!wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const BrandMark(),
                    const SizedBox(height: 26),
                    if (tagline.isNotEmpty)
                      Text(tagline, style: Theme.of(context).textTheme.headlineMedium),
                    if (tagline.isNotEmpty) const SizedBox(height: 22),
                    child,
                  ],
                ),
              );
            }
            return Row(
              children: [
                Expanded(
                  flex: 11,
                  child: Container(
                    height: double.infinity,
                    padding: const EdgeInsets.all(52),
                    decoration: BoxDecoration(
                      color: IndiBizzColors.navy,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0B1F3A), Color(0xFF102E54), Color(0xFF071322)],
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -90,
                          top: -110,
                          child: _Orb(size: 320, color: (accent ?? IndiBizzColors.gold).withValues(alpha: 0.13)),
                        ),
                        Positioned(
                          left: -80,
                          bottom: -160,
                          child: _Orb(size: 380, color: Colors.white.withValues(alpha: 0.04)),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BrandMark(inverse: true),
                            const Spacer(),
                            Text(
                              tagline,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                height: 1.12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(width: 54, height: 3, color: accent ?? IndiBizzColors.gold),
                            const SizedBox(height: 20),
                            Text(
                              'Premium commerce, honest logistics and COD reconciliation in one place.',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 14, height: 1.6),
                            ),
                            const Spacer(),
                            Text(
                              'SECURE • PRIVATE • INDIA-READY',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Container(
                    color: dark ? IndiBizzColors.darkCanvas : IndiBizzColors.canvas,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class OtpLoginView extends StatefulWidget {
  const OtpLoginView({super.key, required this.controller, required this.tagline, required this.purpose, this.accent});
  final AuthController controller;
  final String tagline;
  final String purpose;
  final Color? accent;

  @override
  State<OtpLoginView> createState() => _OtpLoginViewState();
}

class _OtpLoginViewState extends State<OtpLoginView> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _otpFocus = FocusNode();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _timer?.cancel();
    setState(() => _cooldown = seconds);
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _sendOtp() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.controller.requestOtp(_phone.text, purpose: widget.purpose);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _codeSent = true;
        _startCooldown(result.cooldownSeconds > 0 ? result.cooldownSeconds : 30);
        WidgetsBinding.instance.addPostFrameCallback((_) => _otpFocus.requestFocus());
      } else {
        _error = result.message ?? 'The OTP could not be sent.';
      }
    });
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.verifyOtp(_phone.text, _otp.text);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = widget.controller.error ?? error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = widget.accent ?? IndiBizzColors.gold;
    return _AuthScaffold(
      tagline: widget.tagline,
      accent: accent,
      child: SurfaceCard(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: IndiBizzColors.navy, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 21),
            ),
            const SizedBox(height: 18),
            Text(_codeSent ? 'Enter the OTP' : 'Sign in with your mobile', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 7),
            Text(
              _codeSent
                  ? 'We sent a 6-digit code to ${formatPhone(normalizePhone(_phone.text))}. It expires in 5 minutes.'
                  : 'Use the phone number registered with IndiaBizz. We send a real SMS OTP — no passwords, no shortcuts.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 22),
            Text('Mobile number', style: theme.textTheme.labelMedium),
            const SizedBox(height: 7),
            TextField(
              controller: _phone,
              enabled: !_codeSent && !_busy,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]'))],
              decoration: InputDecoration(
                hintText: '98765 43210',
                prefixText: '+91  ',
                prefixIcon: const Icon(Icons.phone_iphone_rounded, size: 19),
              ),
              onSubmitted: (_) => _sendOtp(),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              Text('6-digit OTP', style: theme.textTheme.labelMedium),
              const SizedBox(height: 7),
              TextField(
                controller: _otp,
                focusNode: _otpFocus,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 10),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                onSubmitted: (_) => _verify(),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _cooldown == 0 && !_busy && !_codeSent ? null : (_cooldown == 0 && !_busy ? _sendOtp : null),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(_cooldown > 0 ? 'Resend in ${_cooldown}s' : 'Resend OTP'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() {
                      _codeSent = false;
                      _otp.clear();
                      _error = null;
                    }),
                    child: const Text('Change number'),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 6),
              InlineNotice(message: _error!, tone: StatusTone.danger, title: 'OTP not sent'),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || (_codeSent && _otp.text.length != 6) ? null : (_codeSent ? _verify : _sendOtp),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_codeSent ? 'Verify & sign in' : 'Send OTP'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: dark ? IndiBizzColors.darkInkMuted : IndiBizzColors.inkMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Your session is stored securely on this device. Never share your OTP.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.title, required this.message, required this.onSignOut, required this.role});
  final String title;
  final String message;
  final VoidCallback onSignOut;
  final String role;

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      tagline: 'Private access',
      child: SurfaceCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_outlined, size: 36, color: IndiBizzColors.warning),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Signed in as $role', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }
}

class _ActivateStaff extends StatefulWidget {
  const _ActivateStaff({required this.controller, required this.tagline, required this.profile, this.accent});
  final AuthController controller;
  final String tagline;
  final Profile profile;
  final Color? accent;

  @override
  State<_ActivateStaff> createState() => _ActivateStaffState();
}

class _ActivateStaffState extends State<_ActivateStaff> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.redeemStaffInvite(_code.text);
      if (mounted) showToast(context, 'Staff access activated.');
    } catch (error) {
      if (mounted) setState(() => _error = _clean(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object error) {
    final text = error.toString();
    if (text.contains('Activation code is invalid')) return 'Activation code is invalid or expired. Ask your manager for a new one.';
    if (text.contains('already provisioned')) return 'This account is already a staff account. Sign in to the correct app.';
    return text.replaceFirst('PostgrestException(message: ', '').split(', code:').first;
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      tagline: widget.tagline,
      accent: widget.accent,
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.badge_outlined, size: 32, color: IndiBizzColors.gold),
            const SizedBox(height: 14),
            Text('Activate staff access', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 7),
            Text(
              'Welcome, ${widget.profile.fullName}. Your mobile is verified but not yet linked to a delivery team. '
              'Enter the single-use activation code issued by the owner or your partner manager.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              maxLength: 12,
              decoration: const InputDecoration(labelText: 'Activation code', counterText: '', hintText: 'ABC123XYZ0'),
              onSubmitted: (_) => _redeem(),
            ),
            if (_error != null) ...[const SizedBox(height: 10), InlineNotice(message: _error!, tone: StatusTone.danger)],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy || _code.text.trim().length < 6 ? null : _redeem,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Activate access'),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: widget.controller.signOut, child: const Text('Use a different number')),
          ],
        ),
      ),
    );
  }
}

/// A small role badge used in account screens.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: IndiBizzColors.navy,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role.replaceAll('_', ' '),
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6),
      ),
    );
  }
}

/// Shared theme mode button for app bars.
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key, required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = mode == ThemeMode.dark;
    return IconButton(
      tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 20),
      onPressed: () => onChanged(isDark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}

/// Common configuration banner used when --dart-define values are missing.
class ConfigurationMissing extends StatelessWidget {
  const ConfigurationMissing({super.key, this.appLabel = AppConfig.appName});
  final String appLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SurfaceCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 24),
                  Text('$appLabel needs backend configuration', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Build or run this app with the Supabase URL and anon key:',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: IndiBizzColors.canvas, borderRadius: BorderRadius.circular(10)),
                    child: const SelectableText(
                      'flutter run \\\n'
                      '  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \\\n'
                      '  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Never embed a service-role key in a Flutter app. Only the public anon key is used.',
                    style: TextStyle(fontSize: 12, color: IndiBizzColors.inkMuted, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
