import 'package:cron_parser/cron_parser.dart';
import 'package:intl/intl.dart';

String cronPreview(String expression, {String? locale}) {
  final resolvedLocale = locale == 'ja' ? 'ja' : 'en';
  final trimmed = expression.trim();
  if (trimmed.isEmpty) {
    return resolvedLocale == 'ja' ? 'スケジュールなし' : 'No schedule';
  }

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length != 5) {
    return trimmed;
  }

  try {
    final next = Cron().parse(trimmed, 'UTC').next().toLocal();
    return DateFormat.yMMMd(resolvedLocale).add_jm().format(next);
  } catch (_) {
    return trimmed;
  }
}
