import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/transaksi_outbox_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('batas aman pembayaran offline', () {
    test('metode non-manual mengikuti aturan saldo efektif backend', () {
      final voucher = CaraBayar.fromJson({
        'id': 7,
        'nama': 'Voucher Pejuang',
        'manual': false,
      });
      expect(voucher.memotongDepositEfektif, isTrue);
      expect(voucher.wajibPilihMember, isTrue);
      expect(TransaksiOutboxService.metodeAmanUntukKoreksiOffline(voucher),
          isFalse);
    });

    test(
        'tunai manual aman diantre sedangkan piutang tetap server-authoritative',
        () {
      final tunai = CaraBayar(id: 1, nama: 'Tunai', manual: true);
      final kasbon = CaraBayar(
        id: 2,
        nama: 'Kasbon Divisi',
        manual: true,
        masukSebagaiHutang: true,
      );
      expect(tunai.memotongDepositEfektif, isFalse);
      expect(
          TransaksiOutboxService.metodeAmanUntukKoreksiOffline(tunai), isTrue);
      expect(TransaksiOutboxService.metodeAmanUntukKoreksiOffline(kasbon),
          isFalse);
    });

    test('koreksi metode menjaga identitas dan meratakan split pembayaran', () {
      final sumber = <String, dynamic>{
        'kodeUnik': 'AB20909202600019',
        'clientTrxId': 'AB20909202600019',
        'waktu': '09-09-2026 06:38:30',
        'kasir': 'agung',
        'tokoId': 11,
        'total': 149500,
        'caraBayar': 99,
        'caraBayarNama': 'Voucher Pejuang',
        'caraBayarNominal': 100000,
        'caraBayarTambahan': [
          {'caraBayar': 1, 'nominal': 49500}
        ],
        'pembayaran': [
          {'caraBayar': 99, 'nominal': 100000}
        ],
        'transaksi': [
          {'kode': 'P001', 'jumlah': 1, 'harga': 149500}
        ],
      };
      final tunai = CaraBayar(id: 1, nama: 'Tunai', manual: true);
      final hasil =
          TransaksiOutboxService.payloadDenganMetodePengganti(sumber, tunai);

      expect(hasil['kodeUnik'], 'AB20909202600019');
      expect(hasil['clientTrxId'], 'AB20909202600019');
      expect(hasil['waktu'], '09-09-2026 06:38:30');
      expect(hasil['kasir'], 'agung');
      expect(hasil['total'], 149500);
      expect(hasil['caraBayar'], 1);
      expect(hasil['caraBayarNama'], 'Tunai');
      expect(hasil.containsKey('caraBayarTambahan'), isFalse);
      expect(hasil.containsKey('pembayaran'), isFalse);
      expect(hasil['transaksi'], isNotEmpty);
      expect(hasil['pengiriman_pending'], isTrue);
    });

    test('checkout saldo wajib melewati cabang ACK server sebelum outbox', () {
      final source =
          File('lib/screens/keranjang_screen.dart').readAsStringSync();
      expect(source,
          contains('(_saldoAkanDipotong || _pinWajibUntukMetodeTerpilih)'));
      final posisiGuard = source.indexOf(
          'if (_verifikasiMemberWajibServer || _memberMemilikiLimitTransaksi)');
      final posisiApi = source.indexOf(
          "ApiClient.instance.aksi('bayar', payload)", posisiGuard);
      final posisiSimpan =
          source.indexOf('simpanTransaksiPending(', posisiGuard);
      expect(posisiGuard, greaterThan(0));
      expect(posisiApi, greaterThan(posisiGuard));
      expect(posisiSimpan, greaterThan(posisiApi));
    });
  });
}
