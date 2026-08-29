import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('menu sistem menyediakan riwayat perubahan lintas CRUD', () {
    final shell = File('lib/widgets/app_shell.dart').readAsStringSync();
    final layar =
        File('lib/screens/riwayat_audit_screen.dart').readAsStringSync();

    expect(shell, contains('Riwayat Perubahan Data'));
    expect(layar, contains("aksi('revisi_entitas'"));
    expect(layar, contains("aksi('revisi_jelajah'"));
    expect(layar, contains('final bool embedded'));
    expect(layar, contains("'satuan_produk': 'Satuan/UOM Produk'"));
    expect(layar, contains("'stok_opname': 'Detail Stok Opname'"));
    expect(layar, contains("'produksi': 'Produksi'"));
    expect(layar, contains("'pembayaran_anggota': 'Pembayaran Member'"));
  });

  test('label field baru tetap ramah tanpa hardcode tiap CRUD', () {
    final dialog =
        File('lib/widgets/riwayat_data_dialog.dart').readAsStringSync();
    final layar =
        File('lib/screens/riwayat_audit_screen.dart').readAsStringSync();

    expect(dialog, contains("replaceAll('_', ' ')"));
    expect(dialog, contains("RegExp(r'(?<=[a-z0-9])(?=[A-Z])')"));
    expect(layar, contains("_labelEntitas[kode] ?? _ramah(kode)"));
    expect(layar, contains("'Riwayat Perubahan Data'"));
  });
}
