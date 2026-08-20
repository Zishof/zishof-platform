import 'package:ebisnis/screens/bantuan_content.dart';
import 'package:ebisnis/screens/bantuan_kontekstual.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('setiap panduan platform berisi minimal 3500 kata', () {
    expect(artikelBantuan, hasLength(3));
    for (final artikel in artikelBantuan) {
      expect(
        artikel.jumlahKata,
        greaterThanOrEqualTo(3500),
        reason: '${artikel.judul} hanya ${artikel.jumlahKata} kata',
      );
    }
  });

  test('setiap panduan mempunyai struktur operasional lengkap', () {
    for (final artikel in artikelBantuan) {
      expect(artikel.bagian.length, greaterThanOrEqualTo(10));
      expect(artikel.ringkasan, isNotEmpty);
    }
  });

  test('setiap menu memiliki bantuan kontekstual minimal 3500 kata dan diagram',
      () {
    // Harus sama dengan jumlah MenuEBisnis pada app_shell.dart. Penambahan menu
    // baru wajib diikuti artikel bantuan sebelum test ini dapat lulus.
    expect(spesifikasiBantuanMenu.length, 50);
    for (final entri in spesifikasiBantuanMenu.entries) {
      final artikel =
          artikelBantuanUntukMenu(entri.key, entri.value.judul, 'android');
      expect(artikel.jumlahKata, greaterThanOrEqualTo(3500),
          reason:
              'Bantuan ${entri.value.judul} hanya ${artikel.jumlahKata} kata');
      expect(artikel.workflow.length, greaterThanOrEqualTo(5));
      expect(artikel.ilustrasi.length, greaterThanOrEqualTo(5));
      expect(artikel.bagian.length, greaterThanOrEqualTo(12));
    }
  });
}
