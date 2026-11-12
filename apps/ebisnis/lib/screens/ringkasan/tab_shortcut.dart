import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/aksi_baris_menu.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/safe_state.dart';
import '../anggota_screen.dart';
import '../cara_bayar_screen.dart';
import '../diskon_screen.dart';
import '../grup_produk_screen.dart';
import '../jenis_produk_screen.dart';
import '../kasir_screen.dart';
import '../kedaluwarsa_screen.dart';
import '../kulakan_screen.dart';
import '../laporan_detail_screen.dart';
import '../laporan_screen.dart';
import '../laporan_transaksi_screen.dart';
import '../pesanan_screen.dart';
import '../produk_screen.dart';
import '../rak_produk_screen.dart';
import '../retur_penjualan_screen.dart';
import '../riwayat_penjualan_screen.dart';
import '../ringkasan_screen.dart';
import '../stok_opname_screen.dart';
import '../supplier_screen.dart';
import '../uom_screen.dart';

/// Daftar bawaan 21 Shortcut Menu Utama & Laporan Vital yang terisi otomatis
/// sejak awal aplikasi berjalan (sinkron penuh dengan `EbisnisShortcutHelper.java`
/// di server AIS).
///
/// Daftar ini mencakup 5 laporan utama yang diminta manajemen:
/// 1. Laporan Penjualan per Cabang (`pnj_per_cabang`)
/// 2. Laporan Penjualan per Barang & Mutasi Barang (`pnj_per_barang`, `gud_mutasi_item`, `produk:tab:1`)
/// 3. Mutasi Barang per Tanggal & Stok Barang per Tanggal (`produk:tab:2`, `mutasi_barang_per_tanggal`, `stok_per_tanggal`)
/// 4. Penerimaan Kas per Bank (Harian) (`fin_penerimaan_per_metode`, `pos_per_akun_bank`)
/// 5. Laporan Harian Outlet (`laporan_harian_outlet`)
/// serta pintasan operasional paling sering diakses (Kasir/POS, Stok Opname per Rak,
/// Manajemen Rak Produk, Kulakan, Topup Member, Laporan Transaksi Per Kasir, dsb.).
List<Map<String, dynamic>> buatDaftarShortcutDefaultLokal() =>
    <Map<String, dynamic>>[
      // =====================================================================
      // GRUP 1: LAPORAN VITAL & HARIAN (5 LAPORAN UTAMA + PENDUKUNG)
      // =====================================================================
      {
        'id': 'sc_pnj_per_cabang',
        'judul': 'Laporan Penjualan per Cabang',
        'ket':
            'Ringkasan penjualan, HPP/BPP, dan laba kotor per cabang/toko & harian',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'pnj_per_cabang',
        'kunciMenu': 'laporan',
        'ikon': 'storefront',
        'warna': '#2563EB',
        'urutan': 1,
        'aktif': true,
      },
      {
        'id': 'sc_pnj_per_barang',
        'judul': 'Laporan Penjualan per Barang',
        'ket': 'Kuantitas terjual, omzet, diskon, HPP, dan laba per produk',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'pnj_per_barang',
        'kunciMenu': 'laporan',
        'ikon': 'shopping_bag',
        'warna': '#0D9488',
        'urutan': 2,
        'aktif': true,
      },
      {
        'id': 'sc_mutasi_barang_tab',
        'judul': 'Mutasi Barang (Kartu Stok & Analisis)',
        'ket':
            'Rincian saldo awal, masuk, terjual, opname (+/-), saldo akhir & analisis cerdas',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'TAB',
        'target': 'produk:tab:1',
        'kunciMenu': 'produk',
        'ikon': 'swap_horiz',
        'warna': '#7C3AED',
        'urutan': 3,
        'aktif': true,
      },
      {
        'id': 'sc_mutasi_per_tanggal_tab',
        'judul': 'Mutasi Barang per Tanggal',
        'ket':
            'Rekapitulasi mutasi masuk, keluar, penjualan, dan SO barang per tanggal',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'TAB',
        'target': 'produk:tab:2',
        'kunciMenu': 'produk',
        'ikon': 'calendar_month',
        'warna': '#EA580C',
        'urutan': 4,
        'aktif': true,
      },
      {
        'id': 'sc_stok_per_tanggal',
        'judul': 'Stok Barang per Tanggal',
        'ket':
            'Posisi kuantitas stok dan nilai persediaan barang pada tanggal acuan tertentu',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'stok_per_tanggal',
        'kunciMenu': 'laporan',
        'ikon': 'event_available',
        'warna': '#0284C7',
        'urutan': 5,
        'aktif': true,
      },
      {
        'id': 'sc_penerimaan_kas_bank_harian',
        'judul': 'Penerimaan Kas per Bank (Harian)',
        'ket':
            'Rekap penerimaan harian per Kas/Bank (Tunai, QRIS, Transfer Bank, EDC, Voucher)',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'fin_penerimaan_per_metode',
        'kunciMenu': 'laporan',
        'ikon': 'account_balance',
        'warna': '#16A34A',
        'urutan': 6,
        'aktif': true,
      },
      {
        'id': 'sc_laporan_harian_outlet',
        'judul': 'Laporan Harian Outlet',
        'ket':
            'Rekapitulasi omzet harian outlet: jumlah nota, diskon, pajak, tunai & non-tunai',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'laporan_harian_outlet',
        'kunciMenu': 'laporan',
        'ikon': 'assessment',
        'warna': '#D97706',
        'urutan': 7,
        'aktif': true,
      },
      {
        'id': 'sc_pos_per_akun_bank',
        'judul': 'Penjualan per Akun Kas & Bank',
        'ket':
            'Penerimaan penjualan POS dikelompokkan per akun kas/bank penampung',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'pos_per_akun_bank',
        'kunciMenu': 'laporan',
        'ikon': 'payments',
        'warna': '#059669',
        'urutan': 8,
        'aktif': true,
      },
      {
        'id': 'sc_gud_mutasi_item',
        'judul': 'Laporan Ringkasan Mutasi per Item',
        'ket':
            'Tabel laporan mutasi stok per barang (Masuk, Retur, Keluar/Terjual, Opname)',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'gud_mutasi_item',
        'kunciMenu': 'laporan',
        'ikon': 'inventory',
        'warna': '#4F46E5',
        'urutan': 9,
        'aktif': true,
      },
      {
        'id': 'sc_mutasi_barang_per_tanggal_lap',
        'judul': 'Laporan Mutasi Barang per Tanggal (Cetak/Excel)',
        'ket':
            'Cetak PDF & ekspor Excel mutasi barang harian per tanggal transaksi',
        'grup': 'Laporan Vital & Harian',
        'jenis': 'LAPORAN',
        'target': 'mutasi_barang_per_tanggal',
        'kunciMenu': 'laporan',
        'ikon': 'date_range',
        'warna': '#9333EA',
        'urutan': 10,
        'aktif': true,
      },

      // =====================================================================
      // GRUP 2: OPERASIONAL & PERSEDIAAN VITAL
      // =====================================================================
      {
        'id': 'sc_kasir_pos',
        'judul': 'Kasir / POS',
        'ket':
            'Layar transaksi penjualan kasir, scan barcode, dan cetak struk pelanggan',
        'grup': 'Operasional & Persediaan',
        'jenis': 'MENU',
        'target': 'kasir',
        'kunciMenu': 'kasir',
        'ikon': 'point_of_sale',
        'warna': '#15803D',
        'urutan': 11,
        'aktif': true,
      },
      {
        'id': 'sc_data_produk',
        'judul': 'Manajemen Produk & Stok Tanggal',
        'ket':
            'Kelola katalog barang, harga beli/jual, stok per tanggal, dan kartu stok',
        'grup': 'Operasional & Persediaan',
        'jenis': 'TAB',
        'target': 'produk:tab:0',
        'kunciMenu': 'produk',
        'ikon': 'inventory_2',
        'warna': '#2563EB',
        'urutan': 12,
        'aktif': true,
      },
      {
        'id': 'sc_stok_opname',
        'judul': 'Stok Opname (SO Grand & By Scan per Rak)',
        'ket':
            'Input stok opname per Rak, auto-save centang hijau, ekspor & impor Excel SO',
        'grup': 'Operasional & Persediaan',
        'jenis': 'MENU',
        'target': 'stokopname',
        'kunciMenu': 'stokopname',
        'ikon': 'fact_check',
        'warna': '#0D9488',
        'urutan': 13,
        'aktif': true,
      },
      {
        'id': 'sc_rak_produk',
        'judul': 'Manajemen Rak Produk',
        'ket':
            'Kelola Rak Utama & rak display, AmbilDataBanyak, pindah rak, dan impor Excel rak',
        'grup': 'Operasional & Persediaan',
        'jenis': 'MENU',
        'target': 'rak_produk',
        'kunciMenu': 'produk',
        'ikon': 'shelves',
        'warna': '#7C3AED',
        'urutan': 14,
        'aktif': true,
      },
      {
        'id': 'sc_kulakan',
        'judul': 'Kulakan / Pembelian Barang',
        'ket':
            'Catat barang masuk dari pemasok/supplier dan pembaruan HPP persediaan',
        'grup': 'Operasional & Persediaan',
        'jenis': 'MENU',
        'target': 'kulakan',
        'kunciMenu': 'kulakan',
        'ikon': 'local_shipping',
        'warna': '#EA580C',
        'urutan': 15,
        'aktif': true,
      },
      {
        'id': 'sc_riwayat_penjualan',
        'judul': 'Riwayat Penjualan & Detail Nota',
        'ket':
            'Cek struk penjualan, ubah rak pengambilan barang, atau batalkan transaksi',
        'grup': 'Operasional & Persediaan',
        'jenis': 'MENU',
        'target': 'riwayatpenjualan',
        'kunciMenu': 'riwayatpenjualan',
        'ikon': 'history',
        'warna': '#0284C7',
        'urutan': 16,
        'aktif': true,
      },

      // =====================================================================
      // GRUP 3: PELANGGAN, KASIR & KEUANGAN
      // =====================================================================
      {
        'id': 'sc_laporan_trx_kasir',
        'judul': 'Laporan Transaksi Per Kasir',
        'ket':
            'Rekap sesi kasir, rincian nota + nama pelanggan, penjualan & penerimaan per kasir',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'TAB',
        'target': 'laporantransaksi:tab:2',
        'kunciMenu': 'laporantransaksi',
        'ikon': 'badge',
        'warna': '#2563EB',
        'urutan': 17,
        'aktif': true,
      },
      {
        'id': 'sc_penerimaan_per_kasir',
        'judul': 'Penerimaan Per Kasir & Metode Bayar',
        'ket':
            'Rincian penerimaan uang per kasir dan per metode pembayaran (Tunai/QRIS/Transfer)',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'TAB',
        'target': 'laporantransaksi:tab:5',
        'kunciMenu': 'laporantransaksi',
        'ikon': 'point_of_sale',
        'warna': '#16A34A',
        'urutan': 18,
        'aktif': true,
      },
      {
        'id': 'sc_topup_member',
        'judul': 'Topup Saldo & Voucher Pelanggan',
        'ket':
            'Input topup saldo/voucher member, unduh template Excel per Unit/Satuan Kerja',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'TAB',
        'target': 'anggota:tab:4',
        'kunciMenu': 'anggota',
        'ikon': 'account_balance_wallet',
        'warna': '#0D9488',
        'urutan': 19,
        'aktif': true,
      },
      {
        'id': 'sc_tab_piutang_pelanggan',
        'judul': 'Mutasi & Pelunasan Piutang Pelanggan',
        'ket':
            'Rekap piutang pelanggan/member, rincian mutasi piutang, dan entri pelunasan piutang',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'TAB',
        'target': 'anggota:tab:7',
        'kunciMenu': 'anggota',
        'ikon': 'payments',
        'warna': '#E11D48',
        'urutan': 20,
        'aktif': true,
      },
      {
        'id': 'sc_data_pelanggan',
        'judul': 'Data Pelanggan / Member',
        'ket':
            'Kelola data member, cek saldo voucher, limit piutang, dan unit sivitas',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'TAB',
        'target': 'anggota:tab:0',
        'kunciMenu': 'anggota',
        'ikon': 'people',
        'warna': '#7C3AED',
        'urutan': 21,
        'aktif': true,
      },
      {
        'id': 'sc_katalog_semua_laporan',
        'judul': 'Katalog Lengkap Laporan-Laporan',
        'ket':
            'Buka seluruh katalog ~150 laporan penjualan, persediaan, kasir, dan akuntansi',
        'grup': 'Pelanggan & Keuangan',
        'jenis': 'MENU',
        'target': 'laporan',
        'kunciMenu': 'laporan',
        'ikon': 'folder_open',
        'warna': '#D97706',
        'urutan': 22,
        'aktif': true,
      },
    ];

/// Metadata bawaan untuk laporan yang dibuka langsung dari shortcut agar
/// `LaporanDetailScreen` dapat langsung menampilkan filter Tanggal/Produk/PerToko
/// yang akurat tanpa harus menunggu pemuatan seluruh katalog 150 laporan.
Map<String, dynamic> metadataLaporanShortcut(
  String idLaporan, {
  String? judulOverride,
  String? ketOverride,
}) {
  final peta = <String, Map<String, dynamic>>{
    'pnj_per_cabang': {
      'id': 'pnj_per_cabang',
      'judul': 'Penjualan per Cabang',
      'ket': 'Ringkasan cabang & harian: Penjualan, BPP, Laba per toko/cabang.',
      'produk': false,
      'pelanggan': false,
      'perToko': false,
    },
    'pnj_per_barang': {
      'id': 'pnj_per_barang',
      'judul': 'Penjualan per Barang (Kuantitas & Nilai)',
      'ket':
          'Qty terjual, diskon, penjualan kotor/bersih, HPP & laba per barang.',
      'produk': true,
      'pelanggan': false,
      'perToko': true,
    },
    'gud_mutasi_item': {
      'id': 'gud_mutasi_item',
      'judul': 'Mutasi Stok per Item (Ringkasan)',
      'ket':
          'Ringkasan mutasi masuk, retur masuk, keluar/terjual, dan opname per barang.',
      'produk': true,
      'pelanggan': false,
      'perToko': true,
    },
    'mutasi_barang_per_tanggal': {
      'id': 'mutasi_barang_per_tanggal',
      'judul': 'Mutasi Barang per Tanggal',
      'ket':
          'Rincian mutasi masuk, retur, keluar/terjual, dan opname barang dikelompokkan per tanggal.',
      'produk': true,
      'pelanggan': false,
      'perToko': true,
    },
    'stok_per_tanggal': {
      'id': 'stok_per_tanggal',
      'judul': 'Stok Barang per Tanggal',
      'ket':
          'Posisi stok dan nilai persediaan pada tanggal acuan (Sampai Tanggal).',
      'produk': true,
      'pelanggan': false,
      'perToko': true,
    },
    'fin_penerimaan_per_metode': {
      'id': 'fin_penerimaan_per_metode',
      'judul': 'Penerimaan per Kas/Bank (Harian)',
      'ket': 'Rekap penerimaan kas & bank harian per metode pembayaran.',
      'produk': false,
      'pelanggan': false,
      'perToko': true,
    },
    'pos_per_akun_bank': {
      'id': 'pos_per_akun_bank',
      'judul': 'Penjualan per Akun Kas & Bank',
      'ket':
          'Penerimaan penjualan POS dikelompokkan per akun kas/bank penampung.',
      'produk': false,
      'pelanggan': false,
      'perToko': true,
    },
    'laporan_harian_outlet': {
      'id': 'laporan_harian_outlet',
      'judul': 'Laporan Harian Outlet',
      'ket':
          'Rekapitulasi penjualan harian per outlet: nota, omzet kotor, diskon, pajak, tunai & non-tunai.',
      'produk': false,
      'pelanggan': false,
      'perToko': true,
    },
  };
  final dasar = peta[idLaporan] ??
      <String, dynamic>{
        'id': idLaporan,
        'judul': judulOverride ?? idLaporan,
        'ket': ketOverride ?? '',
        'produk': true,
        'pelanggan': false,
        'perToko': true,
      };
  return <String, dynamic>{
    ...dasar,
    if (judulOverride != null && judulOverride.trim().isNotEmpty)
      'judul': judulOverride.trim(),
    if (ketOverride != null && ketOverride.trim().isNotEmpty)
      'ket': ketOverride.trim(),
  };
}

/// Memeriksa apakah pengguna yang sedang login di [Sesi.instance] berhak
/// melihat dan mengakses suatu item shortcut.
///
/// Pemeriksaan ini menghormati:
/// 1. Status `aktif` shortcut.
/// 2. Hak akses menu (`kunciMenu` / `Sesi.instance.bolehMenu`).
/// 3. Hak akses khusus tab (mis. `anggota:tab:4` Topup memerlukan `bolehEntryTopup`
///    atau `bolehKelola` atau `isAdmin`).
/// 4. Hak akses menu varian/role melalui `bolehTampilMenu`.
bool bolehAksesItemShortcut(Map<String, dynamic> item) {
  if (item['aktif'] == false) return false;
  if (Sesi.instance.isAdmin) return true;

  final kunciMenu = '${item['kunciMenu'] ?? ''}'.trim();
  final jenis = '${item['jenis'] ?? 'MENU'}'.trim().toUpperCase();
  final target = '${item['target'] ?? ''}'.trim();

  if (kunciMenu.isNotEmpty) {
    final kunciNormal = kunciMenu == 'rak_produk' || kunciMenu == 'jenis_produk'
        ? 'produk'
        : kunciMenu;
    if (!Sesi.instance.bolehMenu(kunciNormal)) {
      return false;
    }
  }

  if (jenis == 'TAB' || jenis.endsWith('_TAB') || target.contains(':tab:')) {
    if (target.startsWith('produk:')) {
      return bolehTampilMenu(MenuEBisnis.produk);
    }
    if (target.startsWith('anggota:')) {
      if (!bolehTampilMenu(MenuEBisnis.anggota)) return false;
      if (target == 'anggota:tab:4') {
        return Sesi.instance.bolehEntryTopup || Sesi.instance.bolehKelola;
      }
      return true;
    }
    if (target.startsWith('laporantransaksi:') ||
        target.startsWith('laporan_transaksi:')) {
      return bolehTampilMenu(MenuEBisnis.laporanTransaksi);
    }
    if (target.startsWith('stokopname:') || target.startsWith('stok_opname:')) {
      return bolehTampilMenu(MenuEBisnis.stokOpname);
    }
  } else if (jenis == 'LAPORAN') {
    return bolehTampilMenu(MenuEBisnis.laporanLaporan);
  } else if (jenis == 'MENU') {
    final menuTarget = _petakanTargetKeMenu(target);
    if (menuTarget != null) {
      return bolehTampilMenu(menuTarget);
    }
  }
  return true;
}

MenuEBisnis? _petakanTargetKeMenu(String target) {
  switch (target.trim().toLowerCase()) {
    case 'kasir':
      return MenuEBisnis.kasir;
    case 'ringkasan':
      return MenuEBisnis.ringkasan;
    case 'pesanan':
      return MenuEBisnis.pesanan;
    case 'anggota':
      return MenuEBisnis.anggota;
    case 'produk':
      return MenuEBisnis.produk;
    case 'jenis_produk':
    case 'jenisproduk':
      return MenuEBisnis.jenisProduk;
    case 'uom':
    case 'uom_konversi':
      return MenuEBisnis.uom;
    case 'grup_produk':
    case 'grupproduk':
      return MenuEBisnis.grupProduk;
    case 'rak_produk':
    case 'rakproduk':
      return MenuEBisnis.rakProduk;
    case 'stokopname':
    case 'stok_opname':
      return MenuEBisnis.stokOpname;
    case 'kedaluwarsa':
      return MenuEBisnis.kedaluwarsa;
    case 'kulakan':
      return MenuEBisnis.kulakan;
    case 'penyedia':
    case 'supplier':
      return MenuEBisnis.penyedia;
    case 'diskon':
      return MenuEBisnis.diskon;
    case 'pembayaran':
    case 'cara_bayar':
      return MenuEBisnis.caraBayar;
    case 'returpenjualan':
    case 'retur_penjualan':
      return MenuEBisnis.returPenjualan;
    case 'riwayatpenjualan':
    case 'riwayat_penjualan':
      return MenuEBisnis.riwayatPenjualan;
    case 'laporantransaksi':
    case 'laporan_transaksi':
      return MenuEBisnis.laporanTransaksi;
    case 'laporan':
    case 'laporan_laporan':
      return MenuEBisnis.laporanLaporan;
    default:
      return null;
  }
}

IconData ikonShortcutDariNama(String? namaIkon) {
  switch ((namaIkon ?? '').trim().toLowerCase()) {
    case 'storefront':
      return Icons.storefront_outlined;
    case 'shopping_bag':
      return Icons.shopping_bag_outlined;
    case 'swap_horiz':
      return Icons.swap_horiz_rounded;
    case 'calendar_month':
      return Icons.calendar_month_outlined;
    case 'event_available':
      return Icons.event_available_outlined;
    case 'account_balance':
      return Icons.account_balance_outlined;
    case 'assessment':
      return Icons.assessment_outlined;
    case 'payments':
      return Icons.payments_outlined;
    case 'inventory':
      return Icons.inventory_outlined;
    case 'date_range':
      return Icons.date_range_outlined;
    case 'point_of_sale':
      return Icons.point_of_sale_outlined;
    case 'inventory_2':
      return Icons.inventory_2_outlined;
    case 'fact_check':
      return Icons.fact_check_outlined;
    case 'shelves':
      return Icons.shelves;
    case 'local_shipping':
      return Icons.local_shipping_outlined;
    case 'history':
      return Icons.history_rounded;
    case 'badge':
      return Icons.badge_outlined;
    case 'account_balance_wallet':
      return Icons.account_balance_wallet_outlined;
    case 'people':
      return Icons.people_outline;
    case 'folder_open':
      return Icons.folder_open_outlined;
    default:
      return Icons.bolt_rounded;
  }
}

Color warnaShortcutDariHex(String? hex) {
  final bersih = (hex ?? '').trim().replaceAll('#', '');
  if (bersih.length == 6) {
    final nilai = int.tryParse('FF$bersih', radix: 16);
    if (nilai != null) return Color(nilai);
  }
  return AppColors.primary;
}

/// Melakukan navigasi 1-klik dari kartu shortcut ke layar, sub-tab, atau
/// laporan tujuan.
Future<void> bukaShortcutMenu(
  BuildContext context,
  Map<String, dynamic> item,
) async {
  final jenis = '${item['jenis'] ?? 'MENU'}'.trim().toUpperCase();
  final target = '${item['target'] ?? ''}'.trim();
  final judul = '${item['judul'] ?? target}'.trim();
  final ket = '${item['ket'] ?? ''}'.trim();

  if (jenis == 'LAPORAN') {
    final meta = metadataLaporanShortcut(
      target,
      judulOverride: judul,
      ketOverride: ket,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LaporanDetailScreen(
          item: meta,
          autoTampilkan: true,
        ),
      ),
    );
    return;
  }

  if (jenis == 'TAB' || jenis.endsWith('_TAB') || target.contains(':tab:')) {
    final bagian = target.split(':');
    final modul = bagian.isNotEmpty ? bagian[0].trim().toLowerCase() : '';
    final idxTab = bagian.length >= 3 ? (int.tryParse(bagian[2]) ?? 0) : 0;
    if (modul == 'produk') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProdukScreen(tabAwal: idxTab),
        ),
      );
      return;
    }
    if (modul == 'anggota') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AnggotaScreen(tabAwal: idxTab),
        ),
      );
      return;
    }
    if (modul == 'laporantransaksi' || modul == 'laporan_transaksi') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LaporanTransaksiScreen(tabAwal: idxTab),
        ),
      );
      return;
    }
    if (modul == 'stokopname' || modul == 'stok_opname') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StokOpnameScreen(tabAwal: idxTab),
        ),
      );
      return;
    }
  }

  // Default: jenis == 'MENU'
  final layar = _bangunLayarMenuTarget(target);
  if (layar != null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => layar),
    );
  }
}

Widget? _bangunLayarMenuTarget(String target) {
  switch (target.trim().toLowerCase()) {
    case 'kasir':
      return const KasirScreen();
    case 'pesanan':
      return const PesananScreen();
    case 'anggota':
      return const AnggotaScreen();
    case 'produk':
      return const ProdukScreen();
    case 'jenis_produk':
    case 'jenisproduk':
      return const JenisProdukScreen();
    case 'uom':
    case 'uom_konversi':
      return const UomScreen();
    case 'grup_produk':
    case 'grupproduk':
      return const GrupProdukScreen();
    case 'rak_produk':
    case 'rakproduk':
      return const RakProdukScreen();
    case 'stokopname':
    case 'stok_opname':
      return const StokOpnameScreen();
    case 'kedaluwarsa':
      return const KedaluwarsaScreen();
    case 'kulakan':
      return const KulakanScreen();
    case 'penyedia':
    case 'supplier':
      return const SupplierScreen();
    case 'diskon':
      return const DiskonScreen();
    case 'pembayaran':
    case 'cara_bayar':
      return const CaraBayarScreen();
    case 'returpenjualan':
    case 'retur_penjualan':
      return const ReturPenjualanScreen();
    case 'riwayatpenjualan':
    case 'riwayat_penjualan':
      return const RiwayatPenjualanScreen();
    case 'laporantransaksi':
    case 'laporan_transaksi':
      return const LaporanTransaksiScreen();
    case 'laporan':
    case 'laporan_laporan':
      return const LaporanScreen();
    default:
      return null;
  }
}

const String _kunciCacheShortcut = 'master:shortcut_menu_utama_v1';
const String _kunciCacheShortcutAdmin = 'master:shortcut_menu_admin_v1';
const String kTargetRoleShortcutDefault = '__DEFAULT__';

/// Menghasilkan kunci cache SQLite per-role (`Tbmrole.roleId`, ATURAN MUTLAK 4A)
/// agar saat perangkat berpindah akun dengan role berbeda, daftar shortcut tidak
/// saling bocor dari cache pengguna sebelumnya.
String _kunciCacheShortcutAktif() {
  final rid = Sesi.instance.userRoleId.trim();
  return rid.isEmpty
      ? _kunciCacheShortcut
      : 'master:shortcut_menu_utama_v2:$rid';
}

String _kunciCacheShortcutAdminUntukRole(String targetRoleId) {
  final norm = targetRoleId.trim().isEmpty
      ? kTargetRoleShortcutDefault
      : targetRoleId.trim();
  return norm == kTargetRoleShortcutDefault
      ? _kunciCacheShortcutAdmin
      : 'master:shortcut_menu_admin_v2:$norm';
}
const String kPesanShortcutBelumTersimpan =
    'Perubahan belum tersimpan. Pastikan koneksi tersedia, lalu coba simpan kembali.';

/// Menyamakan nama isian layanan AIS dengan nama yang dipakai layar Pintasan.
/// Layanan mengirim `deskripsi`/`aksesKunci`, sedangkan layar memakai `ket`/
/// `kunciMenu`; normalisasi ini mencegah informasi hilang saat dibuka ulang.
Map<String, dynamic> normalisasiShortcutDariLayanan(Map<String, dynamic> raw) =>
    <String, dynamic>{
      ...raw,
      'ket': raw['ket'] ?? raw['deskripsi'] ?? '',
      'kunciMenu': raw['kunciMenu'] ?? raw['aksesKunci'] ?? '',
    };

/// Menyusun nama properti yang diterima endpoint penyimpanan shortcut.
List<Map<String, dynamic>> siapkanShortcutUntukDisimpan(
  List<Map<String, dynamic>> daftar,
) =>
    daftar.map((item) {
      final hasil = Map<String, dynamic>.from(item);
      hasil['deskripsi'] = item['ket'] ?? item['deskripsi'] ?? '';
      hasil['aksesKunci'] = item['kunciMenu'] ?? item['aksesKunci'] ?? '';
      hasil.remove('ket');
      hasil.remove('kunciMenu');
      return hasil;
    }).toList();

List<Map<String, dynamic>> _daftarShortcutDariRespons(dynamic raw) =>
    (raw is List ? raw : const <dynamic>[])
        .whereType<Map>()
        .map(
            (e) => normalisasiShortcutDariLayanan(Map<String, dynamic>.from(e)))
        .toList();

/// Menjalankan pengaturan bersama hanya setelah server mengakui perubahan.
/// Konfigurasi global tidak masuk antrean offline: pengiriman ulang salinan
/// usang berisiko menimpa perubahan administrator lain. Callback cache hanya
/// dipanggil sesudah server memberi status sukses dan daftar kanonis.
Future<Map<String, dynamic>> jalankanAksiShortcutOnlineOnly({
  required Future<Map<String, dynamic>> Function(String, Map<String, dynamic>?)
      kirim,
  required String aksi,
  required Map<String, dynamic> payload,
  required Future<void> Function(Map<String, dynamic>) setelahDikonfirmasi,
}) async {
  final respons = await kirim(aksi, payload);
  final status = respons['status'];
  if (status != '00' && status != 'success') {
    throw StateError('Server belum mengonfirmasi perubahan shortcut.');
  }
  if (_daftarShortcutDariRespons(respons['semuaShortcut']).isEmpty) {
    throw StateError('Server belum mengembalikan daftar shortcut terbaru.');
  }
  await setelahDikonfirmasi(respons);
  return respons;
}

/// Tab pertama pada `RingkasanScreen` ("Menu Utama Shortcut") yang menampilkan
/// pintasan cepat ke menu, sub-tab, dan laporan paling vital sesuai hak akses
/// pengguna yang sedang login.
class RingkasanTabShortcut extends StatefulWidget {
  const RingkasanTabShortcut({super.key});

  @override
  State<RingkasanTabShortcut> createState() => _RingkasanTabShortcutState();
}

class _RingkasanTabShortcutState extends State<RingkasanTabShortcut>
    with JejakGalat {
  final _controllerCari = TextEditingController();
  String _kataKunci = '';
  String _grupTerpilih = 'SEMUA';
  bool _memuat = false;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _controllerCari.addListener(() {
      if (mounted) {
        setStateIfMounted(() => _kataKunci = _controllerCari.text.trim());
      }
    });
    _siapkanDataAwal();
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    super.dispose();
  }

  Future<void> _siapkanDataAwal() async {
    // 1. Tampilkan segera dari Sesi atau daftar default lokal agar 0ms tanpa tunggu
    if (Sesi.instance.shortcutMenu.isNotEmpty) {
      _terapkanDaftar(Sesi.instance.shortcutMenu);
    } else {
      try {
        final rawLokal = await CoreDb.instance
            .ambilCacheReferensi(_kunciCacheShortcutAktif());
        if (rawLokal != null && rawLokal.isNotEmpty) {
          final decoded = jsonDecode(rawLokal);
          if (decoded is List && decoded.isNotEmpty) {
            _terapkanDaftar(
              decoded
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList(),
            );
          }
        }
      } catch (_) {}
      if (_daftar.isEmpty) {
        _terapkanDaftar(buatDaftarShortcutDefaultLokal());
      }
    }
    // 2. Segarkan dari server di latar belakang bila online
    await _muatDariServer();
  }

  void _terapkanDaftar(List<Map<String, dynamic>> sumber) {
    final dinormalisasi = sumber.map(normalisasiShortcutDariLayanan).toList();
    final tersaring = dinormalisasi.where(bolehAksesItemShortcut).toList()
      ..sort((a, b) => ((a['urutan'] as num?)?.toInt() ?? 999)
          .compareTo((b['urutan'] as num?)?.toInt() ?? 999));
    if (!mounted) return;
    setStateIfMounted(() {
      _daftar = tersaring;
    });
  }

  Future<void> _muatDariServer() async {
    if (!mounted) return;
    setStateIfMounted(() => _memuat = true);
    try {
      final res = await ApiClient.instance.aksi('shortcut_menu_list');
      final dataServer = _daftarShortcutDariRespons(res['data']);
      final roleIdRes = '${res['userRoleId'] ?? ''}'.trim();
      final roleNameRes = '${res['userRoleName'] ?? ''}'.trim();
      if (roleIdRes.isNotEmpty) {
        Sesi.instance.userRoleId = roleIdRes;
      }
      if (roleNameRes.isNotEmpty) {
        Sesi.instance.userRoleName = roleNameRes;
      }
      if (res.containsKey('bolehKelolaShortcut')) {
        Sesi.instance.bolehKelolaShortcut =
            res['bolehKelolaShortcut'] == true ||
                Sesi.instance.isAdmin ||
                Sesi.instance.supervisorPedagang;
      }
      if (dataServer.isNotEmpty) {
        Sesi.instance.shortcutMenu = dataServer;
        try {
          await CoreDb.instance.simpanCacheReferensi(
            _kunciCacheShortcutAktif(),
            jsonEncode(dataServer),
          );
        } catch (_) {}
        _terapkanDaftar(dataServer);
      }
    } catch (_) {
      // Bila server belum di-update atau sedang offline, daftar default lokal
      // yang sudah tersaring sesuai hak akses tetap tampil dengan aman.
    } finally {
      if (mounted) {
        setStateIfMounted(() => _memuat = false);
      }
    }
  }

  Future<void> _bukaKelolaShortcut() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const KelolaShortcutScreen(),
      ),
    );
    if (mounted) {
      await _siapkanDataAwal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupTersedia = <String>['SEMUA'];
    for (final item in _daftar) {
      final g = '${item['grup'] ?? 'Lainnya'}'.trim();
      if (g.isNotEmpty && !grupTersedia.contains(g)) {
        grupTersedia.add(g);
      }
    }
    if (!grupTersedia.contains(_grupTerpilih)) {
      _grupTerpilih = 'SEMUA';
    }

    final q = _kataKunci.toLowerCase();
    final itemTampil = _daftar.where((item) {
      final g = '${item['grup'] ?? 'Lainnya'}'.trim();
      if (_grupTerpilih != 'SEMUA' && g != _grupTerpilih) return false;
      if (q.isEmpty) return true;
      final judul = '${item['judul'] ?? ''}'.toLowerCase();
      final ket = '${item['ket'] ?? ''}'.toLowerCase();
      final grup = g.toLowerCase();
      return judul.contains(q) || ket.contains(q) || grup.contains(q);
    }).toList();

    // Kelompokkan per grup untuk tampilan terstruktur
    final perGrup = <String, List<Map<String, dynamic>>>{};
    for (final item in itemTampil) {
      final g = '${item['grup'] ?? 'Lainnya'}'.trim();
      perGrup.putIfAbsent(g, () => []).add(item);
    }

    final bolehKelola = Sesi.instance.isAdmin ||
        Sesi.instance.bolehKelola ||
        Sesi.instance.bolehKelolaShortcut;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Banner Header Pintasan Cepat
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.10),
                  AppColors.teal.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Menu Utama Shortcut (Pintasan Cepat & Laporan Vital)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Akses langsung 1-klik ke laporan vital harian, mutasi stok, stok opname per rak, dan menu operasional sesuai hak akses Anda.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AksiToolbarMenu(
                      tooltip: 'Aksi Menu Utama Shortcut',
                      aksi: [
                        AksiBaris(
                          ikon: Icons.refresh,
                          label: 'Muat Ulang',
                          onTap: _memuat ? null : _muatDariServer,
                        ),
                        if (bolehKelola)
                          AksiBaris(
                            ikon: Icons.tune_outlined,
                            label: 'Kelola Shortcut',
                            onTap: _bukaKelolaShortcut,
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Baris Pencarian & Chip Filter Kategori
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controllerCari,
                  decoration: InputDecoration(
                    hintText:
                        'Cari menu atau laporan di shortcut (mis. Penjualan Cabang, Mutasi Tanggal, Kas Bank, Outlet, Rak)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _kataKunci.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _controllerCari.clear(),
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.cardBgOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final g in grupTersedia)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g == 'SEMUA'
                          ? 'Semua Kategori (${_daftar.length})'
                          : g),
                      selected: _grupTerpilih == g,
                      onSelected: (_) => setState(() => _grupTerpilih = g),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (itemTampil.isEmpty)
            AppSectionCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 44,
                      color: AppColors.textSecondaryOf(context),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tidak ada shortcut yang cocok dengan pencarian Anda.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final entry in perGrup.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.primary),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${entry.value.length} pintasan',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final lebar = constraints.maxWidth;
                  final kolom = lebar >= 1150
                      ? 3
                      : lebar >= 700
                          ? 2
                          : 1;
                  const spasi = 12.0;
                  final lebarKartu = (lebar - (spasi * (kolom - 1))) / kolom;
                  return Wrap(
                    spacing: spasi,
                    runSpacing: spasi,
                    children: [
                      for (final sc in entry.value)
                        SizedBox(
                          width: lebarKartu,
                          child: _KartuShortcutItem(
                            item: sc,
                            onTap: () => bukaShortcutMenu(context, sc),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
            ],
        ],
      ),
    );
  }
}

class _KartuShortcutItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  const _KartuShortcutItem({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final judul = '${item['judul'] ?? ''}'.trim();
    final ket = '${item['ket'] ?? ''}'.trim();
    final jenis = '${item['jenis'] ?? 'MENU'}'.trim().toUpperCase();
    final warna = warnaShortcutDariHex(item['warna'] as String?);
    final ikon = ikonShortcutDariNama(item['ikon'] as String?);

    final labelJenis = switch (jenis) {
      'LAPORAN' => 'Laporan Siap Pakai',
      'TAB' => 'Tab / Sub-Menu',
      _ => 'Menu Utama',
    };

    return Material(
      color: AppColors.cardBgOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: warna.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(ikon, color: warna, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            judul,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 15,
                          color: warna,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ket,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: warna.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        labelJenis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: warna,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Layar Admin untuk mengelola "Menu Utama Shortcut" (diakses dari grup
/// sidebar `SISTEM > Kelola Shortcut` maupun tombol `Kelola Shortcut` di
/// tab `Menu Utama Shortcut`).
class KelolaShortcutScreen extends StatefulWidget {
  const KelolaShortcutScreen({super.key});

  @override
  State<KelolaShortcutScreen> createState() => _KelolaShortcutScreenState();
}

class _KelolaShortcutScreenState extends State<KelolaShortcutScreen>
    with JejakGalat {
  bool _memuat = true;
  bool _menyimpan = false;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  String _targetRoleId = kTargetRoleShortcutDefault;
  bool _punyaKonfigurasiKhusus = true;
  bool _menggunakanFallbackDefault = false;
  List<Map<String, dynamic>> _daftarRole = const [
    {
      'roleId': kTargetRoleShortcutDefault,
      'roleName': 'Default Global (Semua Role Tanpa Pengaturan Khusus)',
      'punyaKonfigurasiKhusus': true,
    },
  ];

  static const List<Map<String, String>> _pilihanTargetSiapPakai = [
    {
      'label': 'Laporan: Penjualan per Cabang (pnj_per_cabang)',
      'jenis': 'LAPORAN',
      'target': 'pnj_per_cabang',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'storefront',
      'warna': '#2563EB',
    },
    {
      'label': 'Laporan: Penjualan per Barang (pnj_per_barang)',
      'jenis': 'LAPORAN',
      'target': 'pnj_per_barang',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'shopping_bag',
      'warna': '#0D9488',
    },
    {
      'label': 'Tab: Mutasi Barang & Analisis Cerdas (produk:tab:1)',
      'jenis': 'TAB',
      'target': 'produk:tab:1',
      'kunciMenu': 'produk',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'swap_horiz',
      'warna': '#7C3AED',
    },
    {
      'label': 'Tab: Mutasi Barang per Tanggal (produk:tab:2)',
      'jenis': 'TAB',
      'target': 'produk:tab:2',
      'kunciMenu': 'produk',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'calendar_month',
      'warna': '#EA580C',
    },
    {
      'label':
          'Laporan: Mutasi Barang per Tanggal Cetak/Excel (mutasi_barang_per_tanggal)',
      'jenis': 'LAPORAN',
      'target': 'mutasi_barang_per_tanggal',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'date_range',
      'warna': '#9333EA',
    },
    {
      'label': 'Laporan: Stok Barang per Tanggal (stok_per_tanggal)',
      'jenis': 'LAPORAN',
      'target': 'stok_per_tanggal',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'event_available',
      'warna': '#0284C7',
    },
    {
      'label':
          'Laporan: Penerimaan Kas per Bank Harian (fin_penerimaan_per_metode)',
      'jenis': 'LAPORAN',
      'target': 'fin_penerimaan_per_metode',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'account_balance',
      'warna': '#16A34A',
    },
    {
      'label': 'Laporan: Penjualan per Akun Kas & Bank (pos_per_akun_bank)',
      'jenis': 'LAPORAN',
      'target': 'pos_per_akun_bank',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'payments',
      'warna': '#059669',
    },
    {
      'label': 'Laporan: Laporan Harian Outlet (laporan_harian_outlet)',
      'jenis': 'LAPORAN',
      'target': 'laporan_harian_outlet',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'assessment',
      'warna': '#D97706',
    },
    {
      'label': 'Laporan: Ringkasan Mutasi Stok per Item (gud_mutasi_item)',
      'jenis': 'LAPORAN',
      'target': 'gud_mutasi_item',
      'kunciMenu': 'laporan',
      'grup': 'Laporan Vital & Harian',
      'ikon': 'inventory',
      'warna': '#4F46E5',
    },
    {
      'label': 'Menu: Kasir / POS (kasir)',
      'jenis': 'MENU',
      'target': 'kasir',
      'kunciMenu': 'kasir',
      'grup': 'Operasional & Persediaan',
      'ikon': 'point_of_sale',
      'warna': '#15803D',
    },
    {
      'label': 'Menu: Stok Opname per Rak (stokopname)',
      'jenis': 'MENU',
      'target': 'stokopname',
      'kunciMenu': 'stokopname',
      'grup': 'Operasional & Persediaan',
      'ikon': 'fact_check',
      'warna': '#0D9488',
    },
    {
      'label': 'Menu: Manajemen Rak Produk (rak_produk)',
      'jenis': 'MENU',
      'target': 'rak_produk',
      'kunciMenu': 'produk',
      'grup': 'Operasional & Persediaan',
      'ikon': 'shelves',
      'warna': '#7C3AED',
    },
    {
      'label': 'Menu: Kulakan / Pembelian Barang (kulakan)',
      'jenis': 'MENU',
      'target': 'kulakan',
      'kunciMenu': 'kulakan',
      'grup': 'Operasional & Persediaan',
      'ikon': 'local_shipping',
      'warna': '#EA580C',
    },
    {
      'label': 'Menu: Riwayat Penjualan & Detail Nota (riwayatpenjualan)',
      'jenis': 'MENU',
      'target': 'riwayatpenjualan',
      'kunciMenu': 'riwayatpenjualan',
      'grup': 'Operasional & Persediaan',
      'ikon': 'history',
      'warna': '#0284C7',
    },
    {
      'label': 'Tab: Laporan Transaksi Per Kasir (laporantransaksi:tab:2)',
      'jenis': 'TAB',
      'target': 'laporantransaksi:tab:2',
      'kunciMenu': 'laporantransaksi',
      'grup': 'Pelanggan & Keuangan',
      'ikon': 'badge',
      'warna': '#2563EB',
    },
    {
      'label': 'Tab: Penerimaan Per Kasir (laporantransaksi:tab:5)',
      'jenis': 'TAB',
      'target': 'laporantransaksi:tab:5',
      'kunciMenu': 'laporantransaksi',
      'grup': 'Pelanggan & Keuangan',
      'ikon': 'point_of_sale',
      'warna': '#16A34A',
    },
    {
      'label': 'Tab: Topup Saldo & Voucher Member (anggota:tab:4)',
      'jenis': 'TAB',
      'target': 'anggota:tab:4',
      'kunciMenu': 'anggota',
      'grup': 'Pelanggan & Keuangan',
      'ikon': 'account_balance_wallet',
      'warna': '#0D9488',
    },
    {
      'label': 'Tab: Data Member / Pelanggan (anggota:tab:0)',
      'jenis': 'TAB',
      'target': 'anggota:tab:0',
      'kunciMenu': 'anggota',
      'grup': 'Pelanggan & Keuangan',
      'ikon': 'people',
      'warna': '#7C3AED',
    },
    {
      'label': 'Menu: Katalog Lengkap Laporan-Laporan (laporan)',
      'jenis': 'MENU',
      'target': 'laporan',
      'kunciMenu': 'laporan',
      'grup': 'Pelanggan & Keuangan',
      'ikon': 'folder_open',
      'warna': '#D97706',
    },
  ];

  @override
  void initState() {
    super.initState();
    _muatDaftar();
  }

  Future<void> _muatDaftar({String? targetRoleBaru}) async {
    final roleDiminta = targetRoleBaru?.trim();
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
      if (roleDiminta != null && roleDiminta.isNotEmpty) {
        _targetRoleId = roleDiminta;
      }
    });
    final kunciAdminLokal = _kunciCacheShortcutAdminUntukRole(_targetRoleId);
    // Cache admin dipisahkan per targetRoleId dari daftar pengguna yang sudah disaring haknya.
    try {
      final rawLokal =
          await CoreDb.instance.ambilCacheReferensi(kunciAdminLokal);
      if (rawLokal != null && rawLokal.isNotEmpty) {
        final decoded = jsonDecode(rawLokal);
        if (decoded is List && decoded.isNotEmpty) {
          setStateIfMounted(() {
            _daftar = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          });
        }
      }
    } catch (_) {}

    try {
      final payloadList = <String, dynamic>{
        if (roleDiminta != null && roleDiminta.isNotEmpty)
          'targetRoleId': roleDiminta,
      };
      final res = await ApiClient.instance.aksi(
        'shortcut_menu_list',
        payloadList.isEmpty ? null : payloadList,
      );
      final roleEfektif = '${res['targetRoleId'] ?? _targetRoleId}'.trim();
      final daftarRoleRes = (res['daftarRole'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final sumber = _daftarShortcutDariRespons(res['semuaShortcut']);
      if (sumber.isNotEmpty) {
        sumber.sort((a, b) => ((a['urutan'] as num?)?.toInt() ?? 999)
            .compareTo((b['urutan'] as num?)?.toInt() ?? 999));
        setStateIfMounted(() {
          _targetRoleId = roleEfektif.isEmpty
              ? kTargetRoleShortcutDefault
              : roleEfektif;
          _punyaKonfigurasiKhusus = res['punyaKonfigurasiKhusus'] == true;
          _menggunakanFallbackDefault =
              res['menggunakanFallbackDefault'] == true;
          if (daftarRoleRes != null && daftarRoleRes.isNotEmpty) {
            _daftarRole = daftarRoleRes;
          }
          _daftar = sumber;
        });
        await CoreDb.instance.simpanCacheReferensi(
            _kunciCacheShortcutAdminUntukRole(_targetRoleId),
            jsonEncode(sumber));
      } else if (_daftar.isEmpty) {
        setStateIfMounted(() => _daftar = buatDaftarShortcutDefaultLokal());
      }
    } catch (_) {
      if (_daftar.isEmpty) {
        setStateIfMounted(() => _daftar = buatDaftarShortcutDefaultLokal());
      }
      setStateIfMounted(() => _pesanError =
          'Data terakhir ditampilkan. Hubungkan perangkat ke jaringan untuk memuat pengaturan terbaru.');
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  void _urutkanUlangNomor() {
    for (var i = 0; i < _daftar.length; i++) {
      _daftar[i]['urutan'] = i + 1;
    }
  }

  Future<void> _simpanKeServer() async {
    _urutkanUlangNomor();
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      // Pengaturan ini dibagi antar admin; jangan antrekan daftar lama saat
      // offline karena replay dapat menimpa perubahan admin lain.
      final res = await jalankanAksiShortcutOnlineOnly(
        aksi: 'shortcut_menu_simpan',
        payload: {
          'targetRoleId': _targetRoleId,
          'items': siapkanShortcutUntukDisimpan(_daftar),
        },
        kirim: ApiClient.instance.aksi,
        setelahDikonfirmasi: (konfirmasi) async {
          final admin = _daftarShortcutDariRespons(konfirmasi['semuaShortcut']);
          final daftarAktif = _daftarShortcutDariRespons(konfirmasi['data']);
          final daftarRoleRes = (konfirmasi['daftarRole'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setStateIfMounted(() {
            _daftar = admin;
            _punyaKonfigurasiKhusus = true;
            _menggunakanFallbackDefault = false;
            if (daftarRoleRes != null && daftarRoleRes.isNotEmpty) {
              _daftarRole = daftarRoleRes;
            }
          });
          Sesi.instance.shortcutMenu = daftarAktif;
          await CoreDb.instance.simpanCacheReferensi(
              _kunciCacheShortcutAdminUntukRole(_targetRoleId),
              jsonEncode(admin));
          await CoreDb.instance.simpanCacheReferensi(
              _kunciCacheShortcutAktif(), jsonEncode(daftarAktif));
        },
      );
      final dariServer = _daftarShortcutDariRespons(res['semuaShortcut']);
      setStateIfMounted(() => _daftar = dariServer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konfigurasi Menu Utama Shortcut berhasil disimpan.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$kPesanShortcutBelumTersimpan ($e)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() {
          _menyimpan = false;
          _memuat = false;
        });
      }
    }
  }

  Future<void> _resetKeDefault() async {
    final modeDefaultGlobal = _targetRoleId == kTargetRoleShortcutDefault;
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(modeDefaultGlobal
            ? 'Reset Shortcut Default ke Bawaan?'
            : 'Kembalikan Role Ini ke Shortcut Default?'),
        content: Text(
          modeDefaultGlobal
              ? 'Daftar shortcut Default Global akan dikembalikan ke pintasan vital bawaan sistem (termasuk 5 laporan utama). Lanjutkan?'
              : 'Pengaturan khusus pada jenis pengguna ini akan dihapus sehingga kembali mengikuti daftar Shortcut Default Global. Lanjutkan?',
        ),
        actions: [
          AksiBarisMenu(aksi: [
            AksiBaris(
                ikon: Icons.close,
                label: 'Batal',
                onTap: () => Navigator.of(ctx).pop(false)),
            AksiBaris(
                ikon: Icons.restore,
                label: 'Ya, Reset',
                onTap: () => Navigator.of(ctx).pop(true)),
          ]),
        ],
      ),
    );
    if (konfirmasi != true) return;

    setStateIfMounted(() => _menyimpan = true);
    try {
      final res = await jalankanAksiShortcutOnlineOnly(
        aksi: 'shortcut_menu_reset',
        payload: {'targetRoleId': _targetRoleId},
        kirim: ApiClient.instance.aksi,
        setelahDikonfirmasi: (konfirmasi) async {
          final semua = _daftarShortcutDariRespons(konfirmasi['semuaShortcut']);
          final aktif = _daftarShortcutDariRespons(konfirmasi['data']);
          final daftarRoleRes = (konfirmasi['daftarRole'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          setStateIfMounted(() {
            _daftar = semua;
            _punyaKonfigurasiKhusus =
                konfirmasi['punyaKonfigurasiKhusus'] == true;
            _menggunakanFallbackDefault =
                konfirmasi['menggunakanFallbackDefault'] == true;
            if (daftarRoleRes != null && daftarRoleRes.isNotEmpty) {
              _daftarRole = daftarRoleRes;
            }
          });
          Sesi.instance.shortcutMenu = aktif;
          await CoreDb.instance.simpanCacheReferensi(
              _kunciCacheShortcutAdminUntukRole(_targetRoleId),
              jsonEncode(semua));
          await CoreDb.instance.simpanCacheReferensi(
              _kunciCacheShortcutAktif(), jsonEncode(aktif));
        },
      );
      final semua = _daftarShortcutDariRespons(res['semuaShortcut']);
      setStateIfMounted(() => _daftar = semua);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Shortcut berhasil dikembalikan ke pengaturan default.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Reset belum berhasil. Periksa koneksi, lalu coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _menyimpan = false);
      }
    }
  }

  Future<void> _tampilkanDialogForm({int? indexEdit}) async {
    final modeEdit = indexEdit != null;
    final awal = modeEdit
        ? Map<String, dynamic>.from(_daftar[indexEdit])
        : <String, dynamic>{
            'id': 'sc_custom_${DateTime.now().millisecondsSinceEpoch}',
            'judul': '',
            'ket': '',
            'grup': 'Laporan Vital & Harian',
            'jenis': 'LAPORAN',
            'target': 'pnj_per_cabang',
            'kunciMenu': 'laporan',
            'ikon': 'assessment',
            'warna': '#2563EB',
            'urutan': _daftar.length + 1,
            'aktif': true,
          };

    final ctrlJudul = TextEditingController(text: '${awal['judul'] ?? ''}');
    final ctrlKet = TextEditingController(text: '${awal['ket'] ?? ''}');
    final ctrlGrup = TextEditingController(
        text: '${awal['grup'] ?? 'Laporan Vital & Harian'}');
    final ctrlTarget = TextEditingController(text: '${awal['target'] ?? ''}');
    final ctrlKunciMenu =
        TextEditingController(text: '${awal['kunciMenu'] ?? 'laporan'}');
    String jenis = '${awal['jenis'] ?? 'LAPORAN'}'.toUpperCase();
    String ikon = '${awal['ikon'] ?? 'assessment'}';
    String warna = '${awal['warna'] ?? '#2563EB'}';
    bool aktif = awal['aktif'] != false;

    final disimpan = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(modeEdit ? 'Ubah Shortcut' : 'Tambah Shortcut Baru'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Pilih Preset Menu / Laporan Cepat (Opsional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (var i = 0; i < _pilihanTargetSiapPakai.length; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text(
                            _pilihanTargetSiapPakai[i]['label']!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (idx) {
                      if (idx == null) return;
                      final p = _pilihanTargetSiapPakai[idx];
                      setDialogState(() {
                        jenis = p['jenis']!;
                        ctrlTarget.text = p['target']!;
                        ctrlKunciMenu.text = p['kunciMenu']!;
                        ctrlGrup.text = p['grup']!;
                        ikon = p['ikon']!;
                        warna = p['warna']!;
                        if (ctrlJudul.text.trim().isEmpty) {
                          ctrlJudul.text = p['label']!
                              .replaceFirst(
                                  RegExp(r'^(Laporan|Tab|Menu):\s*'), '')
                              .replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrlJudul,
                    decoration: const InputDecoration(
                      labelText: 'Judul Shortcut *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrlKet,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan Singkat',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value:
                              const ['LAPORAN', 'TAB', 'MENU'].contains(jenis)
                                  ? jenis
                                  : 'MENU',
                          decoration: const InputDecoration(
                            labelText: 'Jenis Target',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'LAPORAN',
                                child: Text('Laporan Katalog')),
                            DropdownMenuItem(
                                value: 'TAB', child: Text('Sub-Tab Layar')),
                            DropdownMenuItem(
                                value: 'MENU', child: Text('Menu Utama')),
                          ],
                          onChanged: (v) {
                            if (v != null) setDialogState(() => jenis = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: ctrlGrup,
                          decoration: const InputDecoration(
                            labelText: 'Grup / Kategori Shortcut',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: ctrlTarget,
                          decoration: const InputDecoration(
                            labelText:
                                'Kode Target (mis. pnj_per_cabang / produk:tab:2)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: ctrlKunciMenu,
                          decoration: const InputDecoration(
                            labelText:
                                'Kunci Hak Akses (mis. laporan / produk)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tampilkan Shortcut Ini (Aktif)'),
                    value: aktif,
                    onChanged: (v) => setDialogState(() => aktif = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            AksiBarisMenu(aksi: [
              AksiBaris(
                  ikon: Icons.close,
                  label: 'Batal',
                  onTap: () => Navigator.of(dialogCtx).pop(false)),
              AksiBaris(
                  ikon: Icons.check,
                  label: 'Terapkan',
                  onTap: () {
                    if (ctrlJudul.text.trim().isEmpty ||
                        ctrlTarget.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.of(dialogCtx).pop(true);
                  }),
            ]),
          ],
        ),
      ),
    );

    if (disimpan == true) {
      final itemBaru = <String, dynamic>{
        ...awal,
        'judul': ctrlJudul.text.trim(),
        'ket': ctrlKet.text.trim(),
        'grup': ctrlGrup.text.trim().isEmpty
            ? 'Laporan Vital & Harian'
            : ctrlGrup.text.trim(),
        'jenis': jenis,
        'target': ctrlTarget.text.trim(),
        'kunciMenu': ctrlKunciMenu.text.trim(),
        'ikon': ikon,
        'warna': warna,
        'aktif': aktif,
      };
      setStateIfMounted(() {
        if (modeEdit) {
          _daftar[indexEdit] = itemBaru;
        } else {
          _daftar.add(itemBaru);
        }
      });
      await _simpanKeServer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kelolaShortcut,
      judul: 'Kelola Shortcut Menu Utama',
      subjudul:
          'Atur pintasan menu, sub-tab, dan laporan paling vital yang tampil di Menu Utama Shortcut',
      aksiHeader: AksiToolbarMenu(
        tooltip: 'Aksi Kelola Shortcut',
        aksi: [
          AksiBaris(
              ikon: Icons.add_rounded,
              label: 'Tambah Shortcut',
              onTap: _menyimpan ? null : () => _tampilkanDialogForm()),
          AksiBaris(
              ikon: Icons.save_outlined,
              label: 'Simpan Perubahan',
              onTap: _menyimpan ? null : _simpanKeServer),
          AksiBaris(
              ikon: Icons.restore_rounded,
              label: 'Reset Default',
              onTap: _menyimpan ? null : _resetKeDefault,
              merusak: true),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                      builder: (_) => const RingkasanScreen()),
                ),
                child: const Text('Dashboard'),
              ),
              const Icon(Icons.chevron_right, size: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                      builder: (_) => const KelolaShortcutScreen()),
                ),
                child: const Text('Kelola Shortcut'),
              ),
            ],
          ),
          if (_pesanError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _pesanError!,
                style: const TextStyle(color: AppColors.danger),
              ),
            ),
          AppSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Shortcut dapat diatur berbeda-beda untuk setiap Jenis Pengguna (Role / Tbmrole). Bila suatu Role belum diatur secara khusus, maka otomatis mengikuti daftar Shortcut Default Global.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 380,
                      child: DropdownButtonFormField<String>(
                        value: _daftarRole.any(
                                (r) => '${r['roleId']}' == _targetRoleId)
                            ? _targetRoleId
                            : (_daftarRole.isNotEmpty
                                ? '${_daftarRole.first['roleId']}'
                                : kTargetRoleShortcutDefault),
                        decoration: const InputDecoration(
                          labelText: 'Pilih Jenis Pengguna (Role)',
                          prefixIcon: Icon(Icons.admin_panel_settings_outlined,
                              size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _daftarRole.map((r) {
                          final rid =
                              '${r['roleId'] ?? kTargetRoleShortcutDefault}';
                          final rname = '${r['roleName'] ?? rid}';
                          final kustom = rid != kTargetRoleShortcutDefault &&
                              r['punyaKonfigurasiKhusus'] == true;
                          return DropdownMenuItem<String>(
                            value: rid,
                            child: Text(
                              kustom ? '$rname ★ Kustom' : rname,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (_memuat || _menyimpan)
                            ? null
                            : (val) {
                                if (val != null && val != _targetRoleId) {
                                  _muatDaftar(targetRoleBaru: val);
                                }
                              },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(
                          _targetRoleId == kTargetRoleShortcutDefault
                              ? AppColors.primary
                              : (_punyaKonfigurasiKhusus
                                  ? AppColors.success
                                  : AppColors.warning),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _targetRoleId == kTargetRoleShortcutDefault
                            ? 'Pengaturan Default Global'
                            : (_punyaKonfigurasiKhusus
                                ? 'Pengaturan Khusus Role Ini'
                                : (_menggunakanFallbackDefault
                                    ? 'Belum Diatur Khusus (Mengikuti Default)'
                                    : 'Mengikuti Default')),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _targetRoleId == kTargetRoleShortcutDefault
                              ? AppColors.primary
                              : (_punyaKonfigurasiKhusus
                                  ? AppColors.success
                                  : AppColors.warning),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                if (_daftar.isEmpty && _memuat)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _daftar.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final item = _daftar[idx];
                      final aktif = item['aktif'] != false;
                      final warna =
                          warnaShortcutDariHex(item['warna'] as String?);
                      final ikon =
                          ikonShortcutDariNama(item['ikon'] as String?);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: warna.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(ikon, color: warna, size: 20),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${idx + 1}. ${item['judul'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration:
                                      aktif ? null : TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.latarLembut(warna),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  '${item['grup'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: warna),
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${item['ket'] ?? ''}  •  [${item['jenis']}: ${item['target']} | Akses: ${item['kunciMenu']}]',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: AksiBarisMenu(
                          aksi: [
                            AksiBaris(
                              ikon: aktif
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              label: aktif ? 'Nonaktifkan' : 'Aktifkan',
                              onTap: () =>
                                  setState(() => item['aktif'] = !aktif),
                            ),
                            AksiBaris(
                              ikon: Icons.arrow_upward,
                              label: 'Geser Naik',
                              onTap: idx == 0
                                  ? null
                                  : () => setState(() {
                                        final tmp = _daftar.removeAt(idx);
                                        _daftar.insert(idx - 1, tmp);
                                        _urutkanUlangNomor();
                                      }),
                            ),
                            AksiBaris(
                              ikon: Icons.arrow_downward,
                              label: 'Geser Turun',
                              onTap: idx >= _daftar.length - 1
                                  ? null
                                  : () => setState(() {
                                        final tmp = _daftar.removeAt(idx);
                                        _daftar.insert(idx + 1, tmp);
                                        _urutkanUlangNomor();
                                      }),
                            ),
                            AksiBaris(
                              ikon: Icons.edit_outlined,
                              label: 'Ubah',
                              onTap: () => _tampilkanDialogForm(indexEdit: idx),
                            ),
                            AksiBaris(
                              ikon: Icons.delete_outline,
                              label: 'Hapus',
                              merusak: true,
                              onTap: () => setState(() {
                                _daftar.removeAt(idx);
                                _urutkanUlangNomor();
                              }),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
