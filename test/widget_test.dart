import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:upsnap_client/app/app.dart';

void main() {
  testWidgets('shows connection screen without saved server', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: UpSnapApp()));

    await tester.pumpAndSettle();

    expect(find.text('Connect to UpSnap'), findsOneWidget);
  });
}
