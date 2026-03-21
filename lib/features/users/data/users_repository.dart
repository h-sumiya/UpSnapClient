import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../devices/domain/device_models.dart';
import '../../session/application/session_controller.dart';
import '../domain/user_models.dart';

final usersRepositoryProvider = Provider<UsersRepository>(UsersRepository.new);

class UsersRepository {
  const UsersRepository(this.ref);

  final Ref ref;

  PocketBase get _client {
    final client = ref.read(pocketBaseProvider);
    if (client == null) {
      throw StateError('PocketBase client is not initialized.');
    }
    return client;
  }

  Future<List<UserModel>> fetchUsers() async {
    final records = await _client
        .collection('users')
        .getFullList(sort: 'username');
    return records.map(UserModel.fromRecord).toList();
  }

  Future<List<PermissionModel>> fetchPermissions() async {
    final records = await _client.collection('permissions').getFullList();
    return records.map(PermissionModel.fromRecord).toList();
  }

  Future<List<DeviceModel>> fetchDevices() async {
    final records = await _client
        .collection('devices')
        .getFullList(sort: 'name');
    return records.map(DeviceModel.fromRecord).toList();
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String passwordConfirm,
  }) async {
    await _client
        .collection('users')
        .create(
          body: {
            'username': username.trim(),
            'password': password,
            'passwordConfirm': passwordConfirm,
          },
        );
  }

  Future<void> deleteUser(UserModel user, PermissionModel? permission) async {
    if (permission?.id != null) {
      await _client.collection('permissions').delete(permission!.id!);
    }
    await _client.collection('users').delete(user.id);
  }

  Future<PermissionModel> savePermission(PermissionModel permission) async {
    final record = permission.id == null
        ? await _client
              .collection('permissions')
              .create(body: permission.toBody())
        : await _client
              .collection('permissions')
              .update(permission.id!, body: permission.toBody());
    return PermissionModel.fromRecord(record);
  }
}
