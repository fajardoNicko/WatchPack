import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:watchpack/data/models.dart';
import 'package:watchpack/data/trips.dart';

/// A day of fixes 30 s apart, heading north at the given speed.
class _Day {
  var ts = DateTime(2026, 10, 20, 7);
  var lat = 14.68;
  final fixes = <Fix>[];

  void add(int count, double kmh) {
    for (var i = 0; i < count; i++) {
      fixes.add(Fix(point: LatLng(lat, 120.98), speedKmh: kmh, ts: ts));
      ts = ts.add(const Duration(seconds: 30));
      lat += kmh / 3.6 * 30 / 110600;           // metres → degrees of latitude here
    }
  }
}

void main() {
  group('TripSummary', () {
    test('needs two fixes', () {
      expect(TripSummary.compute(const []).segments, isEmpty);
      final one = _Day()..add(1, 0);
      expect(TripSummary.compute(one.fixes).segments, isEmpty);
    });

    test('home, a ride with a short stop, then school', () {
      final day = _Day()
        ..add(20, 0)       // 07:00 at home
        ..add(20, 30)      // 07:10 riding, 250 m per fix
        ..add(2, 0)        // 07:20 one-minute stop at a light
        ..add(10, 30)      // 07:21 riding again
        ..add(20, 0);      // 07:26 at school
      final s = TripSummary.compute(day.fixes);

      expect(s.segments.map((x) => x.kind), [SegmentKind.idle, SegmentKind.moving, SegmentKind.idle]);
      final ride = s.segments[1];
      expect(ride.start, DateTime(2026, 10, 20, 7, 10));
      expect(ride.end, DateTime(2026, 10, 20, 7, 26));
      expect(s.moving, const Duration(minutes: 16));
      expect(s.meters, closeTo(7000, 100));       // 19 + 9 steps of 250 m
      expect(s.avgKmh, closeTo(26.25, 0.5));
      expect(s.first, day.fixes.first.ts);
      expect(s.last, day.fixes.last.ts);
    });

    test('a long stop stays its own segment', () {
      final day = _Day()
        ..add(10, 20)
        ..add(10, 0)       // 5 min
        ..add(10, 20);
      expect(TripSummary.compute(day.fixes).segments.map((x) => x.kind),
          [SegmentKind.moving, SegmentKind.idle, SegmentKind.moving]);
    });
  });

  group('simplify', () {
    test('a straight line keeps only its ends', () {
      final line = [for (var i = 0; i < 50; i++) LatLng(14.68 + i * 0.0005, 120.98)];
      expect(simplify(line), [line.first, line.last]);
    });

    test('keeps a corner', () {
      final pts = [
        for (var i = 0; i <= 10; i++) LatLng(14.68 + i * 0.0005, 120.98),
        for (var i = 1; i <= 10; i++) LatLng(14.685, 120.98 + i * 0.0005),
      ];
      expect(simplify(pts), [pts.first, pts[10], pts.last]);
    });

    test('short lists pass through', () {
      const two = [LatLng(14.6, 121.0), LatLng(14.7, 121.0)];
      expect(simplify(two), two);
    });
  });
}
