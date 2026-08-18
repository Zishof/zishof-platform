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

  test('hanya mengizinkan payload checkout lokal yang lengkap', () {
    final hasil = periksaKelayakanPayloadSinkronisasi(<String, dynamic>{
      'kodeUnik': 'TRX-LOKAL-1',
      'idToko': 1,
      'kasir': 'kasir1',
      'caraBayar': 2,
      'transaksi': <Map<String, dynamic>>[
        <String, dynamic>{'id': 10, 'jumlah': 2, 'harga': 5000}
      ],
    });
    expect(hasil.status, StatusKelayakanSinkronisasi.siapKirim);
    expect(hasil.siapDikirim, isTrue);
  });

  test('arsip hasil salinan server tidak dikirim kembali ke endpoint bayar',
      () {
    for (final asal in <String>[
      'SERVER_TOKO_SAMA',
      'REPLIKASI_OTOMATIS_TOKO_SAMA'
    ]) {
      final hasil = periksaKelayakanPayloadSinkronisasi(<String, dynamic>{
        'kodeUnik': 'TRX-SERVER-1',
        'idToko': 1,
        'kasir': 'kasir1',
        'asal_backup': asal,
        'transaksi': <Map<String, dynamic>>[
          <String, dynamic>{'id': 10, 'jumlah': 1}
        ],
      });
      expect(hasil.status, StatusKelayakanSinkronisasi.arsipDariServer);
      expect(hasil.siapDikirim, isFalse);
    }
  });

  test('payload lokal tanpa metode atau rincian lengkap ditahan untuk audit',
      () {
    final tanpaMetode = periksaKelayakanPayloadSinkronisasi(<String, dynamic>{
      'kodeUnik': 'TRX-RUSAK-1',
      'idToko': 1,
      'kasir': 'kasir1',
      'transaksi': <Map<String, dynamic>>[
        <String, dynamic>{'id': 10, 'jumlah': 1}
      ],
    });
    final tanpaProduk = periksaKelayakanPayloadSinkronisasi(<String, dynamic>{
      'kodeUnik': 'TRX-RUSAK-2',
      'idToko': 1,
      'kasir': 'kasir1',
      'caraBayar': 2,
      'transaksi': <Map<String, dynamic>>[
        <String, dynamic>{'jumlah': 1}
      ],
    });
    expect(tanpaMetode.status, StatusKelayakanSinkronisasi.tidakLengkap);
    expect(tanpaProduk.status, StatusKelayakanSinkronisasi.tidakLengkap);
  });
}
