import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _rapat(String value) => value.replaceAll(RegExp(r'\s+'), '');

void main() {
  final pr = File('lib/screens/pengadaan_pr_screen.dart');
  final po = File('lib/screens/pengadaan_po_screen.dart');
  final bast = File('lib/screens/pengadaan_bast_screen.dart');
  final bayar = File('lib/screens/pengadaan_bayar_screen.dart');

  test('form PR memilih UOM per baris dan mengirim snapshot', () {
    final source = pr.readAsStringSync();
    expect(source, contains("labelText: 'Satuan pembelian'"));
    expect(source, contains('pilihanSatuan'));
    expect(source, contains("'satuan_input_id': b.satuanId"));
    expect(source, contains("'faktor_ke_dasar': b.faktorKeDasar"));
  });

  test('tombol Buat PR berada pada header dan bukan floating', () {
    final source = _rapat(pr.readAsStringSync());
    expect(source, contains(_rapat('aksiHeader: Wrap')));
    expect(source, contains(_rapat("label: const Text('Buat PR')")));
    expect(source, isNot(contains('floatingActionButton:')));
  });

  test('approval pengadaan selalu menunggu konfirmasi server', () {
    final kasus = <File, String>{
      pr: 'pengadaan_pr_putusan',
      po: 'pengadaan_po_putusan',
      bast: 'pengadaan_bast_putusan',
      bayar: 'pengadaan_bayar_putusan',
    };
    for (final entry in kasus.entries) {
      final source = _rapat(entry.key.readAsStringSync());
      final marker = _rapat("ApiClient.instance.aksi('${entry.value}'");
      expect(source, contains(marker), reason: entry.key.path);
      final index = source.indexOf(marker);
      final sekitar = source.substring((index - 120).clamp(0, index),
          (index + marker.length + 200).clamp(0, source.length));
      expect(sekitar, isNot(contains('prosesSimpanMaster')),
          reason: '${entry.value} tidak boleh masuk outbox approval');
    }
  });

  test('backend menyaring PR disetujui dan membawa UOM hingga Kulakan', () {
    final helper = File(
        r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\PengadaanPosApiHelper.java');
    final entity = File(
        r'C:\opt\AIS\ais\src\main\src\ais\database\model\asset\PermintaanPengadaanMasterAssetDetail.java');
    final migration = File(
        r'C:\opt\AIS\ais\src\main\webapp\sql\migrasi_pengadaan_pr_uom_20260906.sql');
    if (!helper.existsSync()) return;

    final source = _rapat(helper.readAsStringSync()).toLowerCase();
    expect(source, contains('restrictions.isnotnull("tanggalpersetujuan")'));
    expect(source, contains('"uomoptions"'));
    expect(source, contains('tambahsnapshotuom'));
    expect(source, contains('nilaikulakandariuom'));
    expect(source, contains('qtyinput*faktor'));
    expect(source, contains('hanyabarispraktif,sudahdisetujui'));
    expect(entity.readAsStringSync(), contains('satuan_input_id'));
    expect(migration.existsSync(), isTrue);
    expect(migration.readAsStringSync(), contains('faktor_ke_dasar'));
  });

  test('pemilih PR di PO menampilkan satuan pilihan', () {
    final source = po.readAsStringSync();
    expect(source, contains("b.data['satuanInputNama']"));
    expect(source, contains("satuan: '\${m['satuanInputNama'] ?? ''}'"));
  });
}
