import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_message.dart';
import '../../session/application/session_controller.dart';
import '../data/devices_repository.dart';
import '../domain/device_models.dart';
import 'device_editor_screen.dart';
import 'widgets/device_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _poller;
  List<DeviceModel> _devices = const <DeviceModel>[];
  bool _loading = true;
  String? _error;
  bool _groupByCollection = true;
  _DeviceSortField _sortField = _DeviceSortField.name;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDevices());
    _poller = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_loadDevices(silent: true));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(authAccountProvider);
    final permission = ref.watch(permissionProvider);
    final canCreate =
        account?.isSuperuser == true || permission?.canCreateDevices == true;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadDevices, child: const Text('Retry')),
          ],
        ),
      );
    }

    final filtered = _filteredDevices();
    final ungrouped = filtered.where((device) => device.groups.isEmpty).toList()
      ..sort(_compareDevices);
    final grouped = groupBy<DeviceModel, String>(
      filtered.where((device) => device.groups.isNotEmpty),
      (device) => device.groups.first.id,
    )..removeWhere((key, value) => value.isEmpty);

    return RefreshIndicator(
      onRefresh: _loadDevices,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    labelText: 'Search devices',
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              setState(() => _searchController.clear());
                            },
                            icon: const Icon(Icons.clear_rounded),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SegmentedButton<_DeviceSortField>(
                segments: const [
                  ButtonSegment(
                    value: _DeviceSortField.name,
                    label: Text('Name'),
                    icon: Icon(Icons.sort_by_alpha_rounded),
                  ),
                  ButtonSegment(
                    value: _DeviceSortField.ip,
                    label: Text('IP'),
                    icon: Icon(Icons.numbers_rounded),
                  ),
                ],
                selected: {_sortField},
                onSelectionChanged: (value) {
                  setState(() => _sortField = value.first);
                },
              ),
              FilterChip(
                selected: _groupByCollection,
                onSelected: (value) {
                  setState(() => _groupByCollection = value);
                },
                label: const Text('Group by collections'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadDevices,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (filtered.isEmpty)
            _EmptyDevicesState(canCreate: canCreate)
          else if (!_groupByCollection)
            _DeviceGrid(
              devices: filtered..sort(_compareDevices),
              onRefresh: _loadDevices,
            )
          else ...[
            if (ungrouped.isNotEmpty)
              _DeviceGrid(devices: ungrouped, onRefresh: _loadDevices),
            for (final entry
                in grouped.entries.toList()..sort((a, b) {
                  final left = a.value.first.groups.first.name;
                  final right = b.value.first.groups.first.name;
                  return left.toLowerCase().compareTo(right.toLowerCase());
                }))
              _GroupSection(
                groupName: entry.value.first.groups.first.name,
                devices: entry.value..sort(_compareDevices),
                onWakeGroup: () => _wakeGroup(entry.key),
                onRefresh: _loadDevices,
              ),
          ],
        ],
      ),
    );
  }

  List<DeviceModel> _filteredDevices() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _devices.toList();
    }

    return _devices.where((device) {
      return device.name.toLowerCase().contains(query) ||
          device.ip.toLowerCase().contains(query) ||
          device.mac.toLowerCase().contains(query) ||
          device.description.toLowerCase().contains(query);
    }).toList();
  }

  int _compareDevices(DeviceModel left, DeviceModel right) {
    final leftValue = _sortField == _DeviceSortField.name ? left.name : left.ip;
    final rightValue = _sortField == _DeviceSortField.name
        ? right.name
        : right.ip;
    return compareNatural(leftValue.toLowerCase(), rightValue.toLowerCase());
  }

  Future<void> _loadDevices({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final devices = await ref.read(devicesRepositoryProvider).fetchDevices();
      if (!mounted) {
        return;
      }
      setState(() {
        _devices = devices;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = errorMessage(error);
      });
    }
  }

  Future<void> _wakeGroup(String groupId) async {
    try {
      await ref.read(devicesRepositoryProvider).wakeGroup(groupId);
      await _loadDevices();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    }
  }
}

enum _DeviceSortField { name, ip }

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.groupName,
    required this.devices,
    required this.onWakeGroup,
    required this.onRefresh,
  });

  final String groupName;
  final List<DeviceModel> devices;
  final VoidCallback onWakeGroup;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  groupName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onWakeGroup,
                icon: const Icon(Icons.power_rounded),
                label: const Text('Wake group'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeviceGrid(devices: devices, onRefresh: onRefresh),
        ],
      ),
    );
  }
}

class _DeviceGrid extends StatelessWidget {
  const _DeviceGrid({required this.devices, required this.onRefresh});

  final List<DeviceModel> devices;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 1400
            ? 4
            : width >= 1000
            ? 3
            : width >= 640
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: width >= 640 ? 1.14 : 0.98,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return DeviceCard(
              device: device,
              onRefreshRequested: onRefresh,
              onEditRequested: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => DeviceEditorScreen(deviceId: device.id),
                  ),
                );
                if (changed == true) {
                  await onRefresh();
                }
              },
            );
          },
        );
      },
    );
  }
}

class _EmptyDevicesState extends StatelessWidget {
  const _EmptyDevicesState({required this.canCreate});

  final bool canCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.desktop_windows_rounded,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              canCreate
                  ? 'No devices yet. Use the button below to add your first machine.'
                  : 'No devices are available for your account.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
