import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UAT kontrak PIN dan limit member', () {
    test('aturan PIN dan limit dari server masuk ke model kasir', () {
      final member = Anggota.fromJson({
        'id': 7,
        'nama': 'Santri UAT',
        'kodeIdentitas': 'UAT-007',
        'wajibPin': true,
        'minSaldo': 0,
        'maksimalTransaksiHarian': 50000,
        'maksimalTransaksiMingguan': 200000,
        'maksimalTransaksiBulanan': 600000,
      });

      expect(member.wajibPin, isTrue);
      expect(member.maksimalTransaksiHarian, 50000);
      expect(member.maksimalTransaksiMingguan, 200000);
      expect(member.maksimalTransaksiBulanan, 600000);
    });

    test('snapshot local-first mempertahankan PIN dan seluruh limit', () {
      final row = Anggota.keCacheRow({
        'id': 8,
        'nama': 'Pegawai UAT',
        'kodeIdentitas': 'UAT-008',
        'wajibPin': true,
        'maksimalTransaksiHarian': 75000,
        'maksimalTransaksiMingguan': 250000,
        'maksimalTransaksiBulanan': 700000,
      });
      final member = Anggota.fromCache(row);

      expect(member.wajibPin, isTrue);
      expect(member.maksimalTransaksiHarian, 75000);
      expect(member.maksimalTransaksiMingguan, 250000);
      expect(member.maksimalTransaksiBulanan, 700000);
    });

    test('checkout berlimit wajib menunggu ACK server', () {
      final source =
          File('lib/screens/keranjang_screen.dart').readAsStringSync();

      expect(source, contains('bool get _memberMemilikiLimitTransaksi'));
      expect(source, contains('bool get _verifikasiMemberWajibServer'));
      expect(source, contains('_pinWajibUntukMetodeTerpilih'));
      expect(source, contains('pembayaranMemerlukanPin'));
      expect(
          source,
          contains(
              'if (_verifikasiMemberWajibServer || _memberMemilikiLimitTransaksi)'));
      expect(source, contains("ApiClient.instance.aksi('bayar', payload)"));
      expect(source, contains("e.kode == 'PENGAJUAN_LIMIT_MENUNGGU'"));
      expect(source, contains('_kodePengajuanLimitTertunda ='));
    });

    test('PIN memakai event server yang terikat pada kode transaksi', () {
      final source =
          File('lib/screens/keranjang_screen.dart').readAsStringSync();

      expect(source, contains("ApiClient.instance.aksi('verifikasi_pin'"));
      expect(source, contains("'reference_type': 'POS_PURCHASE'"));
      expect(source, contains("'reference_id': kodeUnik"));
      expect(source, contains("'pin_verification_event_id'"));
    });
  });
}
