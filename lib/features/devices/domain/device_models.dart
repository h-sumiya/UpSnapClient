import 'package:pocketbase/pocketbase.dart';

import '../../../core/utils/date_formatters.dart';

enum DeviceStatus {
  pending,
  online,
  offline,
  unknown;

  factory DeviceStatus.fromValue(String value) {
    return switch (value) {
      'pending' => DeviceStatus.pending,
      'online' => DeviceStatus.online,
      'offline' => DeviceStatus.offline,
      _ => DeviceStatus.unknown,
    };
  }

  String get value => switch (this) {
    DeviceStatus.pending => 'pending',
    DeviceStatus.online => 'online',
    DeviceStatus.offline => 'offline',
    DeviceStatus.unknown => '',
  };
}

enum DeviceLinkOpenMode {
  none(''),
  sameTab('same_tab'),
  newTab('new_tab');

  const DeviceLinkOpenMode(this.value);

  final String value;

  factory DeviceLinkOpenMode.fromValue(String value) {
    return DeviceLinkOpenMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => DeviceLinkOpenMode.none,
    );
  }
}

class DeviceGroup {
  const DeviceGroup({required this.id, required this.name});

  final String id;
  final String name;

  factory DeviceGroup.fromRecord(RecordModel record) {
    return DeviceGroup(id: record.id, name: record.getStringValue('name'));
  }
}

class DevicePort {
  const DevicePort({
    this.id,
    required this.name,
    required this.number,
    required this.link,
    this.status = false,
  });

  final String? id;
  final String name;
  final int number;
  final String link;
  final bool status;

  factory DevicePort.fromRecord(RecordModel record) {
    return DevicePort(
      id: record.id,
      name: record.getStringValue('name'),
      number: record.getIntValue('number'),
      link: record.getStringValue('link'),
      status: record.getBoolValue('status'),
    );
  }

  DevicePort copyWith({
    String? id,
    String? name,
    int? number,
    String? link,
    bool? status,
  }) {
    return DevicePort(
      id: id ?? this.id,
      name: name ?? this.name,
      number: number ?? this.number,
      link: link ?? this.link,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toBody() {
    return {'name': name.trim(), 'number': number, 'link': link.trim()};
  }
}

class DeviceModel {
  const DeviceModel({
    required this.id,
    required this.name,
    required this.ip,
    required this.mac,
    required this.netmask,
    required this.description,
    required this.status,
    required this.link,
    required this.linkOpen,
    required this.pingCommand,
    required this.wakeCron,
    required this.wakeCronEnabled,
    required this.wakeCommand,
    required this.wakeConfirm,
    required this.wakeTimeout,
    required this.shutdownCron,
    required this.shutdownCronEnabled,
    required this.shutdownCommand,
    required this.shutdownConfirm,
    required this.shutdownTimeout,
    required this.password,
    required this.groupIds,
    required this.createdBy,
    required this.solEnabled,
    required this.solAuth,
    required this.solUser,
    required this.solPassword,
    required this.solPort,
    required this.portIds,
    required this.ports,
    required this.groups,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String ip;
  final String mac;
  final String netmask;
  final String description;
  final DeviceStatus status;
  final String link;
  final DeviceLinkOpenMode linkOpen;
  final String pingCommand;
  final String wakeCron;
  final bool wakeCronEnabled;
  final String wakeCommand;
  final bool wakeConfirm;
  final int wakeTimeout;
  final String shutdownCron;
  final bool shutdownCronEnabled;
  final String shutdownCommand;
  final bool shutdownConfirm;
  final int shutdownTimeout;
  final String password;
  final List<String> groupIds;
  final String createdBy;
  final bool solEnabled;
  final bool solAuth;
  final String solUser;
  final String solPassword;
  final int solPort;
  final List<String> portIds;
  final List<DevicePort> ports;
  final List<DeviceGroup> groups;
  final DateTime? updatedAt;

  factory DeviceModel.fromRecord(RecordModel record) {
    final expandedPorts = record
        .get<List<RecordModel>>('expand.ports', const <RecordModel>[])
        .map(DevicePort.fromRecord)
        .toList();
    final expandedGroups = record
        .get<List<RecordModel>>('expand.groups', const <RecordModel>[])
        .map(DeviceGroup.fromRecord)
        .toList();

    return DeviceModel(
      id: record.id,
      name: record.getStringValue('name'),
      ip: record.getStringValue('ip'),
      mac: record.getStringValue('mac'),
      netmask: record.getStringValue('netmask'),
      description: record.getStringValue('description'),
      status: DeviceStatus.fromValue(record.getStringValue('status')),
      link: record.getStringValue('link'),
      linkOpen: DeviceLinkOpenMode.fromValue(
        record.getStringValue('link_open'),
      ),
      pingCommand: record.getStringValue('ping_cmd'),
      wakeCron: record.getStringValue('wake_cron'),
      wakeCronEnabled: record.getBoolValue('wake_cron_enabled'),
      wakeCommand: record.getStringValue('wake_cmd'),
      wakeConfirm: record.getBoolValue('wake_confirm'),
      wakeTimeout: record.getIntValue('wake_timeout'),
      shutdownCron: record.getStringValue('shutdown_cron'),
      shutdownCronEnabled: record.getBoolValue('shutdown_cron_enabled'),
      shutdownCommand: record.getStringValue('shutdown_cmd'),
      shutdownConfirm: record.getBoolValue('shutdown_confirm'),
      shutdownTimeout: record.getIntValue('shutdown_timeout'),
      password: record.getStringValue('password'),
      groupIds: record.getListValue<String>('groups', const <String>[]),
      createdBy: record.getStringValue('created_by'),
      solEnabled: record.getBoolValue('sol_enabled'),
      solAuth: record.getBoolValue('sol_auth'),
      solUser: record.getStringValue('sol_user'),
      solPassword: record.getStringValue('sol_password'),
      solPort: record.getIntValue('sol_port'),
      portIds: record.getListValue<String>('ports', const <String>[]),
      ports: expandedPorts,
      groups: expandedGroups,
      updatedAt: tryParseDate(record.getStringValue('updated')),
    );
  }
}

class DeviceSaveInput {
  const DeviceSaveInput({
    this.id,
    required this.name,
    required this.ip,
    required this.mac,
    required this.netmask,
    required this.description,
    required this.link,
    required this.linkOpen,
    required this.pingCommand,
    required this.wakeCron,
    required this.wakeCronEnabled,
    required this.wakeCommand,
    required this.wakeConfirm,
    required this.wakeTimeout,
    required this.shutdownCron,
    required this.shutdownCronEnabled,
    required this.shutdownCommand,
    required this.shutdownConfirm,
    required this.shutdownTimeout,
    required this.password,
    required this.groupIds,
    required this.createdBy,
    required this.solEnabled,
    required this.solAuth,
    required this.solUser,
    required this.solPassword,
    required this.solPort,
    required this.ports,
    this.removedPortIds = const <String>[],
  });

  final String? id;
  final String name;
  final String ip;
  final String mac;
  final String netmask;
  final String description;
  final String link;
  final DeviceLinkOpenMode linkOpen;
  final String pingCommand;
  final String wakeCron;
  final bool wakeCronEnabled;
  final String wakeCommand;
  final bool wakeConfirm;
  final int wakeTimeout;
  final String shutdownCron;
  final bool shutdownCronEnabled;
  final String shutdownCommand;
  final bool shutdownConfirm;
  final int shutdownTimeout;
  final String password;
  final List<String> groupIds;
  final String createdBy;
  final bool solEnabled;
  final bool solAuth;
  final String solUser;
  final String solPassword;
  final int solPort;
  final List<DevicePort> ports;
  final List<String> removedPortIds;

  Map<String, dynamic> toBody(List<String> portIds) {
    return {
      'name': name.trim(),
      'ip': ip.replaceAll(' ', ''),
      'mac': mac.replaceAll(' ', ''),
      'netmask': netmask.replaceAll(' ', ''),
      'description': description.trim(),
      'link': link.trim(),
      'link_open': linkOpen.value,
      'ping_cmd': pingCommand.trim(),
      'wake_cron': wakeCron.trim(),
      'wake_cron_enabled': wakeCronEnabled,
      'wake_cmd': wakeCommand.trim(),
      'wake_confirm': wakeConfirm,
      'wake_timeout': wakeTimeout,
      'shutdown_cron': shutdownCron.trim(),
      'shutdown_cron_enabled': shutdownCronEnabled,
      'shutdown_cmd': shutdownCommand.trim(),
      'shutdown_confirm': shutdownConfirm,
      'shutdown_timeout': shutdownTimeout,
      'password': password.trim(),
      'groups': groupIds,
      'created_by': createdBy,
      'sol_enabled': solEnabled,
      'sol_auth': solAuth,
      'sol_user': solUser.trim(),
      'sol_password': solPassword,
      'sol_port': solPort,
      'ports': portIds,
    };
  }
}

class ScannedDevice {
  const ScannedDevice({
    required this.name,
    required this.ip,
    required this.mac,
    required this.macVendor,
    this.netmask = '',
  });

  final String name;
  final String ip;
  final String mac;
  final String macVendor;
  final String netmask;

  factory ScannedDevice.fromJson(Map<String, dynamic> json) {
    return ScannedDevice(
      name: json['name']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      macVendor: json['mac_vendor']?.toString() ?? 'Unknown',
      netmask: json['netmask']?.toString() ?? '',
    );
  }
}

class ScanResponse {
  const ScanResponse({required this.netmask, required this.devices});

  final String netmask;
  final List<ScannedDevice> devices;

  factory ScanResponse.fromJson(Map<String, dynamic> json) {
    final items = (json['devices'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ScannedDevice.fromJson)
        .toList();

    return ScanResponse(
      netmask: json['netmask']?.toString() ?? '',
      devices: items,
    );
  }
}
