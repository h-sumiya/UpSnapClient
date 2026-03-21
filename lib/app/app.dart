import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/welcome_setup_screen.dart';
import '../features/server_config/presentation/server_config_screen.dart';
import '../features/session/application/session_controller.dart';
import '../features/session/domain/app_session_state.dart';
import '../shared/widgets/app_shell.dart';
import '../shared/widgets/loading_view.dart';
import 'theme/app_theme.dart';

class UpSnapApp extends ConsumerWidget {
  const UpSnapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final title = session.publicSettings?.effectiveTitle ?? 'UpSnap';

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: switch (session.stage) {
        SessionStage.loading => const LoadingView(message: 'Starting UpSnap…'),
        SessionStage.serverConfig => ServerConfigScreen(
          initialValue: session.serverUrl ?? '',
          errorMessage: session.errorMessage,
        ),
        SessionStage.welcome => const WelcomeSetupScreen(),
        SessionStage.login => const LoginScreen(),
        SessionStage.authenticated => const AppShell(),
      },
    );
  }
}
