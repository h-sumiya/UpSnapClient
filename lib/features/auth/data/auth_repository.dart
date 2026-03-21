import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../session/application/session_controller.dart';
import '../../users/domain/user_models.dart';

final authRepositoryProvider = Provider<AuthRepository>(AuthRepository.new);

class AuthRepository {
  const AuthRepository(this.ref);

  final Ref ref;

  PocketBase get _client {
    final client = ref.read(pocketBaseProvider);
    if (client == null) {
      throw StateError('PocketBase client is not initialized.');
    }
    return client;
  }

  Future<void> login({
    required String identity,
    required String password,
  }) async {
    try {
      await _client
          .collection('_superusers')
          .authWithPassword(identity, password);
    } catch (_) {
      await _client.collection('users').authWithPassword(identity, password);
    }
  }

  Future<List<AuthMethodProvider>> listOAuthProviders() async {
    final methods = await _client.collection('users').listAuthMethods();
    if (!methods.oauth2.enabled) {
      return const <AuthMethodProvider>[];
    }

    return methods.oauth2.providers;
  }

  Future<void> loginWithOAuth(String providerName) async {
    await _client.collection('users').authWithOAuth2(providerName, (url) async {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    });
  }

  Future<void> initializeSuperuser({
    required String email,
    required String password,
    required String passwordConfirm,
  }) async {
    await _client.send<Map<String, dynamic>>(
      '/api/upsnap/init-superuser',
      method: 'POST',
      body: {
        'email': email.trim(),
        'password': password,
        'password_confirm': passwordConfirm,
      },
    );
    await _client
        .collection('_superusers')
        .authWithPassword(email.trim(), password);
  }

  Future<void> refreshCurrentAuth([PocketBase? client]) async {
    final activeClient = client ?? _client;
    final record = activeClient.authStore.record;
    if (record == null) {
      return;
    }

    if (record.collectionName == '_superusers') {
      await activeClient.collection('_superusers').authRefresh();
    } else {
      await activeClient.collection('users').authRefresh();
    }
  }

  Future<PermissionModel?> fetchPermissionForUser(
    String userId, {
    PocketBase? client,
  }) async {
    final activeClient = client ?? _client;

    try {
      final record = await activeClient
          .collection('permissions')
          .getFirstListItem(
            activeClient.filter("user.id = {:userId}", {'userId': userId}),
          );
      return PermissionModel.fromRecord(record);
    } catch (_) {
      return null;
    }
  }
}
