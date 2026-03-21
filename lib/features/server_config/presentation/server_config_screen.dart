import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/app_localizations.dart';
import '../../../features/session/application/session_controller.dart';
import '../../../shared/widgets/section_card.dart';
import '../../../shared/widgets/upsnap_logo.dart';

class ServerConfigScreen extends ConsumerStatefulWidget {
  const ServerConfigScreen({
    super.key,
    required this.initialValue,
    this.errorMessage,
  });

  final String initialValue;
  final String? errorMessage;

  @override
  ConsumerState<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends ConsumerState<ServerConfigScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SectionCard(
              title: l10n.tr('Connect to UpSnap'),
              subtitle: l10n.tr(
                'Enter the base URL of your UpSnap server. HTTP on a local network is supported.',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: UpSnapLogo(size: 96)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: l10n.tr('Server URL'),
                      hintText: 'http://192.168.1.10:8090',
                    ),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr(
                      'Examples: `http://upsnap.local:8090`, `https://myserver.example.com`',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (widget.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.wifi_find_rounded),
                      label: Text(l10n.tr('Save and connect')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    await ref
        .read(sessionControllerProvider.notifier)
        .connect(_urlController.text, preserveAuth: false);
  }
}
