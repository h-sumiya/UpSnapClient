import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/app_localizations.dart';
import '../../features/account/presentation/account_screen.dart';
import '../../features/devices/presentation/device_editor_screen.dart';
import '../../features/devices/presentation/home_screen.dart';
import '../../features/session/application/session_controller.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import 'avatar_image.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(sessionControllerProvider);
    final account = session.account;
    final permission = session.permission;

    final destinations = <_AppDestination>[
      _AppDestination(
        title: l10n.tr('Devices'),
        icon: Icons.computer_rounded,
        builder: HomeScreen.new,
      ),
      if (account?.isSuperuser == true)
        _AppDestination(
          title: l10n.tr('Users'),
          icon: Icons.manage_accounts_rounded,
          builder: UsersScreen.new,
        ),
      _AppDestination(
        title: l10n.tr('Settings'),
        icon: Icons.settings_rounded,
        builder: SettingsScreen.new,
      ),
      _AppDestination(
        title: l10n.tr('Account'),
        icon: Icons.person_rounded,
        builder: AccountScreen.new,
      ),
    ];

    final selected = destinations[_selectedIndex];
    final canCreate =
        account?.isSuperuser == true || permission?.canCreateDevices == true;

    return Scaffold(
      appBar: AppBar(title: Text(selected.title)),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: account == null
                    ? const Icon(Icons.computer_rounded)
                    : AvatarImage(index: account.avatar),
                title: Text(session.publicSettings?.effectiveTitle ?? 'UpSnap'),
                subtitle: Text(account?.displayName ?? ''),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: destinations.length,
                  itemBuilder: (context, index) {
                    final destination = destinations[index];
                    return ListTile(
                      leading: Icon(destination.icon),
                      title: Text(destination.title),
                      selected: index == _selectedIndex,
                      onTap: () {
                        Navigator.of(context).pop();
                        setState(() => _selectedIndex = index);
                      },
                    );
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: Text(l10n.tr('Logout')),
                onTap: () async {
                  Navigator.of(context).pop();
                  await ref.read(sessionControllerProvider.notifier).logout();
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const DeviceEditorScreen()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.tr('New Device')),
            )
          : null,
      body: SafeArea(child: destinationScreen(selected)),
    );
  }

  Widget destinationScreen(_AppDestination destination) {
    return destination.builder();
  }
}

class _AppDestination {
  const _AppDestination({
    required this.title,
    required this.icon,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final Widget Function() builder;
}
