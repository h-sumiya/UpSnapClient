import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/settings/application/client_preferences_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/welcome_setup_screen.dart';
import '../features/server_config/presentation/server_config_screen.dart';
import '../features/session/application/session_controller.dart';
import '../features/session/domain/app_session_state.dart';
import '../shared/widgets/app_shell.dart';
import '../shared/widgets/loading_view.dart';
import 'localization/app_localizations.dart';
import 'theme/app_theme.dart';

class UpSnapApp extends ConsumerWidget {
  const UpSnapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final clientPreferences = ref.watch(clientPreferencesControllerProvider);
    final title = session.publicSettings?.effectiveTitle ?? 'UpSnap';

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: clientPreferences.themeMode,
      locale: clientPreferences.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        return AppLocalizations.resolve(locale);
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final l10n = context.l10n;
          return switch (session.stage) {
            SessionStage.loading => LoadingView(
              message: l10n.tr('Starting {appName}...', {'appName': title}),
            ),
            SessionStage.serverConfig => ServerConfigScreen(
              initialValue: session.serverUrl ?? '',
              errorMessage: session.errorMessage,
            ),
            SessionStage.welcome => const WelcomeSetupScreen(),
            SessionStage.login => const LoginScreen(),
            SessionStage.authenticated => const AppShell(),
          };
        },
      ),
    );
  }
}
