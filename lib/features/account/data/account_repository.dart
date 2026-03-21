import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../session/application/session_controller.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  AccountRepository.new,
);

class AccountRepository {
  const AccountRepository(this.ref);

  final Ref ref;

  PocketBase get _client {
    final client = ref.read(pocketBaseProvider);
    if (client == null) {
      throw StateError('PocketBase client is not initialized.');
    }
    return client;
  }

  Future<void> updateAvatar({
    required bool isSuperuser,
    required String id,
    required int avatar,
  }) async {
    await _client
        .collection(isSuperuser ? '_superusers' : 'users')
        .update(id, body: {'avatar': avatar});
  }

  Future<void> changePassword({
    required bool isSuperuser,
    required String id,
    required String oldPassword,
    required String newPassword,
    required String passwordConfirm,
  }) async {
    final body = isSuperuser
        ? {'password': newPassword, 'passwordConfirm': passwordConfirm}
        : {
            'oldPassword': oldPassword,
            'password': newPassword,
            'passwordConfirm': passwordConfirm,
          };

    await _client
        .collection(isSuperuser ? '_superusers' : 'users')
        .update(id, body: body);
  }
}
