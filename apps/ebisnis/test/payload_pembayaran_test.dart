import 'package:ebisnis/services/payload_pembayaran.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ID draft tidak dikirim sebagai ID header saat finalisasi pembayaran',
      () {
    final payload = payloadBayarAman(
      {
        'id': 888,
        'kodeUnik': 'nota-uji',
        'draftPembelianAnggotaKoperasi': 888,
        'transaksi': const [],
      },
      melanjutkanDraft: true,
    );

    expect(payload.containsKey('id'), isFalse);
    expect(payload['draftPembelianAnggotaKoperasi'], 888);
    expect(payload['kodeUnik'], 'nota-uji');
  });

  test('ID header biasa tidak diubah bila transaksi bukan lanjutan draft', () {
    final payload = payloadBayarAman(
      {'id': 42, 'kodeUnik': 'nota-uji'},
      melanjutkanDraft: false,
    );

    expect(payload['id'], 42);
  });

  test('payload asal tidak dimutasi', () {
    final asal = {'id': 888, 'draftPembelianAnggotaKoperasi': 888};
    payloadBayarAman(asal, melanjutkanDraft: true);

    expect(asal['id'], 888);
  });
}
