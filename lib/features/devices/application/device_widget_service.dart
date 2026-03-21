import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/device_models.dart';

final deviceWidgetServiceProvider = Provider<DeviceWidgetService>(
  (ref) => const DeviceWidgetService(),
);

enum DeviceWidgetType {
  labeled('labeled'),
  powerIcon('power_icon');

  const DeviceWidgetType(this.platformValue);

  final String platformValue;
}

class DeviceWidgetService {
  const DeviceWidgetService();

  static const _channel = MethodChannel('red.hiro.upsnap/device_widget');

  bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> pinDeviceWidget(
    DeviceModel device, {
    required DeviceWidgetType type,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }

    final result = await _channel.invokeMethod<bool>('pinDeviceWidget', {
      'deviceId': device.id,
      'deviceName': device.name,
      'widgetType': type.platformValue,
    });
    return result ?? false;
  }

  Future<void> refreshWidgets() async {
    if (!isSupportedPlatform) {
      return;
    }

    await _channel.invokeMethod<void>('refreshDeviceWidgets');
  }
}
