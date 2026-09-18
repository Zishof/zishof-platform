import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:core_db/core_db.dart';
import 'package:ebisnis/app_variant.dart';
import 'package:ebisnis/models.dart';
import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/screens/kasir_screen.dart';
import 'package:ebisnis/screens/pesanan_screen.dart';
import 'package:ebisnis/screens/kulakan_screen.dart';
import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/screens/laporan_screen.dart';
import 'package:ebisnis/sesi.dart';
import 'package:ebisnis/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';

const _outputDir = r'C:\opt\uat-frozenfood-screenshots';

final _sampleProducts = [
  Produk(
    id: 1,
    kode: 'PKJ01',
    barcode: 'FRZ-PKJ-01',
    nama: 'Pentol KJ Kecil (Isi 50)',
    hargaJual: 18000,
    hargaBeli: 14000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/pentol_kj_kecil.png',
  ),
  Produk(
    id: 2,
    kode: 'PKJ02',
    barcode: 'FRZ-PKJ-02',
    nama: 'Pentol KJ Besar (Isi 10)',
    hargaJual: 18000,
    hargaBeli: 14000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/pentol_kj_besar.png',
  ),
  Produk(
    id: 3,
    kode: 'BDH01',
    barcode: 'FRZ-BDH-01',
    nama: 'Bakso Daging Halus Kecil (Isi 50)',
    hargaJual: 28000,
    hargaBeli: 22000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_daging_kecil.png',
  ),
  Produk(
    id: 4,
    kode: 'BDH02',
    barcode: 'FRZ-BDH-02',
    nama: 'Bakso Daging Halus Besar (Isi 10)',
    hargaJual: 28000,
    hargaBeli: 22000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_daging_besar.png',
  ),
  Produk(
    id: 5,
    kode: 'BSK25',
    barcode: 'FRZ-BSK-25',
    nama: 'Bakso Sedang Kasar (Isi 25)',
    hargaJual: 50000,
    hargaBeli: 40000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_sedang_25.png',
  ),
  Produk(
    id: 6,
    kode: 'BBK10',
    barcode: 'FRZ-BBK-10',
    nama: 'Bakso Besar Kasar (Isi 10)',
    hargaJual: 45000,
    hargaBeli: 36000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_besar_10.png',
  ),
  Produk(
    id: 7,
    kode: 'BJK06',
    barcode: 'FRZ-BJK-06',
    nama: 'Bakso Jumbo Kasar (Isi 6)',
    hargaJual: 45000,
    hargaBeli: 36000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_jumbo_6.png',
  ),
  Produk(
    id: 8,
    kode: 'BKL04',
    barcode: 'FRZ-BKL-04',
    nama: 'Bakso Klenger Kasar (Isi 4)',
    hargaJual: 45000,
    hargaBeli: 36000,
    stok: 100,
    kategoriId: 1,
    kategoriNama: 'Bakso & Pentol',
    gambarUrl: 'assets/images/frozenfood/produk/bakso_klenger_4.png',
  ),
  Produk(
    id: 9,
    kode: 'ADNAYM',
    barcode: 'FRZ-ADN-AYM',
    nama: 'Adonan Ayam',
    hargaJual: 26000,
    hargaBeli: 20000,
    stok: 100,
    kategoriId: 2,
    kategoriNama: 'Adonan Bakso',
    gambarUrl: 'assets/images/frozenfood/produk/adonan_ayam.png',
  ),
  Produk(
    id: 10,
    kode: 'ADNSPI',
    barcode: 'FRZ-ADN-SPI',
    nama: 'Adonan Sapi',
    hargaJual: 28000,
    hargaBeli: 22000,
    stok: 100,
    kategoriId: 2,
    kategoriNama: 'Adonan Bakso',
    gambarUrl: 'assets/images/frozenfood/produk/adonan_sapi.png',
  ),
  Produk(
    id: 11,
    kode: 'ADNSLH',
    barcode: 'FRZ-ADN-SLH',
    nama: 'Adonan Solo Halus',
    hargaJual: 44000,
    hargaBeli: 35000,
    stok: 100,
    kategoriId: 2,
    kategoriNama: 'Adonan Bakso',
    gambarUrl: 'assets/images/frozenfood/produk/adonan_solo_halus.png',
  ),
  Produk(
    id: 12,
    kode: 'ADNSLK',
    barcode: 'FRZ-ADN-SLK',
    nama: 'Adonan Solo Kasar',
    hargaJual: 44000,
    hargaBeli: 35000,
    stok: 100,
    kategoriId: 2,
    kategoriNama: 'Adonan Bakso',
    gambarUrl: 'assets/images/frozenfood/produk/adonan_solo_kasar.png',
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

  testWidgets('UAT Real 10x Transaksi & Laporan Sarimpi Jaya Frozen POS',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Setup Sesi lokal
    Sesi.instance.userId = 'kasir_sarimpi';
    Sesi.instance.tokoId = 1;
    Sesi.instance.tokoNama = 'Outlet Sarimpi Jaya Frozen';
    Sesi.instance.tenantId = 0;
    Sesi.instance.tenantKode = 'sarimpijaya';
    Sesi.instance.tenantNama = 'Sarimpi Jaya Frozen';
    Sesi.instance.wajibSesiKas = false;
    Sesi.instance.isAdmin = true; // Menampilkan tombol dan akses penuh
    Sesi.instance.supervisorPedagang = true;

    // 1. Masukkan Katalog 12 Produk ke Cache SQLite Lokal
    final rowsCache = _sampleProducts.map((p) => {
      'id': p.id,
      'kode': p.kode,
      'barcode': p.barcode,
      'nama': p.nama,
      'harga_jual': p.hargaJual,
      'stok': p.stok,
      'kategori_id': p.kategoriId,
      'kategori_nama': p.kategoriNama,
      'gambar_url': p.gambarUrl,
      'izinkan_jual_minus_stok': 0,
      'ekstra_pilihan': '[]',
      'kemasan': '[]',
      'foto_urls': '[]',
    }).toList();
    await CoreDb.instance.upsertProdukCache(rowsCache);

    // 2. Simulasikan 10x Transaksi Penjualan Produk Random
    final rng = Random(42);
    final listPesanan = <Map<String, dynamic>>[];
    final listKulakan = <Map<String, dynamic>>[];
    final listRekapPerProduk = <String, Map<String, dynamic>>{};

    double totalOmzet10Transaksi = 0;
    int totalQty10Transaksi = 0;

    final baseDate = DateTime.now().subtract(const Duration(hours: 3));

    final supplierList = [
      'Pabrik Sarimpi Frozen Kraksaan',
      'Dapur Sentral Olahan Sapi Kraksaan',
      'Supplier Daging Segar Bromo',
      'Sentra Bumbu Bakso Nusantara',
    ];

    for (var i = 1; i <= 10; i++) {
      final waktuTrx = baseDate.add(Duration(minutes: i * 15));
      final nomorNota = 'FRZ-${DateFormat('yyyyMMdd').format(waktuTrx)}-${i.toString().padLeft(4, '0')}';
      
      // Pilih 1 - 3 jenis produk acak
      final jumlahItem = 1 + rng.nextInt(3);
      final itemsTrx = <Map<String, dynamic>>[];
      double subtotalTrx = 0;

      for (var j = 0; j < jumlahItem; j++) {
        final prod = _sampleProducts[rng.nextInt(_sampleProducts.length)];
        final qty = 1 + rng.nextInt(3); // 1-3 pack/kg
        final harga = prod.hargaJual;
        final subtotal = harga * qty;
        subtotalTrx += subtotal;

        itemsTrx.add({
          'id': prod.id,
          'kode': prod.kode,
          'nama': prod.nama,
          'harga': harga,
          'jumlah': qty,
          'diskon': 0,
          'cashback': 0,
          'ekstra': [],
        });

        // Agregasi untuk laporan
        if (!listRekapPerProduk.containsKey(prod.kode)) {
          listRekapPerProduk[prod.kode] = {
            'kode': prod.kode,
            'nama': prod.nama,
            'qty': 0,
            'omzet': 0.0,
            'hpp': 0.0,
          };
        }
        listRekapPerProduk[prod.kode]!['qty'] = (listRekapPerProduk[prod.kode]!['qty'] as int) + qty;
        listRekapPerProduk[prod.kode]!['omzet'] = (listRekapPerProduk[prod.kode]!['omzet'] as double) + subtotal;
        listRekapPerProduk[prod.kode]!['hpp'] = (listRekapPerProduk[prod.kode]!['hpp'] as double) + (prod.hargaBeli * qty);

        totalQty10Transaksi += qty;
      }

      totalOmzet10Transaksi += subtotalTrx;

      final metodeBayar = (i % 3 == 0) ? 'QRIS' : ((i % 3 == 1) ? 'Tunai' : 'Transfer Bank');

      final payload = {
        'kodeUnik': nomorNota,
        'nomorNota': nomorNota,
        'waktu': DateFormat('dd-MM-yyyy HH:mm:ss').format(waktuTrx),
        'total': subtotalTrx,
        'pajak': 0,
        'caraBayarNama': metodeBayar,
        'kasir': 'Kasir Sarimpi Jaya',
        'nama_mesin': 'POS-FROZEN-01',
        'nama_member': 'Pelanggan Toko #$i',
        'transaksi': itemsTrx,
      };

      // Simpan ke arsip transaksi lokal SQLite
      await CoreDb.instance.simpanTransaksiPending(
        nomorNota,
        jsonEncode(payload),
        akunKunci: 'kasir_sarimpi',
        tokoId: 1,
        idPerangkat: 'POS-FROZEN-01',
      );

      // Simulasikan 10 data Pesanan Online & Keranjang Tertahan
      listPesanan.add({
        'id': i,
        'kode': 'ORD-${DateFormat('yyyyMMdd').format(waktuTrx)}-${i.toString().padLeft(4, '0')}',
        'pemesan': 'Pelanggan Frozen Member #$i',
        'anggotaId': i,
        'totalBiaya': subtotalTrx,
        'lunas': (i % 2 == 0),
        'lunasId': (i % 2 == 0) ? 1 : null,
        'totalDiskon': 0,
        'totalCashback': 0,
        'tokoNama': 'Outlet Sarimpi Jaya Frozen',
        'keterangan': (i % 2 == 1) ? 'Hold Order: Tambah adonan kiloan' : 'Pesanan PO Pelanggan Online',
        'tanggalPembayaran': DateFormat('dd-MM-yyyy HH:mm:ss').format(waktuTrx),
        'caraBayarId': 1,
        'dariPembeliOnline': (i % 2 == 0),
        'kasirLoginNama': 'kasir_sarimpi',
        'namaMesin': 'POS-FROZEN-01',
        'items': itemsTrx,
      });

      // Simulasikan 10 data Faktur Kulakan / Pembelian Stok Masuk
      final qtyKulakan = 20 + i * 5;
      final totalKulakan = qtyKulakan * 16000.0;
      listKulakan.add({
        'id': i,
        'fakturId': i,
        'nomorFaktur': 'KUL-${DateFormat('yyyyMMdd').format(waktuTrx)}-${i.toString().padLeft(4, '0')}',
        'tanggalFaktur': DateFormat('dd/MM/yyyy').format(waktuTrx),
        'namaSupplier': supplierList[(i - 1) % supplierList.length],
        'supplierId': ((i - 1) % supplierList.length) + 1,
        'jumlahItem': 2 + (i % 3),
        'totalHitung': totalKulakan,
        'diskon': 0,
        'keterangan': 'Penerimaan pasokan restock rantai dingin harian batch #${i.toString().padLeft(3, '0')}',
      });
    }

    // Simpan cache riwayat pesanan (semua key yang relevan di MasterOffline)
    final cachePesananJson = jsonEncode(listPesanan);
    await CoreDb.instance.simpanCacheReferensi('master:pesanan:semua:semua', cachePesananJson);
    await CoreDb.instance.simpanCacheReferensi('master:pesanan:semua:belum_lunas', cachePesananJson);
    await CoreDb.instance.simpanCacheReferensi('master:pesanan:online:semua', cachePesananJson);
    await CoreDb.instance.simpanCacheReferensi('master:pesanan:tertahan:semua', cachePesananJson);
    await CoreDb.instance.simpanCacheReferensi('pesanan:semua', cachePesananJson);

    // Simpan cache riwayat faktur kulakan
    final cacheKulakanJson = jsonEncode(listKulakan);
    await CoreDb.instance.simpanCacheReferensi('master:kulakan_faktur', cacheKulakanJson);

    // Simpan cache katalog laporan (10+ laporan siap pakai)
    final katalogLaporan = [
      {
        'kat': 'Laporan Penjualan',
        'items': [
          {'id': 'pnj_per_barang', 'judul': 'Laporan Penjualan per Barang', 'ket': 'Rekap kuantiti, omzet, dan laba per barang', 'produk': true, 'pelanggan': false, 'perToko': true},
          {'id': 'pnj_rekap_harian', 'judul': 'Rekap Penjualan Harian', 'ket': 'Ringkasan penjualan harian shift kasir', 'produk': false, 'pelanggan': false, 'perToko': true},
          {'id': 'pnj_per_kasir', 'judul': 'Laporan Penjualan per Kasir', 'ket': 'Omzet dan rekap transaksi kasir aktif', 'produk': false, 'pelanggan': false, 'perToko': true},
          {'id': 'pnj_per_pelanggan', 'judul': 'Laporan Penjualan per Pelanggan', 'ket': 'Penjualan ke member dan pelanggan umum', 'produk': false, 'pelanggan': true, 'perToko': true},
          {'id': 'pnj_metode_bayar', 'judul': 'Rekap Penerimaan Cara Bayar', 'ket': 'Rincian transaksi Tunai, QRIS, dan Transfer', 'produk': false, 'pelanggan': false, 'perToko': true},
        ],
      },
      {
        'kat': 'Laporan Persediaan & Kulakan',
        'items': [
          {'id': 'stk_posisi_stok', 'judul': 'Posisi Stok Barang Beku', 'ket': 'Daftar stok fisik terkini dan nilai persediaan', 'produk': true, 'pelanggan': false, 'perToko': true},
          {'id': 'stk_mutasi_harian', 'judul': 'Mutasi Stok Harian', 'ket': 'Kartu stok masuk, keluar, dan penyesuaian', 'produk': true, 'pelanggan': false, 'perToko': true},
          {'id': 'stk_kulakan_faktur', 'judul': 'Rekap Faktur Kulakan Supplier', 'ket': 'Histori penerimaan barang kulakan dari supplier', 'produk': false, 'pelanggan': false, 'perToko': true},
          {'id': 'stk_stok_minimum', 'judul': 'Peringatan Stok Minimum', 'ket': 'Produk dengan kuantiti mendekati batas reorder', 'produk': true, 'pelanggan': false, 'perToko': true},
        ],
      },
      {
        'kat': 'Laporan Keuangan Toko',
        'items': [
          {'id': 'keu_laba_kotor', 'judul': 'Laporan Laba Kotor Produk', 'ket': 'Perhitungan margin laba kotor per produk beku', 'produk': true, 'pelanggan': false, 'perToko': true},
          {'id': 'keu_rekap_kasir', 'judul': 'Rekap Kas Masuk Kasir', 'ket': 'Setoran dan penerimaan uang kas kasir shift', 'produk': false, 'pelanggan': false, 'perToko': true},
          {'id': 'keu_arus_kas', 'judul': 'Arus Kas Operasional Toko', 'ket': 'Penerimaan dan pengeluaran kas harian', 'produk': false, 'pelanggan': false, 'perToko': true},
        ],
      }
    ];
    final katalogStr = jsonEncode(katalogLaporan);
    final sekarang = DateTime.now();
    final tglMulaiStr = DateFormat('yyyy-MM-dd').format(DateTime(sekarang.year, sekarang.month, 1));
    final tglSampaiStr = DateFormat('yyyy-MM-dd').format(sekarang);

    // Kunci cache katalog laporan
    final katalogKeys = [
      'master:laporan_katalog:laporan_katalog:0:kasir_sarimpi',
      'master:laporan_katalog:laporan_katalog:${Uri.encodeComponent('0:kasir_sarimpi')}',
      'master:laporan_katalog:laporan_katalog:1:kasir_sarimpi',
      'master:laporan_katalog:laporan_katalog:${Uri.encodeComponent('1:kasir_sarimpi')}',
      'master:laporan_katalog:laporan_katalog:sarimpijaya:kasir_sarimpi',
      'master:laporan_katalog:laporan_katalog:kasir_sarimpi',
      'master:laporan_katalog:laporan_katalog:',
    ];
    for (final k in katalogKeys) {
      await CoreDb.instance.simpanCacheReferensi(k, katalogStr);
    }

    // Siapkan data laporan penjualan per barang (10 baris terisi)
    final barisLaporanProduk = listRekapPerProduk.values.map((v) {
      final qty = v['qty'] as int;
      final omzet = v['omzet'] as double;
      final hpp = v['hpp'] as double;
      final laba = omzet - hpp;
      return [
        v['kode'],
        v['nama'],
        qty,
        'Bungkus/Kg',
        omzet,
        laba,
      ];
    }).toList();

    final kolomLaporanDetail = [
      {'l': 'Kode', 't': 'text'},
      {'l': 'Nama Produk', 't': 'text'},
      {'l': 'Terjual (Qty)', 't': 'num'},
      {'l': 'Satuan', 't': 'text'},
      {'l': 'Total Omzet', 't': 'num'},
      {'l': 'Laba Kotor', 't': 'num'},
    ];

    final payloadLaporanProduk = {
      'status': '00',
      'judul': 'Laporan Penjualan per Barang (Sarimpi Jaya Frozen)',
      'kolom': kolomLaporanDetail,
      'baris': barisLaporanProduk,
      'grandTotal': true,
      'totalHitung': totalOmzet10Transaksi,
      '_disimpanPada': DateTime.now().toIso8601String(),
    };

    final jsonLaporanStr = jsonEncode(payloadLaporanProduk);

    final detailKeys = [
      'laporan:jalankan:pnj_per_barang:${tglMulaiStr}_$tglSampaiStr:-:-:-:-',
      'laporan:jalankan:pnj_per_barang:${tglMulaiStr}_$tglSampaiStr:-:-:true:-',
      'laporan:jalankan:pnj_per_barang:${tglMulaiStr}_$tglSampaiStr:-:-:-:0',
      'laporan:jalankan:pnj_per_barang:${tglMulaiStr}_$tglSampaiStr:-:-:true:0',
      'laporan:jalankan:pnj_per_barang:-_-:-:-:-:-',
      'laporan:jalankan:pnj_per_barang:-_-:-:-:true:-',
      'laporan:jalankan:pnj_per_barang:-_-:-:-:-:0',
    ];
    for (final k in detailKeys) {
      await CoreDb.instance.simpanCacheReferensi(k, jsonLaporanStr);
    }

    // =========================================================================
    // SCREENSHOT 1: Jual Produk (Katalog Kasir Bersih Penuh Produk & Keranjang)
    // =========================================================================
    final itemKasir1 = ItemKeranjang(produk: _sampleProducts[0], jumlah: 2); // Pentol KJ Kecil
    final itemKasir2 = ItemKeranjang(produk: _sampleProducts[4], jumlah: 1); // Bakso Sedang 25
    final itemKasir3 = ItemKeranjang(produk: _sampleProducts[9], jumlah: 1); // Adonan Sapi 1Kg

    await _pumpPage(
      tester,
      KasirScreen(
        keranjangAwal: [itemKasir1, itemKasir2, itemKasir3],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '01_jual_produk_katalog_kasir');

    // =========================================================================
    // SCREENSHOT 2: Menu Pemesanan & Draft Penjualan (10 Record Terisi)
    // =========================================================================
    await _pumpPage(tester, const PesananScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '02_menu_pemesanan_dan_penjualan');

    // =========================================================================
    // SCREENSHOT 3: Kulakan / Pembelian Stok Barang Beku (10 Faktur Terisi)
    // =========================================================================
    await _pumpPage(tester, const KulakanScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '03_kulakan_pembelian_stok');

    // =========================================================================
    // SCREENSHOT 4: Riwayat 10x Transaksi Penjualan
    // =========================================================================
    await _pumpPage(tester, const RiwayatPenjualanScreen());
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '04_riwayat_10_penjualan');

    // =========================================================================
    // SCREENSHOT 5: Katalog Laporan-Laporan (12 Pilihan Laporan Siap Pakai)
    // =========================================================================
    await _pumpPage(
      tester,
      LaporanScreen(
        kategoriAwal: katalogLaporan,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _shot(tester, '05_laporan_laporan_katalog');

    // =========================================================================
    // SCREENSHOT 6: Hasil Laporan Rekap Penjualan 10x Transaksi per Produk (Tabel Terisi)
    // =========================================================================
    await _pumpPage(
      tester,
      LaporanDetailScreen(
        item: const {
          'id': 'pnj_per_barang',
          'judul': 'Laporan Penjualan per Barang',
          'kategori': 'Laporan Penjualan',
          'produk': true,
          'perToko': true,
        },
        hasilAwal: payloadLaporanProduk,
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await _shot(tester, '06_hasil_laporan_rekap_penjualan_10_trx');
  });
}
