import 'package:ebisnis/screens/bantuan_kontekstual.dart';
import 'package:ebisnis/screens/tanya_jawab_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setiap menu memiliki QA kontekstual minimal 2000 kata', () {
    for (final entry in spesifikasiBantuanMenu.entries) {
      final qa = tanyaJawabUntukMenu(entry.key, entry.value.judul);
      expect(qa.length, greaterThanOrEqualTo(10), reason: entry.key);
      expect(jumlahKataTanyaJawab(qa), greaterThanOrEqualTo(2000),
          reason: entry.key);
    }
  });
}
