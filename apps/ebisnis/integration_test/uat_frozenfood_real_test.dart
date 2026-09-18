import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/models.dart';
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:ebisnis/screens/keranjang_screen.dart';
import 'package:ebisnis/screens/pesanan_screen.dart';
import 'package:ebisnis/screens/kulakan_screen.dart';
import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:ebisnis/screens/laporan_screen.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _outputDir = r'C:\opt\uat-frozenfood-screenshots';

Produk _buatProduk({
  required int id,
  required String kode,
  required String barcode,
  required String nama,
  required double hargaJual,
  required double hargaBeli,
  required String foto,
}) {
  return Produk(
    id: id,
    kode: kode,
    barcode: barcode,
    nama: nama,
    hargaJual: hargaJual,
    hargaBeli: hargaBeli,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Frozen Food',
    gambarUrl: foto,
  );
}

final _sampleProducts = [
  _buatProduk(
    id: 1,
    kode: 'PKJ01',
    barcode: 'FRZ-KJ-KECIL',
    nama: 'Pentol KJ Daging Sapi Kecil',
    hargaJual: 16000,
    hargaBeli: 13000,
    foto: 'assets/images/frozenfood/produk/pentol_kj_kecil.png',
  ),
  _buatProduk(
    id: 2,
    kode: 'PKJ02',
    barcode: 'FRZ-KJ-BESAR',
    nama: 'Pentol KJ Daging Sapi Besar',
    hargaJual: 21000,
    hargaBeli: 17000,
    foto: 'assets/images/frozenfood/produk/pentol_kj_besar.png',
  ),
  _buatProduk(
    id: 3,
    kode: 'BDK01',
    barcode: 'FRZ-BKS-DG-KECIL',
    nama: 'Bakso Daging Sapi Kecil',
    hargaJual: 16000,
    hargaBeli: 13000,
    foto: 'assets/images/frozenfood/produk/bakso_daging_kecil.png',
  ),
  _buatProduk(
    id: 4,
    kode: 'BDB01',
    barcode: 'FRZ-BKS-DG-BESAR',
    nama: 'Bakso Daging Sapi Besar',
    hargaJual: 21000,
    hargaBeli: 17000,
    foto: 'assets/images/frozenfood/produk/bakso_daging_besar.png',
  ),
  _buatProduk(
    id: 5,
    kode: 'BSD25',
    barcode: 'FRZ-BKS-SDG-25',
    nama: 'Bakso Sedang Isi 25',
    hargaJual: 30000,
    hargaBeli: 24000,
    foto: 'assets/images/frozenfood/produk/bakso_sedang_25.png',
  ),
  _buatProduk(
    id: 6,
    kode: 'BBS10',
    barcode: 'FRZ-BKS-BSR-10',
    nama: 'Bakso Besar Isi 10',
    hargaJual: 35000,
    hargaBeli: 28000,
    foto: 'assets/images/frozenfood/produk/bakso_besar_10.png',
  ),
  _buatProduk(
    id: 7,
    kode: 'BJB06',
    barcode: 'FRZ-BKS-JMB-6',
    nama: 'Bakso Jumbo Isi 6',
    hargaJual: 35000,
    hargaBeli: 28000,
    foto: 'assets/images/frozenfood/produk/bakso_jumbo_6.png',
  ),
  _buatProduk(
    id: 8,
    kode: 'BKL04',
    barcode: 'FRZ-BKS-KLG-4',
    nama: 'Bakso Klenger Isi 4',
    hargaJual: 35000,
    hargaBeli: 28000,
    foto: 'assets/images/frozenfood/produk/bakso_klenger_4.png',
  ),
  _buatProduk(
    id: 9,
    kode: 'ADNAYM',
    barcode: 'FRZ-ADN-AYAM',
    nama: 'Adonan Ayam 1 Kg',
    hargaJual: 33000,
    hargaBeli: 26000,
    foto: 'assets/images/frozenfood/produk/adonan_ayam.png',
  ),
  _buatProduk(
    id: 10,
    kode: 'ADNSPI',
    barcode: 'FRZ-ADN-SAPI',
    nama: 'Adonan Sapi 1 Kg',
    hargaJual: 47000,
    hargaBeli: 38000,
    foto: 'assets/images/frozenfood/produk/adonan_sapi.png',
  ),
  _buatProduk(
    id: 11,
    kode: 'ADNSLH',
    barcode: 'FRZ-ADN-SOLO-HLS',
    nama: 'Adonan Bakso Solo Halus 1 Kg',
    hargaJual: 40000,
    hargaBeli: 32000,
    foto: 'assets/images/frozenfood/produk/adonan_solo_halus.png',
  ),
  _buatProduk(
    id: 12,
    kode: 'ADNSLK',
    barcode: 'FRZ-ADN-SOLO-KSR',
    nama: 'Adonan Bakso Solo Kasar 1 Kg',
    hargaJual: 40000,
    hargaBeli: 32000,
    foto: 'assets/images/frozenfood/produk/adonan_solo_kasar.png',
  ),
];

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 600));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak ada');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir);
  await directory.create(recursive: true);
  final f = File('${directory.path}\\$name.png');
  await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<void> _pumpPage(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      title: 'Sarimpi Jaya Frozen POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: child,
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT Real Varian Sarimpi Jaya Frozen POS', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // =========================================================================
    // 1. JUAL PRODUK & KERANJANG
    // =========================================================================
    final itemKeranjang1 = ItemKeranjang(produk: _sampleProducts[0], jumlah: 2);
    final itemKeranjang2 = ItemKeranjang(produk: _sampleProducts[4], jumlah: 1);
    final itemKeranjang3 = ItemKeranjang(produk: _sampleProducts[9], jumlah: 1);

    await _pumpPage(
      tester,
      KasirScreen(
        keranjangAwal: [itemKeranjang1, itemKeranjang2, itemKeranjang3],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '01_jual_produk_katalog_kasir');

    // Buka Keranjang Pembayaran
    await _pumpPage(
      tester,
      KeranjangScreen(
        keranjang: [itemKeranjang1, itemKeranjang2, itemKeranjang3],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '02_jual_produk_keranjang_pembayaran');

    // =========================================================================
    // 2. MENU PEMESANAN & DRAFT
    // =========================================================================
    await _pumpPage(tester, const PesananScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '03_menu_pemesanan_dan_penjualan');

    // =========================================================================
    // 3. KULAKAN / PEMBELIAN STOK BARANG BEKU
    // =========================================================================
    await _pumpPage(tester, const KulakanScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '04_kulakan_pembelian_stok');

    // =========================================================================
    // 4. RIWAYAT PENJUALAN
    // =========================================================================
    await _pumpPage(tester, const RiwayatPenjualanScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '05_riwayat_penjualan');

    // =========================================================================
    // 5. LAPORAN-LAPORAN
    // =========================================================================
    await _pumpPage(tester, const LaporanScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '06_laporan_laporan_katalog');
  });
}
