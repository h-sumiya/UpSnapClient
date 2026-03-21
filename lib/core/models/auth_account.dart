import 'package:pocketbase/pocketbase.dart';

class AuthAccount {
  const AuthAccount({
    required this.id,
    required this.isSuperuser,
    required this.avatar,
    required this.displayName,
    this.username,
    this.email,
    required this.collectionName,
  });

  final String id;
  final bool isSuperuser;
  final int avatar;
  final String displayName;
  final String? username;
  final String? email;
  final String collectionName;

  factory AuthAccount.fromRecord(RecordModel record) {
    final collectionName = record.collectionName;
    final isSuperuser = collectionName == '_superusers';
    final email = record.getStringValue('email');
    final username = record.getStringValue('username');

    return AuthAccount(
      id: record.id,
      isSuperuser: isSuperuser,
      avatar: record.getIntValue('avatar', 0),
      displayName: isSuperuser ? email : (username.isEmpty ? email : username),
      username: username.isEmpty ? null : username,
      email: email.isEmpty ? null : email,
      collectionName: collectionName,
    );
  }
}
