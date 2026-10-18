import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tab and which Notification segment are showing — providers rather than
/// widget state so a tapped push notification can move the app to the right place.
/// One notifier class each: two providers built from the same class shared state.

class TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

/// 0 Map Pin · 1 Trip History · 2 Notification · 3 Settings
final tabProvider = NotifierProvider<TabIndex, int>(TabIndex.new);

class AlertsSegment extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

/// Notification tab: 0 Zones & triggers · 1 Alert feed
final alertsSegmentProvider = NotifierProvider<AlertsSegment, int>(AlertsSegment.new);
