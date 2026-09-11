import 'dart:io';
import 'dart:math';

import 'package:ebisnis/features/apotik/core/apotik_lokal_dulu.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kunci idempotensi penerimaan PBF (`kode_dokumen`).
///
/// Latar belakangnya cacat nyata: layar persediaan lama MENGANTRE
/// `apotik_terima_barang` secara offline dengan alasan "aman karena hanya
/// menambah stok", tanpa kunci apa pun. Bila respons pertama hilang dan
/// antrean mengirim ulang, server membuat kode acak baru dan stok bertambah
/// dua kali. Menambah stok dua kali justru kerusakannya.
void main() {
  group('kodeDokumenPenerimaanBaru', () {
    test('berbentuk PBF-APT-<cap waktu>-<8 hex> dan di bawah 80 karakter', () {
      final kode = kodeDokumenPenerimaanBaru(
          sekarang: DateTime(2026, 9, 11, 7, 5, 9), acak: Random(1));
      expect(kode, matches(RegExp(r'^PBF-APT-20260911070509-[0-9A-F]{8}$')));
      expect(kode.length, lessThan(80));
    });

    test('dua penerimaan berbeda tidak pernah berbagi kunci', () {
      final kunci = <String>{
        for (var i = 0; i < 2000; i++) kodeDokumenPenerimaanBaru(),
      };
      expect(kunci.length, 2000);
    });
  });

  group('Kontrak sumber: kunci ikut terkirim dan dipakai ulang', () {
    test('antrean penerimaan lama menyimpan kode_dokumen di body antrean', () {
      final src = File('lib/screens/apotik/persediaan_apotik_screen.dart')
          .readAsStringSync();
      final i = src.indexOf("aksi: 'apotik_terima_barang'");
      expect(i, greaterThanOrEqualTo(0));
      final sekitar = src.substring(i, i + 400);
      // Kode HARUS di body (bukan hanya kunci antrean lokal), karena body
      // itulah yang dikirim ulang apa adanya oleh antrean.
      expect(sekitar, contains("'kode_dokumen': kodeDokumen"));
      expect(src, isNot(contains('apotik_terima:baru:')),
          reason: 'kunci antrean berbasis waktu tanpa kode_dokumen sudah '
              'terbukti menggandakan stok saat dikirim ulang');
    });

    test('layar modern memakai ulang kode sampai server mengonfirmasi', () {
      final src = File(
              'lib/features/apotik/procurement/apotik_penerimaan_page.dart')
          .readAsStringSync();
      expect(src, contains('_kodeDokumen ??= kodeDokumenPenerimaanBaru()'));
      expect(src, contains("'kode_dokumen': _kodeDokumen"));
      // Satu-satunya reset ada di jalur sukses -- bukan di catch/penolakan.
      expect('_kodeDokumen = null'.allMatches(src).length, 1);
      final iReset = src.indexOf('_kodeDokumen = null');
      final iDialog = src.indexOf("'Penerimaan Tercatat'");
      expect(iReset, greaterThan(iDialog),
          reason: 'kode hanya boleh direset setelah dialog sukses');
    });

    test('dialog replay tidak mengklaim batch baru masuk stok', () {
      final src = File(
              'lib/features/apotik/procurement/apotik_penerimaan_page.dart')
          .readAsStringSync();
      expect(src, contains("r['idempoten'] == true"));
      expect(src, contains('tidak ada stok yang ditambahkan lagi'));
    });
  });
}
