import 'package:flutter_test/flutter_test.dart';
import 'package:watchpack/util/format.dart';

void main() {
  test('durations', () {
    expect(fmtDuration(const Duration(seconds: 42)), '42 s');
    expect(fmtDuration(const Duration(minutes: 5)), '5 min');
    expect(fmtDuration(const Duration(hours: 2)), '2 h');
    expect(fmtDuration(const Duration(hours: 1, minutes: 5)), '1 h 5 min');
  });

  test('distances and speeds', () {
    expect(fmtKm(850), '850 m');
    expect(fmtKm(1234), '1.2 km');
    expect(fmtSpeed(4.2), '4.2 km/h');
    expect(fmtSpeed(23.6), '24 km/h');
  });

  test('relative times', () {
    final now = DateTime(2026, 10, 20, 12);
    expect(fmtRelative(null), 'never');
    expect(fmtRelative(now.subtract(const Duration(seconds: 10)), now: now), 'just now');
    expect(fmtRelative(now.subtract(const Duration(seconds: 50)), now: now), '1 min ago');
    expect(fmtRelative(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(fmtRelative(now.subtract(const Duration(minutes: 75)), now: now), 'an hour ago');
    expect(fmtRelative(now.subtract(const Duration(hours: 3)), now: now), '3 hours ago');
    expect(fmtRelative(DateTime(2026, 10, 19, 9), now: now), 'yesterday');
    expect(fmtRelative(DateTime(2026, 10, 18, 9), now: now), 'Sun, Oct 18');
  });

  test('last seen', () {
    final now = DateTime(2026, 10, 20, 12);
    expect(fmtLastSeen(null), 'Not seen yet');
    expect(fmtLastSeen(now.subtract(const Duration(minutes: 70)), now: now), 'Last seen an hour ago');
  });

  test('days', () {
    expect(dateOnly(DateTime(2026, 10, 20, 17, 13)), DateTime(2026, 10, 20));
    expect(sameDay(DateTime(2026, 10, 20, 0, 1), DateTime(2026, 10, 20, 23, 59)), isTrue);
    expect(sameDay(DateTime(2026, 10, 20), DateTime(2026, 10, 21)), isFalse);
  });

  test('PH mobile numbers', () {
    expect(normalizePhPhone('0917 123 4567'), '+639171234567');
    expect(normalizePhPhone('+63 917-123-4567'), '+639171234567');
    expect(normalizePhPhone('639171234567'), '+639171234567');
    expect(normalizePhPhone('+639171234567'), '+639171234567');
    expect(normalizePhPhone('12345'), isNull);
    expect(normalizePhPhone('028123456'), isNull);              // landline
    expect(normalizePhPhone('0917123456'), isNull);             // one digit short
  });
}
