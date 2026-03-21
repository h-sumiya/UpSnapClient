import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../core/utils/cron_utils.dart';
import '../../../../core/utils/date_formatters.dart';
import '../../../../core/utils/error_message.dart';
import '../../../session/application/session_controller.dart';
import '../../data/devices_repository.dart';
import '../../domain/device_models.dart';

class DeviceCard extends ConsumerStatefulWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onRefreshRequested,
    required this.onEditRequested,
  });

  final DeviceModel device;
  final Future<void> Function() onRefreshRequested;
  final Future<void> Function() onEditRequested;

  @override
  ConsumerState<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends ConsumerState<DeviceCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final account = ref.watch(authAccountProvider);
    final permission = ref.watch(permissionProvider);

    final canPower =
        account?.isSuperuser == true ||
        permission?.canPower(widget.device.id) == true;
    final canEdit =
        account?.isSuperuser == true ||
        permission?.canUpdate(widget.device.id) == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (widget.device.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(widget.device.description),
                      ],
                    ],
                  ),
                ),
                _StatusBadge(status: widget.device.status),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _InfoChip(
                  icon: Icons.language_rounded,
                  label: widget.device.ip,
                ),
                _InfoChip(icon: Icons.memory_rounded, label: widget.device.mac),
                for (final group in widget.device.groups)
                  _InfoChip(icon: Icons.folder_open_rounded, label: group.name),
              ],
            ),
            if (widget.device.ports.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: widget.device.ports
                    .map(
                      (port) => ActionChip(
                        avatar: Icon(
                          port.status ? Icons.circle : Icons.circle_outlined,
                          size: 16,
                          color: port.status ? Colors.green : Colors.red,
                        ),
                        label: Text('${port.name} (${port.number})'),
                        onPressed: port.link.trim().isEmpty
                            ? null
                            : () => launchUrl(Uri.parse(port.link)),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (widget.device.wakeCronEnabled ||
                widget.device.shutdownCronEnabled ||
                widget.device.password.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (widget.device.wakeCronEnabled)
                    _InfoChip(
                      icon: Icons.schedule_send_rounded,
                      label:
                          '${l10n.tr('Wake')}: ${cronPreview(widget.device.wakeCron, locale: locale)}',
                    ),
                  if (widget.device.shutdownCronEnabled)
                    _InfoChip(
                      icon: Icons.schedule_rounded,
                      label:
                          '${l10n.tr('Shutdown')}: ${cronPreview(widget.device.shutdownCron, locale: locale)}',
                    ),
                  if (widget.device.password.trim().isNotEmpty)
                    _InfoChip(
                      icon: Icons.password_rounded,
                      label: l10n.tr('Wake password'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr('Updated {date}', {
                      'date': formatRelativeDate(
                        widget.device.updatedAt,
                        locale: locale,
                      ),
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (canPower)
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _handlePrimaryPowerAction,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.power_settings_new_rounded),
                    label: Text(
                      _primaryActionLabel(context, widget.device.status),
                    ),
                  ),
                const SizedBox(width: 8),
                PopupMenuButton<_CardAction>(
                  onSelected: (value) =>
                      _handleMenuAction(value, canEdit, canPower),
                  itemBuilder: (context) {
                    final l10n = context.l10n;
                    return [
                      if (canEdit)
                        PopupMenuItem(
                          value: _CardAction.edit,
                          child: Text(l10n.tr('Edit device')),
                        ),
                      if (canPower &&
                          widget.device.status == DeviceStatus.online)
                        PopupMenuItem(
                          value: _CardAction.sleep,
                          child: Text(l10n.tr('Sleep')),
                        ),
                      if (canPower &&
                          widget.device.status == DeviceStatus.online)
                        PopupMenuItem(
                          value: _CardAction.reboot,
                          child: Text(l10n.tr('Reboot')),
                        ),
                    ];
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePrimaryPowerAction() async {
    final l10n = context.l10n;
    final repo = ref.read(devicesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _busy = true);
    try {
      if (widget.device.status == DeviceStatus.offline) {
        if (widget.device.wakeConfirm) {
          final confirmed = await _confirm(
            l10n.tr('Wake {name}?', {'name': widget.device.name}),
          );
          if (!confirmed) {
            return;
          }
        }
        await repo.wakeDevice(widget.device.id);
        if (widget.device.link.trim().isNotEmpty) {
          await launchUrl(Uri.parse(widget.device.link));
        }
      } else if (widget.device.status == DeviceStatus.online) {
        if (widget.device.shutdownCommand.trim().isEmpty) {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.tr('No shutdown command configured.'))),
          );
          return;
        }
        if (widget.device.shutdownConfirm) {
          final confirmed = await _confirm(
            l10n.tr('Shutdown {name}?', {'name': widget.device.name}),
          );
          if (!confirmed) {
            return;
          }
        }
        await repo.shutdownDevice(widget.device.id);
      }

      await widget.onRefreshRequested();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleMenuAction(
    _CardAction action,
    bool canEdit,
    bool canPower,
  ) async {
    if (action == _CardAction.edit && canEdit) {
      await widget.onEditRequested();
      return;
    }

    if (!canPower) {
      return;
    }

    final repo = ref.read(devicesRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (action == _CardAction.sleep) {
        await repo.sleepDevice(widget.device.id);
      } else if (action == _CardAction.reboot) {
        final confirmed = widget.device.shutdownConfirm
            ? await _confirm(
                context.l10n.tr('Reboot {name}?', {'name': widget.device.name}),
              )
            : true;
        if (!confirmed) {
          return;
        }
        await repo.rebootDevice(widget.device.id);
      }
      await widget.onRefreshRequested();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(error))));
    }
  }

  Future<bool> _confirm(String text) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.tr('Confirm')),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  String _primaryActionLabel(BuildContext context, DeviceStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      DeviceStatus.offline => l10n.tr('Wake'),
      DeviceStatus.online => l10n.tr('Shutdown'),
      DeviceStatus.pending => l10n.tr('Pending'),
      DeviceStatus.unknown => l10n.tr('Refresh'),
    };
  }
}

enum _CardAction { edit, sleep, reboot }

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final DeviceStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (color, label) = switch (status) {
      DeviceStatus.online => (Colors.green, l10n.tr('Online')),
      DeviceStatus.offline => (Colors.red, l10n.tr('Offline')),
      DeviceStatus.pending => (Colors.orange, l10n.tr('Pending')),
      DeviceStatus.unknown => (Colors.grey, l10n.tr('Unknown')),
    };

    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide.none,
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }
}
