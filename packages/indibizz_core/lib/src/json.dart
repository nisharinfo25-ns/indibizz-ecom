/// Small, defensive JSON readers used by every model factory.
library;

Map<String, dynamic> jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> jsonList(Object? value) {
  if (value is List) return value.map(jsonMap).where((item) => item.isNotEmpty || value.isEmpty).toList();
  return const <Map<String, dynamic>>[];
}

List<String> jsonStringList(Object? value) {
  if (value is List) return value.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
  return const <String>[];
}

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
}

String? asNullableString(Object? value) {
  final text = asString(value);
  return text.isEmpty ? null : text;
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double asDouble(Object? value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true' || text == '1') return true;
  if (text == 'false' || text == '0') return false;
  return fallback;
}

DateTime? asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toUtc();
}

DateTime asRequiredDate(Object? value) => asDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// PostgreSQL `jsonb_agg` returns null for empty sets. Owners of payloads can
/// safely map it with this helper.
List<T> mapJsonList<T>(Object? value, T Function(Map<String, dynamic>) build) =>
    jsonList(value).map(build).toList(growable: false);
