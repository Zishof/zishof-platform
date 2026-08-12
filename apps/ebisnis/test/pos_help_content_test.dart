import 'package:ebisnis/screens/apotik/pos_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setiap bantuan POS memiliki narasi minimal 1000 kata dan workflow', () {
    expect(PosHelpCatalog.specs.length, 16);
    for (final entry in PosHelpCatalog.specs.entries) {
      final words = entry.value.narrative
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      expect(words, greaterThanOrEqualTo(1000),
          reason: '${entry.key} hanya memiliki $words kata');
      expect(entry.value.flow.length, greaterThanOrEqualTo(6));
    }
  });
}
