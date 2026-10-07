import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

void main() {
  final layar =
      _rapat(File('lib/screens/jurnal_umum_screen.dart').readAsStringSync());

  test('Tombol Download dan Cetak PDF tersedia di filter bar', () {
    expect(layar, contains(_rapat('_tampilkanDialogDownload')),
        reason: 'Tombol Download harus memicu dialog pemilihan format');
    expect(layar, contains(_rapat('_cetakPdf')),
        reason: 'Tombol Cetak PDF harus memicu layout PDF');
    expect(layar, contains(_rapat("label:constText('Download')")));
    expect(layar, contains(_rapat("label:constText('CetakPDF')")));
  });

  test('Tombol Upload bergerbang Administrator dan hak Tambah/Edit', () {
    expect(
      layar,
      contains(_rapat(
          "bolehUpload=Sesi.instance.isAdmin&&(_boleh('create')||_boleh('edit'))")),
      reason: 'Upload hanya boleh untuk Administrator dengan hak create/edit',
    );
    expect(layar, contains(_rapat('if(bolehUpload)')));
    expect(layar, contains(_rapat("label:constText('Upload')")));
    expect(layar, contains(_rapat('_tampilkanDialogUpload')));
  });

  test('Upload menampilkan pratinjau (preview) dengan status closing dan keseimbangan', () {
    expect(layar, contains(_rapat('PratinjauImporJurnalUmum')),
        reason: 'Harus menampilkan dialog pratinjau sebelum upload');
    expect(layar, contains(_rapat('TerkunciClosing(Ditolak)')),
        reason: 'Harus mendeteksi transaksi yang masuk periode closing');
    expect(layar, contains(_rapat('TimpaUlang(BelumClosing)')),
        reason: 'Harus menandai nomor bukti yang sudah ada dan belum closing untuk ditimpa ulang');
  });

  test('Upload menampilkan progress bar dan persentase', () {
    expect(layar, contains(_rapat('LinearProgressIndicator(value:progres')),
        reason: 'Harus menampilkan progress bar linear');
    expect(layar, contains(_rapat('(progres*100).toStringAsFixed(0)')),
        reason: 'Harus menampilkan persentase progres upload');
    expect(layar, contains(_rapat(r'Memproses $selesai dari $total jurnal')),
        reason: 'Harus menampilkan counter jurnal yang sedang diproses');
  });

  test('Upload menampilkan laporan hasil upload dengan penyebab dan solusi', () {
    expect(layar, contains(_rapat('LaporanHasilUploadJurnal')),
        reason: 'Harus menampilkan dialog laporan hasil upload');
    expect(layar, contains(_rapat(r'Penyebab: ${g.penyebab}')),
        reason: 'Harus menampilkan penyebab kegagalan');
    expect(layar, contains(_rapat(r'Solusi: ${g.solusi}')),
        reason: 'Harus memberikan solusi perbaikan');
  });

  test('Server JurnalUmumApiHelper menerapkan nomor bukti sebagai kunci dan tolak closing', () {
    final serverFile = File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\JurnalUmumApiHelper.java');
    if (!serverFile.existsSync()) return;
    final serverCode = _rapat(serverFile.readAsStringSync());
    expect(serverCode, contains(_rapat('fromGrupTransaksiwherekode=:kode')),
        reason: 'Server harus memeriksa nomor bukti di database');
    expect(serverCode, contains(_rapat('Nomorbukti')),
        reason: 'Pesan penolakan harus menyebut nomor bukti');
    expect(serverCode, contains(_rapat('DELETEFROMakunting.transaksiWHEREgrup_transaksi=')),
        reason: 'Server harus menghapus transaksi lama bila nomor bukti sudah ada dan belum closing');
  });
}

