import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/widgets/app_shell.dart';

/// Permintaan 21-08-2026: SELURUH grup menu sidebar dapat dilipat dan tertutup
/// secara bawaan, KECUALI Operasional yang terbuka sejak awal.
///
/// Uji ini membaca daftar grup yang sesungguhnya dipakai sidebar, sehingga grup
/// baru yang ditambahkan kemudian ikut tercakup tanpa mengubah test.
void main() {
  test('semua grup dapat dilipat', () {
    final tidakDapatDilipat = ringkasanGrupSidebar()
        .where((g) => !g.dapatDilipat)
        .map((g) => g.label);
    expect(tidakDapatDilipat, isEmpty,
        reason:
            'grup ini belum dapat dilipat: ${tidakDapatDilipat.join(", ")}');
  });

  test('hanya Operasional yang terbuka secara bawaan', () {
    final terbuka = ringkasanGrupSidebar()
        .where((g) => g.terbukaBawaan)
        .map((g) => g.label)
        .toList();
    expect(terbuka, ['Operasional']);
  });

  test('setiap grup punya label dan isi', () {
    for (final g in ringkasanGrupSidebar()) {
      expect(g.label.trim(), isNotEmpty);
      expect(g.jumlahItem, greaterThan(0), reason: 'grup ${g.label} kosong');
    }
  });
}
