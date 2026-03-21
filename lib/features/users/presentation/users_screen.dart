import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_message.dart';
import '../../../shared/widgets/avatar_image.dart';
import '../../devices/domain/device_models.dart';
import '../../session/application/session_controller.dart';
import '../data/users_repository.dart';
import '../domain/user_models.dart';

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  bool _loading = true;
  List<UserModel> _users = const <UserModel>[];
  List<PermissionModel> _permissions = const <PermissionModel>[];
  List<DeviceModel> _devices = const <DeviceModel>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuperuser = ref.watch(authAccountProvider)?.isSuperuser == true;
    if (!isSuperuser) {
      return const Center(child: Text('Admin access required.'));
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final user in _users) ...[
          _UserCard(
            user: user,
            devices: _devices,
            permission: _permissionForUser(user.id),
            onChanged: (permission) async {
              try {
                final saved = await ref
                    .read(usersRepositoryProvider)
                    .savePermission(permission);
                setState(() {
                  _permissions = [
                    for (final item in _permissions)
                      if (item.userId == saved.userId) saved else item,
                    if (_permissions.every(
                      (item) => item.userId != saved.userId,
                    ))
                      saved,
                  ];
                });
                _show('Permissions saved for ${user.username}.');
              } catch (error) {
                _show(errorMessage(error));
              }
            },
            onDelete: () => _deleteUser(user),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create user',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _createUser,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Create user'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  PermissionModel _permissionForUser(String userId) {
    return _permissions.forUser(userId);
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(usersRepositoryProvider);
      final results = await Future.wait([
        repo.fetchUsers(),
        repo.fetchPermissions(),
        repo.fetchDevices(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _users = results[0] as List<UserModel>;
        _permissions = results[1] as List<PermissionModel>;
        _devices = results[2] as List<DeviceModel>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _show(errorMessage(error));
    }
  }

  Future<void> _createUser() async {
    try {
      await ref
          .read(usersRepositoryProvider)
          .createUser(
            username: _usernameController.text,
            password: _passwordController.text,
            passwordConfirm: _passwordConfirmController.text,
          );
      _usernameController.clear();
      _passwordController.clear();
      _passwordConfirmController.clear();
      await _load();
      _show('User created.');
    } catch (error) {
      _show(errorMessage(error));
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text('Delete ${user.username}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref
          .read(usersRepositoryProvider)
          .deleteUser(user, _permissionForUser(user.id));
      await _load();
      _show('User deleted.');
    } catch (error) {
      _show(errorMessage(error));
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

class _UserCard extends StatefulWidget {
  const _UserCard({
    required this.user,
    required this.devices,
    required this.permission,
    required this.onChanged,
    required this.onDelete,
  });

  final UserModel user;
  final List<DeviceModel> devices;
  final PermissionModel permission;
  final ValueChanged<PermissionModel> onChanged;
  final VoidCallback onDelete;

  @override
  State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  late PermissionModel _permission;

  @override
  void initState() {
    super.initState();
    _permission = widget.permission;
  }

  @override
  void didUpdateWidget(covariant _UserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.permission != widget.permission) {
      _permission = widget.permission;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarImage(index: widget.user.avatar),
                const SizedBox(width: 12),
                Text(
                  widget.user.username,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            SwitchListTile(
              value: _permission.create,
              onChanged: (value) {
                setState(
                  () => _permission = _permission.copyWith(create: value),
                );
              },
              title: const Text('Allow creating devices'),
            ),
            ExpansionTile(
              title: const Text('Device permissions'),
              children: [
                for (final device in widget.devices)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${device.name} (${device.ip})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _permChip(
                              label: 'Read',
                              selected: _permission.read.contains(device.id),
                              onSelected: (value) => _toggleList(
                                value,
                                device.id,
                                _permission.read,
                                (items) => _permission = _permission.copyWith(
                                  read: items,
                                ),
                              ),
                            ),
                            _permChip(
                              label: 'Update',
                              selected: _permission.update.contains(device.id),
                              onSelected: (value) => _toggleList(
                                value,
                                device.id,
                                _permission.update,
                                (items) => _permission = _permission.copyWith(
                                  update: items,
                                ),
                              ),
                            ),
                            _permChip(
                              label: 'Delete',
                              selected: _permission.delete.contains(device.id),
                              onSelected: (value) => _toggleList(
                                value,
                                device.id,
                                _permission.delete,
                                (items) => _permission = _permission.copyWith(
                                  delete: items,
                                ),
                              ),
                            ),
                            _permChip(
                              label: 'Power',
                              selected: _permission.power.contains(device.id),
                              onSelected: (value) => _toggleList(
                                value,
                                device.id,
                                _permission.power,
                                (items) => _permission = _permission.copyWith(
                                  power: items,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => widget.onChanged(_permission),
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
    );
  }

  void _toggleList(
    bool selected,
    String deviceId,
    List<String> current,
    void Function(List<String>) apply,
  ) {
    final next = {...current};
    if (selected) {
      next.add(deviceId);
    } else {
      next.remove(deviceId);
    }
    setState(() => apply(next.toList()));
  }
}
