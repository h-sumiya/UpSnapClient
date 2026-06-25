import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

@visibleForTesting
bool shouldRestoreStoredAuth({
  required bool preserveAuth,
  required String normalizedUrl,
  String? activeServerUrl,
  String? savedServerUrl,
}) {
  if (!preserveAuth) {
    return false;
  }

  final currentServerUrl = activeServerUrl ?? savedServerUrl;
  return currentServerUrl == normalizedUrl;
}

class SessionController extends Notifier<AppSessionState> {
  AppPreferences? _preferences;
  Timer? _authRenewalTimer;
  bool _initialized = false;

  @override
  AppSessionState build() {
    ref.onDispose(() => _authRenewalTimer?.cancel());

    if (!_initialized) {
      _initialized = true;
      unawaited(_initialize());
    }

    return AppSessionState.loading();
  }

  bool get rememberLogin => _preferences?.rememberLogin ?? false;

  SavedLoginCredentials? get savedLoginCredentials =>
      _preferences?.savedLoginCredentials;

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
      final sameServer = shouldRestoreStoredAuth(
        preserveAuth: preserveAuth,
        normalizedUrl: normalizedUrl,
        activeServerUrl: state.serverUrl,
        savedServerUrl: _preferences?.serverUrl,
      );
      final initialAuth = sameServer ? _preferences?.pocketBaseAuth : null;

      await _preferences?.setServerUrl(normalizedUrl);
      if (!sameServer) {
        await _preferences?.clearPocketBaseAuth();
        await _preferences?.clearLoginCredentials();
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
    _cancelAuthRenewal();
    await _preferences?.clearPocketBaseAuth();
    await _preferences?.clearLoginCredentials();
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
    bool rememberCredentials = false,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    final normalizedIdentity = identity.trim();
    await repository.login(identity: normalizedIdentity, password: password);
    if (rememberCredentials) {
      await _preferences?.saveLoginCredentials(
        identity: normalizedIdentity,
        password: password,
      );
    } else {
      await _preferences?.clearLoginCredentials();
    }
    await refresh();
  }

  Future<void> loginWithOAuth(String providerName) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.loginWithOAuth(providerName);
    await _preferences?.clearLoginCredentials();
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

  Future<void> logout({bool clearCredentials = true}) async {
    _cancelAuthRenewal();
    final client = state.client;
    if (client != null) {
      client.authStore.clear();
      await _preferences?.clearPocketBaseAuth();
    }
    if (clearCredentials) {
      await _preferences?.clearLoginCredentials();
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
    _cancelAuthRenewal();

    if (!publicSettings.setupCompleted) {
      return AppSessionState(
        stage: SessionStage.welcome,
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
        busy: false,
      );
    }

    final authenticated = await _restoreAuthentication(client);
    if (!authenticated) {
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
    final repository = ref.read(authRepositoryProvider);
    final permission = account.isSuperuser
        ? null
        : await repository.fetchPermissionForUser(account.id, client: client);

    _scheduleAuthRenewal(client);

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

  Future<bool> _restoreAuthentication(PocketBase client) async {
    if (client.authStore.record == null) {
      return _loginWithSavedCredentials(client);
    }

    if (client.authStore.isValid) {
      try {
        await ref.read(authRepositoryProvider).refreshCurrentAuth(client);
        return client.authStore.record != null && client.authStore.isValid;
      } catch (_) {
        return _loginWithSavedCredentials(client);
      }
    }

    return _loginWithSavedCredentials(client);
  }

  Future<bool> _loginWithSavedCredentials(PocketBase client) async {
    final credentials = _preferences?.savedLoginCredentials;
    if (credentials == null) {
      return false;
    }

    try {
      await ref
          .read(authRepositoryProvider)
          .login(
            identity: credentials.identity,
            password: credentials.password,
            client: client,
          );
      return client.authStore.record != null && client.authStore.isValid;
    } catch (_) {
      return false;
    }
  }

  void _scheduleAuthRenewal(PocketBase client) {
    _cancelAuthRenewal();
    _authRenewalTimer = Timer(_authRenewalDelay(client.authStore.token), () {
      if (state.client != client || state.stage != SessionStage.authenticated) {
        return;
      }

      unawaited(_renewAuth(client));
    });
  }

  void _cancelAuthRenewal() {
    _authRenewalTimer?.cancel();
    _authRenewalTimer = null;
  }

  Duration _authRenewalDelay(String token) {
    final expiresAt = _jwtExpiresAt(token);
    if (expiresAt == null) {
      return const Duration(hours: 1);
    }

    final delay = expiresAt
        .subtract(const Duration(minutes: 5))
        .difference(DateTime.now());
    return delay.isNegative || delay == Duration.zero
        ? const Duration(seconds: 1)
        : delay;
  }

  DateTime? _jwtExpiresAt(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }

    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      final exp = payload['exp'];
      final seconds = exp is int ? exp : int.tryParse(exp.toString());
      if (seconds == null || seconds <= 0) {
        return null;
      }

      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    } catch (_) {
      return null;
    }
  }

  Future<void> _renewAuth(PocketBase client) async {
    final serverUrl = state.serverUrl;
    final publicSettings = state.publicSettings;
    if (serverUrl == null || publicSettings == null) {
      return;
    }

    try {
      final nextState = await _buildConnectedState(
        client: client,
        serverUrl: serverUrl,
        publicSettings: publicSettings,
      );
      if (state.client == client) {
        state = nextState;
      }
    } catch (_) {
      if (state.client == client && state.stage == SessionStage.authenticated) {
        _authRenewalTimer = Timer(
          const Duration(minutes: 5),
          () => unawaited(_renewAuth(client)),
        );
      }
    }
  }
}
