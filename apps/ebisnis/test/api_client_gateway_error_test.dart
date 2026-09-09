import 'dart:io';

import 'package:ebisnis/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('penanganan gangguan gateway', () {
    test('HTTP 522 dan 5xx diklasifikasikan sebagai gangguan sementara', () {
      for (final status in [500, 502, 503, 504, 522, 599]) {
        expect(ApiClient.gangguanSementaraStatusHttp(status), isTrue,
            reason: 'HTTP $status harus mempertahankan cache/outbox');
      }
    });

    test('penolakan autentikasi dan validasi bukan gangguan sementara', () {
      for (final status in [400, 401, 403, 404, 422, 429]) {
        expect(ApiClient.gangguanSementaraStatusHttp(status), isFalse,
            reason: 'HTTP $status tidak boleh melewati keputusan server');
      }
    });

    test('timeout HTTP dapat memakai jalur pemulihan sementara', () {
      expect(ApiClient.gangguanSementaraStatusHttp(408), isTrue);
      expect(ApiClient.gangguanSementaraStatusHttp(425), isTrue);
    });

    test('pesan login tidak menyebut parsing JSON sebagai masalah utama', () {
      final pesan = ApiClient.pesanGangguanStatusHttp(522, 'login');
      expect(pesan, contains('proses masuk'));
      expect(pesan, contains('HTTP 522'));
      expect(pesan, contains('belum dinilai'));
      expect(pesan, isNot(contains('FormatException')));
      expect(pesan, isNot(contains('jsonDecode')));
    });

    test('solusi login tidak menyuruh pengguna mengganti kata sandi', () {
      final solusi = ApiClient.solusiGangguanStatusHttp('login').join(' ');
      expect(solusi, contains('Alamat Server'));
      expect(solusi, contains('Kode Referensi'));
      expect(solusi, contains('jangan mengganti kata sandi'));
    });

    test('kontrak parser memakai klasifikasi 522 sebelum membentuk galat', () {
      final source = File('lib/api_client.dart').readAsStringSync();
      expect(source,
          contains('offline: gangguanSementaraStatusHttp(resp.statusCode)'));
      expect(source, contains('pesanGangguanStatusHttp(resp.statusCode'));
      expect(source, contains("aktivitas == 'login'"));
    });
  });

  test('ApiException gateway menampilkan panduan, teknis tetap terpisah', () {
    final gagal = ApiException(
      ApiClient.pesanGangguanStatusHttp(522, 'login'),
      offline: true,
      aktivitas: 'login',
      statusHttp: 522,
      kodeReferensi: 'MTTS778J-590NX3',
      judul: 'Layanan server sedang terganggu',
      solusi: ApiClient.solusiGangguanStatusHttp('login'),
      teknis: 'HTTP 522; Respons: error code: 522',
    );

    expect(gagal.info.judul, 'Layanan server sedang terganggu');
    expect(gagal.info.pesan, contains('belum dinilai'));
    expect(gagal.info.pesan, contains('HTTP 522'));
    expect(gagal.info.pesan, isNot(contains('FormatException')));
    expect(gagal.info.solusi.join(' '), contains('Kode Referensi'));
    expect(gagal.info.teknis, contains('error code: 522'));
    expect(gagal.info.kodeReferensi, 'MTTS778J-590NX3');
  });
}
