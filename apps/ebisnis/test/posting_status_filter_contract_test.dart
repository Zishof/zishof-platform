import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semua keluarga halaman posting memakai filter status API eksplisit', () {
    final laporan = File('lib/screens/laporan_screen.dart').readAsStringSync();
    final toko = File('lib/screens/posting_toko_dialog.dart').readAsStringSync();

    for (final source in [laporan, toko]) {
      expect(source, contains('Semua ('));
      expect(source, contains('Telah Diposting ('));
      expect(source, contains('Belum Diposting ('));
      expect(source, contains("['rincianSudahDiposting']"));
      expect(source, contains("['statusPosting']"));
      expect(source, contains("['sudahDiposting']"));
      expect(source, contains("'batasRiwayat': 10000"));
      expect(source, contains("'SUDAH_DIPOSTING'"));
      expect(source, contains('Belum Diposting - Siap'));
      expect(source, contains('Belum Diposting - Tertahan'));
    }
  });
}
