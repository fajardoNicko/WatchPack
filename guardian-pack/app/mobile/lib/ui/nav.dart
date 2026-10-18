import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which tab and which Notification segment are showing — providers rather than
/// widget state so a tapped push notification can move the app to the right place.

class _Index extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

/// 0 Map Pin · 1 Trip History · 2 Notification · 3 Settings
final tabProvider = NotifierProvider<_Index, int>(_Index.new);

/// Notification tab: 0 Zones & triggers · 1 Alert feed
final alertsSegmentProvider = NotifierProvider<_Index, int>(_Index.new);
