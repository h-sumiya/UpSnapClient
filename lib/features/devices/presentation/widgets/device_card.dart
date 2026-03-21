import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../core/utils/cron_utils.dart';
import '../../../../core/utils/date_formatters.dart';
import '../../../../core/utils/error_message.dart';
import '../../application/device_widget_service.dart';
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
    final widgetService = ref.watch(deviceWidgetServiceProvider);
    final canPinWidget = canPower && widgetService.isSupportedPlatform;
    final canTogglePower =
        canPower &&
        (widget.device.status == DeviceStatus.online ||
            widget.device.status == DeviceStatus.offline);
    final statusColor = _statusColor(widget.device.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PowerIconButton(
                  color: statusColor,
                  isBusy: _busy,
                  onTap: canTogglePower && !_busy
                      ? _handlePrimaryPowerAction
                      : null,
                  tooltip: _powerActionTooltip(context, widget.device.status),
                ),
                const SizedBox(width: 12),
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
              ],
            ),
            const SizedBox(height: 14),
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
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
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
            const SizedBox(height: 14),
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
                const SizedBox(width: 8),
                _CardMenuButton(
                  canEdit: canEdit,
                  canPinWidget: canPinWidget,
                  canPower: canPower,
                  isOnline: widget.device.status == DeviceStatus.online,
                  onSelected: (value) =>
                      _handleMenuAction(value, canEdit, canPower),
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

      await ref.read(deviceWidgetServiceProvider).refreshWidgets();
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
    if (action == _CardAction.addWidget) {
      await _pinWidget();
      return;
    }

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
      await ref.read(deviceWidgetServiceProvider).refreshWidgets();
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

  Future<void> _pinWidget() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final added = await ref
          .read(deviceWidgetServiceProvider)
          .pinDeviceWidget(widget.device);
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            added
                ? context.l10n.tr(
                    'Confirm the launcher prompt to place the widget.',
                  )
                : context.l10n.tr('Widget pinning is not available here.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(error))));
    }
  }

  String _powerActionTooltip(BuildContext context, DeviceStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      DeviceStatus.offline => l10n.tr('Wake'),
      DeviceStatus.online => l10n.tr('Shutdown'),
      DeviceStatus.pending => l10n.tr('Pending'),
      DeviceStatus.unknown => l10n.tr('Unknown'),
    };
  }
}

enum _CardAction { addWidget, edit, sleep, reboot }

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class _CardMenuButton extends StatelessWidget {
  const _CardMenuButton({
    required this.canEdit,
    required this.canPinWidget,
    required this.canPower,
    required this.isOnline,
    required this.onSelected,
  });

  final bool canEdit;
  final bool canPinWidget;
  final bool canPower;
  final bool isOnline;
  final ValueChanged<_CardAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final hasActions = canEdit || canPinWidget || (canPower && isOnline);
    if (!hasActions) {
      return Icon(
        Icons.more_vert_rounded,
        color: Theme.of(context).disabledColor,
      );
    }

    return PopupMenuButton<_CardAction>(
      onSelected: onSelected,
      itemBuilder: (context) {
        final l10n = context.l10n;
        return [
          if (canPinWidget)
            PopupMenuItem(
              value: _CardAction.addWidget,
              child: Text(l10n.tr('Add widget')),
            ),
          if (canEdit)
            PopupMenuItem(
              value: _CardAction.edit,
              child: Text(l10n.tr('Edit device')),
            ),
          if (canPower && isOnline)
            PopupMenuItem(
              value: _CardAction.sleep,
              child: Text(l10n.tr('Sleep')),
            ),
          if (canPower && isOnline)
            PopupMenuItem(
              value: _CardAction.reboot,
              child: Text(l10n.tr('Reboot')),
            ),
        ];
      },
      icon: const Icon(Icons.more_vert_rounded),
    );
  }
}

class _PowerIconButton extends StatelessWidget {
  const _PowerIconButton({
    required this.color,
    required this.isBusy,
    required this.onTap,
    required this.tooltip,
  });

  final Color color;
  final bool isBusy;
  final VoidCallback? onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Material(
          color: color.withValues(alpha: 0.12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: isBusy
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  : Icon(Icons.power_settings_new_rounded, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

Color _statusColor(DeviceStatus status) {
  return switch (status) {
    DeviceStatus.online => Colors.green,
    DeviceStatus.offline => Colors.red,
    DeviceStatus.pending => Colors.orange,
    DeviceStatus.unknown => Colors.grey,
  };
}
