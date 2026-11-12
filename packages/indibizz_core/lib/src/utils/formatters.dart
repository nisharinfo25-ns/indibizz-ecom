import 'package:intl/intl.dart';

import '../config/app_config.dart';

/// Money is always an integer number of paise. Never use floating point for
/// arithmetic; these helpers only format values supplied by the database.
String formatMoney(int paise, {bool withSymbol = true}) {
  final negative = paise < 0;
  final absolute = paise.abs();
  final rupees = absolute ~/ 100;
  final fraction = absolute % 100;
  final grouped = _groupIndian(rupees.toString());
  final body = fraction == 0 ? grouped : '$grouped.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}${withSymbol ? '\u20B9' : ''}$body';
}

String formatMoneyCompact(int paise) {
  final value = paise / 100;
  if (value.abs() >= 10000000) return '\u20B9${(value / 10000000).toStringAsFixed(2)} Cr';
  if (value.abs() >= 100000) return '\u20B9${(value / 100000).toStringAsFixed(2)} L';
  if (value.abs() >= 1000) return '\u20B9${(value / 1000).toStringAsFixed(1)}k';
  return formatMoney(paise);
}

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Parses a user-entered rupee amount into paise without floating point drift.
int? parseRupeesToPaise(String input) {
  final normalized = input.replaceAll(',', '').replaceAll('\u20B9', '').trim();
  if (normalized.isEmpty) return null;
  final match = RegExp(r'^(\d+)(?:\.(\d{0,2}))?$').firstMatch(normalized);
  if (match == null) return null;
  final rupees = int.parse(match.group(1)!);
  final fractionText = (match.group(2) ?? '').padRight(2, '0');
  final fraction = fractionText.isEmpty ? 0 : int.parse(fractionText);
  return rupees * 100 + fraction;
}

String formatDateTime(DateTime? value, {bool includeYear = false}) {
  if (value == null) return '—';
  final local = value.toLocal();
  return DateFormat(includeYear ? 'd MMM yyyy, h:mm a' : 'd MMM, h:mm a').format(local);
}

String formatDate(DateTime? value, {bool includeYear = true}) {
  if (value == null) return '—';
  return DateFormat(includeYear ? 'd MMM yyyy' : 'd MMM').format(value.toLocal());
}

String relativeTime(DateTime? value) {
  if (value == null) return '—';
  final diff = DateTime.now().difference(value.toLocal());
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return formatDate(value, includeYear: false);
}

String formatWeight(int? grams) {
  if (grams == null || grams <= 0) return '—';
  if (grams >= 1000) return '${(grams / 1000).toStringAsFixed(grams % 1000 == 0 ? 0 : 1)} kg';
  return '$grams g';
}

String formatPhone(String? phone) {
  if (phone == null || phone.isEmpty) return '—';
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
  }
  if (digits.length == 10) return '${digits.substring(0, 5)} ${digits.substring(5)}';
  return phone;
}

String maskPhone(String? phone) {
  if (phone == null || phone.length < 6) return '—';
  return '${phone.substring(0, phone.length - 6)}******';
}

String normalizePhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) digits = '91$digits';
  if (digits.startsWith('0') && digits.length == 11) digits = '91${digits.substring(1)}';
  return digits.isEmpty ? '' : '+$digits';
}

bool isValidPhone(String input) => RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalizePhone(input));

String appName = AppConfig.appName;

String titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_\s]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
      .join(' ');
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'IB';
  if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
