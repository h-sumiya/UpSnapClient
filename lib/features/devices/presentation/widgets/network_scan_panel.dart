import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../core/utils/error_message.dart';
import '../../../settings/data/settings_repository.dart';
import '../../../settings/domain/settings_models.dart';
import '../../data/devices_repository.dart';
import '../../domain/device_models.dart';

class NetworkScanPanel extends ConsumerStatefulWidget {
  const NetworkScanPanel({super.key, required this.onDevicesAdded});

  final Future<void> Function() onDevicesAdded;

  @override
  ConsumerState<NetworkScanPanel> createState() => _NetworkScanPanelState();
}

class _NetworkScanPanelState extends ConsumerState<NetworkScanPanel> {
  final _rangeController = TextEditingController();
  ScanResponse? _scanResponse;
  PrivateSettings? _privateSettings;
  bool _loading = true;
  bool _scanning = false;
  bool _replaceNetmask = false;
  bool _includeUnknown = true;
  String _replacementNetmask = '';
  final Set<String> _addedIps = <String>{};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _rangeController,
          decoration: InputDecoration(
            labelText: l10n.tr('Scan range'),
            hintText: '192.168.1.0/24',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _scanning ? null : _saveRange,
              icon: const Icon(Icons.save_alt_rounded),
              label: Text(l10n.tr('Save range')),
            ),
            FilledButton.tonalIcon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar_rounded),
              label: Text(l10n.tr(_scanning ? 'Scanning...' : 'Scan')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          value: _replaceNetmask,
          onChanged: (value) => setState(() => _replaceNetmask = value),
          title: Text(l10n.tr('Replace scanned netmask')),
        ),
        if (_replaceNetmask) ...[
          const SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(labelText: l10n.tr('New netmask')),
            onChanged: (value) => _replacementNetmask = value,
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile(
          value: _includeUnknown,
          onChanged: (value) => setState(() => _includeUnknown = value),
          title: Text(l10n.tr('Include devices named "Unknown"')),
        ),
        const SizedBox(height: 16),
        if (_scanResponse != null && _scanResponse!.devices.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: _addAll,
            icon: const Icon(Icons.playlist_add_rounded),
            label: Text(
              l10n.tr('Add all ({count})', {
                'count': _eligibleDevices.length.toString(),
              }),
            ),
          ),
          const SizedBox(height: 16),
          for (final device in _scanResponse!.devices)
            Card(
              child: ExpansionTile(
                title: Text(device.name),
                subtitle: Text(device.ip),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.tr('MAC: {value}', {'value': device.mac})),
                        Text(
                          l10n.tr('Vendor: {value}', {
                            'value': device.macVendor,
                          }),
                        ),
                        Text(
                          l10n.tr('Netmask: {value}', {
                            'value': _scanResponse!.netmask,
                          }),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _addedIps.contains(device.ip)
                              ? null
                              : () => _addOne(device),
                          child: Text(
                            _addedIps.contains(device.ip)
                                ? l10n.tr('Added')
                                : l10n.tr('Add device'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ] else
          Text(l10n.tr('No scan results yet.')),
      ],
    );
  }

  List<ScannedDevice> get _eligibleDevices {
    final response = _scanResponse;
    if (response == null) {
      return const <ScannedDevice>[];
    }

    return response.devices
        .where((device) => _includeUnknown || device.name != 'Unknown')
        .toList();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await ref
          .read(settingsRepositoryProvider)
          .fetchPrivateSettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _privateSettings = settings;
        _rangeController.text = settings.scanRange;
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
    }
  }

  Future<void> _saveRange() async {
    final settings = _privateSettings;
    if (settings == null) {
      return;
    }

    try {
      await ref
          .read(devicesRepositoryProvider)
          .saveScanRange(settings.id, _rangeController.text);
      final refreshed = settings.copyWith(
        scanRange: _rangeController.text.trim(),
      );
      setState(() => _privateSettings = refreshed);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('Scan range saved.'))),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final result = await ref.read(devicesRepositoryProvider).scanNetwork();
      if (!mounted) {
        return;
      }
      setState(() => _scanResponse = result);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _scanning = false);
      }
    }
  }

  Future<void> _addOne(ScannedDevice device) async {
    final netmask = _replaceNetmask
        ? _replacementNetmask
        : (_scanResponse?.netmask ?? '');

    try {
      await ref
          .read(devicesRepositoryProvider)
          .addScannedDevice(device, netmask: netmask);
      if (!mounted) {
        return;
      }
      setState(() => _addedIps.add(device.ip));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('{name} added.', {'name': device.name}),
          ),
        ),
      );
      await widget.onDevicesAdded();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
    }
  }

  Future<void> _addAll() async {
    for (final device in _eligibleDevices) {
      await _addOne(device);
    }
  }
}
