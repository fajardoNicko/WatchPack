import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The time, refreshed every 30 s, so "last seen 5 min ago" keeps counting while no
/// new data arrives.
class Clock extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => state = DateTime.now());
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }
}

final nowProvider = NotifierProvider<Clock, DateTime>(Clock.new);
