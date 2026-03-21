import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import '../../session/application/session_controller.dart';
import '../domain/settings_models.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>(
  SettingsRepository.new,
);

class SettingsRepository {
  const SettingsRepository(this.ref);

  final Ref ref;

  PocketBase get _client {
    final client = ref.read(pocketBaseProvider);
    if (client == null) {
      throw StateError('PocketBase client is not initialized.');
    }
    return client;
  }

  Future<PublicSettings> fetchPublicSettings() async {
    final record = await _client
        .collection('settings_public')
        .getFirstListItem('');
    return PublicSettings.fromRecord(record);
  }

  Future<PrivateSettings> fetchPrivateSettings() async {
    final record = await _client
        .collection('settings_private')
        .getFirstListItem('');
    return PrivateSettings.fromRecord(record);
  }

  Future<PublicSettings> savePublicSettings(PublicSettings settings) async {
    final record = await _client
        .collection('settings_public')
        .update(settings.id, body: settings.toBody());
    return PublicSettings.fromRecord(record);
  }

  Future<PublicSettings> uploadFavicon({
    required String recordId,
    required List<int> bytes,
    required String filename,
  }) async {
    final file = http.MultipartFile.fromBytes(
      'favicon',
      bytes,
      filename: filename,
    );

    final record = await _client
        .collection('settings_public')
        .update(recordId, files: [file]);
    return PublicSettings.fromRecord(record);
  }

  Future<PrivateSettings> savePrivateSettings(PrivateSettings settings) async {
    final record = await _client
        .collection('settings_private')
        .update(settings.id, body: settings.toBody());
    return PrivateSettings.fromRecord(record);
  }

  Future<bool> validateCron(String cron) async {
    try {
      await _client.send<String>(
        '/api/upsnap/validate-cron',
        method: 'POST',
        body: {'cron': cron.trim()},
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
