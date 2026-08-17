import 'dart:convert';

import 'package:ebisnis/services/transaksi_rekonsiliasi_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> lokal(String kode, num total) => <String, Object?>{
      'kode_unik': kode,
      'akun_kunci': 'kasir-lokal',
      'id_perangkat': 'mesin-lokal',
      'payload_json': jsonEncode(<String, dynamic>{
        'total': total,
        'sumber_username': 'kasir-asal',
        'sumber_mesin': 'pos-depan'
      }),
    };

Map<String, dynamic> server(String kode, num total) => <String, dynamic>{
      'kodeUnik': kode,
      'totalBiaya': total,
      'kasir': 'kasir-server',
      'namaMesin': 'pos-belakang',
    };

void main() {
  test('membedakan data sama dan data yang hanya ada di satu sisi', () {
    final hasil = bandingkanTransaksiLokalDanServer(
      <Map<String, Object?>>[lokal('TRX-1', 100), lokal('TRX-2', 200)],
      <Map<String, dynamic>>[server('trx-1', 100), server('TRX-3', 300)],
    );
    expect(hasil.jumlah(StatusPerbandinganTransaksi.sama), 1);
    expect(hasil.jumlah(StatusPerbandinganTransaksi.hanyaLokal), 1);
    expect(hasil.jumlah(StatusPerbandinganTransaksi.hanyaServer), 1);
    expect(hasil.jumlahSelisih, 2);
  });

  test('menandai nominal berbeda dan kode duplikat', () {
    final hasil = bandingkanTransaksiLokalDanServer(
      <Map<String, Object?>>[
        lokal('TRX-1', 100),
        lokal('TRX-2', 200),
        lokal('TRX-2', 200),
      ],
      <Map<String, dynamic>>[server('TRX-1', 125), server('TRX-2', 200)],
    );
    expect(hasil.jumlah(StatusPerbandinganTransaksi.berbeda), 1);
    expect(hasil.jumlah(StatusPerbandinganTransaksi.duplikat), 1);
  });

  test('mengenali kode server lama di dalam label nomor nota', () {
    expect(
      kodeTransaksiServer(
          <String, dynamic>{'nomorNota': 'Order 001 - 0001 - 001 (AB-001)'}),
      'ab-001',
    );
  });

  test('mempertahankan username dan mesin asal pada audit perbandingan', () {
    final hasil = bandingkanTransaksiLokalDanServer(
      <Map<String, Object?>>[lokal('TRX-ASAL', 100)],
      <Map<String, dynamic>>[server('TRX-ASAL', 100)],
    );
    expect(hasil.baris.single.asalLokal, 'kasir-asal / pos-depan');
    expect(hasil.baris.single.asalServer, 'kasir-server / pos-belakang');
  });
}
