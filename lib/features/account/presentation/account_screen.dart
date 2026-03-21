import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/avatar_image.dart';
import '../../../shared/widgets/section_card.dart';
import '../../session/application/session_controller.dart';
import '../data/account_repository.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  late int _avatar;
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _savingAvatar = false;
  bool _changingPassword = false;

  @override
  void initState() {
    super.initState();
    _avatar = ref.read(sessionControllerProvider).account?.avatar ?? 0;
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final account = session.account;
    if (account == null) {
      return const Center(child: Text('No active account.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Profile',
          subtitle: account.isSuperuser
              ? account.email ?? account.displayName
              : account.displayName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarImage(index: _avatar, radius: 28),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        account.isSuperuser ? 'Admin account' : 'User account',
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Avatar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  10,
                  (index) => InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setState(() => _avatar = index),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _avatar == index
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AvatarImage(index: index, radius: 24),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingAvatar ? null : _saveAvatar,
                  icon: _savingAvatar
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save account'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Change password',
          subtitle: 'Update the password for the current account.',
          child: Column(
            children: [
              if (!account.isSuperuser) ...[
                TextField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _changingPassword ? null : _changePassword,
                  icon: _changingPassword
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_reset_rounded),
                  label: const Text('Change password'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _saveAvatar() async {
    final account = ref.read(sessionControllerProvider).account;
    if (account == null) {
      return;
    }

    setState(() => _savingAvatar = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateAvatar(
            isSuperuser: account.isSuperuser,
            id: account.id,
            avatar: _avatar,
          );
      await ref.read(sessionControllerProvider.notifier).refresh();
      _show('Account saved.');
    } catch (error) {
      _show(errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _savingAvatar = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final account = ref.read(sessionControllerProvider).account;
    if (account == null) {
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _show('Passwords do not match.');
      return;
    }

    setState(() => _changingPassword = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .changePassword(
            isSuperuser: account.isSuperuser,
            id: account.id,
            oldPassword: _oldPasswordController.text,
            newPassword: _newPasswordController.text,
            passwordConfirm: _confirmPasswordController.text,
          );
      await ref.read(sessionControllerProvider.notifier).logout();
      _show('Password changed. Please sign in again.');
    } catch (error) {
      _show(errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _changingPassword = false);
      }
    }
  }

  void _show(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
