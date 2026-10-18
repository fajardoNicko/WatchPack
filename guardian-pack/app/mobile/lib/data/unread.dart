import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'repo.dart';

/// Unread alerts: newer than the last time the Alert feed was open on this phone.
/// Kept per device in shared_preferences (`alertsSeen.{deviceId}` = epoch ms).

const _prefix = 'alertsSeen.';

/// Null until loaded from disk.
class AlertsSeen extends Notifier<Map<String, DateTime>?> {
  @override
  Map<String, DateTime>? build() {
    SharedPreferences.getInstance().then((p) {
      state = {
        for (final k in p.getKeys().where((k) => k.startsWith(_prefix)))
          k.substring(_prefix.length): DateTime.fromMillisecondsSinceEpoch(p.getInt(k) ?? 0),
      };
    });
    return null;
  }

  Future<void> markSeen(String deviceId) async {
    final now = DateTime.now();
    state = {...?state, deviceId: now};
    await (await SharedPreferences.getInstance()).setInt('$_prefix$deviceId', now.millisecondsSinceEpoch);
  }
}

final alertsSeenProvider = NotifierProvider<AlertsSeen, Map<String, DateTime>?>(AlertsSeen.new);

final unreadAlertsProvider = Provider<int>((ref) {
  final id = ref.watch(deviceIdProvider);
  final seen = ref.watch(alertsSeenProvider);
  if (id == null || seen == null) return 0;
  final alerts = ref.watch(alertsProvider).value ?? const [];
  // Never opened on this phone: only the last day counts, not the whole history.
  final since = seen[id] ?? DateTime.now().subtract(const Duration(days: 1));
  return alerts.where((a) => a.ts.isAfter(since)).length;
});
