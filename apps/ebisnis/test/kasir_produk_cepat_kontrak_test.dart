import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak fitur lapangan 30 Agustus 2026 (laporan toko Al-Bahjah):
/// 1. Dropdown pencarian kasir yang kosong menawarkan "Sinkronkan Produk"
///    (tarik ulang katalog ke cache) dan "Tambah produk ini" (buat produk
///    ber-barcode hasil scan tanpa meninggalkan kasir. Produk disimpan lokal
///    dahulu dan baru masuk keranjang setelah mendapat id server.
/// 2. Server menolak barcode produk yang sama dgn produk lain di TOKO YANG
///    SAMA (toko berbeda boleh) -- diverifikasi kompilasi javac; penanda
///    source backend tidak dicek dari sini karena beda repo (SVN).
/// 3. Sheet split metode pembayaran punya tombol "Sinkronkan cara
///    pembayaran" yang memuat ulang izin metode member dari server tanpa
///    menutup sheet, dan membuang slot yang metodenya sudah dicabut.
void main() {
  String rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

  test('dropdown kasir kosong menawarkan sinkron produk + tambah cepat', () {
    final source =
        rapat(File('lib/screens/kasir_screen.dart').readAsStringSync());
    expect(source, contains(rapat("const Text('Sinkronkan Produk')")));
    expect(source, contains(rapat("const Text('Tambah produk ini')")));
    expect(source,
        contains(rapat("SinkronisasiTabelService.instance.sinkronkan('produk_cache')")),
        reason: 'sinkron produk kasir harus lewat jalur service yang sama '
            'dgn menu Sinkronisasi');
    // Tambah cepat wajib memakai alur local-first generik. Id sementara tidak
    // boleh masuk keranjang/transaksi sebelum server memberi id positif.
    expect(source, contains(rapat("aksi: 'produk_simpan'")));
    expect(source, contains(rapat('prosesSimpanMaster(')));
    expect(source, contains(rapat('MasterOffline.idSementaraBaru()')));
    expect(source, contains(rapat("hasil['offline'] == true")));
    expect(source, contains(rapat('upsertProdukCache')));
    expect(source, contains(rapat('_pilihHasilPencarian(Produk.fromJson')));
  });

  test('sheet split punya tombol sinkron metode pembayaran', () {
    final source =
        rapat(File('lib/screens/keranjang_screen.dart').readAsStringSync());
    expect(source,
        contains(rapat("const Text('Sinkronkan cara pembayaran')")));
    // Muat ulang lewat jalur izin-member yang sama dgn pembukaan sheet.
    expect(source, contains(rapat('muatUlang: () async {')));
    expect(source, contains(rapat('_muatCaraBayarUntukMember(')));
    // Slot metode yang dicabut admin dibuang, tidak dibiarkan terbayar.
    expect(source, contains(rapat('_terpilih.removeWhere')));
  });
}
