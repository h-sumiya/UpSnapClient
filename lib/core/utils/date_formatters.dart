import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

DateTime? tryParseDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toLocal();
}

String formatRelativeDate(DateTime? value, {String? locale}) {
  final resolvedLocale = locale == 'ja' ? 'ja' : 'en';
  if (value == null) {
    return resolvedLocale == 'ja' ? '不明' : 'Unknown';
  }

  return timeago.format(value, locale: resolvedLocale);
}

String formatPreciseDate(DateTime? value, {String? locale}) {
  final resolvedLocale = locale == 'ja' ? 'ja' : 'en';
  if (value == null) {
    return resolvedLocale == 'ja' ? '不明' : 'Unknown';
  }

  return DateFormat.yMMMd(resolvedLocale).add_jm().format(value);
}
