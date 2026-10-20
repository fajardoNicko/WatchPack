import 'package:flutter_test/flutter_test.dart';
import 'package:watchpack/data/models.dart';

void main() {
  test('zone kinds saved before the new places still read back', () {
    for (final n in ['home', 'school', 'park', 'other']) {
      expect(ZoneType.values.byName(n).name, n);
    }
  });

  test('every kind has a label, a default name and an example', () {
    for (final z in ZoneType.values) {
      expect(z.label, isNotEmpty);
      expect(z.defaultName, isNotEmpty);
      expect(z.example, isNotEmpty);
      expect(z.label.length, lessThanOrEqualTo(8), reason: 'fits a chip five to a row');
    }
  });
}
