import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchpack/data/linking.dart';

void main() {
  test('codes are read loosely', () {
    expect(normalizeCode('k7qm-2xpa'), 'K7QM2XPA');
    expect(normalizeCode(' K7QM 2XPA '), 'K7QM2XPA');
    expect(normalizeCode('K7QM2XPA'), 'K7QM2XPA');
  });

  test('codes that cannot exist', () {
    expect(normalizeCode('K7QM-2XP'), isNull);       // too short
    expect(normalizeCode('K7QM-2XPA9'), isNull);     // too long
    expect(normalizeCode('K7QM-2XP0'), isNull);      // 0 is not in the alphabet
    expect(normalizeCode('K7QM-2XPI'), isNull);      // nor is I
    expect(normalizeCode(''), isNull);
  });

  test('formatting', () {
    expect(fmtCode('K7QM2XPA'), 'K7QM-2XPA');
    expect(fmtCode('short'), 'short');
  });

  test('scanned QR codes', () {
    expect(codeFromScan(qrPayload('K7QM2XPA')), 'K7QM2XPA');
    expect(codeFromScan('watchpack:k7qm-2xpa'), 'K7QM2XPA');
    expect(codeFromScan('K7QM-2XPA'), 'K7QM2XPA');                  // a bare code
    expect(codeFromScan('https://example.com/K7QM2XPA'), isNull);     // someone else's QR
    expect(codeFromScan('WATCHPACK:'), isNull);
  });

  test('new codes are always valid', () {
    final rng = Random(7);
    for (var i = 0; i < 500; i++) {
      final c = newCode(rng);
      expect(c.length, 8);
      expect(normalizeCode(c), c);
    }
  });
}
