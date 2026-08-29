import 'dart:io';

import 'package:ebisnis/services/sinkronisasi_tabel_service.dart';
import 'package:ebisnis/widgets/penawaran_sinkronisasi_versi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('penawaran sinkronisasi setelah instalasi/update', () {
    test('instalasi baru ditawarkan karena belum ada versi tersimpan', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+161',
          versiTerakhirDitawarkan: null,
        ),
        isTrue,
      );
    });

    test('versi/build yang sama tidak ditawarkan berulang', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+161',
          versiTerakhirDitawarkan: '1.34.03+161',
        ),
        isFalse,
      );
    });

    test('perubahan build maupun versi memicu penawaran baru', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+162',
          versiTerakhirDitawarkan: '1.34.03+161',
        ),
        isTrue,
      );
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.04+163',
          versiTerakhirDitawarkan: '1.34.03+162',
        ),
        isTrue,
      );
    });

    test('kunci dipisahkan per tenant agar data usaha tidak tertukar', () {
      expect(
        PenawaranSinkronisasiVersi.kunciPenyimpanan(tenantId: 1),
        isNot(equals(PenawaranSinkronisasiVersi.kunciPenyimpanan(tenantId: 2))),
      );
    });

    test('persentase berasal dari jumlah adapter yang benar-benar selesai', () {
      const kemajuan = KemajuanSinkronisasiTabel(
        nama: 'anggota_cache',
        label: 'Data member',
        jumlahSelesai: 2,
        total: 5,
        sedangBerjalan: true,
      );

      expect(kemajuan.fraksi, 0.4);
      expect(kemajuan.persen, 40);
      expect(SinkronisasiTabelService.labelTabel('produk_cache'),
          'Katalog produk');
    });

    test('kemajuan dalam katalog dihitung sebagai bagian tahap aktif', () {
      const kemajuan = KemajuanSinkronisasiTabel(
        nama: 'produk_cache',
        label: 'Katalog produk',
        jumlahSelesai: 0,
        total: 5,
        sedangBerjalan: true,
        detail: '7.000 dari 14.200 produk',
        fraksiTahap: 0.5,
      );

      expect(kemajuan.fraksi, 0.1);
      expect(kemajuan.persen, 10);
      expect(kemajuan.detail, contains('14.200'));
    });

    test('pembatalan kooperatif menghentikan tahap berikutnya', () {
      final pembatalan = PembatalanSinkronisasi();
      expect(pembatalan.dibatalkan, isFalse);

      pembatalan.batalkan();

      expect(pembatalan.dibatalkan, isTrue);
      expect(pembatalan.pastikanLanjut, throwsA(isA<SinkronisasiDibatalkan>()));
    });

    test('dialog menampilkan data aktif, persen, dan jumlah tahap', () {
      final source = File('lib/widgets/penawaran_sinkronisasi_versi.dart')
          .readAsStringSync();

      expect(source, contains('Sedang memproses'));
      expect(source, contains('LinearProgressIndicator'));
      expect(source, contains('detail-kemajuan-sinkronisasi'));
      expect(source, contains('tabel secara paralel'));
      expect(source, contains("'Batalkan'"));
      expect(source, contains('pembatalan: _pembatalan'));
      expect(source, contains('final tahapanAktif'));
      expect(source, contains('tahapanAktif.length'));
      expect(source, contains('dikeluarkan dari daftar aktif'));
      expect(source, contains(r"'$persen%'"));
      expect(source, contains(r"'$selesai dari $total tahap selesai'"));
      expect(source, contains('onProgress: _laporKemajuan'));
    });

    test('Nanti menjadi aksi default yang aman', () {
      final source = File('lib/widgets/penawaran_sinkronisasi_versi.dart')
          .readAsStringSync();
      final posisiNanti = source.indexOf("child: const Text('Nanti')");
      final potongan = source.substring(posisiNanti - 180, posisiNanti + 40);

      expect(posisiNanti, greaterThan(0));
      expect(potongan, contains('autofocus: true'));
    });

    test('sinkron semua memakai satu prasyarat master bersama', () {
      final source = File('lib/services/sinkronisasi_tabel_service.dart')
          .readAsStringSync();

      expect(source, contains('final futureMaster'));
      expect(source, contains('Future.wait<String>'));
      expect(source,
          contains("jalankan('produk_cache', tungguMaster: futureMaster)"));
      expect(source,
          contains("jalankan('anggota_cache', tungguMaster: futureMaster)"));
    });

    test('tombol header membuka dialog seluruh tabel termasuk transaksi', () {
      final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
      final dialog = File('lib/widgets/penawaran_sinkronisasi_versi.dart')
          .readAsStringSync();
      final service = File('lib/services/sinkronisasi_tabel_service.dart')
          .readAsStringSync();

      expect(
          shell, contains('await tampilkanSinkronisasiSeluruhTabel(context)'));
      expect(shell, contains('termasuk transaksi'));
      expect(
          dialog, contains('Future<void> tampilkanSinkronisasiSeluruhTabel'));
      expect(service, contains("'transaksi_pending': 'transaksi'"));
      expect(service, contains('Transaksi lokal & pending'));
    });
  });
}
