import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../core/models/auth_account.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/utils/error_message.dart';
import '../../../core/utils/url_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/domain/settings_models.dart';
import '../../users/domain/user_models.dart';
import '../domain/app_session_state.dart';

final sessionControllerProvider =
    NotifierProvider<SessionController, AppSessionState>(SessionController.new);

final pocketBaseProvider = Provider<PocketBase?>((ref) {
  return ref.watch(sessionControllerProvider).client;
});

final authAccountProvider = Provider<AuthAccount?>((ref) {
  return ref.watch(sessionControllerProvider).account;
});

final permissionProvider = Provider<PermissionModel?>((ref) {
  return ref.watch(sessionControllerProvider).permission;
});

class SessionController extends Notifier<AppSessionState> {
  AppPreferences? _preferences;
  bool _initialized = false;

  @override
  AppSessionState build() {
    if (!_initialized) {
      _initialized = true;
      unawaited(_initialize());
    }

    return AppSessionState.loading();
  }

  Future<void> _initialize() async {
    state = AppSessionState.loading();
    _preferences = await AppPreferences.create();

    final serverUrl = _preferences?.serverUrl;
    if (serverUrl == null) {
      state = const AppSessionState(stage: SessionStage.serverConfig);
      return;
    }

    await connect(serverUrl, preserveAuth: true);
  }

  Future<void> connect(String rawUrl, {bool preserveAuth = false}) async {
    try {
      final normalizedUrl = normalizeBaseUrl(rawUrl);
      final previousUrl = state.serverUrl;
      final sameServer = previousUrl == normalizedUrl;
      final initialAuth = preserveAuth && sameServer
          ? _preferences?.pocketBaseAuth
          : null;

      await _preferences?.setServerUrl(normalizedUrl);
      if (!sameServer) {
        await _preferences?.clearPocketBaseAuth();
      }

      state = state.copyWith(
        stage: SessionStage.loading,
        serverUrl: normalizedUrl,
        busy: true,
        clearError: true,
      );

      final client = PocketBase(
        normalizedUrl,
        authStore: AsyncAuthStore(
          save: (value) async => _preferences?.savePocketBaseAuth(value),
          clear: () async => _preferences?.clearPocketBaseAuth(),
          initial: initialAuth,
        ),
      );

      final publicSettings = await _readPublicSettings(client);
      final nextState = await _buildConnectedState(
        client: client,
        serverUrl: normalizedUrl,
        publicSettings: publicSettings,
      );
      state = nextState;
    } catch (error) {
      state = AppSessionState(
        stage: SessionStage.serverConfig,
        serverUrl: rawUrl.trim(),
        errorMessage: errorMessage(error),
      );
    }
  }

  Future<void> disconnect() async {
    await _preferences?.clearPocketBaseAuth();
    await _preferences?.clearServerUrl();
    state = const AppSessionState(stage: SessionStage.serverConfig);
  }

  void showServerConfiguration() {
    state = state.copyWith(
      stage: SessionStage.serverConfig,
      busy: false,
      clearError: true,
    );
  }

  Future<void> refresh() async {
    final serverUrl = state.serverUrl;
    if (serverUrl == null) {
      return;
    }

    await connect(serverUrl, preserveAuth: true);
  }

  Future<void> login({
    required String identity,
    required String password,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.login(identity: identity, password: password);
    await refresh();
  }

  Future<void> loginWithOAuth(String providerName) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.loginWithOAuth(providerName);
    await refresh();
  }

  Future<void> initializeSuperuser({
    required String email,
    required String password,
    required String passwordConfirm,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.initializeSuperuser(
      email: email,
      password: password,
      passwordConfirm: passwordConfirm,
    );
    await refresh();
  }

  Future<void> logout() async {
    final client = state.client;
    if (client != null) {
      client.authStore.clear();
      await _preferences?.clearPocketBaseAuth();
    }

    state = state.copyWith(
      stage: SessionStage.login,
      clearAccount: true,
      clearPermission: true,
      busy: false,
      clearError: true,
    );
  }

  void updatePublicSettings(PublicSettings settings) {
    state = state.copyWith(publicSettings: settings);
  }

  Future<PublicSettings> _readPublicSettings(PocketBase client) async {
    final record = await client
        .collection('settings_public')
        .getFirstListItem('');
    return PublicSettings.fromRecord(record);
  }

  Future<AppSessionState> _buildConnectedState({
    required PocketBase client,
    required String serverUrl,
    required PublicSettings publicSettings,
  }) async {
    if (!publicSettings.setupCompleted) {
      return AppSessionState(
        stage: SessionStage.welcome,
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
        busy: false,
      );
    }

    if (!client.authStore.isValid || client.authStore.record == null) {
      return AppSessionState(
        stage: SessionStage.login,
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
        busy: false,
      );
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.refreshCurrentAuth(client);
    } catch (_) {
      client.authStore.clear();
      await _preferences?.clearPocketBaseAuth();

      return AppSessionState(
        stage: SessionStage.login,
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
        busy: false,
      );
    }

    final record = client.authStore.record;
    if (record == null) {
      return AppSessionState(
        stage: SessionStage.login,
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
        busy: false,
      );
    }

    final account = AuthAccount.fromRecord(record);
    final permission = account.isSuperuser
        ? null
        : await repository.fetchPermissionForUser(account.id, client: client);

    return AppSessionState(
      stage: SessionStage.authenticated,
      client: client,
      serverUrl: serverUrl,
      publicSettings: publicSettings,
      account: account,
      permission: permission,
      busy: false,
    );
  }
}
