import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('halaman produk mempunyai tab riwayat audit server', () {
    final layar = File('lib/screens/produk_screen.dart').readAsStringSync();
    final tab = File('lib/screens/produk_riwayat_perubahan_tab.dart')
        .readAsStringSync();

    expect(layar, contains('ProdukRiwayatPerubahanTab'));
    expect(layar, contains("text: 'Riwayat Perubahan'"));
    expect(tab, contains("aksi('revisi_jelajah'"));
    expect(tab, contains("'entitas': 'produk'"));
    expect(tab, contains('nilai lama → nilai baru'));
  });

  test('dialog menerangkan field dan nilai dari-ke', () {
    final dialog =
        File('lib/widgets/riwayat_data_dialog.dart').readAsStringSync();

    expect(dialog, contains("revisi['perubahan']"));
    expect(dialog, contains("p['jenisData']"));
    expect(dialog, contains("p['dari']"));
    expect(dialog, contains("p['menjadi']"));
    expect(dialog, contains('Satuan pembelian'));
    expect(dialog, contains('Harga jual'));
  });
}
