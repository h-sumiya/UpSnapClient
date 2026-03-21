import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

DateTime? tryParseDate(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  return DateTime.tryParse(value)?.toLocal();
}

String formatRelativeDate(DateTime? value) {
  if (value == null) {
    return 'Unknown';
  }

  return timeago.format(value);
}

String formatPreciseDate(DateTime? value) {
  if (value == null) {
    return 'Unknown';
  }

  return DateFormat.yMMMd().add_jm().format(value);
}
