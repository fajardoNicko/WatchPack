import 'package:latlong2/latlong.dart';

/// Rough dead reckoning between device reports. The WatchPack reports every 30 s
/// (10 s in SOS); in between, the map keeps the pin moving along the last heading
/// at the reported speed for at most one report interval, then holds it there until
/// the next report. Only an estimate: turns and stops show up with the next fix.
class Estimate {
  const Estimate({required this.fix, required this.fixedAt, this.speedKmh = 0, this.bearing});

  /// Builds the estimate for a new report at [fix], heading on from [from] (the
  /// previous report, or the trail). Moves only if the child is going faster than
  /// walking-drift speed and the report is fresh — an old position stays put.
  factory Estimate.from({
    required LatLng fix,
    required double speedKmh,
    required DateTime? seenAt,
    LatLng? from,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final fresh = seenAt != null && n.difference(seenAt) <= horizon * 2;
    final heading = from != null && _d.distance(from, fix) >= minStepM ? _d.bearing(from, fix) : null;
    return Estimate(fix: fix, fixedAt: n, speedKmh: fresh ? speedKmh : 0, bearing: heading);
  }

  final LatLng fix;
  final DateTime fixedAt;                  // when the app got the report
  final double speedKmh;
  final double? bearing;                   // degrees from north; null = heading unknown

  static const horizon = Duration(seconds: 30);
  static const minKmh = 3.0;               // the firmware's own "moving" threshold
  static const minStepM = 5.0;             // closer than this, two fixes give no heading
  static const _d = DistanceHaversine(roundResult: false);

  bool get moves => bearing != null && speedKmh >= minKmh;

  /// Where the child probably is at [now].
  LatLng positionAt(DateTime now) {
    if (!moves) return fix;
    final dt = now.difference(fixedAt);
    if (dt <= Duration.zero) return fix;
    final seconds = (dt < horizon ? dt : horizon).inMilliseconds / 1000;
    return _d.offset(fix, speedKmh / 3.6 * seconds, bearing!);
  }

  /// True while [positionAt] still changes.
  bool movingAt(DateTime now) => moves && now.difference(fixedAt) < horizon;

  /// The latest of [points] (oldest first) at least [minStepM] from [fix] — where the
  /// child came from, for a heading when the app has seen only one report so far.
  static LatLng? cameFrom(List<LatLng> points, LatLng fix) {
    for (var i = points.length - 1; i >= 0 && i >= points.length - 10; i--) {
      if (_d.distance(points[i], fix) >= minStepM) return points[i];
    }
    return null;
  }
}
