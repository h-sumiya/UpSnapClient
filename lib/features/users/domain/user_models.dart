import 'package:collection/collection.dart';
import 'package:pocketbase/pocketbase.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.avatar,
  });

  final String id;
  final String username;
  final String email;
  final int avatar;

  factory UserModel.fromRecord(RecordModel record) {
    return UserModel(
      id: record.id,
      username: record.getStringValue('username'),
      email: record.getStringValue('email'),
      avatar: record.getIntValue('avatar', 0),
    );
  }
}

class PermissionModel {
  const PermissionModel({
    this.id,
    required this.userId,
    required this.create,
    required this.read,
    required this.update,
    required this.delete,
    required this.power,
  });

  final String? id;
  final String userId;
  final bool create;
  final List<String> read;
  final List<String> update;
  final List<String> delete;
  final List<String> power;

  factory PermissionModel.fromRecord(RecordModel record) {
    return PermissionModel(
      id: record.id,
      userId: record.getStringValue('user'),
      create: record.getBoolValue('create'),
      read: record.getListValue<String>('read', const <String>[]),
      update: record.getListValue<String>('update', const <String>[]),
      delete: record.getListValue<String>('delete', const <String>[]),
      power: record.getListValue<String>('power', const <String>[]),
    );
  }

  factory PermissionModel.empty(String userId) {
    return PermissionModel(
      userId: userId,
      create: false,
      read: const <String>[],
      update: const <String>[],
      delete: const <String>[],
      power: const <String>[],
    );
  }

  bool canRead(String deviceId) => read.contains(deviceId);

  bool canUpdate(String deviceId) => update.contains(deviceId);

  bool canDelete(String deviceId) => delete.contains(deviceId);

  bool canPower(String deviceId) => power.contains(deviceId);

  bool get canCreateDevices => create;

  Map<String, dynamic> toBody() {
    return {
      'user': userId,
      'create': create,
      'read': read,
      'update': update,
      'delete': delete,
      'power': power,
    };
  }

  PermissionModel copyWith({
    String? id,
    String? userId,
    bool? create,
    List<String>? read,
    List<String>? update,
    List<String>? delete,
    List<String>? power,
  }) {
    return PermissionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      create: create ?? this.create,
      read: read ?? this.read,
      update: update ?? this.update,
      delete: delete ?? this.delete,
      power: power ?? this.power,
    );
  }
}

extension PermissionListX on Iterable<PermissionModel> {
  PermissionModel forUser(String userId) =>
      firstWhereOrNull((permission) => permission.userId == userId) ??
      PermissionModel.empty(userId);
}
