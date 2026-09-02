import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tombol Inventory & Sales mengikuti hak dari konteks aktor.
///
/// Modul ini SUDAH punya plumbing-nya sejak awal: `si_actor_context` mengirim
/// `permissions`, `Sesi` menguraikannya, dan `Sesi.bolehAksiIs(menu, aksi)` siap
/// dipakai. Yang kurang hanya pemakaiannya di sebagian layar — jadi tidak ada
/// mekanisme baru di sini, hanya penjaga yang sudah ada dipakai konsisten.
String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

String _layar(String berkas) =>
    _rapat(File('lib/screens/inventory_sales/$berkas').readAsStringSync());

void main() {
  test('sesi Nota Sales memadamkan tombol transaksinya', () {
    // Layar ini sebelumnya NOL gerbang untuk enam aksi mutasi, padahal peladen
    // memeriksa kunci nota_sales enam kali. Sesi keliling dikerjakan di lapangan:
    // penolakan yang baru muncul sesudah tombol ditekan berarti sales sudah
    // terlanjur mencatat transaksi di depan pelanggan.
    final s = _layar('nota_sales_screen.dart');
    expect(s, contains(_rapat("bolehAksiIs('nota_sales', aksi)")));
    expect(s, contains(_rapat("_bolehSesi('create')")));
    expect(s, contains(_rapat("_bolehSesi('update')")));
  });

  test('penjaga tidak memadamkan tombol saat konteks aktor belum dimuat', () {
    // bolehAksiIs fail-closed. Bila dipakai polos sebelum konteks tiba, seluruh
    // tombol padam untuk pengguna yang sebenarnya berhak — dan menyala sendiri
    // beberapa detik kemudian, gejala yang mahal dilacak.
    for (final berkas in [
      'nota_sales_screen.dart',
      'piutang_screen.dart',
      'hutang_supplier_screen.dart',
      'spj_screen.dart',
    ]) {
      expect(_layar(berkas), contains(_rapat('crudInventorySales.isEmpty')),
          reason: '$berkas memadamkan tombol sebelum konteks aktor tiba');
    }
  });

  test('reversal adalah wewenang terpisah dari membuat', () {
    // Membalik kwitansi/voucher yang sudah posting bukan pekerjaan yang sama
    // dengan menerbitkannya, jadi tidak boleh menumpang hak create.
    expect(_layar('piutang_screen.dart'),
        contains(_rapat("bolehAksiIs('piutang', 'delete')")));
    expect(_layar('hutang_supplier_screen.dart'),
        contains(_rapat("bolehAksiIs('hutang', 'delete')")));
  });

  test('Mulai Jalan memakai hak SPJ, bukan dibiarkan terbuka', () {
    expect(_layar('spj_screen.dart'),
        contains(_rapat("bolehAksiIs('surat_perintah_sales', 'update')")));
  });
}
