import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upsnap_client/core/storage/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPreferences login credentials', () {
    test('stores and clears remembered login credentials', () async {
      SharedPreferences.setMockInitialValues({});

      final preferences = await AppPreferences.create();
      expect(preferences.rememberLogin, isFalse);
      expect(preferences.savedLoginCredentials, isNull);

      await preferences.saveLoginCredentials(
        identity: ' user@example.com ',
        password: 'secret',
      );

      final credentials = preferences.savedLoginCredentials;
      expect(preferences.rememberLogin, isTrue);
      expect(credentials?.identity, 'user@example.com');
      expect(credentials?.password, 'secret');

      await preferences.clearLoginCredentials();

      expect(preferences.rememberLogin, isFalse);
      expect(preferences.savedLoginCredentials, isNull);
    });
  });
}
