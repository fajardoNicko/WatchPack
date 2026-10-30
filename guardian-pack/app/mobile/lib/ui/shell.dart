import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../auth/auth.dart';
import '../data/linking.dart';
import '../data/repo.dart';
import '../data/unread.dart';
import '../push/push.dart';
import 'alerts/alerts_screen.dart';
import 'map/map_screen.dart';
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

  final _removals = <String>{};

  /// Another parent removed me from [deviceId]: say so and drop it from my profile.
  void _removed(String deviceId, String by) {
    if (!_removals.add(deviceId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final d = ref.read(deviceProvider).value;
      final child = d != null && d.id == deviceId ? '${d.name}\'s WatchPack' : 'a WatchPack';
      final messenger = ScaffoldMessenger.of(context);
      ref.read(linkActionsProvider).unlink(deviceId).catchError((_) {});
      messenger.showSnackBar(SnackBar(
        content: Text('$by removed you from $child. Ask for a new invite to see it again.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pushOpenProvider, (_, t) { if (t != null) _open(t); });
    for (final id in ref.watch(userProfileProvider).value?.deviceIds ?? const <String>[]) {
      final by = ref.watch(removalProvider(id)).value;
      if (by != null) {
        _removed(id, by);
      } else {
        _removals.remove(id);             // linked again later: a new removal must show
      }
    }
    final index = ref.watch(tabProvider);
    final unread = ref.watch(unreadAlertsProvider);
    final setTab = ref.read(tabProvider.notifier).set;
    return Scaffold(
      // Tabs swap instantly: no fade or slide between them.
      body: IndexedStack(
        index: index,
        children: [
          MapScreen(onOpenHistory: () => setTab(1)),
          const TripsScreen(),
          const AlertsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: setTab,
        // Same line icon selected or not; the tab shows as selected by its colour.
        destinations: [
          const NavigationDestination(icon: Icon(Symbols.location_on), label: 'Map Pin'),
          const NavigationDestination(icon: Icon(Symbols.history), label: 'Trip History'),
          NavigationDestination(
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Symbols.notifications)),
            label: 'Notification',
          ),
          const NavigationDestination(icon: Icon(Symbols.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
