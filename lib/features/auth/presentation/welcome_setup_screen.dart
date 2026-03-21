import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/upsnap_logo.dart';
import '../../session/application/session_controller.dart';

class WelcomeSetupScreen extends ConsumerStatefulWidget {
  const WelcomeSetupScreen({super.key});

  @override
  ConsumerState<WelcomeSetupScreen> createState() => _WelcomeSetupScreenState();
}

class _WelcomeSetupScreenState extends ConsumerState<WelcomeSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = ref.watch(sessionControllerProvider).publicSettings;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
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
                      const Center(child: UpSnapLogo(size: 96)),
                      const SizedBox(height: 16),
                      Text(
                        l10n.tr('Set up {appName}', {
                          'appName': settings?.effectiveTitle ?? 'UpSnap',
                        }),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.tr(
                          'Create the initial admin account to complete the first-run setup.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Admin email'),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.tr('Required');
                          }
                          if (!value.contains('@')) {
                            return l10n.tr('Enter a valid email address');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Password'),
                        ),
                        validator: (value) {
                          if (value == null || value.length < 10) {
                            return l10n.tr('At least 10 characters');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Confirm password'),
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return l10n.tr('Passwords do not match');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            l10n.tr(
                              _busy ? 'Creating admin...' : 'Create admin',
                            ),
                          ),
                        ),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .initializeSuperuser(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            passwordConfirm: _confirmController.text,
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
}
