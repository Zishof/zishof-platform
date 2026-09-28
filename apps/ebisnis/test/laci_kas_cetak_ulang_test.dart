import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Laci kasir tetap terbuka saat tombol Cetak Struk dipakai dari semua asal
/// layar, termasuk preview dari riwayat/dashboard.
///
/// Laporan lapangan 28-09-2026: setelah fallback PDF printer ditambahkan,
/// cetak dari preview riwayat/dashboard kembali tidak membuka laci walaupun
/// printer aktif. Penyebabnya `modeCetakUlang` dipakai ganda: untuk tampilan
/// preview dan untuk mematikan pulsa laci.
///
/// Berbasis sumber karena jalur cetaknya memanggil winspool.drv lewat FFI dan
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

  test('pembukaan laci otomatis tidak dikunci oleh modeCetakUlang', () {
    expect(struk, contains('final bool bukaLaciSaatCetak;'));
    expect(struk, contains('this.bukaLaciSaatCetak = true'));
    expect(struk, contains('if (bukaLaciSaatCetak) {'),
        reason: 'Cetak Struk dari riwayat/dashboard memakai modeCetakUlang, '
            'tetapi laci tetap harus dibuka saat printer aktif');
    expect(struk, isNot(contains('if (!modeCetakUlang) {')),
        reason: 'modeCetakUlang hanya boleh mengatur tampilan preview, bukan '
            'mematikan pulsa laci pada tombol Cetak Struk');

    final iPenjaga = struk.indexOf('if (bukaLaciSaatCetak) {');
    final iBuka = struk.indexOf('await bukaLaciKasir(', iPenjaga);
    expect(iBuka, greaterThan(iPenjaga),
        reason: 'pemanggilan bukaLaciKasir pada jalur cetak harus berada DI '
            'DALAM flag eksplisit, bukan dikunci mode preview');

    // Jarak dijaga longgar tetapi terbatas: kalau pemanggilannya berpindah
    // keluar blok, jaraknya melonjak dan uji ini merah.
    expect(iBuka - iPenjaga, lessThan(400),
        reason: 'bukaLaciKasir terlalu jauh dari flag bukaLaciSaatCetak -- '
            'kemungkinan sudah tidak berada di dalam blok yang sama');
  });

  test('tiket dapur tidak membuka laci kasir', () {
    expect(struk, contains('jenisDokumen: \'TIKET DAPUR\''));
    expect(struk, contains('bukaLaciSaatCetak: false'));
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

  test('alasan pemisahan pulsa laci tetap tertulis di helper', () {
    expect(laci, contains('JANGAN memindahkan pulsa ini ke dalam'));
    expect(laci, contains('keputusan apakah laci dibuka berada di'));
  });
}
