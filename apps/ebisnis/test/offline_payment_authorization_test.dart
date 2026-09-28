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

    test('koreksi lokal voucher member tetap menunggu validasi server', () {
      final sumber = <String, dynamic>{
        'kodeUnik': 'EB260921122101245V',
        'clientTrxId': 'EB260921122101245V',
        'waktu': '21-09-2026 12:21:00',
        'kasir': 'mutia',
        'tokoId': 5,
        'id_member': 1001,
        'nama_member': 'Santri UAT',
        'total': 3500,
        'caraBayar': 1,
        'caraBayarNama': 'Tunai',
        'transaksi': [
          {'kode': 'P001', 'jumlah': 1, 'harga': 3500}
        ],
      };
      final voucher = CaraBayar(
        id: 7,
        nama: 'Voucher Santri',
        manual: false,
        wajibPilihMember: true,
      );

      expect(
        () => TransaksiOutboxService.payloadDenganMetodeTerkoreksi(
            sumber, voucher),
        throwsArgumentError,
      );

      final hasil = TransaksiOutboxService.payloadDenganMetodeTerkoreksi(
        sumber,
        voucher,
        izinkanValidasiServer: true,
      );
      expect(hasil['kodeUnik'], 'EB260921122101245V');
      expect(hasil['waktu'], '21-09-2026 12:21:00');
      expect(hasil['id_member'], 1001);
      expect(hasil['caraBayar'], 7);
      expect(hasil['caraBayarNama'], 'Voucher Santri');
      expect(hasil['pengiriman_pending'], isTrue);
    });

    test('koreksi member menambal pembeli tanpa mengubah kode waktu item', () {
      final sumber = <String, dynamic>{
        'kodeUnik': 'AB2609281357231ZUV',
        'clientTrxId': 'AB2609281357231ZUV',
        'waktu': '28-09-2026 13:57:23',
        'kasir': 'agung',
        'tokoId': 11,
        'total': 62000,
        'caraBayar': 7,
        'caraBayarNama': 'eMoney Santri',
        'id_member': null,
        'nama_member': null,
        'transaksi': [
          {'kode': 'P001', 'jumlah': 1, 'harga': 62000}
        ],
      };
      final emoney = CaraBayar(
        id: 7,
        nama: 'eMoney Santri',
        manual: false,
        wajibPilihMember: true,
      );
      final member = Anggota.fromJson({'id': 262707001, 'nama': 'ACHMAD UJI'});

      final hasil = TransaksiOutboxService.payloadDenganMemberTerkoreksi(
        sumber,
        member,
        metodeDiizinkan: [emoney],
      );

      expect(hasil['kodeUnik'], 'AB2609281357231ZUV');
      expect(hasil['clientTrxId'], 'AB2609281357231ZUV');
      expect(hasil['waktu'], '28-09-2026 13:57:23');
      expect(hasil['kasir'], 'agung');
      expect(hasil['total'], 62000);
      expect(hasil['caraBayar'], 7);
      expect(hasil['caraBayarNama'], 'eMoney Santri');
      expect(hasil['id_member'], 262707001);
      expect(hasil['memberId'], 262707001);
      expect(hasil['nama_member'], 'ACHMAD UJI');
      expect(hasil['pembeli'], 'ACHMAD UJI');
      expect(hasil['transaksi'], sumber['transaksi']);
      expect(hasil['pengiriman_pending'], isTrue);
    });

    test('koreksi member menolak metode yang tidak diizinkan untuk member', () {
      final sumber = <String, dynamic>{
        'kodeUnik': 'AB2609281353212OA',
        'caraBayar': 7,
        'caraBayarNama': 'eMoney Santri',
      };
      final tunai = CaraBayar(id: 1, nama: 'Tunai', manual: true);
      final member = Anggota.fromJson({'id': 99, 'nama': 'Santri UAT'});

      expect(
        () => TransaksiOutboxService.payloadDenganMemberTerkoreksi(
          sumber,
          member,
          metodeDiizinkan: [tunai],
        ),
        throwsArgumentError,
      );
    });

    test('checkout saldo wajib melewati cabang ACK server sebelum outbox', () {
      final source =
          File('lib/screens/keranjang_screen.dart').readAsStringSync();
      expect(source, contains('_saldoAkanDipotong ||'));
      expect(source, contains('_pinWajibUntukMetodeTerpilih ||'));
      expect(source, contains('_hutangAkanDipakai'));
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

    test('checkout non-tunai melakukan preflight jaringan sebelum transaksi',
        () {
      final source =
          File('lib/screens/keranjang_screen.dart').readAsStringSync();
      expect(source, contains('bool _metodeWajibOnline(CaraBayar caraBayar)'));
      expect(source, contains("nama.contains('voucher')"));
      expect(source, contains("nama.contains('qris')"));
      expect(source, contains("nama.contains('transfer')"));
      expect(source, contains('StatusJaringan.instance.periksaSekarang()'));

      final mulai = source.indexOf('Future<void> _bayar() async');
      final selesai = source.indexOf('Future<void> _pilihMetode()', mulai);
      final bayar = source.substring(mulai, selesai);
      final jaringan =
          bayar.indexOf('await _pastikanJaringanOnlineSebelumBayar()');
      final saldo = bayar.indexOf('await _validasiSaldoPusatSebelumBayar()');
      final kode = bayar.indexOf('await _buatKodeUnik()');
      expect(jaringan, greaterThanOrEqualTo(0));
      expect(saldo, greaterThan(jaringan));
      expect(kode, greaterThan(saldo));
    });

    test('kasir menampilkan status jaringan realtime di toolbar POS', () {
      final source = File('lib/screens/kasir_screen.dart').readAsStringSync();
      final rapat = source.replaceAll(RegExp(r'\s+'), '');
      expect(rapat, contains('Timer.periodic(constDuration(seconds:15)'));
      expect(source, contains('StatusJaringan.instance.periksaSekarang()'));
      expect(source, contains('Status jaringan POS'));
      expect(source, contains('Icons.wifi'));
      expect(source, contains('Icons.wifi_off'));
      expect(source, contains('Online'));
      expect(source, contains('Offline'));
      expect(source, contains('Tidak Stabil'));
    });
  });
}
