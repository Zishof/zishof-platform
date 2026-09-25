import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pemilih barang PO menampilkan stok dan pemakaian outlet', () {
    final layar =
        File('lib/screens/pengadaan_po_screen.dart').readAsStringSync();
    expect(layar, contains("aksi('pengadaan_pr_barang_tersedia'"));
    expect(layar, contains("b.data['stokSaatIni']"));
    expect(layar, contains("b.data['pemakaian30Hari']"));
    expect(layar, contains("b.data['proyeksiStokSetelahPo']"));
  });
}
