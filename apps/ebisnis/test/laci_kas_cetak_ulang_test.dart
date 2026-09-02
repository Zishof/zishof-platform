import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Laci kasir tidak boleh terbuka saat CETAK ULANG.
///
/// Aturan ini adalah kontrol kas, bukan kerapian. `struk_screen.dart` sendiri
/// menuliskannya:
///
///   "Menghapusnya membuat laci dapat dibuka kapan saja oleh siapa pun cukup
///    dengan membuka riwayat lalu menekan Cetak Ulang, tanpa ada transaksi
///    maupun uang yang masuk."
///
/// Dan `packages/core_hw/lib/src/buka_laci.dart` menuliskan pasangannya:
///
///   "JANGAN memindahkan pulsa ini ke dalam `_strukEscPos`. Aliran struk dibaca
///    juga oleh jalur pratinjau dan cetak ulang; menaruh pulsanya di sana
///    membuat laci terbuka pada cetak ulang struk lama."
///
/// Sampai berkas ini ada, kedua aturan itu dijaga **hanya oleh komentar**.
/// Tidak ada satu uji pun yang menyebut `modeCetakUlang`, `bukaLaciKasir`,
/// maupun `PengaturanLaci`. Komentar tidak dijalankan, tidak dikompilasi, dan
/// tidak menghentikan siapa pun yang merapikan kode enam bulan dari sekarang.
///
/// Berbasis sumber, karena jalur cetaknya memanggil winspool.drv lewat FFI dan
/// tidak dapat dijalankan di uji. Yang ditegaskan sengaja hal yang dapat PATAH,
/// bukan sekadar hal yang ada -- pelajaran docs/pos/85, tempat sebuah uji tetap
/// hijau selama cacatnya hidup karena hanya memeriksa bahwa sebuah nama muncul.
void main() {
  late String struk;
  late String laci;

  setUpAll(() {
    struk = File('lib/screens/struk_screen.dart').readAsStringSync();
    laci = File('../../packages/core_hw/lib/src/buka_laci.dart')
        .readAsStringSync();
  });

  test('pembukaan laci otomatis dijaga syarat !modeCetakUlang', () {
    expect(struk, contains('if (!modeCetakUlang) {'),
        reason: 'penjaga cetak-ulang hilang: laci akan terbuka dari menu '
            'riwayat tanpa ada uang masuk');

    final iPenjaga = struk.indexOf('if (!modeCetakUlang) {');
    final iBuka = struk.indexOf('await bukaLaciKasir(', iPenjaga);
    expect(iBuka, greaterThan(iPenjaga),
        reason: 'pemanggilan bukaLaciKasir pada jalur cetak harus berada DI '
            'DALAM penjaga, bukan sebelum atau sesudahnya');

    // Jarak dijaga longgar tetapi terbatas: kalau pemanggilannya berpindah
    // keluar blok, jaraknya melonjak dan uji ini merah.
    expect(iBuka - iPenjaga, lessThan(400),
        reason: 'bukaLaciKasir terlalu jauh dari penjaganya -- kemungkinan '
            'sudah tidak berada di dalam blok yang sama');
  });

  test('pulsa buka laci tidak boleh masuk ke aliran ESC/POS struk', () {
    // Aliran struk dipakai juga oleh pratinjau dan cetak ulang. Pulsa di sana
    // membuat laci terbuka pada struk lama.
    for (final pola in ['0x1B, 0x70', '0x1b, 0x70', '27, 112']) {
      expect(struk.contains(pola), isFalse,
          reason: 'pulsa buka laci ($pola) muncul di struk_screen.dart; '
              'ia hanya boleh berada di core_hw/buka_laci.dart');
    }
  });

  test('pulsa laci tetap berada di satu tempat', () {
    expect(laci, contains('0x1B, 0x70, 0x00, 0x19, 0xFA'));
    expect(laci, contains('0x1B, 0x70, 0x01, 0x19, 0xFA'));
  });

  test('alasan kontrol kas tetap tertulis di dekat penjaganya', () {
    // Kalau alasannya hilang, penjaganya akan tampak seperti kerapian dan
    // orang berikutnya akan menghapusnya dengan niat baik.
    expect(struk, contains('kontrol kas'));
    expect(laci, contains('JANGAN memindahkan pulsa ini ke dalam'));
  });
}
