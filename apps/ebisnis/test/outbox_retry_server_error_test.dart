import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/transaksi_outbox_service.dart';

/// Insiden Toko Al-Bahjah 20-08-2026 (nota AB22008202600105): server membalas
/// kode SERVER_ERROR lewat HTTP 200. Aturan lama menganggap SEMUA respons
/// bernomor kode sebagai penolakan permanen, sehingga nota ditandai GAGAL dan
/// tidak pernah dijemput retry -- nilainya hilang dari omzet server.
void main() {
  final svc = TransaksiOutboxService.instance;

  ApiException galat(String? kode, {int? http, bool offline = false}) =>
      ApiException('galat uji', kode: kode, statusHttp: http, offline: offline);

  group('gangguan teknis harus dicoba ulang', () {
    test('SERVER_ERROR lewat HTTP 200 dicoba ulang', () {
      expect(svc.dapatDicobaUlang(galat('SERVER_ERROR', http: 200)), isTrue);
    });

    test('kode tak dikenal dicoba ulang, bukan divonis permanen', () {
      expect(svc.dapatDicobaUlang(galat('KODE_BARU_BELUM_DIKENAL', http: 200)),
          isTrue);
    });

    test('offline dicoba ulang', () {
      expect(svc.dapatDicobaUlang(galat('APA_PUN', offline: true)), isTrue);
    });

    test('HTTP 5xx dicoba ulang', () {
      expect(svc.dapatDicobaUlang(galat('SERVER_ERROR', http: 503)), isTrue);
    });

    test('galat non-API dicoba ulang', () {
      expect(svc.dapatDicobaUlang(Exception('putus di tengah jalan')), isTrue);
    });
  });

  group('penolakan bisnis tetap permanen', () {
    for (final kode in TransaksiOutboxService.kodePenolakanPermanen) {
      test('$kode tidak dikirim berulang', () {
        expect(svc.dapatDicobaUlang(galat(kode, http: 200)), isFalse);
      });
    }

    test('pencocokan kode tidak peka huruf besar-kecil', () {
      expect(
          svc.dapatDicobaUlang(galat('stok_tidak_cukup', http: 200)), isFalse);
    });
  });

  test('SERVER_ERROR bukan bagian daftar permanen', () {
    expect(TransaksiOutboxService.kodePenolakanPermanen,
        isNot(contains('SERVER_ERROR')));
  });
}
