import 'package:flutter_test/flutter_test.dart';
import 'package:upsnap_client/features/session/application/session_controller.dart';

void main() {
  group('shouldRestoreStoredAuth', () {
    test('restores auth on startup when saved server matches', () {
      expect(
        shouldRestoreStoredAuth(
          preserveAuth: true,
          normalizedUrl: 'https://upsnap.example.com',
          activeServerUrl: null,
          savedServerUrl: 'https://upsnap.example.com',
        ),
        isTrue,
      );
    });

    test('does not restore auth when switching servers', () {
      expect(
        shouldRestoreStoredAuth(
          preserveAuth: true,
          normalizedUrl: 'https://other.example.com',
          activeServerUrl: 'https://upsnap.example.com',
          savedServerUrl: 'https://upsnap.example.com',
        ),
        isFalse,
      );
    });
  });
}
