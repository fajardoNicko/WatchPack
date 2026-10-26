import 'package:flutter_test/flutter_test.dart';
import 'package:watchpack/data/models.dart';

void main() {
  final now = DateTime(2026, 10, 26, 20, 0);
  DateTime ago(int min) => now.subtract(Duration(minutes: min));
  DeviceStatus status(String stored, {int? seenMin, int? sosMin, int? clearedMin}) => Device.effectiveStatus(
        stored,
        now: now,
        seen: seenMin == null ? null : ago(seenMin),
        sosAt: sosMin == null ? null : ago(sosMin),
        sosClearedAt: clearedMin == null ? null : ago(clearedMin),
      );

  test('normal states, and offline after 15 quiet minutes', () {
    expect(status('moving', seenMin: 1), DeviceStatus.moving);
    expect(status('idle', seenMin: 14), DeviceStatus.idle);
    expect(status('idle', seenMin: 16), DeviceStatus.offline);
    expect(status('idle'), DeviceStatus.offline);
  });

  test('an SOS stays up even when the device goes quiet', () {
    expect(status('sos', seenMin: 600, sosMin: 600), DeviceStatus.sos);
  });

  test('marked safe clears it, a newer press brings it back', () {
    expect(status('sos', seenMin: 1, sosMin: 30, clearedMin: 5), DeviceStatus.idle);
    expect(status('sos', seenMin: 600, sosMin: 600, clearedMin: 5), DeviceStatus.offline);
    expect(status('sos', seenMin: 1, sosMin: 2, clearedMin: 5), DeviceStatus.sos);
  });
}
