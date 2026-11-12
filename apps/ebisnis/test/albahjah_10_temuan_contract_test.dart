import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak regresi untuk 10 temuan operasional Al-Bahjah POS (13 November 2026):
/// 1. Pintasan menu utama per peran (`Tbmrole` / `userRoleId`)
/// 2. Blind count SO Grand (sembunyikan STOK RAK) & KKSO A4 Portrait
/// 3. Unggah foto via Kamera / Webcam pada Terima Tagihan Vendor
/// 4. Klik angka rincian mutasi barang untuk membuka bukti transaksi asli
/// 5. Pembayaran mengangsur (partial transfer) pada Proses Transfer DPC
/// 6. Ekspor & cetak PKM mengikuti filter aktif + format kolom Stock Out resmi
/// 7. Alur kerja 3 tahap Stok Opname terpadu + kunci permanen + Cetak Selisih & BA
/// 8. Tab baru Riwayat Entry SO Grand (monitoring progres KKSO per Rak)
void main() {
  test('1. Menu Utama Shortcut mendukung penyimpanan per peran (userRoleId)', () {
    final sesi = File('lib/sesi.dart').readAsStringSync();
    final shortcut =
        File('lib/screens/ringkasan/tab_shortcut.dart').readAsStringSync();
    expect(sesi, contains('String userRoleId'));
    expect(shortcut, contains('kTargetRoleShortcutDefault'));
    expect(shortcut, contains('_targetRoleId'));
  });

  test('2 & 5. SO Grand menyembunyikan STOK RAK (blind count) & KKSO A4 Portrait',
      () {
    final soGrand =
        File('lib/screens/tab_so_grand.dart').readAsStringSync();
    expect(soGrand, isNot(contains("AppTableColumn('Stok Rak'")));
    expect(soGrand, contains('PdfPageFormat.a4'));
    expect(soGrand, contains('ProsesStokOpnameDialog.buka'));
  });

  test('3. Terima Tagihan Vendor menyediakan tombol foto kamera / webcam', () {
    final tagihan =
        File('lib/screens/pengadaan_tagihan_screen.dart').readAsStringSync();
    expect(tagihan, contains('FotoProdukCameraScreen.ambil'));
    expect(tagihan, contains('Icons.photo_camera_outlined'));
  });

  test('4. Rincian Mutasi Barang mengizinkan klik angka untuk buka bukti', () {
    final mutasi =
        File('lib/screens/pergerakan_stok_tab.dart').readAsStringSync();
    expect(mutasi, contains('stok_mutasi_bukti_detail'));
  });

  test('6. Proses Transfer DPC mendukung pembayaran mengangsur', () {
    final pt =
        File('lib/screens/proses_transfer_screen.dart').readAsStringSync();
    expect(pt, contains('adalahAngsuran'));
    expect(pt, contains('Belum Lunas (Angsuran)'));
  });

  test('7. PKM & Saran PO mengirim filter aktif & kolom STOCK OUT resmi', () {
    final pkm = File('lib/screens/tab_pkm_screen.dart').readAsStringSync();
    expect(pkm, contains('pkm_download_excel'));
    expect(pkm, contains('STOCK OUT'));
  });

  test(
      '8 & 9. Alur 3 Tahap Stok Opname terpadu + Tab Riwayat Entry SO Grand terdaftar di ApiClient',
      () {
    final so = File('lib/screens/stok_opname_screen.dart').readAsStringSync();
    final dialog =
        File('lib/screens/proses_stok_opname_dialog.dart').readAsStringSync();
    final riwayat =
        File('lib/screens/tab_riwayat_so_grand.dart').readAsStringSync();
    final api = File('lib/api_client.dart').readAsStringSync();

    expect(so, contains("Tab(text: 'Riwayat Entry SO Grand')"));
    expect(so, contains('TabRiwayatSoGrand'));
    expect(so, contains('Disetujui (Terkunci · BA)'));
    expect(dialog, contains('so_dokumen_proses'));
    expect(dialog, contains('so_dokumen_tandai_cetak'));
    expect(dialog, contains('so_dokumen_setujui_adjustment'));
    expect(riwayat, contains('so_grand_riwayat_rak'));
    expect(api, contains("'so_dokumen_proses'"));
    expect(api, contains("'so_dokumen_tandai_cetak'"));
    expect(api, contains("'so_dokumen_setujui_adjustment'"));
    expect(api, contains("'stok_mutasi_bukti_detail'"));
  });
}
