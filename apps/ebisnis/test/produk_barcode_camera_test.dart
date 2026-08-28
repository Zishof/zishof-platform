import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('form produk menyediakan scan kamera barcode dan QR-Code', () {
    final source = File('lib/screens/produk_screen.dart').readAsStringSync();

    expect(source, contains("import 'package:core_hw/core_hw.dart';"));
    expect(source, contains('BarcodeScannerScreen.pindai('));
    expect(source, contains("judul: 'Scan Barcode / QR-Code Produk'"));
    expect(source, contains('icon: const Icon(Icons.qr_code_scanner)'));
    expect(source, contains('_barcode.text = hasil.trim();'));
  });

  test('pencarian produk bersama mendukung kamera HP dan webcam Desktop', () {
    final komponen = File('lib/widgets/app_components.dart').readAsStringSync();
    final banbox =
        File('lib/widgets/pencarian_produk_banbox.dart').readAsStringSync();
    final kasir = File('lib/screens/kasir_screen.dart').readAsStringSync();

    expect(komponen, contains('final bool scanProduk;'));
    expect(komponen, contains("judul: 'Scan Barcode / QR Produk'"));
    expect(komponen, contains('BarcodeScannerScreen.pindai('));
    expect(banbox, contains('this.tampilkanScanner = true'));
    expect(banbox, contains('BarcodeScannerScreen.pindai('));
    expect(kasir, contains('Future<void> _scanProdukKasir()'));
    expect(kasir, contains('await _submitPencarian(nilai)'));
  });

  test('seluruh pencarian produk utama mengaktifkan scanner kamera', () {
    const layar = <String>[
      'lib/screens/apotik/kasir_apotik_screen.dart',
      'lib/screens/apotik/persediaan_apotik_screen.dart',
      'lib/screens/grup_produk_screen.dart',
      'lib/screens/inventory_sales/harga_screen.dart',
      'lib/screens/inventory_sales/penjualan_sales_screen.dart',
      'lib/screens/inventory_sales/persediaan_screen.dart',
      'lib/screens/inventory_sales/piutang_screen.dart',
      'lib/screens/inventory_sales/spj_screen.dart',
      'lib/screens/kedaluwarsa_screen.dart',
      'lib/screens/laporan_detail_screen.dart',
      'lib/screens/mutasi_antar_outlet_screen.dart',
      'lib/screens/pengadaan_bast_screen.dart',
      'lib/screens/pengadaan_po_screen.dart',
      'lib/screens/pengadaan_pr_screen.dart',
      'lib/screens/price_tag_screen.dart',
      'lib/screens/produk_mutasi_barang_tab.dart',
      'lib/screens/produk_rekonsiliasi_ledger_tab.dart',
      'lib/screens/produk_screen.dart',
      'lib/screens/retur_penjualan_screen.dart',
      'lib/screens/stok_opname_screen.dart',
    ];

    for (final path in layar) {
      expect(File(path).readAsStringSync(), contains('scanProduk: true'),
          reason: '$path belum mengaktifkan scanner produk');
    }
  });
}
