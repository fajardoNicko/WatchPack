import 'package:latlong2/latlong.dart';

import 'models.dart';

/// Derives trips from raw fixes. Pure functions, no Flutter.

const _dist = Distance();
const _movingKmh = 2.0;                       // below this we treat the device as stopped
const _idleMin = Duration(minutes: 3);        // a stop shorter than this is just traffic

enum SegmentKind { moving, idle }

class Segment {
  const Segment({required this.kind, required this.start, required this.end, required this.meters, required this.fixes});
  final SegmentKind kind;
  final DateTime start, end;
  final double meters;
  final List<Fix> fixes;
  Duration get duration => end.difference(start);
}

class TripSummary {
  const TripSummary({required this.meters, required this.moving, required this.segments, required this.first, required this.last});
  final double meters;
  final Duration moving;
  final List<Segment> segments;
  final DateTime? first, last;

  double get avgKmh => moving.inSeconds == 0 ? 0 : (meters / 1000) / (moving.inSeconds / 3600);

  static const empty = TripSummary(meters: 0, moving: Duration.zero, segments: [], first: null, last: null);

  static TripSummary compute(List<Fix> fixes) {
    if (fixes.length < 2) return empty;

    // 1. Label each fix moving/stopped, then merge into runs.
    final runs = <Segment>[];
    var runStart = 0;
    bool movingAt(int i) => fixes[i].speedKmh >= _movingKmh;
    for (var i = 1; i <= fixes.length; i++) {
      if (i == fixes.length || movingAt(i) != movingAt(runStart)) {
        final slice = fixes.sublist(runStart, i);
        runs.add(Segment(
          kind: movingAt(runStart) ? SegmentKind.moving : SegmentKind.idle,
          start: slice.first.ts,
          end: i < fixes.length ? fixes[i].ts : slice.last.ts,
          meters: _pathMeters(slice),
          fixes: slice,
        ));
        runStart = i;
      }
    }

    // 2. Short stops are absorbed into the surrounding movement.
    final merged = <Segment>[];
    for (final r in runs) {
      final prev = merged.isEmpty ? null : merged.last;
      final absorb = r.kind == SegmentKind.idle && r.duration < _idleMin && prev != null && prev.kind == SegmentKind.moving;
      if (absorb || (prev != null && prev.kind == r.kind)) {
        merged[merged.length - 1] = Segment(
          kind: prev.kind,
          start: prev.start,
          end: r.end,
          meters: prev.meters + r.meters,
          fixes: [...prev.fixes, ...r.fixes],
        );
      } else {
        merged.add(r);
      }
    }

    final movingSegs = merged.where((s) => s.kind == SegmentKind.moving);
    return TripSummary(
      meters: movingSegs.fold(0, (a, s) => a + s.meters),
      moving: movingSegs.fold(Duration.zero, (a, s) => a + s.duration),
      segments: merged,
      first: fixes.first.ts,
      last: fixes.last.ts,
    );
  }
}

double _pathMeters(List<Fix> f) {
  var m = 0.0;
  for (var i = 1; i < f.length; i++) {
    m += _dist.as(LengthUnit.Meter, f[i - 1].point, f[i].point);
  }
  return m;
}

/// Ramer–Douglas–Peucker: fewer points on the map, same shape. Tolerance in metres.
List<LatLng> simplify(List<LatLng> pts, {double toleranceM = 8}) {
  if (pts.length < 3) return pts;
  final keep = List<bool>.filled(pts.length, false)..[0] = true..[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0, idx = -1;
    for (var i = a + 1; i < b; i++) {
      final d = _perpMeters(pts[i], pts[a], pts[b]);
      if (d > maxD) { maxD = d; idx = i; }
    }
    if (maxD > toleranceM && idx > 0) {
      keep[idx] = true;
      stack..add((a, idx))..add((idx, b));
    }
  }
  return [for (var i = 0; i < pts.length; i++) if (keep[i]) pts[i]];
}

double _perpMeters(LatLng p, LatLng a, LatLng b) {
  // Small-area planar approximation, good enough at city scale.
  final kx = 111320.0 * _cos(a.latitude), ky = 110540.0;
  final ax = a.longitude * kx, ay = a.latitude * ky;
  final bx = b.longitude * kx, by = b.latitude * ky;
  final px = p.longitude * kx, py = p.latitude * ky;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return _hyp(px - ax, py - ay);
  final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  return _hyp(px - (ax + t * dx), py - (ay + t * dy));
}

double _cos(double deg) => _cosRad(deg * 3.141592653589793 / 180);
double _cosRad(double r) { var t = 1.0, s = 1.0; for (var i = 1; i < 12; i++) { t *= -r * r / ((2 * i - 1) * (2 * i)); s += t; } return s; }
double _hyp(double x, double y) { var v = x * x + y * y; if (v == 0) return 0; var g = v; for (var i = 0; i < 30; i++) { g = 0.5 * (g + v / g); } return g; }
