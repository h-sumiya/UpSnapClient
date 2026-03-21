import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../core/storage/client_preferences.dart';
import '../../../core/utils/cron_utils.dart';
import '../../../core/utils/error_message.dart';
import '../application/client_preferences_controller.dart';
import '../../../features/session/application/session_controller.dart';
import '../../../shared/widgets/section_card.dart';
import '../data/settings_repository.dart';
import '../domain/settings_models.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _serverUrlController = TextEditingController();
  final _websiteTitleController = TextEditingController();
  final _intervalController = TextEditingController();
  final _scanRangeController = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _lazyPing = false;
  PublicSettings? _publicSettings;
  PrivateSettings? _privateSettings;
  PlatformFile? _favicon;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionControllerProvider);
    _serverUrlController.text = session.serverUrl ?? '';
    _publicSettings = session.publicSettings;
    _websiteTitleController.text = session.publicSettings?.websiteTitle ?? '';
    _load();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _websiteTitleController.dispose();
    _intervalController.dispose();
    _scanRangeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final clientPreferences = ref.watch(clientPreferencesControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final isSuperuser = session.account?.isSuperuser == true;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: l10n.tr('App'),
          subtitle: l10n.tr('This changes only this client app.'),
          child: Column(
            children: [
              DropdownButtonFormField<AppThemePreference>(
                initialValue: clientPreferences.themePreference,
                decoration: InputDecoration(labelText: l10n.tr('Theme')),
                items: AppThemePreference.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_themePreferenceLabel(value, l10n)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(clientPreferencesControllerProvider.notifier)
                      .updateThemePreference(value);
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AppLanguagePreference>(
                initialValue: clientPreferences.languagePreference,
                decoration: InputDecoration(labelText: l10n.tr('Language')),
                items: AppLanguagePreference.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_languagePreferenceLabel(value, l10n)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  ref
                      .read(clientPreferencesControllerProvider.notifier)
                      .updateLanguagePreference(value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: l10n.tr('Connection'),
          subtitle: l10n.tr('Change the target UpSnap server for this client.'),
          child: Column(
            children: [
              TextField(
                controller: _serverUrlController,
                decoration: InputDecoration(labelText: l10n.tr('Server URL')),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _saveServerUrl,
                  icon: const Icon(Icons.cloud_done_rounded),
                  label: Text(l10n.tr('Save connection')),
                ),
              ),
            ],
          ),
        ),
        if (isSuperuser &&
            _publicSettings != null &&
            _privateSettings != null) ...[
          const SizedBox(height: 16),
          SectionCard(
            title: l10n.tr('Server'),
            subtitle: l10n.tr(
              'Manage server-wide settings from the mobile client.',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _websiteTitleController,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Website title'),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _intervalController,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Ping interval cron'),
                    helperText: cronPreview(
                      _intervalController.text,
                      locale: locale,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: _lazyPing,
                  onChanged: (value) => setState(() => _lazyPing = value),
                  title: Text(l10n.tr('Enable lazy ping')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _scanRangeController,
                  decoration: InputDecoration(
                    labelText: l10n.tr('Network scan range'),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _pickFavicon,
                      icon: const Icon(Icons.image_rounded),
                      label: Text(
                        _favicon == null
                            ? l10n.tr('Select favicon')
                            : _favicon!.name,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _saveServerSettings,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(l10n.tr('Save server settings')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _load() async {
    final session = ref.read(sessionControllerProvider);
    if (session.account?.isSuperuser != true) {
      setState(() => _loading = false);
      return;
    }

    try {
      final privateSettings = await ref
          .read(settingsRepositoryProvider)
          .fetchPrivateSettings();
      if (!mounted) {
        return;
      }

      setState(() {
        _privateSettings = privateSettings;
        _intervalController.text = privateSettings.interval;
        _scanRangeController.text = privateSettings.scanRange;
        _lazyPing = privateSettings.lazyPing;
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

  Future<void> _saveServerUrl() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .connect(_serverUrlController.text, preserveAuth: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickFavicon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'svg', 'gif', 'jpg', 'jpeg', 'ico'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    setState(() => _favicon = result.files.single);
  }

  Future<void> _saveServerSettings() async {
    final l10n = context.l10n;
    final publicSettings = _publicSettings;
    final privateSettings = _privateSettings;
    if (publicSettings == null || privateSettings == null) {
      return;
    }

    setState(() => _busy = true);

    try {
      final repository = ref.read(settingsRepositoryProvider);
      final valid = await repository.validateCron(
        _intervalController.text.trim(),
      );
      if (!valid) {
        _show(l10n.tr('Ping interval cron is invalid.'));
        return;
      }

      var updatedPublic = await repository.savePublicSettings(
        publicSettings.copyWith(websiteTitle: _websiteTitleController.text),
      );

      if (_favicon?.bytes case final bytes?) {
        updatedPublic = await repository.uploadFavicon(
          recordId: publicSettings.id,
          bytes: bytes,
          filename: _favicon!.name,
        );
      }

      final updatedPrivate = await repository.savePrivateSettings(
        privateSettings.copyWith(
          interval: _intervalController.text,
          lazyPing: _lazyPing,
          scanRange: _scanRangeController.text,
        ),
      );

      ref
          .read(sessionControllerProvider.notifier)
          .updatePublicSettings(updatedPublic);
      setState(() {
        _publicSettings = updatedPublic;
        _privateSettings = updatedPrivate;
        _favicon = null;
      });
      _show(l10n.tr('Settings saved.'));
    } catch (error) {
      _show(errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
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

  String _themePreferenceLabel(
    AppThemePreference value,
    AppLocalizations l10n,
  ) {
    return switch (value) {
      AppThemePreference.system => l10n.tr('Follow system'),
      AppThemePreference.light => l10n.tr('Light'),
      AppThemePreference.dark => l10n.tr('Dark'),
    };
  }

  String _languagePreferenceLabel(
    AppLanguagePreference value,
    AppLocalizations l10n,
  ) {
    return switch (value) {
      AppLanguagePreference.system => l10n.tr('Follow system'),
      AppLanguagePreference.english => l10n.tr('English'),
      AppLanguagePreference.japanese => l10n.tr('Japanese'),
    };
  }
}
