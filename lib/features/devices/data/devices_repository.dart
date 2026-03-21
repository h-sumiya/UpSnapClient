import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../core/models/auth_account.dart';
import '../../session/application/session_controller.dart';
import '../domain/device_models.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>(
  DevicesRepository.new,
);

class DevicesRepository {
  const DevicesRepository(this.ref);

  final Ref ref;

  PocketBase get _client {
    final client = ref.read(pocketBaseProvider);
    if (client == null) {
      throw StateError('PocketBase client is not initialized.');
    }
    return client;
  }

  Future<List<DeviceModel>> fetchDevices() async {
    final records = await _client
        .collection('devices')
        .getFullList(sort: 'name', expand: 'ports,groups');

    return records.map(DeviceModel.fromRecord).toList();
  }

  Future<DeviceModel> fetchDevice(String id) async {
    final record = await _client
        .collection('devices')
        .getOne(id, expand: 'ports,groups');
    return DeviceModel.fromRecord(record);
  }

  Future<List<DeviceGroup>> fetchGroups() async {
    final records = await _client.collection('device_groups').getFullList();
    return records.map(DeviceGroup.fromRecord).toList();
  }

  Future<DeviceGroup> createGroup(String name) async {
    final record = await _client
        .collection('device_groups')
        .create(body: {'name': name.trim()});
    return DeviceGroup.fromRecord(record);
  }

  Future<void> deleteGroup(String id) async {
    await _client.collection('device_groups').delete(id);
  }

  Future<DeviceModel> saveDevice({
    required DeviceSaveInput input,
    required AuthAccount? account,
  }) async {
    for (final portId in input.removedPortIds) {
      await _client.collection('ports').delete(portId);
    }

    final portIds = <String>[];
    for (final port in input.ports) {
      final saved = await _savePort(port);
      portIds.add(saved.id!);
    }

    final body = input.toBody(portIds);

    final record = input.id == null || input.id!.isEmpty
        ? await _client
              .collection('devices')
              .create(
                body: {
                  ...body,
                  'created_by': account?.isSuperuser == true
                      ? ''
                      : (account?.id ?? ''),
                },
              )
        : await _client.collection('devices').update(input.id!, body: body);

    final fresh = await _client
        .collection('devices')
        .getOne(record.id, expand: 'ports,groups');
    return DeviceModel.fromRecord(fresh);
  }

  Future<void> deleteDevice(String id) async {
    await _client.collection('devices').delete(id);
  }

  Future<void> wakeDevice(String id) => _client.send('/api/upsnap/wake/$id');

  Future<void> shutdownDevice(String id) =>
      _client.send('/api/upsnap/shutdown/$id');

  Future<void> sleepDevice(String id) => _client.send('/api/upsnap/sleep/$id');

  Future<void> rebootDevice(String id) =>
      _client.send('/api/upsnap/reboot/$id');

  Future<void> wakeGroup(String id) =>
      _client.send('/api/upsnap/wakegroup/$id');

  Future<ScanResponse> scanNetwork() async {
    final response = await _client.send<Map<String, dynamic>>(
      '/api/upsnap/scan',
    );
    return ScanResponse.fromJson(response);
  }

  Future<void> saveScanRange(String settingsId, String scanRange) {
    return _client
        .collection('settings_private')
        .update(settingsId, body: {'scan_range': scanRange.trim()});
  }

  Future<void> addScannedDevice(
    ScannedDevice device, {
    required String netmask,
  }) async {
    await _client
        .collection('devices')
        .create(
          body: {
            'name': device.name,
            'ip': device.ip,
            'mac': device.mac,
            'netmask': device.netmask.isEmpty ? netmask : device.netmask,
          },
        );
  }

  Future<DevicePort> _savePort(DevicePort port) async {
    final record = port.id == null
        ? await _client.collection('ports').create(body: port.toBody())
        : await _client
              .collection('ports')
              .update(port.id!, body: port.toBody());
    return DevicePort.fromRecord(record);
  }
}
