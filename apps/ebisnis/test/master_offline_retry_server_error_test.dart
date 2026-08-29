import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/master_offline.dart';

void main() {
  ApiException galat(String? kode, {int? http, bool offline = false}) =>
      ApiException('galat uji', kode: kode, statusHttp: http, offline: offline);

  group('gangguan teknis master tetap diantre dan dicoba ulang', () {
    test('offline dan HTTP 5xx dapat dicoba ulang', () {
      expect(
          MasterOffline.dapatDicobaUlang(galat(null, offline: true)), isTrue);
      expect(MasterOffline.dapatDicobaUlang(galat(null, http: 503)), isTrue);
    });

    test('SERVER_ERROR melalui HTTP 200 dapat dicoba ulang', () {
      expect(MasterOffline.dapatDicobaUlang(galat('SERVER_ERROR', http: 200)),
          isTrue);
    });

    test('kode teknis baru tidak divonis permanen', () {
      expect(
          MasterOffline.dapatDicobaUlang(
              galat('DATABASE_CONSTRAINT_ERROR', http: 200)),
          isTrue);
    });

    test('jawaban server non-JSON dapat dicoba ulang', () {
      expect(
          MasterOffline.dapatDicobaUlang(ApiException(
              'Jawaban server belum dapat diproses.',
              statusHttp: 200)),
          isTrue);
    });

    test('error endpoint lama tanpa kode melalui HTTP 200 dapat dicoba ulang',
        () {
      expect(MasterOffline.dapatDicobaUlang(galat(null, http: 200)), isTrue);
    });
  });

  group('validasi bisnis tetap meminta koreksi user', () {
    for (final kode in MasterOffline.kodePenolakanPermanen) {
      test('$kode tidak dikirim otomatis berulang', () {
        expect(MasterOffline.dapatDicobaUlang(galat(kode, http: 200)), isFalse);
      });
    }

    test('HTTP autentikasi/otorisasi tidak diputar tanpa akhir', () {
      expect(MasterOffline.dapatDicobaUlang(galat(null, http: 401)), isFalse);
      expect(MasterOffline.dapatDicobaUlang(galat(null, http: 403)), isFalse);
    });
  });
}
