import 'package:pocketbase/pocketbase.dart';

import '../../../core/models/auth_account.dart';
import '../../settings/domain/settings_models.dart';
import '../../users/domain/user_models.dart';

enum SessionStage { loading, serverConfig, welcome, login, authenticated }

class AppSessionState {
  const AppSessionState({
    required this.stage,
    this.client,
    this.serverUrl,
    this.publicSettings,
    this.account,
    this.permission,
    this.errorMessage,
    this.busy = false,
  });

  final SessionStage stage;
  final PocketBase? client;
  final String? serverUrl;
  final PublicSettings? publicSettings;
  final AuthAccount? account;
  final PermissionModel? permission;
  final String? errorMessage;
  final bool busy;

  factory AppSessionState.loading() =>
      const AppSessionState(stage: SessionStage.loading, busy: true);

  AppSessionState copyWith({
    SessionStage? stage,
    PocketBase? client,
    String? serverUrl,
    PublicSettings? publicSettings,
    AuthAccount? account,
    PermissionModel? permission,
    String? errorMessage,
    bool? busy,
    bool clearClient = false,
    bool clearAccount = false,
    bool clearPermission = false,
    bool clearError = false,
  }) {
    return AppSessionState(
      stage: stage ?? this.stage,
      client: clearClient ? null : (client ?? this.client),
      serverUrl: serverUrl ?? this.serverUrl,
      publicSettings: publicSettings ?? this.publicSettings,
      account: clearAccount ? null : (account ?? this.account),
      permission: clearPermission ? null : (permission ?? this.permission),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      busy: busy ?? this.busy,
    );
  }
}
