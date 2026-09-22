import 'dart:async';
import 'package:ebisnis/services/transaksi_outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ok = HasilSinkronisasiTransaksi(total: 1, berhasil: 1);
  test('manual langsung memakai jeda nol; otomatis tetap memiliki backoff',
      () async {
    final jeda = <Duration>[];
    final service = TransaksiOutboxService.untukUji((
        {required sertakanGagal, required jedaRetry}) async {
      jeda.add(jedaRetry);
      return ok;
    });
    await service.sinkronkan();
    await service.sinkronkan(sertakanGagal: true);
    expect(jeda, [const Duration(minutes: 10), Duration.zero]);
  });
  for (final gagal in [false, true]) {
    test('manual menunggu otomatis, digabung dan tidak paralel (gagal=$gagal)',
        () async {
      final otomatis = Completer<HasilSinkronisasiTransaksi>();
      final manual = Completer<HasilSinkronisasiTransaksi>();
      final panggilan = <bool>[];
      final service = TransaksiOutboxService.untukUji((
          {required sertakanGagal, required jedaRetry}) {
        panggilan.add(sertakanGagal);
        return sertakanGagal ? manual.future : otomatis.future;
      });
      final pertama = service.sinkronkan();
      final terpantau = pertama.then((_) {}, onError: (Object _) {});
      final kedua = service.sinkronkan(sertakanGagal: true);
      final ketiga = service.sinkronkan(sertakanGagal: true);
      expect(identical(kedua, ketiga), isTrue);
      expect(panggilan, [false]);
      if (gagal) {
        otomatis.completeError(StateError('uji offline'));
      } else {
        otomatis.complete(ok);
      }
      await terpantau;
      await Future<void>.delayed(Duration.zero);
      expect(panggilan, [false, true]);
      manual.complete(ok);
      expect(await kedua, same(ok));
      expect(await ketiga, same(ok));
    });
  }
}
