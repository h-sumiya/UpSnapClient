import 'package:cron_parser/cron_parser.dart';
import 'package:intl/intl.dart';

String cronPreview(String expression) {
  final trimmed = expression.trim();
  if (trimmed.isEmpty) {
    return 'No schedule';
  }

  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length != 5) {
    return trimmed;
  }

  try {
    final next = Cron().parse(trimmed, 'UTC').next().toLocal();
    return DateFormat.yMMMd().add_jm().format(next);
  } catch (_) {
    return trimmed;
  }
}
