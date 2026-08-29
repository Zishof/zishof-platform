import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('halaman pelanggan mempunyai tab riwayat CRUD dengan default member',
      () {
    final layar = File('lib/screens/anggota_screen.dart').readAsStringSync();
    final audit =
        File('lib/screens/riwayat_audit_screen.dart').readAsStringSync();

    expect(layar, contains('TabController(length: 13'));
    expect(layar, contains("Tab(text: 'Riwayat CRUD')"));
    expect(layar, contains('RiwayatAuditScreen('));
    expect(layar, contains('embedded: true'));
    expect(layar, contains("entitasAwal: 'anggota'"));
    expect(audit, contains("aksi('revisi_jelajah'"));
    expect(audit, contains('nilai dari → menjadi'));
  });

  test('dialog riwayat menerjemahkan field bisnis member', () {
    final dialog =
        File('lib/widgets/riwayat_data_dialog.dart').readAsStringSync();

    expect(dialog, contains("'jenisAnggotaKoperasi': 'Jenis member'"));
    expect(dialog, contains("'tipeAnggotaKoperasi': 'Tipe member'"));
    expect(dialog, contains("'limitKredit': 'Batas kredit/piutang'"));
    expect(dialog, contains("'nomorHpNormalisasi': 'Nomor HP ternormalisasi'"));
  });
}
