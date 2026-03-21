import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/cron_utils.dart';
import '../../../core/utils/error_message.dart';
import '../../session/application/session_controller.dart';
import '../../settings/data/settings_repository.dart';
import '../data/devices_repository.dart';
import '../domain/device_models.dart';
import 'widgets/device_port_editor.dart';
import 'widgets/network_scan_panel.dart';

class DeviceEditorScreen extends ConsumerStatefulWidget {
  const DeviceEditorScreen({super.key, this.deviceId});

  final String? deviceId;

  bool get isEditing => deviceId != null;

  @override
  ConsumerState<DeviceEditorScreen> createState() => _DeviceEditorScreenState();
}

class _DeviceEditorScreenState extends ConsumerState<DeviceEditorScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _macController = TextEditingController();
  final _netmaskController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();
  final _pingCommandController = TextEditingController();
  final _wakeCommandController = TextEditingController();
  final _wakeCronController = TextEditingController();
  final _shutdownCommandController = TextEditingController();
  final _shutdownCronController = TextEditingController();
  final _passwordController = TextEditingController();
  final _solUserController = TextEditingController();
  final _solPasswordController = TextEditingController();
  final _newGroupController = TextEditingController();
  late final TabController _tabController;

  bool _loading = true;
  bool _saving = false;
  DeviceLinkOpenMode _linkOpen = DeviceLinkOpenMode.none;
  bool _wakeCronEnabled = false;
  bool _wakeConfirm = false;
  int _wakeTimeout = 0;
  bool _shutdownCronEnabled = false;
  bool _shutdownConfirm = false;
  int _shutdownTimeout = 0;
  bool _solEnabled = false;
  bool _solAuth = false;
  int _solPort = 0;
  List<DevicePort> _ports = <DevicePort>[];
  final Set<String> _removedPortIds = <String>{};
  List<DeviceGroup> _groups = <DeviceGroup>[];
  Set<String> _selectedGroupIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.isEditing ? 1 : 2,
      vsync: this,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _ipController.dispose();
    _macController.dispose();
    _netmaskController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    _pingCommandController.dispose();
    _wakeCommandController.dispose();
    _wakeCronController.dispose();
    _shutdownCommandController.dispose();
    _shutdownCronController.dispose();
    _passwordController.dispose();
    _solUserController.dispose();
    _solPasswordController.dispose();
    _newGroupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Device' : 'New Device'),
        bottom: widget.isEditing
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Manual'),
                  Tab(text: 'Network Scan'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildForm(),
                if (!widget.isEditing)
                  const NetworkScanPanel(onDevicesAdded: _noopAsync),
              ],
            ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'General',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _wideField(_nameController, 'Name', required: true),
                _wideField(_ipController, 'IP address', required: true),
                _wideField(_macController, 'MAC address', required: true),
                _wideField(_netmaskController, 'Netmask', required: true),
                _wideField(_descriptionController, 'Description'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Ports',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < _ports.length; index++) ...[
                  DevicePortEditor(
                    port: _ports[index],
                    onChanged: (value) {
                      setState(() => _ports[index] = value);
                    },
                    onDelete: () {
                      setState(() {
                        final port = _ports.removeAt(index);
                        if (port.id != null) {
                          _removedPortIds.add(port.id!);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _ports = [
                        ..._ports,
                        const DevicePort(name: '', number: 1, link: ''),
                      ];
                    });
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add port'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Link',
            child: Column(
              children: [
                TextField(
                  controller: _linkController,
                  decoration: const InputDecoration(labelText: 'Device link'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<DeviceLinkOpenMode>(
                  initialValue: _linkOpen,
                  decoration: const InputDecoration(
                    labelText: 'Open link after wake',
                  ),
                  items: DeviceLinkOpenMode.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(switch (value) {
                            DeviceLinkOpenMode.none => 'No',
                            DeviceLinkOpenMode.sameTab => 'Open immediately',
                            DeviceLinkOpenMode.newTab => 'Open externally',
                          }),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(
                      () => _linkOpen = value ?? DeviceLinkOpenMode.none,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Ping',
            child: TextField(
              controller: _pingCommandController,
              decoration: const InputDecoration(
                labelText: 'Ping command override',
                prefixText: '\$ ',
              ),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Wake',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _wakeCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Wake command override',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _wakeTimeout.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Wake timeout (seconds)',
                  ),
                  onChanged: (value) => _wakeTimeout = int.tryParse(value) ?? 0,
                ),
                SwitchListTile(
                  value: _wakeCronEnabled,
                  onChanged: (value) =>
                      setState(() => _wakeCronEnabled = value),
                  title: const Text('Enable wake schedule'),
                ),
                if (_wakeCronEnabled) ...[
                  TextField(
                    controller: _wakeCronController,
                    decoration: InputDecoration(
                      labelText: 'Wake cron',
                      helperText: cronPreview(_wakeCronController.text),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                SwitchListTile(
                  value: _wakeConfirm,
                  onChanged: (value) => setState(() => _wakeConfirm = value),
                  title: const Text('Require wake confirmation'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Shutdown',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _shutdownCommandController,
                  decoration: const InputDecoration(
                    labelText: 'Shutdown command',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: _shutdownTimeout.toString(),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Shutdown timeout (seconds)',
                  ),
                  onChanged: (value) =>
                      _shutdownTimeout = int.tryParse(value) ?? 0,
                ),
                SwitchListTile(
                  value: _shutdownCronEnabled,
                  onChanged: (value) =>
                      setState(() => _shutdownCronEnabled = value),
                  title: const Text('Enable shutdown schedule'),
                ),
                if (_shutdownCronEnabled) ...[
                  TextField(
                    controller: _shutdownCronController,
                    decoration: InputDecoration(
                      labelText: 'Shutdown cron',
                      helperText: cronPreview(_shutdownCronController.text),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                SwitchListTile(
                  value: _shutdownConfirm,
                  onChanged: (value) =>
                      setState(() => _shutdownConfirm = value),
                  title: const Text('Require shutdown confirmation'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Sleep-On-LAN',
            child: Column(
              children: [
                SwitchListTile(
                  value: _solEnabled,
                  onChanged: (value) => setState(() => _solEnabled = value),
                  title: const Text('Enable Sleep-On-LAN'),
                ),
                if (_solEnabled) ...[
                  TextFormField(
                    initialValue: _solPort.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Sleep-On-LAN port',
                    ),
                    onChanged: (value) => _solPort = int.tryParse(value) ?? 0,
                  ),
                  SwitchListTile(
                    value: _solAuth,
                    onChanged: (value) => setState(() => _solAuth = value),
                    title: const Text('Require authorization'),
                  ),
                  if (_solAuth) ...[
                    TextField(
                      controller: _solUserController,
                      decoration: const InputDecoration(labelText: 'SOL user'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _solPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'SOL password',
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Wake Password',
            child: TextField(
              controller: _passwordController,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Wake password'),
            ),
          ),
          const SizedBox(height: 16),
          _Section(
            title: 'Groups',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _groups
                      .map(
                        (group) => FilterChip(
                          selected: _selectedGroupIds.contains(group.id),
                          label: Text(group.name),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedGroupIds.add(group.id);
                              } else {
                                _selectedGroupIds.remove(group.id);
                              }
                            });
                          },
                          deleteIcon: const Icon(Icons.close_rounded),
                          onDeleted: () => _deleteGroup(group),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newGroupController,
                        decoration: const InputDecoration(
                          labelText: 'New group',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: _addGroup,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (widget.isEditing) ...[
                OutlinedButton.icon(
                  onPressed: _saving ? null : _deleteDevice,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
                const Spacer(),
              ],
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wideField(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return SizedBox(
      width: 320,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          if (!required) {
            return null;
          }
          return value == null || value.trim().isEmpty ? 'Required' : null;
        },
      ),
    );
  }

  Future<void> _load() async {
    try {
      final groups = await ref.read(devicesRepositoryProvider).fetchGroups();
      if (widget.isEditing) {
        final device = await ref
            .read(devicesRepositoryProvider)
            .fetchDevice(widget.deviceId!);
        _applyDevice(device);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      Navigator.of(context).maybePop();
    }
  }

  void _applyDevice(DeviceModel device) {
    _nameController.text = device.name;
    _ipController.text = device.ip;
    _macController.text = device.mac;
    _netmaskController.text = device.netmask;
    _descriptionController.text = device.description;
    _linkController.text = device.link;
    _pingCommandController.text = device.pingCommand;
    _wakeCommandController.text = device.wakeCommand;
    _wakeCronController.text = device.wakeCron;
    _shutdownCommandController.text = device.shutdownCommand;
    _shutdownCronController.text = device.shutdownCron;
    _passwordController.text = device.password;
    _solUserController.text = device.solUser;
    _solPasswordController.text = device.solPassword;

    _linkOpen = device.linkOpen;
    _wakeCronEnabled = device.wakeCronEnabled;
    _wakeConfirm = device.wakeConfirm;
    _wakeTimeout = device.wakeTimeout;
    _shutdownCronEnabled = device.shutdownCronEnabled;
    _shutdownConfirm = device.shutdownConfirm;
    _shutdownTimeout = device.shutdownTimeout;
    _solEnabled = device.solEnabled;
    _solAuth = device.solAuth;
    _solPort = device.solPort;
    _ports = device.ports;
    _selectedGroupIds = device.groupIds.toSet();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    if (_wakeCronEnabled &&
        !await settingsRepo.validateCron(_wakeCronController.text.trim())) {
      _showMessage('Wake cron is invalid.');
      return;
    }
    if (_shutdownCronEnabled &&
        !await settingsRepo.validateCron(_shutdownCronController.text.trim())) {
      _showMessage('Shutdown cron is invalid.');
      return;
    }

    final account = ref.read(authAccountProvider);
    final input = DeviceSaveInput(
      id: widget.deviceId,
      name: _nameController.text,
      ip: _ipController.text,
      mac: _macController.text,
      netmask: _netmaskController.text,
      description: _descriptionController.text,
      link: _linkController.text,
      linkOpen: _linkOpen,
      pingCommand: _pingCommandController.text,
      wakeCron: _wakeCronController.text,
      wakeCronEnabled: _wakeCronEnabled,
      wakeCommand: _wakeCommandController.text,
      wakeConfirm: _wakeConfirm,
      wakeTimeout: _wakeTimeout,
      shutdownCron: _shutdownCronController.text,
      shutdownCronEnabled: _shutdownCronEnabled,
      shutdownCommand: _shutdownCommandController.text,
      shutdownConfirm: _shutdownConfirm,
      shutdownTimeout: _shutdownTimeout,
      password: _passwordController.text,
      groupIds: _selectedGroupIds.toList(),
      createdBy: account?.isSuperuser == true ? '' : (account?.id ?? ''),
      solEnabled: _solEnabled,
      solAuth: _solAuth,
      solUser: _solUserController.text,
      solPassword: _solPasswordController.text,
      solPort: _solPort,
      ports: _ports,
      removedPortIds: _removedPortIds.toList(),
    );

    setState(() => _saving = true);
    try {
      await ref
          .read(devicesRepositoryProvider)
          .saveDevice(input: input, account: account);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showMessage(errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteDevice() async {
    if (!widget.isEditing) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text('Delete ${_nameController.text}?'),
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
      await ref.read(devicesRepositoryProvider).deleteDevice(widget.deviceId!);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showMessage(errorMessage(error));
    }
  }

  Future<void> _addGroup() async {
    if (_newGroupController.text.trim().isEmpty) {
      return;
    }

    try {
      final group = await ref
          .read(devicesRepositoryProvider)
          .createGroup(_newGroupController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = [..._groups, group];
        _selectedGroupIds.add(group.id);
        _newGroupController.clear();
      });
    } catch (error) {
      _showMessage(errorMessage(error));
    }
  }

  Future<void> _deleteGroup(DeviceGroup group) async {
    try {
      await ref.read(devicesRepositoryProvider).deleteGroup(group.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _groups.removeWhere((item) => item.id == group.id);
        _selectedGroupIds.remove(group.id);
      });
    } catch (error) {
      _showMessage(errorMessage(error));
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

Future<void> _noopAsync() async {}
