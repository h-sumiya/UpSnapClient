import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/utils/error_message.dart';
import '../../session/application/session_controller.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identityController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _rememberCredentials = false;
  late Future<List<AuthMethodProvider>> _providersFuture;

  @override
  void initState() {
    super.initState();
    final sessionController = ref.read(sessionControllerProvider.notifier);
    final savedCredentials = sessionController.savedLoginCredentials;
    if (savedCredentials != null) {
      _identityController.text = savedCredentials.identity;
      _passwordController.text = savedCredentials.password;
      _rememberCredentials = true;
    } else {
      _rememberCredentials = sessionController.rememberLogin;
    }
    _providersFuture = ref.read(authRepositoryProvider).listOAuthProviders();
  }

  @override
  void dispose() {
    _identityController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(sessionControllerProvider).publicSettings;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings?.effectiveTitle ?? 'UpSnap',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.tr('Sign in with your admin or user account.'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _identityController,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Email or username'),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? l10n.tr('Required')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Password'),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? l10n.tr('Required')
                            : null,
                        onFieldSubmitted: (_) => _login(),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _rememberCredentials,
                        onChanged: _busy
                            ? null
                            : (value) {
                                setState(
                                  () => _rememberCredentials = value ?? false,
                                );
                              },
                        title: Text(l10n.tr('Remember ID and password')),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _login,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded),
                          label: Text(
                            l10n.tr(_busy ? 'Signing in...' : 'Sign in'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<List<AuthMethodProvider>>(
                        future: _providersFuture,
                        builder: (context, snapshot) {
                          final providers =
                              snapshot.data ?? const <AuthMethodProvider>[];
                          if (providers.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: providers
                                .map(
                                  (provider) => OutlinedButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                              _loginWithProvider(provider.name),
                                    icon: const Icon(Icons.login_rounded),
                                    label: Text(provider.displayName),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            ref
                                .read(sessionControllerProvider.notifier)
                                .showServerConfiguration();
                          },
                          child: Text(l10n.tr('Change server')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .login(
            identity: _identityController.text.trim(),
            password: _passwordController.text,
            rememberCredentials: _rememberCredentials,
          );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _loginWithProvider(String providerName) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .loginWithOAuth(providerName);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
