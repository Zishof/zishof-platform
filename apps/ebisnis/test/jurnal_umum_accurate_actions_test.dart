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

  test('Dialog download dan upload menawarkan pilihan Accurate sebagai default', () {
    expect(layar, contains(_rapat("formatTerpilih='accurate'")));
    expect(layar, contains(_rapat("Accurate(HistoriBukuBesarJurnal.xlsx)")));
    expect(layar, contains(_rapat("FormatStandar(.xlsx)")));
  });
}
