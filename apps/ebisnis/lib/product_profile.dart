import 'package:flutter/widgets.dart';

import 'app_variant.dart';
import 'screens/kasir_screen.dart';
import 'screens/inventory_sales/beranda_is_screen.dart';
import 'screens/apotik/beranda_apotik_screen.dart';
import 'sesi.dart';

/// Grup fitur yang bisa diaktifkan per produk -- gerbang level VARIAN (bukan
/// pengganti hak akses per-role: server tetap satu-satunya sumber kebenaran
/// izin lewat `Sesi.aksesMenu`/`aktorInventorySales`; grup fitur hanya
/// menentukan permukaan mana yang DIRAKIT ke dalam binary/menu varian ini).
class FiturGrup {
  FiturGrup._();

  static const pos = 'pos';
  static const inventorySales = 'inventory_sales';
  static const apotik = 'apotik';
}

/// <h3>Profil produk -- SATU deskriptor per varian build (PERINTAH_MASTER §4.1).</h3>
///
/// Menggantikan pola "if (AppVariant.isX)" yang tersebar: layar/menu bertanya ke
/// profil ini ([aktif]), bukan mengecek varian sendiri-sendiri. Konstanta
/// branding compile-time tetap hidup di [AppVariant] (dibutuhkan konteks const
/// + variant.cmake Windows); profil ini adalah lapisan RUNTIME di atasnya:
/// entrypoint (`main.dart` / `main_inventory_sales.dart`) memilih profil
/// eksplisit lewat `bootstrap(profil)`, dan keduanya WAJIB konsisten (dijaga
/// [cocokDenganDartDefine] -- build salah kombinasi langsung ketahuan di log).
class AppProductProfile {
  final String kode;
  final String namaAplikasi;
  final String namaSidebar;
  final String updateAssetKeyword;
  final String logoAsset;
  final Set<String> fiturGrup;

  const AppProductProfile._({
    required this.kode,
    required this.namaAplikasi,
    required this.namaSidebar,
    required this.updateAssetKeyword,
    required this.logoAsset,
    required this.fiturGrup,
  });

  const AppProductProfile.ebisnis()
      : this._(
          kode: 'ebisnis',
          namaAplikasi: 'eBisnis',
          namaSidebar: 'eBisnis POS',
          updateAssetKeyword: 'ebisnis',
          logoAsset: 'assets/images/ebisnis/icon.png',
          fiturGrup: const {FiturGrup.pos},
        );

  const AppProductProfile.alBahjah()
      : this._(
          kode: 'albahjah',
          namaAplikasi: 'Al-Bahjah POS',
          namaSidebar: 'Al-Bahjah POS',
          updateAssetKeyword: 'albahjah',
          logoAsset: 'assets/images/albahjah/icon.png',
          fiturGrup: const {FiturGrup.pos},
        );

  const AppProductProfile.inventorySales()
      : this._(
          kode: 'inventory_sales',
          namaAplikasi: 'eBisnis Inventory & Sales',
          namaSidebar: 'Inventory & Sales',
          updateAssetKeyword: 'inventorysales',
          logoAsset: 'assets/images/inventory_sales/icon.png',
          fiturGrup: const {FiturGrup.pos, FiturGrup.inventorySales},
        );

  /// Varian "POS Apotik" (eFarmasi, JALAN 1: backend Java AIS + modul SIRS).
  /// FiturGrup.pos ikut dirakit: cangkang/menu POS existing tetap berfungsi
  /// untuk Admin -- role "apotik" hasil seed server memang mematikan seluruh
  /// menu POS lama lewat aksesMenu (fail-closed), jadi kasir apotek TIDAK
  /// melihatnya walau dirakit.
  const AppProductProfile.apotik()
      : this._(
          kode: 'apotik',
          namaAplikasi: 'eBisnis POS Apotik',
          namaSidebar: 'POS Apotik',
          updateAssetKeyword: 'apotik',
          logoAsset: 'assets/images/apotik/icon.png',
          fiturGrup: const {FiturGrup.pos, FiturGrup.apotik},
        );

  /// Profil yang cocok dgn `--dart-define=EBISNIS_VARIANT` build ini -- dipakai
  /// `main.dart` (entrypoint default melayani ebisnis & albahjah sekaligus).
  factory AppProductProfile.dariDartDefine() {
    if (AppVariant.isAlBahjah) return const AppProductProfile.alBahjah();
    if (AppVariant.isInventorySales) {
      return const AppProductProfile.inventorySales();
    }
    if (AppVariant.isApotik) return const AppProductProfile.apotik();
    return const AppProductProfile.ebisnis();
  }

  /// Profil aktif proses ini -- di-set SEKALI oleh `bootstrap()` sebelum
  /// `runApp`. Default aman = profil dart-define (identik utk semua alur
  /// normal; berbeda hanya bila entrypoint & dart-define tak konsisten).
  static AppProductProfile aktif = AppProductProfile.dariDartDefine();

  bool get isInventorySales => fiturGrup.contains(FiturGrup.inventorySales);

  bool get isApotik => fiturGrup.contains(FiturGrup.apotik);

  bool cocokDenganDartDefine() => kode == AppProductProfile.dariDartDefine().kode;

  /// Layar pertama setelah login sukses. Varian Inventory & Sales SELALU lewat
  /// beranda per-aktor (Admin/Pemilik -> dasbor modul; Sales -> "Sesi Hari
  /// Ini") -- landing POS existing (KasirScreen) TIDAK berubah utk varian lama.
  Widget buatLayarAwal() {
    if (isInventorySales) {
      return const BerandaInventorySalesScreen();
    }
    if (isApotik) {
      return const BerandaApotikScreen();
    }
    return const KasirScreen();
  }

  /// Gerbang menu level-varian (dipanggil `bolehTampilMenu` app_shell) --
  /// kunci menu khusus satu varian tidak pernah dirakit ke varian lain.
  bool bolehMenuVarian(String kunciMenuVarian) {
    if (kunciMenuVarian == FiturGrup.inventorySales) {
      return isInventorySales;
    }
    if (kunciMenuVarian == FiturGrup.apotik) {
      return isApotik;
    }
    return true;
  }

  /// Label menu yang berbeda makna antar varian (mis. "Anggota / Member" POS =
  /// "Customer" pada Inventory & Sales) -- SATU titik alih-bahasa, bukan
  /// if-variant tersebar di registry menu.
  String labelMenu(String labelPos) {
    if (!isInventorySales) return labelPos;
    switch (labelPos) {
      case 'Customer / Anggota':
      case 'Anggota':
        return 'Customer';
      case 'Kulakan':
        return 'Pembelian Supplier';
      default:
        return labelPos;
    }
  }

  /// Subjudul konteks aktor utk header/landing (dibaca dari [Sesi] yang sudah
  /// diisi aksi `konfigurasi` -- lihat `Sesi.terapkanKonfig`).
  String deskripsiAktor() {
    switch (Sesi.instance.actorType) {
      case 'ADMIN':
        return 'Admin (akses penuh)';
      case 'PEMILIK_SALES_INVENTORY':
        return 'Pemilik Sales / Inventory';
      case 'SALES_KELILING':
        return Sesi.instance.salesNama.isEmpty
            ? 'Sales Keliling'
            : 'Sales Keliling — ${Sesi.instance.salesNama}';
      default:
        return 'Pengguna POS';
    }
  }
}
