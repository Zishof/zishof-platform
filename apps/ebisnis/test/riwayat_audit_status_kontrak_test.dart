import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Riwayat Audit menerima kedua status sukses API eBisnis', () {
    final source =
        File('lib/screens/riwayat_audit_screen.dart').readAsStringSync();

    // Backend lama mengirim "00", sedangkan normalisasi PosApi/ApiEBisnis
    // mengirim "success". Seluruh aksi di layar ini wajib memakai satu kontrak
    // bersama agar jawaban sukses tidak berubah menjadi "Gagal memuat riwayat".
    expect(
      'ApiClient.statusResponsSukses(res[\'status\'])'
          .allMatches(source)
          .length,
      5,
    );
    expect(source, isNot(contains("res['status'] != '00'")));
    expect(source, isNot(contains("res['status'] == '00'")));
  });
}
