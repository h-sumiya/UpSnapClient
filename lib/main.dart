import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  timeago.setLocaleMessages('en', timeago.EnMessages());
  timeago.setLocaleMessages('ja', timeago.JaMessages());
  runApp(const ProviderScope(child: UpSnapApp()));
}
