import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../auth/auth.dart';
import '../data/repo.dart';
import '../data/unread.dart';
import '../push/push.dart';
import 'alerts/alerts_screen.dart';
import 'map/map_screen.dart';
import 'motion.dart';
import 'nav.dart';
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
class _Tabs extends ConsumerStatefulWidget {
  const _Tabs();
  @override
  ConsumerState<_Tabs> createState() => _TabsState();
}

class _TabsState extends ConsumerState<_Tabs> {
  @override
  void initState() {
    super.initState();
    // A notification tap that launched the app arrived before the tabs existed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final t = ref.read(pushOpenProvider);
      if (t != null && mounted) _open(t);
    });
  }

  /// Shows what a tapped notification is about: its device, then the map (where
  /// the child is) or the alert feed.
  void _open(PushTarget t) {
    final ids = ref.read(userProfileProvider).value?.deviceIds ?? const [];
    if (t.deviceId != null && ids.contains(t.deviceId)) ref.read(selectedDeviceProvider.notifier).select(t.deviceId!);
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (t.showsMap) {
      ref.read(tabProvider.notifier).set(0);
    } else {
      ref.read(alertsSegmentProvider.notifier).set(1);
      ref.read(tabProvider.notifier).set(2);
    }
    ref.read(pushOpenProvider.notifier).handled();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pushOpenProvider, (_, t) { if (t != null) _open(t); });
    final index = ref.watch(tabProvider);
    final unread = ref.watch(unreadAlertsProvider);
    final setTab = ref.read(tabProvider.notifier).set;
    return Scaffold(
      body: TabFade(
        switchKey: index,
        child: IndexedStack(
          index: index,
          children: [
            MapScreen(onOpenHistory: () => setTab(1)),
            const TripsScreen(),
            const AlertsScreen(),
            const SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: setTab,
        destinations: [
          const NavigationDestination(icon: Icon(Symbols.location_on_rounded), selectedIcon: Icon(Symbols.location_on_rounded, fill: 1), label: 'Map Pin'),
          const NavigationDestination(icon: Icon(Symbols.history_rounded), selectedIcon: Icon(Symbols.history_rounded, fill: 1), label: 'Trip History'),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Symbols.notifications_rounded)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Symbols.notifications_rounded, fill: 1)),
            label: 'Notification',
          ),
          const NavigationDestination(icon: Icon(Symbols.settings_rounded), selectedIcon: Icon(Symbols.settings_rounded, fill: 1), label: 'Settings'),
        ],
      ),
    );
  }
}
