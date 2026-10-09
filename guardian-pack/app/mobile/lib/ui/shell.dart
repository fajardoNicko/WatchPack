import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../auth/auth.dart';
import '../push/push.dart';
import 'alerts/alerts_screen.dart';
import 'map/map_screen.dart';
import 'motion.dart';
import 'settings/link_device_screen.dart';
import 'settings/settings_screen.dart';
import 'splash.dart';
import 'trips/trips_screen.dart';

/// Waits for the parent's profile, then shows the tabs — or the link screen if
/// no device is on the profile yet.
class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    ref.watch(pushSetupProvider);          // registers for push once per session
    return profile.when(
      loading: () => const ShellSkeleton(),
      error: (e, _) => Scaffold(body: Center(child: Text('Could not load your profile: $e'))),
      data: (p) => (p == null || p.deviceIds.isEmpty) ? const LinkDeviceScreen() : const _Tabs(),
    );
  }
}

/// Four tabs in an IndexedStack so each keeps its scroll position and map camera.
class _Tabs extends StatefulWidget {
  const _Tabs();
  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabFade(
        switchKey: _index,
        child: IndexedStack(
          index: _index,
          children: [
            MapScreen(onOpenHistory: () => setState(() => _index = 1)),
            const TripsScreen(),
            const AlertsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Symbols.location_on_rounded), selectedIcon: Icon(Symbols.location_on_rounded, fill: 1), label: 'Map Pin'),
          NavigationDestination(icon: Icon(Symbols.history_rounded), selectedIcon: Icon(Symbols.history_rounded, fill: 1), label: 'Trip History'),
          NavigationDestination(icon: Icon(Symbols.notifications_rounded), selectedIcon: Icon(Symbols.notifications_rounded, fill: 1), label: 'Notification'),
          NavigationDestination(icon: Icon(Symbols.settings_rounded), selectedIcon: Icon(Symbols.settings_rounded, fill: 1), label: 'Settings'),
        ],
      ),
    );
  }
}
