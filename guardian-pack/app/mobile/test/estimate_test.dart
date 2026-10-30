import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:watchpack/data/estimate.dart';

void main() {
  const d = DistanceHaversine(roundResult: false);
  final t0 = DateTime(2026, 10, 30, 7, 30);
  const school = LatLng(14.6840, 120.9860);
  final north = d.offset(school, 100, 0);           // came from 100 m south, heading north

  test('keeps going at the reported speed along the heading', () {
    final e = Estimate.from(fix: north, speedKmh: 18, seenAt: t0, from: school, now: t0);
    final p = e.positionAt(t0.add(const Duration(seconds: 10)));
    expect(d.distance(north, p), closeTo(50, 0.5));    // 18 km/h = 5 m/s
    expect(p.latitude, greaterThan(north.latitude));
    expect(e.movingAt(t0.add(const Duration(seconds: 10))), isTrue);
  });

  test('stops one report interval ahead and holds there', () {
    final e = Estimate.from(fix: north, speedKmh: 18, seenAt: t0, from: school, now: t0);
    final at30 = e.positionAt(t0.add(const Duration(seconds: 30)));
    final at90 = e.positionAt(t0.add(const Duration(seconds: 90)));
    expect(d.distance(north, at30), closeTo(150, 1));
    expect(at90, at30);
    expect(e.movingAt(t0.add(const Duration(seconds: 31))), isFalse);
  });

  test('stays put when slow, without a heading, or on an old report', () {
    final slow = Estimate.from(fix: north, speedKmh: 2, seenAt: t0, from: school, now: t0);
    final noHeading = Estimate.from(fix: north, speedKmh: 18, seenAt: t0, now: t0);
    final old = Estimate.from(fix: north, speedKmh: 18, seenAt: t0.subtract(const Duration(minutes: 5)), from: school, now: t0);
    final later = t0.add(const Duration(seconds: 20));
    for (final e in [slow, noHeading, old]) {
      expect(e.positionAt(later), north);
      expect(e.movingAt(later), isFalse);
    }
  });

  test('heading from the trail skips points on top of the fix', () {
    final jitter = d.offset(north, 2, 90);
    expect(Estimate.cameFrom([school, jitter, north], north), school);
    expect(Estimate.cameFrom([north, jitter], north), isNull);
    expect(Estimate.cameFrom(const [], north), isNull);
  });
}
