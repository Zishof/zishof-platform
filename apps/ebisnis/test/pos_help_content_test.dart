import 'package:ebisnis/screens/apotik/pos_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setiap bantuan POS memiliki narasi minimal 3500 kata dan workflow', () {
    expect(PosHelpCatalog.specs.length, 17);
    for (final entry in PosHelpCatalog.specs.entries) {
      final words = entry.value.narrative
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      expect(words, greaterThanOrEqualTo(3500),
          reason: '${entry.key} hanya memiliki $words kata');
      expect(entry.value.flow.length, greaterThanOrEqualTo(6));
    }
  });
}
