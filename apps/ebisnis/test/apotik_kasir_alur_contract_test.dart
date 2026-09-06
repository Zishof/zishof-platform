import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rapat(String value) => value.replaceAll(RegExp(r'\s+'), '');

void main() {
  late String source;

  setUpAll(() {
    source =
        File('lib/screens/apotik/kasir_apotik_screen.dart').readAsStringSync();
  });

  test('empat mode kasir terbuka tanpa penanda kunci', () {
    for (final label in [
      'OTC / Obat Bebas',
      'Resep Dokter',
      'Racikan',
      'Produksi Farmasi',
    ]) {
      expect(source, contains(label));
    }
    expect(source, isNot(contains('baris racikan belum bisa diserahkan')));
    expect(source, isNot(contains('Icons.lock')));
  });

  test('endpoint seluruh alur kasir terhubung ke UI', () {
    for (final action in [
      'apotik_item_cari',
      'apotik_item_batch',
      'apotik_cara_bayar_list',
      'apotik_resep_list',
      'apotik_resep_detail',
      'apotik_racikan_list',
      'apotik_bayar',
      'apotik_bayar_racikan',
      'apotik_produksi_katalog',
      'apotik_produksi_proses',
    ]) {
      expect(source, contains("'$action'"), reason: '$action belum dipakai');
    }
  });

  test('tebus resep campuran mengirim item_id atau racikan_id', () {
    final compact = _rapat(source);
    expect(
        compact, contains(_rapat("if (b.racikan) 'racikan_id': b.item['id']")));
    expect(
        compact, contains(_rapat("if (!b.racikan) 'item_id': b.item['id']")));
    expect(
        compact, contains("_adaRacikan?'apotik_bayar_racikan':'apotik_bayar'"));
  });

  test('pembayaran berasal dari master server dan mendukung kembalian', () {
    expect(source, contains("aksi('apotik_cara_bayar_list')"));
    expect(source, contains("'cara_bayar_id': _caraBayarId"));
    expect(source, contains("'pembayaran': ["));
    expect(source, contains("'tunai': diterima"));
    expect(source, contains("'kembalian': diterima - totalKeranjang"));
  });

  test('runner volume menuntut minimal 100 sukses per alur', () {
    final runner = File('tool/uat_apotik_volume.ps1').readAsStringSync();
    expect(runner, contains('[int]\$TargetPerAlur = 100'));
    for (final alur in [
      "'otc'",
      "'resep_dokter'",
      "'racikan'",
      "'produksi_farmasi'",
      "'tebus_resep'",
    ]) {
      expect(runner, contains(alur));
    }
    expect(runner, contains(r'$Sukses -ge $TargetPerAlur'));
  });

  test('posting dan pemetaan Apotik memakai timeout operasi massal', () {
    final api = File('lib/api_client.dart').readAsStringSync();
    expect(api, contains("namaAksi.startsWith('apotik_posting_')"));
    expect(api, contains("namaAksi.startsWith('apotik_pemetaan_akun_')"));
    expect(api, contains('const Duration(minutes: 5)'));
  });
}
