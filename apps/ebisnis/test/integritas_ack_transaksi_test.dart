import 'package:ebisnis/services/integritas_ack_transaksi.dart';
import 'package:ebisnis/services/transaksi_outbox_service.dart';
import 'package:ebisnis/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> payload(double total) => {
        'kodeUnik': 'UAT-NOTA',
        'total': total,
        'pajak': 0,
        'transaksi': [
          {'id': 1, 'jumlah': 1, 'harga': total}
        ],
      };

  for (final pasangan in [
    (79000.0, 341575.0),
    (18500.0, 401890.0),
    (33500.0, 18500.0)
  ]) {
    test('struk lokal ${pasangan.$1} tidak menerima total ${pasangan.$2}', () {
      expect(
          kendalaAckTransaksi(
              payload(pasangan.$1), {'total': pasangan.$2, 'totalDiskon': 0}),
          isNotNull);
    });
  }

  test('ACK cocok dan diskon sah tetap dapat disinkronkan', () {
    expect(
        kendalaAckTransaksi(payload(79000), {'total': 79000, 'totalDiskon': 0}),
        isNull);
    expect(
        kendalaAckTransaksi(
            payload(79000), {'total': 78600, 'totalDiskon': 400}),
        isNull);
  });

  test('ekstra dihitung menurut jumlah induk dan ekstra', () {
    final p = payload(2000);
    p['transaksi'] = [
      {
        'id': 1,
        'harga': 2000,
        'jumlah': 2,
        'ekstra': [
          {'id': 2, 'harga': 500, 'jumlah': 3}
        ]
      }
    ];
    expect(kendalaAckTransaksi(p, {'total': 7000, 'totalDiskon': 0}), isNull);
    expect(
        kendalaAckTransaksi(p, {'total': 4500, 'totalDiskon': 0}), isNotNull);
  });

  test('ACK tidak lengkap dan nominal bukan angka ditahan', () {
    expect(kendalaAckTransaksi(payload(79000), {'status': '00'}), isNotNull);
    expect(
        kendalaAckTransaksi(
            payload(79000), {'total': double.nan, 'totalDiskon': 0}),
        isNotNull);
    expect(
        kendalaAckTransaksi(
            payload(79000), {'total': 79000, 'totalDiskon': -1}),
        isNotNull);
  });

  test('konflik ACK dan duplikat memerlukan tinjauan, bukan retry otomatis',
      () {
    for (final kode in [
      'ACK_TRANSAKSI_TIDAK_COCOK',
      'DUPLIKAT_KODE_TRANSAKSI'
    ]) {
      expect(
          TransaksiOutboxService.instance
              .dapatDicobaUlang(ApiException('Perlu ditinjau', kode: kode)),
          isFalse);
    }
  });
}
