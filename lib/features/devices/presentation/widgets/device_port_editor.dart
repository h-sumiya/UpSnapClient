import 'package:flutter/material.dart';

import '../../domain/device_models.dart';

class DevicePortEditor extends StatelessWidget {
  const DevicePortEditor({
    super.key,
    required this.port,
    required this.onChanged,
    required this.onDelete,
  });

  final DevicePort port;
  final ValueChanged<DevicePort> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    port.id == null ? 'New port' : 'Port ${port.number}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: port.name,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (value) => onChanged(port.copyWith(name: value)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: port.number.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port number'),
              onChanged: (value) {
                onChanged(port.copyWith(number: int.tryParse(value) ?? 1));
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: port.link,
              decoration: const InputDecoration(labelText: 'Link'),
              onChanged: (value) => onChanged(port.copyWith(link: value)),
            ),
          ],
        ),
      ),
    );
  }
}
