import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:intl/intl.dart';

import 'package:barcode/barcode.dart' as bc;
import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../app_variant.dart';
import '../api_client.dart';
import '../models.dart';
import '../services/pengaturan_price_tag.dart';
import '../services/pengaturan_struk.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/app_components.dart';

/// Cetak price tag dengan beberapa model operasional:
/// tag rak, stiker barcode produk, dan promo tag ukuran besar.
class PriceTagScreen extends StatefulWidget {
  const PriceTagScreen({super.key});

  @override
  State<PriceTagScreen> createState() => _PriceTagScreenState();
}

enum ModelPriceTag { rak, produk, promo }

extension _LabelModelPriceTag on ModelPriceTag {
  String get label {
    switch (this) {
      case ModelPriceTag.rak:
        return 'Price Tag Rak';
      case ModelPriceTag.produk:
        return 'Stiker Produk';
      case ModelPriceTag.promo:
        return 'Promo Tag';
    }
  }
}

/// Kertas tempat tag Rak/Produk dicetak -- terpisah dari ukuran tag itu
/// sendiri karena satu ukuran tag (mis. 50x25mm) bisa dicetak dua cara yang
/// berbeda total: [thermal] langsung ke printer label roll (tiap tag =
/// satu "halaman" pas ukuran tag, dikirim berurutan spt continuous form),
/// ATAU ditata sbg grid di atas kertas umum ([a4]/[f4]) yg dipotong manual.
/// Promo juga memakai pilihan ini sekarang: ukuran Promo menentukan ukuran
/// panel/tag, sedangkan [KertasCetak] menentukan media kertas/roll.
enum KertasCetak { thermal, a4, f4 }

extension _LabelKertasCetak on KertasCetak {
  String get label {
    switch (this) {
      case KertasCetak.thermal:
        return 'Thermal (Roll)';
      case KertasCetak.a4:
        return 'A4';
      case KertasCetak.f4:
        return 'F4';
    }
  }

  /// `null` utk [thermal] -- ukuran halaman dinamis mengikuti ukuran tag
  /// yang dipilih (lihat pemakaian di [_PriceTagPdfBuilder._isiGridLabel]),
  /// bukan ukuran kertas tetap spt A4/F4.
  PdfPageFormat? get pageFormat {
    switch (this) {
      case KertasCetak.thermal:
        return null;
      case KertasCetak.a4:
        return PdfPageFormat.a4;
      case KertasCetak.f4:
        return PdfPageFormat(210 * PdfPageFormat.mm, 330 * PdfPageFormat.mm);
    }
  }
}

/// Lebar roll thermal kontinu (BUKAN ukuran tag/label itu sendiri) --
/// dipakai saat [KertasCetak.thermal] dipilih supaya tag ditata berjajar
/// (grid) melintasi lebar roll spt kertas umum, tapi TINGGI halaman
/// menyesuaikan jumlah tag (bukan tetap spt A4) krn roll maju terus-
/// menerus. 110mm dicantumkan krn kapasitas media TSC TTP-244 Pro
/// (25.4-112mm, maks lebar cetak 108mm) -- lihat datasheet resmi TSC.
/// Sisanya lebar umum yang beredar di pasaran Indonesia utk printer
/// label thermal sejenis (Xprinter/Zebra/Argox/dll, bukan cuma TSC).
class _LebarRoll {
  final String id;
  final String label;
  final double lebarMm;
  final bool populer;

  const _LebarRoll({
    required this.id,
    required this.label,
    required this.lebarMm,
    this.populer = false,
  });
}

const _daftarLebarRoll = [
  _LebarRoll(id: 'roll_40', label: '40 mm', lebarMm: 40),
  _LebarRoll(id: 'roll_50', label: '50 mm', lebarMm: 50),
  _LebarRoll(id: 'roll_58', label: '58 mm', lebarMm: 58, populer: true),
  _LebarRoll(id: 'roll_80', label: '80 mm', lebarMm: 80, populer: true),
  _LebarRoll(id: 'roll_100', label: '100 mm', lebarMm: 100),
  // Terukur langsung dari roll TSC terpasang: lebar 108mm, margin tepi
  // ~1-2mm, jarak antar kotak ~3mm (atur di Konfigurasi > Profil Toko >
  // Margin Antar Kotak Price Tag) -- dgn tag lebar ~33mm (mis. "Barcode
  // Mini 2 Baris"/"Barcode Mini Lebar") hasilnya pas 3 kotak per baris.
  _LebarRoll(
      id: 'roll_108',
      label: '108 mm - Roll TSC terpasang (3 kotak/baris)',
      lebarMm: 108,
      populer: true),
  _LebarRoll(
      id: 'roll_110',
      label: '110 mm - TSC TTP-244 Pro (spesifikasi resmi)',
      lebarMm: 110,
      populer: true),
];

class _UkuranTag {
  final String id;
  final String label;
  final String detail;
  final String kategori;
  final double lebarMm;
  final double tinggiMm;
  final bool bulat;
  final bool populer;
  final PdfPageFormat? pageFormat;

  const _UkuranTag({
    required this.id,
    required this.label,
    required this.detail,
    required this.kategori,
    required this.lebarMm,
    required this.tinggiMm,
    this.bulat = false,
    this.populer = false,
    this.pageFormat,
  });
}

/// Margin cetak aman utk grid Rak/Produk di kertas umum (A4/F4) -- printer
/// konsumen/kantor umumnya TIDAK bisa mencetak sampai tepi mutlak kertas
/// (non-printable area khas ±3-6mm tergantung merek/model). Tanpa margin
/// ini, tag di baris/kolom paling tepi bisa terpotong saat dicetak LANGSUNG
/// ke printer fisik (beda dgn cuma dilihat di PDF viewer, yang menampilkan
/// apa adanya tanpa peduli batas fisik printer). SENGAJA TIDAK dipakai utk
/// roll thermal (`_isiGridLabel` kertasCetak==thermal) -- printer label
/// thermal dikalibrasi cetak pas ke tepi label die-cut, beda karakteristik
/// dgan printer kertas umum. 5mm dipilih spy konsisten dgn margin Promo
/// (Promo kini ikut jalur grid yang sama).
const _marginCetakAmanMm = 5.0;

const _kategoriRakUtama = 'Rak / Gondola';
const _kategoriTscRoll = 'Roll TSC TTP-244 Pro (Rekomendasi)';
const _kategoriThermalBarcode = 'Thermal / Printer Barcode';
const _kategoriPriceGun = 'Price Gun Manual (Gulungan)';
const _kategoriA4Label = 'Lembar A4 (Kertas Label)';
const _kategoriKemasan = 'Kemasan / Logistik';
const _kategoriBulatKotak = 'Cetak Bulat & Kotak';
const _kategoriKertasBesar = 'Kertas Cetak Besar';

const _ukuranRak = [
  _UkuranTag(
      id: 'rak_30x20',
      label: 'Rak Sempit',
      detail: '30 x 20 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 30,
      tinggiMm: 20),
  _UkuranTag(
      id: 'rak_50x30',
      label: 'Rak Gondola',
      detail: '50 x 30 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 50,
      tinggiMm: 30),
  _UkuranTag(
      id: 'rak_60x40',
      label: 'Rak Sedang',
      detail: '60 x 40 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 60,
      tinggiMm: 40),
  _UkuranTag(
      id: 'rak_80x50',
      label: 'Endcap Promo',
      detail: '80 x 50 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 80,
      tinggiMm: 50),
  _UkuranTag(
      id: 'rak_100x70',
      label: 'Hang Tag Besar',
      detail: '100 x 70 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 100,
      tinggiMm: 70),
  _UkuranTag(
      id: 'rak_40x60',
      label: 'Fashion Portrait',
      detail: '40 x 60 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 40,
      tinggiMm: 60),
  _UkuranTag(
      id: 'rak_a6',
      label: 'A6 Promo',
      detail: '105 x 148 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 105,
      tinggiMm: 148),
  _UkuranTag(
      id: 'rak_50x70',
      label: 'Menu Display',
      detail: '50 x 70 mm',
      kategori: _kategoriRakUtama,
      lebarMm: 50,
      tinggiMm: 70),
  _UkuranTag(
      id: 'rak_33x15',
      label: 'Barcode Rak Standar',
      detail: '33 x 15 mm',
      kategori: _kategoriThermalBarcode,
      lebarMm: 33,
      tinggiMm: 15,
      populer: true),
  _UkuranTag(
      id: 'rak_33x25',
      label: 'Barcode Rak Lebar',
      detail: '33 x 25 mm',
      kategori: _kategoriThermalBarcode,
      lebarMm: 33,
      tinggiMm: 25),
];

const _ukuranProduk = [
  // Roll paling umum & pasti cocok di printer TSC TTP-244 Pro (203 dpi):
  // lebar cetak maksimal printer ini 104 mm, jadi semua ukuran di bawah
  // aman dipakai. Ditaruh di kategori sendiri paling atas supaya jadi
  // pilihan utama saat mencetak stiker produk lewat roll thermal.
  _UkuranTag(
      id: 'produk_33x15',
      label: 'Barcode Rak 2 Baris',
      detail: '33 x 15 mm - 2 baris',
      kategori: _kategoriTscRoll,
      lebarMm: 33,
      tinggiMm: 15,
      populer: true),
  _UkuranTag(
      id: 'produk_30x20',
      label: 'Tempel Harga Produk',
      detail: '30 x 20 mm - 1 baris',
      kategori: _kategoriTscRoll,
      lebarMm: 30,
      tinggiMm: 20,
      populer: true),
  _UkuranTag(
      id: 'produk_50x25',
      label: 'Nama + Barcode + Harga',
      detail: '50 x 25 mm - 3 baris',
      kategori: _kategoriTscRoll,
      lebarMm: 50,
      tinggiMm: 25,
      populer: true),
  _UkuranTag(
      id: 'produk_50x30',
      label: 'Nama + Barcode + Harga (Lebar)',
      detail: '50 x 30 mm - 3 baris',
      kategori: _kategoriTscRoll,
      lebarMm: 50,
      tinggiMm: 30,
      populer: true),
  _UkuranTag(
      id: 'produk_100x150',
      label: 'Label Resi / Pengiriman',
      detail: '100 x 150 mm',
      kategori: _kategoriTscRoll,
      lebarMm: 100,
      tinggiMm: 150,
      populer: true),
  _UkuranTag(
      id: 'produk_40x20',
      label: 'Barcode Kecil',
      detail: '40 x 20 mm',
      kategori: _kategoriThermalBarcode,
      lebarMm: 40,
      tinggiMm: 20),
  _UkuranTag(
      id: 'produk_60x30',
      label: 'Barcode Besar',
      detail: '60 x 30 mm',
      kategori: _kategoriThermalBarcode,
      lebarMm: 60,
      tinggiMm: 30),
  _UkuranTag(
      id: 'produk_33x25',
      label: 'Barcode Mini Lebar',
      detail: '33 x 25 mm',
      kategori: _kategoriThermalBarcode,
      lebarMm: 33,
      tinggiMm: 25),
  _UkuranTag(
      id: 'produk_21x12',
      label: 'Price Gun 1 Baris',
      detail: '21 x 12 mm - mis. MX-5500',
      kategori: _kategoriPriceGun,
      lebarMm: 21,
      tinggiMm: 12,
      populer: true),
  _UkuranTag(
      id: 'produk_23x16',
      label: 'Price Gun 2 Baris',
      detail: '23 x 16 mm - mis. MX-6600',
      kategori: _kategoriPriceGun,
      lebarMm: 23,
      tinggiMm: 16,
      populer: true),
  _UkuranTag(
      id: 'produk_22x12',
      label: 'Price Gun Varian A',
      detail: '22 x 12 mm',
      kategori: _kategoriPriceGun,
      lebarMm: 22,
      tinggiMm: 12),
  _UkuranTag(
      id: 'produk_26x16',
      label: 'Price Gun Varian B',
      detail: '26 x 16 mm',
      kategori: _kategoriPriceGun,
      lebarMm: 26,
      tinggiMm: 16),
  _UkuranTag(
      id: 'produk_52x29',
      label: 'A4 40 Label',
      detail: '52 x 29 mm',
      kategori: _kategoriA4Label,
      lebarMm: 52,
      tinggiMm: 29),
  _UkuranTag(
      id: 'produk_70x35',
      label: 'A4 24 Label',
      detail: '70 x 35 mm',
      kategori: _kategoriA4Label,
      lebarMm: 70,
      tinggiMm: 35),
  _UkuranTag(
      id: 'produk_100x50',
      label: 'Label Kemasan',
      detail: '100 x 50 mm',
      kategori: _kategoriKemasan,
      lebarMm: 100,
      tinggiMm: 50),
  _UkuranTag(
      id: 'produk_bulat20',
      label: 'Bulat Kecil',
      detail: 'diameter 20 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 20,
      tinggiMm: 20,
      bulat: true),
  _UkuranTag(
      id: 'produk_bulat25',
      label: 'Bulat Sedang',
      detail: 'diameter 25 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 25,
      tinggiMm: 25,
      bulat: true),
  _UkuranTag(
      id: 'produk_bulat30',
      label: 'Bulat Besar',
      detail: 'diameter 30 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 30,
      tinggiMm: 30,
      bulat: true),
  _UkuranTag(
      id: 'produk_bulat35',
      label: 'Bulat Ekstra',
      detail: 'diameter 35 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 35,
      tinggiMm: 35,
      bulat: true),
  _UkuranTag(
      id: 'produk_kotak30x20',
      label: 'Kotak Kecil',
      detail: '30 x 20 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 30,
      tinggiMm: 20),
  _UkuranTag(
      id: 'produk_kotak40x30',
      label: 'Kotak Sedang',
      detail: '40 x 30 mm',
      kategori: _kategoriBulatKotak,
      lebarMm: 40,
      tinggiMm: 30),
];

final _ukuranPromo = [
  _UkuranTag(
      id: 'promo_a4_full',
      label: 'A4 Penuh',
      detail: '200 x 287 mm / halaman',
      kategori: _kategoriKertasBesar,
      lebarMm: 200,
      tinggiMm: 287,
      pageFormat: PdfPageFormat.a4),
  _UkuranTag(
      id: 'promo_a5',
      label: 'A4 dibagi 2',
      detail: '200 x 142.5 mm / panel',
      kategori: _kategoriKertasBesar,
      lebarMm: 200,
      tinggiMm: 142.5,
      pageFormat: PdfPageFormat.a4),
  _UkuranTag(
      id: 'promo_a4',
      label: 'A4 dibagi 3',
      detail: '200 x 92 mm / panel',
      kategori: _kategoriKertasBesar,
      lebarMm: 200,
      tinggiMm: 92,
      pageFormat: PdfPageFormat.a4),
  _UkuranTag(
      id: 'promo_f4',
      label: 'F4 - 3 Panel',
      detail: '200 x 103 mm / panel',
      kategori: _kategoriKertasBesar,
      lebarMm: 200,
      tinggiMm: 103,
      pageFormat:
          PdfPageFormat(210 * PdfPageFormat.mm, 330 * PdfPageFormat.mm)),
  for (final u in _ukuranRak)
    _UkuranTag(
      id: 'promo_${u.id}',
      label: 'Promo - ${u.label}',
      detail: u.detail,
      kategori: 'Ukuran Rak untuk Promo',
      lebarMm: u.lebarMm,
      tinggiMm: u.tinggiMm,
      bulat: u.bulat,
      populer: u.populer,
      pageFormat: u.pageFormat,
    ),
  for (final u in _ukuranProduk)
    _UkuranTag(
      id: 'promo_${u.id}',
      label: 'Promo - ${u.label}',
      detail: u.detail,
      kategori: 'Ukuran Price Tag Produk untuk Promo',
      lebarMm: u.lebarMm,
      tinggiMm: u.tinggiMm,
      bulat: u.bulat,
      populer: u.populer,
      pageFormat: u.pageFormat,
    ),
];

class _PriceTagScreenState extends State<PriceTagScreen> with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _semuaProduk = [];
  Set<int>? _promoProdukIds;
  bool _promoTampilkanSemuaProduk = false;
  bool _memuatProdukPromo = false;
  String? _pesanProdukPromo;
  String? _kategoriTerpilihKey;
  final _controllerCari = TextEditingController();
  final _fokusCari = FocusNode();
  final _controllerPromo = TextEditingController(text: 'PROMO');
  final _controllerCopies = TextEditingController(text: '1');
  final _controllerRakHeader = TextEditingController();
  final _controllerRakProduk = TextEditingController();
  final _controllerRakHarga = TextEditingController();
  final _controllerRakHeaderSize = TextEditingController(text: '8');
  final _controllerRakProdukSize = TextEditingController(text: '5.8');
  final _controllerRakKodeSize = TextEditingController(text: '7');
  final _controllerRakHargaSize = TextEditingController(text: '20');
  final _controllerRakHeaderTinggi = TextEditingController();
  final _controllerRakStripTinggi = TextEditingController();
  final _controllerRakHeaderBg = TextEditingController(text: '#505B54');
  final _controllerRakHeaderText = TextEditingController(text: '#FFFFFF');
  final _controllerRakStripBg = TextEditingController(text: '#E6B742');
  final _controllerRakStripText = TextEditingController(text: '#111827');
  final _controllerRakKodeText = TextEditingController(text: '#4D403C');
  final _controllerRakBodyBg = TextEditingController(text: '#FFFFFF');
  final _controllerRakHargaText = TextEditingController(text: '#514B4B');
  final _controllerPromoHeaderBg = TextEditingController(text: '#64605A');
  final _controllerPromoHeaderText = TextEditingController(text: '#FFFFFF');
  final _controllerPromoStripBg = TextEditingController(text: '#E7B640');
  final _controllerPromoStripText = TextEditingController(text: '#111827');
  final _controllerPromoHargaAsliText = TextEditingController(text: '#C62828');
  final _controllerPromoBodyBg = TextEditingController(text: '#FFFFFF');
  final _controllerPromoHargaText = TextEditingController(text: '#5F5555');
  final _controllerPromoHeaderSize = TextEditingController(text: '20');
  final _controllerPromoTokoSize = TextEditingController(text: '9');
  final _controllerPromoProdukSize = TextEditingController(text: '7.5');
  final _controllerPromoHargaAsliSize = TextEditingController(text: '7.5');
  final _controllerPromoHargaSize = TextEditingController(text: '47');
  final _controllerPromoKodeSize = TextEditingController(text: '7');
  final _controllerPromoHeaderTinggi = TextEditingController();
  final _controllerPromoStripTinggi = TextEditingController();
  final _controllerLogoWrapBg = TextEditingController(text: '#FFFFFF');
  final Map<int, String> _promoTeksPerProduk = {};
  final Map<int, String> _promoHargaAsliPerProduk = {};
  final Map<int, String> _promoHargaPromoPerProduk = {};
  final Map<int, String> _promoHargaAsliDefaultPerProduk = {};
  final Map<int, String> _promoHargaPromoDefaultPerProduk = {};
  final Map<int, String> _promoMasaPerProduk = {};
  Map<int, Map<String, dynamic>>? _aturanDiskonPromoById;
  final Map<String, TextEditingController> _controllerPromoItem = {};
  final Map<int, TextEditingController> _controllerSalinanItem = {};
  final Map<int, int> _salinanPerProduk = {};
  final Set<int> _idTerpilih = {};

  ModelPriceTag _model = ModelPriceTag.rak;
  KertasCetak _kertasCetak = KertasCetak.a4;
  String _lebarRollId = 'roll_58';
  String _ukuranId = 'rak_50x30';
  int _copies = 1;
  bool _salinanBerbedaPerProduk = false;
  bool _tampilBarcode = true;
  bool _tampilKode = true;
  // Khusus Rak & Promo -- teks angka barcode (BUKAN kolom Kode Produk),
  // independen dari [_tampilBarcode] (gambar batang) supaya bisa
  // ditampilkan salah satu, keduanya, atau tak satu pun.
  bool _tampilBarcodeTeks = false;
  bool _tampilTanggalCetak = false;
  bool _tampilToko = true;
  bool _tampilLogo = false;
  bool _tampilHargaProduk = true;
  bool _bungkusLogo = false;
  bool _memproses = false;
  String? _logoPath;
  double _marginKotakMm = 2;
  // Khusus model yang dicetak sebagai grid -- horizontal/vertikal bisa
  // diatur terpisah supaya label bisa disesuaikan dgn kertas/roll di
  // lapangan (mis. roll agak sempit butuh margin horizontal lebih kecil
  // spy tetap muat kolom yang diinginkan tanpa mengubah margin vertikal).
  double _marginHorizontalMm = 2;
  double _marginVerticalMm = 2;
  Timer? _debounceSimpanPengaturan;

  /// Controller yang isinya ikut disimpan sbg "pengaturan print" per model
  /// (lihat [PengaturanPriceTag]) -- SENGAJA tidak termasuk [_controllerCari]
  /// (filter pencarian produk, bukan pengaturan cetak) maupun
  /// [_controllerPromoItem] (override teks manual per produk terpilih,
  /// spesifik utk batch cetak saat itu, bukan preferensi yang reusable).
  List<TextEditingController> get _controllerPengaturanTersimpan => [
        _controllerCopies,
        _controllerPromo,
        _controllerRakHeader,
        _controllerRakProduk,
        _controllerRakHarga,
        _controllerRakHeaderSize,
        _controllerRakProdukSize,
        _controllerRakKodeSize,
        _controllerRakHargaSize,
        _controllerRakHeaderTinggi,
        _controllerRakStripTinggi,
        _controllerRakHeaderBg,
        _controllerRakHeaderText,
        _controllerRakStripBg,
        _controllerRakStripText,
        _controllerRakKodeText,
        _controllerRakBodyBg,
        _controllerRakHargaText,
        _controllerPromoHeaderBg,
        _controllerPromoHeaderText,
        _controllerPromoStripBg,
        _controllerPromoStripText,
        _controllerPromoHargaAsliText,
        _controllerPromoBodyBg,
        _controllerPromoHargaText,
        _controllerPromoHeaderSize,
        _controllerPromoTokoSize,
        _controllerPromoProdukSize,
        _controllerPromoHargaAsliSize,
        _controllerPromoHargaSize,
        _controllerPromoKodeSize,
        _controllerPromoHeaderTinggi,
        _controllerPromoStripTinggi,
        _controllerLogoWrapBg,
      ];

  @override
  void initState() {
    super.initState();
    for (final c in _controllerPengaturanTersimpan) {
      c.addListener(_jadwalkanSimpanPengaturan);
    }
    _muat();
  }

  @override
  void dispose() {
    _debounceSimpanPengaturan?.cancel();
    // Flush pengaturan terakhir (mis. keyboard belum sempat "settle" 500ms
    // sebelum user tutup layar) -- baca .text SEBELUM controller di-dispose.
    unawaited(_simpanPengaturanModel(_model));
    for (final c in _controllerPengaturanTersimpan) {
      c.removeListener(_jadwalkanSimpanPengaturan);
    }
    _controllerCari.dispose();
    _fokusCari.dispose();
    _controllerPromo.dispose();
    _controllerCopies.dispose();
    _controllerRakHeader.dispose();
    _controllerRakProduk.dispose();
    _controllerRakHarga.dispose();
    _controllerRakHeaderSize.dispose();
    _controllerRakProdukSize.dispose();
    _controllerRakKodeSize.dispose();
    _controllerRakHargaSize.dispose();
    _controllerRakHeaderTinggi.dispose();
    _controllerRakStripTinggi.dispose();
    _controllerRakHeaderBg.dispose();
    _controllerRakHeaderText.dispose();
    _controllerRakStripBg.dispose();
    _controllerRakStripText.dispose();
    _controllerRakKodeText.dispose();
    _controllerRakBodyBg.dispose();
    _controllerRakHargaText.dispose();
    _controllerPromoHeaderBg.dispose();
    _controllerPromoHeaderText.dispose();
    _controllerPromoStripBg.dispose();
    _controllerPromoStripText.dispose();
    _controllerPromoHargaAsliText.dispose();
    _controllerPromoBodyBg.dispose();
    _controllerPromoHargaText.dispose();
    _controllerPromoHeaderSize.dispose();
    _controllerPromoTokoSize.dispose();
    _controllerPromoProdukSize.dispose();
    _controllerPromoHargaAsliSize.dispose();
    _controllerPromoHargaSize.dispose();
    _controllerPromoKodeSize.dispose();
    _controllerPromoHeaderTinggi.dispose();
    _controllerPromoStripTinggi.dispose();
    _controllerLogoWrapBg.dispose();
    for (final controller in _controllerPromoItem.values) {
      controller.dispose();
    }
    for (final controller in _controllerSalinanItem.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      await PengaturanStruk.instance.muat();
      await PengaturanPriceTag.instance.muat();
      final hasil = await ApiClient.instance.aksi('price_tag_list_produk', {});
      final arr = (hasil['data'] as List?) ?? [];
      final produk =
          arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      await _lengkapiMetadataProduk(produk);
      setStateIfMounted(() {
        _semuaProduk = produk;
        _logoPath = PengaturanStruk.instance.priceTagLogoPath;
        _marginKotakMm = PengaturanStruk.instance.priceTagMarginKotakMm;
        _model =
            _modelDari(PengaturanPriceTag.instance.modelTerakhir) ?? _model;
        _terapkanPengaturanModel(_model);
      });
      if (_model == ModelPriceTag.promo) {
        unawaited(_muatProdukPromoJikaPerlu());
      }
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  /// Endpoint `price_tag_list_produk` kadang hanya membawa data minimal
  /// (nama/kode/harga) tanpa `barcode` dan kategori. Halaman Produk memakai
  /// endpoint `katalog` yang lebih lengkap; supaya filter kategori di sini
  /// konsisten, lengkapi metadata dari cache lokal terlebih dahulu, lalu
  /// fallback ke `katalog` bila cache belum berisi kategori.
  Future<void> _lengkapiMetadataProduk(
      List<Map<String, dynamic>> produk) async {
    var adaKategori = _adaKategoriProduk(produk);
    try {
      final cache = await CoreDb.instance.produkCache();
      _gabungMetadataProduk(produk, cache);
      adaKategori = _adaKategoriProduk(produk);
    } catch (_) {
      // Cache lokal gagal dibaca (mis. belum pernah sinkron). Lanjut fallback
      // ke endpoint katalog di bawah; kalau itu juga gagal, price tag tetap
      // dapat dicetak hanya tanpa filter kategori yang lengkap.
    }

    if (adaKategori) return;
    try {
      final katalog = await ApiClient.instance.aksi('katalog');
      final produkJson =
          ((katalog['produk'] as List?) ?? []).cast<Map<String, dynamic>>();
      await CoreDb.instance.replaceProdukCache(
        produkJson.map(Produk.baseKeCacheRow).toList(),
      );
      _gabungMetadataProduk(produk, produkJson);
    } catch (_) {
      // Fallback katalog gagal/offline -- biarkan daftar tampil dengan data
      // minimal dari price_tag_list_produk.
    }
  }

  bool _adaKategoriProduk(List<Map<String, dynamic>> produk) {
    return produk.any((p) {
      final id = p['kategoriId'] ?? p['kategori_id'];
      final nama = _kategoriNamaProduk(p);
      return id != null || nama.isNotEmpty;
    });
  }

  void _gabungMetadataProduk(
    List<Map<String, dynamic>> produk,
    List<Map<String, dynamic>> sumber,
  ) {
    final byId = <int, Map<String, dynamic>>{};
    final byKode = <String, Map<String, dynamic>>{};
    for (final row in sumber) {
      final id = (row['id'] as num?)?.toInt();
      if (id != null) byId[id] = row;
      final kode = '${row['kode'] ?? ''}'.trim().toLowerCase();
      if (kode.isNotEmpty) byKode[kode] = row;
    }
    if (byId.isEmpty && byKode.isEmpty) return;

    for (final p in produk) {
      final id = (p['id'] as num?)?.toInt();
      final kode = '${p['kode'] ?? ''}'.trim().toLowerCase();
      final sumber = (id == null ? null : byId[id]) ?? byKode[kode];
      if (sumber == null) continue;

      if ('${p['barcode'] ?? ''}'.trim().isEmpty) {
        final barcode = '${sumber['barcode'] ?? ''}'.trim();
        if (barcode.isNotEmpty) p['barcode'] = barcode;
      }

      p['kategoriId'] ??= sumber['kategoriId'] ?? sumber['kategori_id'];
      final kategoriNama = _nilaiStringPertama(sumber, const [
        'kategoriNama',
        'kategori_nama',
        'kategori',
      ]);
      if (_kategoriNamaProduk(p).isEmpty && kategoriNama.isNotEmpty) {
        p['kategoriNama'] = kategoriNama;
      }
    }
  }

  String _nilaiStringPertama(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final value = '${p[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<Map<int, Map<String, dynamic>>> _muatAturanDiskonPromoById() async {
    final cache = _aturanDiskonPromoById;
    if (cache != null) return cache;
    final byId = <int, Map<String, dynamic>>{};
    try {
      final hasil = await ApiClient.instance.aksi('diskon_list', {
        'page': 1,
        'page_size': 1000,
      });
      final data = (hasil['data'] as List?) ?? [];
      for (final row in data) {
        final m = Map<String, dynamic>.from(row as Map);
        final id =
            _intDari(m['id'] ?? m['aturanDiskon'] ?? m['aturanDiskonId']);
        if (id != null) byId[id] = m;
      }
    } catch (_) {
      // Masa promo bukan blocker cetak. Kalau gagal, tag tetap tampil tanpa periode.
    }
    _aturanDiskonPromoById = byId;
    return byId;
  }

  int? _intDari(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim());
  }

  String _masaPromoDariEvaluasi(
    Map<String, dynamic> data,
    Map<int, Map<String, dynamic>> aturanById,
  ) {
    final langsung = _nilaiStringPertama(data, const [
      'masaPromo',
      'masa_promo',
      'periodePromo',
      'periode_promo',
      'berlaku',
      'masaBerlaku',
    ]);
    if (langsung.isNotEmpty) return langsung;

    final aturan = data['aturan'] ?? data['aturanDiskonDetail'];
    final sumberLangsung =
        aturan is Map ? {...data, ...Map<String, dynamic>.from(aturan)} : data;
    final dariLangsung = _masaPromoDariSumber(sumberLangsung);
    if (dariLangsung.isNotEmpty) return dariLangsung;

    final aturanId = _intDari(data['aturanDiskon'] ??
        data['aturanDiskonId'] ??
        data['aturan_diskon'] ??
        data['aturan_diskon_id']);
    final sumberAturan = aturanId == null ? null : aturanById[aturanId];
    if (sumberAturan == null) return '';
    return _masaPromoDariSumber(sumberAturan);
  }

  String _masaPromoDariSumber(Map<String, dynamic> sumber) {
    final mulai = _nilaiStringPertama(sumber, const [
      'tanggalMulai',
      'tanggal_mulai',
      'mulai',
      'start',
      'startDate',
      'berlakuMulai',
    ]);
    final selesai = _nilaiStringPertama(sumber, const [
      'tanggalSelesai',
      'tanggal_selesai',
      'selesai',
      'end',
      'endDate',
      'berlakuSampai',
    ]);
    if (mulai.isEmpty && selesai.isEmpty) return '';
    if (mulai.isEmpty) return 's.d. $selesai';
    if (selesai.isEmpty) return 'Mulai $mulai';
    return '$mulai - $selesai';
  }

  List<Map<String, dynamic>> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    return _produkSumberModel.where((p) {
      final cocokKategori = _kategoriTerpilihKey == null ||
          _kategoriKeyProduk(p) == _kategoriTerpilihKey;
      if (!cocokKategori) return false;
      if (kw.isEmpty) return true;
      final nama = (p['nama'] as String? ?? '').toLowerCase();
      final kode = '${p['kode'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      return nama.contains(kw) || kode.contains(kw) || barcode.contains(kw);
    }).toList();
  }

  void _submitCariProduk(String nilai) {
    final v = nilai.trim();
    if (v.isEmpty) return;
    final cocok = _produkSumberModel.where((p) {
      final kode = '${p['kode'] ?? ''}'.trim();
      final barcode = '${p['barcode'] ?? ''}'.trim();
      return kode == v || barcode == v;
    }).toList();
    setStateIfMounted(() {
      if (cocok.isNotEmpty) {
        _idTerpilih.add(_idProduk(cocok.first));
      }
      _controllerCari.clear();
    });
    _fokusCari.requestFocus();
  }

  List<Map<String, dynamic>> get _daftarProdukTampil {
    final hasilFilter = _terfilter;
    if (_idTerpilih.isEmpty) return hasilFilter;

    final terpilihDiAtas = _produkSumberModel
        .where((p) => _idTerpilih.contains(_idProduk(p)))
        .toList();
    final idTerpilihDiAtas = terpilihDiAtas.map(_idProduk).toSet();
    return [
      ...terpilihDiAtas,
      ...hasilFilter.where((p) => !idTerpilihDiAtas.contains(_idProduk(p))),
    ];
  }

  Iterable<Map<String, dynamic>> get _produkSumberModel {
    if (_model != ModelPriceTag.promo) return _semuaProduk;
    if (_promoTampilkanSemuaProduk) return _semuaProduk;
    final ids = _promoProdukIds;
    if (ids == null) return const Iterable<Map<String, dynamic>>.empty();
    return _semuaProduk.where((p) => ids.contains(_idProduk(p)));
  }

  void _aturPromoTampilkanSemuaProduk(bool value) {
    setStateIfMounted(() {
      _promoTampilkanSemuaProduk = value;
      if (!value) {
        final ids = _promoProdukIds;
        if (ids != null) {
          _idTerpilih.removeWhere((id) => !ids.contains(id));
        }
        if (_kategoriTerpilihKey != null &&
            !_daftarKategoriProduk.any((k) => k.key == _kategoriTerpilihKey)) {
          _kategoriTerpilihKey = null;
        }
      }
    });
    unawaited(_simpanPengaturanModel(_model));
  }

  String _kategoriKeyProduk(Map<String, dynamic> p) {
    final id = p['kategoriId'] ?? p['kategori_id'];
    if (id is num) return 'id:${id.toInt()}';
    final nama = _kategoriNamaProduk(p).trim().toLowerCase();
    return nama.isEmpty ? 'tanpa' : 'nama:$nama';
  }

  String _kategoriNamaProduk(Map<String, dynamic> p) {
    return '${p['kategoriNama'] ?? p['kategori_nama'] ?? p['kategori'] ?? ''}'
        .trim();
  }

  String _labelKategoriProduk(Map<String, dynamic> p) {
    final nama = _kategoriNamaProduk(p);
    return nama.isEmpty ? 'Tanpa Kategori' : nama;
  }

  List<({String key, String label, int jumlah})> get _daftarKategoriProduk {
    final labelByKey = <String, String>{};
    final countByKey = <String, int>{};
    for (final p in _produkSumberModel) {
      final key = _kategoriKeyProduk(p);
      labelByKey.putIfAbsent(key, () => _labelKategoriProduk(p));
      countByKey[key] = (countByKey[key] ?? 0) + 1;
    }
    final keys = labelByKey.keys.toList()
      ..sort((a, b) => labelByKey[a]!.compareTo(labelByKey[b]!));
    return [
      for (final key in keys)
        (key: key, label: labelByKey[key]!, jumlah: countByKey[key] ?? 0),
    ];
  }

  Future<void> _muatProdukPromoJikaPerlu({bool paksa = false}) async {
    if (_memuatProdukPromo) return;
    if (!paksa && _promoProdukIds != null) return;
    if (_semuaProduk.isEmpty) {
      setStateIfMounted(() => _promoProdukIds = <int>{});
      return;
    }
    setStateIfMounted(() {
      _memuatProdukPromo = true;
      _pesanProdukPromo = null;
      if (paksa) _promoProdukIds = null;
    });
    try {
      final idsPromo = <int>{};
      _promoHargaAsliDefaultPerProduk.clear();
      _promoHargaPromoDefaultPerProduk.clear();
      _promoMasaPerProduk.clear();
      final aturanById = await _muatAturanDiskonPromoById();
      const ukuranBatch = 80;
      for (var start = 0; start < _semuaProduk.length; start += ukuranBatch) {
        final batch = _semuaProduk.skip(start).take(ukuranBatch).toList();
        final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
          if (Sesi.instance.tokoId != null) 'toko_id': Sesi.instance.tokoId,
          'items': batch
              .map((p) => {
                    'id': _idProduk(p),
                    'harga': (p['hargaJual'] as num?)?.toDouble() ?? 0,
                    'jumlah': 1,
                  })
              .toList(),
        });
        final items = (hasil['items'] as List?) ?? [];
        for (var i = 0; i < items.length && i < batch.length; i++) {
          final m = Map<String, dynamic>.from(items[i] as Map);
          final p = batch[i];
          final id = _idProduk(p);
          final diskon = (m['diskon'] as num?)?.toDouble() ?? 0;
          final cashback = (m['cashback'] as num?)?.toDouble() ?? 0;
          final aturanDiskon = m['aturanDiskon'];
          if (diskon <= 0 && cashback <= 0 && aturanDiskon == null) continue;
          idsPromo.add(id);
          final harga = (p['hargaJual'] as num?)?.toDouble() ?? 0;
          final hargaPromo = max(0, harga - diskon);
          final hargaAsliText =
              _formatRupiah(harga).replaceFirst('Rp ', 'Rp. ');
          final hargaPromoText =
              _formatRupiah(hargaPromo).replaceFirst('Rp ', 'Rp. ');
          _promoHargaAsliDefaultPerProduk[id] = hargaAsliText;
          _promoHargaPromoDefaultPerProduk[id] = hargaPromoText;
          p['hargaAsliPromoTag'] = harga;
          p['hargaPromoTag'] = hargaPromo;
          final masaPromo = _masaPromoDariEvaluasi(m, aturanById);
          if (masaPromo.isNotEmpty) {
            _promoMasaPerProduk[id] = masaPromo;
            p['masaPromoTag'] = masaPromo;
          }
        }
      }
      if (!mounted) return;
      setStateIfMounted(() {
        _promoProdukIds = idsPromo;
        if (!_promoTampilkanSemuaProduk) {
          _idTerpilih.removeWhere((id) => !idsPromo.contains(id));
          if (_kategoriTerpilihKey != null &&
              !_daftarKategoriProduk
                  .any((k) => k.key == _kategoriTerpilihKey)) {
            _kategoriTerpilihKey = null;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _promoProdukIds = <int>{};
        _pesanProdukPromo = terapkanGalat(e);
      });
    } finally {
      if (mounted) setStateIfMounted(() => _memuatProdukPromo = false);
    }
  }

  List<_UkuranTag> get _ukuranTersedia {
    switch (_model) {
      case ModelPriceTag.rak:
        return _ukuranRak;
      case ModelPriceTag.produk:
        return _ukuranProduk;
      case ModelPriceTag.promo:
        return _ukuranPromo;
    }
  }

  _UkuranTag get _ukuranAktif {
    final daftar = _ukuranTersedia;
    return daftar.firstWhere((u) => u.id == _ukuranId,
        orElse: () => daftar.first);
  }

  _LebarRoll get _lebarRollAktif =>
      _daftarLebarRoll.firstWhere((r) => r.id == _lebarRollId,
          orElse: () => _daftarLebarRoll.first);

  PdfPageFormat get _formatKertasPdfAktif {
    if (_kertasCetak == KertasCetak.thermal) {
      return PdfPageFormat(
        _lebarRollAktif.lebarMm * PdfPageFormat.mm,
        max(_ukuranAktif.tinggiMm, 20) * PdfPageFormat.mm,
        marginAll: 0,
      );
    }
    if (_model == ModelPriceTag.promo && _ukuranAktif.pageFormat != null) {
      return _ukuranAktif.pageFormat!;
    }
    return _kertasCetak.pageFormat ?? PdfPageFormat.a4;
  }

  double get _lebarKertasAktifMm => _kertasCetak == KertasCetak.thermal
      ? _lebarRollAktif.lebarMm
      : _formatKertasPdfAktif.width / PdfPageFormat.mm;

  double get _tinggiKertasAktifMm => _kertasCetak == KertasCetak.thermal
      ? _ukuranAktif.tinggiMm * 4
      : _formatKertasPdfAktif.height / PdfPageFormat.mm;

  String get _labelKertasPreviewAktif {
    final ukuran = _ukuranAktif;
    if (_kertasCetak == KertasCetak.thermal) {
      return 'Roll ${_lebarRollAktif.label} - tag ${ukuran.detail}';
    }
    final lebar = _lebarKertasAktifMm.toStringAsFixed(0);
    final tinggi = _tinggiKertasAktifMm.toStringAsFixed(0);
    if (_model == ModelPriceTag.promo && ukuran.pageFormat != null) {
      return '${ukuran.label} pada $lebar x $tinggi mm - panel ${ukuran.detail}';
    }
    return '${_kertasCetak.label} ($lebar x $tinggi mm) - tag ${ukuran.detail}';
  }

  /// Margin horizontal/vertikal yang benar-benar dipakai saat ini. Semua
  /// model yang dicetak sebagai grid memakai nilai independen ini supaya
  /// preview dan PDF bisa disesuaikan ke media fisik yang tersedia.
  bool get _modelBolehMarginIndependen =>
      _model == ModelPriceTag.produk ||
      _model == ModelPriceTag.rak ||
      _model == ModelPriceTag.promo;
  double get _marginHorizontalAktifMm =>
      _modelBolehMarginIndependen ? _marginHorizontalMm : _marginKotakMm;
  double get _marginVerticalAktifMm =>
      _modelBolehMarginIndependen ? _marginVerticalMm : _marginKotakMm;

  /// Tombol ringkas pengganti daftar ChoiceChip yang dulu selalu terbuka di
  /// panel -- dengan ukuran per model sekarang bisa puluhan (price gun,
  /// thermal, kemasan, bulat/kotak, dst.) menampilkan semuanya langsung di
  /// panel akan membuat sisi kanan kepanjangan. Popup [_pilihUkuran]
  /// mengelompokkannya per kategori supaya tetap mudah dicari.
  Widget _tombolPilihUkuran() {
    final u = _ukuranAktif;
    return InkWell(
      onTap: _pilihUkuran,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(u.bulat ? Icons.circle_outlined : Icons.crop_square_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${u.detail} - ${u.kategori}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.unfold_more,
                size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Future<void> _pilihUkuran() async {
    final daftar = _ukuranTersedia;
    final kategoriUrut = <String>[];
    for (final u in daftar) {
      if (!kategoriUrut.contains(u.kategori)) kategoriUrut.add(u.kategori);
    }
    final dipilih = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pilih Ukuran ${_model.label}'),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        content: SizedBox(
          width: 420,
          height: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final kategori in kategoriUrut) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
                  child: Text(kategori,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ),
                ...daftar
                    .where((u) => u.kategori == kategori)
                    .map(_opsiUkuranTile),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
    if (dipilih != null) {
      setStateIfMounted(() => _ukuranId = dipilih);
      unawaited(_simpanPengaturanModel(_model));
    }
  }

  Widget _opsiUkuranTile(_UkuranTag u) {
    final terpilih = _ukuranId == u.id;
    return InkWell(
      onTap: () => Navigator.pop(context, u.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: terpilih ? AppColors.primary.withValues(alpha: 0.08) : null,
          border: Border.all(
              color: terpilih ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              u.bulat ? Icons.circle_outlined : Icons.crop_square_rounded,
              size: 18,
              color: terpilih ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(u.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: terpilih ? AppColors.primary : null)),
                      ),
                      if (u.populer) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star, size: 13, color: Colors.amber),
                      ],
                    ],
                  ),
                  Text(u.detail,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (terpilih)
              Icon(Icons.check_circle, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Future<void> _infoPrinterTsc() {
    // Angka persis dari datasheet resmi TSC (TTP-244 Pro, model 2017,
    // ks-barcode.com/files/datasheets/ttp-244_pro.pdf) -- BUKAN estimasi.
    const spesifikasi = [
      ('Lebar media', '25,4 - 112 mm (1,0" - 4,4")'),
      ('Lebar cetak maksimal', '108 mm (4,25")'),
      ('Panjang label', '10 - 2.286 mm (0,39" - 90")'),
      ('Ketebalan media', '0,06 - 0,19 mm (2,36 - 7,48 mil)'),
      ('Kapasitas roll (OD) standar', '110 mm (4,33") - dudukan internal'),
      (
        'Kapasitas roll (OD) opsional',
        '214 mm (8,4") - dgn external roll mount, core 1" atau 3"'
      ),
      ('Diameter core roll', '25,4 - 76,2 mm (1" - 3")'),
      ('Jenis media', 'Continuous, die-cut, black mark, fan-fold, notched'),
      (
        'Ribbon (thermal transfer)',
        'lebar 40 - 110 mm, maks. panjang 300 m, core 1"'
      ),
      (
        'Resolusi / kecepatan',
        '203 dpi (8 dot/mm), maks. 127 mm (5") per detik'
      ),
    ];
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spesifikasi Printer TSC TTP-244 Pro'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Printer thermal transfer + direct thermal, 203 dpi.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                for (final item in spesifikasi)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Text(item.$2,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Catatan: pilihan "110 mm" di daftar Lebar Roll adalah '
                    'LEBAR stok label yang dipasang (masih di bawah batas '
                    'lebar media printer ini, 112 mm) -- beda dengan '
                    '"Kapasitas roll (OD) standar 110 mm" di atas, yang '
                    'itu DIAMETER gulungan, bukan lebarnya.',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? get _produkPreview {
    for (final p in _produkSumberModel) {
      if (_idTerpilih.contains(_idProduk(p))) return p;
    }
    return _terfilter.isNotEmpty ? _terfilter.first : null;
  }

  ModelPriceTag? _modelDari(String? nama) {
    for (final m in ModelPriceTag.values) {
      if (m.name == nama) return m;
    }
    return null;
  }

  KertasCetak? _kertasCetakDari(dynamic nama) {
    if (nama is! String) return null;
    for (final k in KertasCetak.values) {
      if (k.name == nama) return k;
    }
    return null;
  }

  /// Snapshot pengaturan print model [model] saat ini -- bentuknya
  /// disesuaikan per model (field yang tidak relevan/tidak tampil di UI
  /// model tsb tidak ikut disimpan, mis. rak tidak punya `tampilHargaProduk`
  /// dan produk tidak punya field kustom warna/teks rak).
  Map<String, dynamic> _snapshotPengaturan(ModelPriceTag model) {
    final umum = <String, dynamic>{
      'ukuranId': _ukuranId,
      'copies': _copies,
      'salinanBerbedaPerProduk': _salinanBerbedaPerProduk,
    };
    switch (model) {
      case ModelPriceTag.rak:
        return {
          ...umum,
          'kertasCetak': _kertasCetak.name,
          'lebarRollId': _lebarRollId,
          'tampilBarcode': _tampilBarcode,
          'tampilKode': _tampilKode,
          'tampilBarcodeTeks': _tampilBarcodeTeks,
          'tampilTanggalCetak': _tampilTanggalCetak,
          'tampilToko': _tampilToko,
          'tampilLogo': _tampilLogo,
          'bungkusLogo': _bungkusLogo,
          'logoWrapBg': _controllerLogoWrapBg.text,
          'marginHorizontalMm': _marginHorizontalMm,
          'marginVerticalMm': _marginVerticalMm,
          'rakHeader': _controllerRakHeader.text,
          'rakProduk': _controllerRakProduk.text,
          'rakHarga': _controllerRakHarga.text,
          'rakHeaderSize': _controllerRakHeaderSize.text,
          'rakProdukSize': _controllerRakProdukSize.text,
          'rakKodeSize': _controllerRakKodeSize.text,
          'rakHargaSize': _controllerRakHargaSize.text,
          'rakHeaderTinggi': _controllerRakHeaderTinggi.text,
          'rakStripTinggi': _controllerRakStripTinggi.text,
          'rakHeaderBg': _controllerRakHeaderBg.text,
          'rakHeaderTextColor': _controllerRakHeaderText.text,
          'rakStripBg': _controllerRakStripBg.text,
          'rakStripText': _controllerRakStripText.text,
          'rakKodeText': _controllerRakKodeText.text,
          'rakBodyBg': _controllerRakBodyBg.text,
          'rakHargaTextColor': _controllerRakHargaText.text,
        };
      case ModelPriceTag.produk:
        return {
          ...umum,
          'kertasCetak': _kertasCetak.name,
          'lebarRollId': _lebarRollId,
          'tampilBarcode': _tampilBarcode,
          'tampilKode': _tampilKode,
          'tampilHargaProduk': _tampilHargaProduk,
          'marginHorizontalMm': _marginHorizontalMm,
          'marginVerticalMm': _marginVerticalMm,
        };
      case ModelPriceTag.promo:
        return {
          ...umum,
          'kertasCetak': _kertasCetak.name,
          'lebarRollId': _lebarRollId,
          'marginHorizontalMm': _marginHorizontalMm,
          'marginVerticalMm': _marginVerticalMm,
          'tampilBarcode': _tampilBarcode,
          'tampilKode': _tampilKode,
          'tampilBarcodeTeks': _tampilBarcodeTeks,
          'tampilTanggalCetak': _tampilTanggalCetak,
          'promoTampilkanSemuaProduk': _promoTampilkanSemuaProduk,
          'tampilToko': _tampilToko,
          'tampilLogo': _tampilLogo,
          'bungkusLogo': _bungkusLogo,
          'logoWrapBg': _controllerLogoWrapBg.text,
          'promoDefault': _controllerPromo.text,
          'promoHeaderBg': _controllerPromoHeaderBg.text,
          'promoHeaderTextColor': _controllerPromoHeaderText.text,
          'promoStripBg': _controllerPromoStripBg.text,
          'promoStripText': _controllerPromoStripText.text,
          'promoHargaAsliText': _controllerPromoHargaAsliText.text,
          'promoBodyBg': _controllerPromoBodyBg.text,
          'promoHargaTextColor': _controllerPromoHargaText.text,
          'promoHeaderSize': _controllerPromoHeaderSize.text,
          'promoTokoSize': _controllerPromoTokoSize.text,
          'promoProdukSize': _controllerPromoProdukSize.text,
          'promoHargaAsliSize': _controllerPromoHargaAsliSize.text,
          'promoHargaSize': _controllerPromoHargaSize.text,
          'promoKodeSize': _controllerPromoKodeSize.text,
          'promoHeaderTinggi': _controllerPromoHeaderTinggi.text,
          'promoStripTinggi': _controllerPromoStripTinggi.text,
        };
    }
  }

  /// Terapkan pengaturan tersimpan utk [model] (kalau ada) ke seluruh
  /// state/controller terkait -- field yang belum pernah disimpan (mis.
  /// pemakaian pertama kali) jatuh ke default bawaan yang sama spt sebelum
  /// fitur penyimpanan ini ada, supaya perilaku first-run tidak berubah.
  void _terapkanPengaturanModel(ModelPriceTag model) {
    final data = PengaturanPriceTag.instance.untukModel(model.name);
    String teks(String kunci, String fallback) {
      final v = data?[kunci];
      return (v is String && v.isNotEmpty) ? v : fallback;
    }

    bool boolean(String kunci, bool fallback) =>
        data?[kunci] as bool? ?? fallback;

    final daftarUkuran = switch (model) {
      ModelPriceTag.rak => _ukuranRak,
      ModelPriceTag.produk => _ukuranProduk,
      ModelPriceTag.promo => _ukuranPromo,
    };
    final ukuranTersimpan = data?['ukuranId'] as String?;
    _ukuranId = (ukuranTersimpan != null &&
            daftarUkuran.any((u) => u.id == ukuranTersimpan))
        ? ukuranTersimpan
        : daftarUkuran.first.id;

    _copies = ((data?['copies'] as num?)?.toInt() ?? 1).clamp(1, 999);
    _salinanBerbedaPerProduk = boolean('salinanBerbedaPerProduk', false);
    _controllerCopies.text = _copies.toString();

    _tampilBarcode = boolean('tampilBarcode', true);
    _tampilKode = boolean('tampilKode', true);
    _tampilBarcodeTeks = boolean('tampilBarcodeTeks', false);
    _tampilTanggalCetak = boolean('tampilTanggalCetak', false);

    switch (model) {
      case ModelPriceTag.rak:
        _kertasCetak = _kertasCetakDari(data?['kertasCetak']) ?? KertasCetak.a4;
        _lebarRollId = teks('lebarRollId', 'roll_58');
        _tampilToko = boolean('tampilToko', true);
        _tampilLogo = boolean('tampilLogo', false);
        _bungkusLogo = boolean('bungkusLogo', false);
        _controllerLogoWrapBg.text = teks('logoWrapBg', '#FFFFFF');
        _controllerRakHeader.text = teks('rakHeader', '');
        _controllerRakProduk.text = teks('rakProduk', '');
        _controllerRakHarga.text = teks('rakHarga', '');
        _controllerRakHeaderSize.text = teks('rakHeaderSize', '8');
        _controllerRakProdukSize.text = teks('rakProdukSize', '5.8');
        _controllerRakKodeSize.text = teks('rakKodeSize', '7');
        _controllerRakHargaSize.text = teks('rakHargaSize', '20');
        _controllerRakHeaderTinggi.text = teks('rakHeaderTinggi', '');
        _controllerRakStripTinggi.text = teks('rakStripTinggi', '');
        _controllerRakHeaderBg.text = teks('rakHeaderBg', '#505B54');
        _controllerRakHeaderText.text = teks('rakHeaderTextColor', '#FFFFFF');
        _controllerRakStripBg.text = teks('rakStripBg', '#E6B742');
        _controllerRakStripText.text = teks('rakStripText', '#111827');
        _controllerRakKodeText.text = teks('rakKodeText', '#4D403C');
        _controllerRakBodyBg.text = teks('rakBodyBg', '#FFFFFF');
        _controllerRakHargaText.text = teks('rakHargaTextColor', '#514B4B');
        _muatMarginIndependen(data);
      case ModelPriceTag.produk:
        _kertasCetak = _kertasCetakDari(data?['kertasCetak']) ?? KertasCetak.a4;
        _lebarRollId = teks('lebarRollId', 'roll_58');
        _tampilHargaProduk = boolean('tampilHargaProduk', true);
        _tampilToko = false;
        _tampilLogo = false;
        _tampilBarcodeTeks = false;
        _muatMarginIndependen(data);
      case ModelPriceTag.promo:
        _kertasCetak = _kertasCetakDari(data?['kertasCetak']) ?? KertasCetak.a4;
        _lebarRollId = teks('lebarRollId', 'roll_58');
        _muatMarginIndependen(data);
        _promoTampilkanSemuaProduk =
            boolean('promoTampilkanSemuaProduk', false);
        _tampilToko = boolean('tampilToko', true);
        _tampilLogo = boolean('tampilLogo', false);
        _bungkusLogo = boolean('bungkusLogo', false);
        _controllerLogoWrapBg.text = teks('logoWrapBg', '#FFFFFF');
        _controllerPromo.text = teks('promoDefault', 'PROMO');
        _controllerPromoHeaderBg.text = teks('promoHeaderBg', '#64605A');
        _controllerPromoHeaderText.text =
            teks('promoHeaderTextColor', '#FFFFFF');
        _controllerPromoStripBg.text = teks('promoStripBg', '#E7B640');
        _controllerPromoStripText.text = teks('promoStripText', '#111827');
        _controllerPromoHargaAsliText.text =
            teks('promoHargaAsliText', '#C62828');
        _controllerPromoBodyBg.text = teks('promoBodyBg', '#FFFFFF');
        _controllerPromoHargaText.text = teks('promoHargaTextColor', '#5F5555');
        _controllerPromoHeaderSize.text = teks('promoHeaderSize', '20');
        _controllerPromoTokoSize.text = teks('promoTokoSize', '9');
        _controllerPromoProdukSize.text = teks('promoProdukSize', '7.5');
        _controllerPromoHargaAsliSize.text = teks('promoHargaAsliSize', '7.5');
        _controllerPromoHargaSize.text = teks('promoHargaSize', '47');
        _controllerPromoKodeSize.text = teks('promoKodeSize', '7');
        _controllerPromoHeaderTinggi.text = teks('promoHeaderTinggi', '');
        _controllerPromoStripTinggi.text = teks('promoStripTinggi', '');
    }
    // Batalkan penjadwalan simpan yg keterpicu krn assignment `.text` di
    // atas (listener ikut jalan tiap controller diisi ulang) -- ini cuma
    // menerapkan data yg SUDAH tersimpan, bukan perubahan baru dari user.
    _debounceSimpanPengaturan?.cancel();
  }

  /// Dipanggil dari cabang Rak & Produk di [_terapkanPengaturanModel] --
  /// belum pernah diutak-atik -> ikut Margin Antar Kotak global (Konfigurasi
  /// > Profil Toko, sudah kebaca ke [_marginKotakMm] di [_muat] sebelum
  /// method ini jalan) spy tampilan awal tak berubah; begitu disentuh
  /// sekali, tersimpan independen spt field lainnya.
  void _muatMarginIndependen(Map<String, dynamic>? data) {
    _marginHorizontalMm =
        ((data?['marginHorizontalMm'] as num?)?.toDouble() ?? _marginKotakMm)
            .clamp(0, 8)
            .toDouble();
    _marginVerticalMm =
        ((data?['marginVerticalMm'] as num?)?.toDouble() ?? _marginKotakMm)
            .clamp(0, 8)
            .toDouble();
  }

  Future<void> _simpanPengaturanModel(ModelPriceTag model) async {
    await PengaturanPriceTag.instance.simpan(
      model.name,
      _snapshotPengaturan(model),
    );
  }

  void _jadwalkanSimpanPengaturan() {
    final model = _model;
    _debounceSimpanPengaturan?.cancel();
    _debounceSimpanPengaturan = Timer(
      const Duration(milliseconds: 500),
      () => unawaited(_simpanPengaturanModel(model)),
    );
  }

  void _ubahModel(ModelPriceTag model) {
    setStateIfMounted(() {
      _model = model;
      _terapkanPengaturanModel(model);
    });
    if (model == ModelPriceTag.promo) {
      unawaited(_muatProdukPromoJikaPerlu());
    }
    unawaited(_simpanPengaturanModel(model));
  }

  void _ubahCopies(int nilai) {
    final normal = nilai.clamp(1, 999).toInt();
    setStateIfMounted(() {
      _copies = normal;
      _controllerCopies.text = normal.toString();
      _controllerCopies.selection =
          TextSelection.collapsed(offset: _controllerCopies.text.length);
    });
  }

  int _salinanProduk(int id) =>
      (_salinanPerProduk[id] ?? _copies).clamp(1, 999);

  TextEditingController _controllerSalinanProduk(int id) {
    return _controllerSalinanItem.putIfAbsent(
      id,
      () => TextEditingController(text: _salinanProduk(id).toString()),
    );
  }

  void _ubahSalinanProduk(int id, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) return;
    setStateIfMounted(() => _salinanPerProduk[id] = parsed.clamp(1, 999));
  }

  int get _totalTagTerpilih {
    if (!_salinanBerbedaPerProduk) return _idTerpilih.length * _copies;
    var total = 0;
    for (final id in _idTerpilih) {
      total += _salinanProduk(id);
    }
    return total;
  }

  void _pilihSemua(bool centang) {
    setStateIfMounted(() {
      if (centang) {
        _idTerpilih.addAll(_terfilter.map((p) => p['id'] as int));
      } else {
        for (final p in _terfilter) {
          _idTerpilih.remove(p['id'] as int);
        }
      }
    });
  }

  Future<void> _cetak() async {
    final terpilih = _semuaProduk
        .where((p) => _idTerpilih.contains(p['id'] as int))
        .toList();
    if (terpilih.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih minimal satu produk.')));
      return;
    }
    if (!_salinanBerbedaPerProduk) {
      _ubahCopies(int.tryParse(_controllerCopies.text) ?? _copies);
    }
    setStateIfMounted(() => _memproses = true);
    try {
      final semuaTag = <Map<String, dynamic>>[];
      for (final p in terpilih) {
        final id = _idProduk(p);
        final jumlah = _salinanBerbedaPerProduk ? _salinanProduk(id) : _copies;
        for (var i = 0; i < jumlah; i++) {
          semuaTag.add(p);
        }
      }
      final logoBytes = await _muatLogoBytes();
      final builder = _PriceTagPdfBuilder(
        model: _model,
        ukuran: _ukuranAktif,
        kertasCetak: _kertasCetak,
        lebarRollMm: _lebarRollAktif.lebarMm,
        tag: semuaTag,
        tampilBarcode: _tampilBarcode,
        tampilKode: _tampilKode,
        tampilBarcodeTeks: _tampilBarcodeTeks,
        tampilTanggalCetak: _tampilTanggalCetak,
        tanggalCetakText: _tanggalCetakText,
        tampilToko: _tampilToko,
        tampilHargaProduk: _tampilHargaProduk,
        promo: _controllerPromo.text.trim(),
        tokoNama: Sesi.instance.tokoNama,
        logoBytes: _tampilLogo ? logoBytes : null,
        rakHeaderText: _teksRakHeader,
        rakProdukText: _controllerRakProduk.text.trim(),
        rakHargaText: _controllerRakHarga.text.trim(),
        rakHeaderBgHex: _hexPdf(_controllerRakHeaderBg, '#505B54'),
        rakHeaderTextHex: _hexPdf(_controllerRakHeaderText, '#FFFFFF'),
        rakStripBgHex: _hexPdf(_controllerRakStripBg, '#E6B742'),
        rakStripTextHex: _hexPdf(_controllerRakStripText, '#111827'),
        rakKodeTextHex: _hexPdf(_controllerRakKodeText, '#4D403C'),
        rakBodyBgHex: _hexPdf(_controllerRakBodyBg, '#FFFFFF'),
        rakHargaTextHex: _hexPdf(_controllerRakHargaText, '#514B4B'),
        promoTeksPerProduk: Map<int, String>.from(_promoTeksPerProduk),
        promoHargaAsliPerProduk:
            Map<int, String>.from(_promoHargaAsliPerProduk),
        promoHargaPromoPerProduk:
            Map<int, String>.from(_promoHargaPromoPerProduk),
        promoMasaPerProduk: Map<int, String>.from(_promoMasaPerProduk),
        promoHeaderBgHex: _hexPdf(_controllerPromoHeaderBg, '#64605A'),
        promoHeaderTextHex: _hexPdf(_controllerPromoHeaderText, '#FFFFFF'),
        promoStripBgHex: _hexPdf(_controllerPromoStripBg, '#E7B640'),
        promoStripTextHex: _hexPdf(_controllerPromoStripText, '#111827'),
        promoHargaAsliTextHex:
            _hexPdf(_controllerPromoHargaAsliText, '#C62828'),
        promoBodyBgHex: _hexPdf(_controllerPromoBodyBg, '#FFFFFF'),
        promoHargaTextHex: _hexPdf(_controllerPromoHargaText, '#5F5555'),
        bungkusLogo: _bungkusLogo,
        logoWrapBgHex: _hexPdf(_controllerLogoWrapBg, '#FFFFFF'),
        marginHorizontalMm: _marginHorizontalAktifMm,
        marginVerticalMm: _marginVerticalAktifMm,
        rakHeaderSize: _ukuranTeks(_controllerRakHeaderSize, 8),
        rakProdukSize: _ukuranTeks(_controllerRakProdukSize, 5.8),
        rakKodeSize: _ukuranTeks(_controllerRakKodeSize, 7),
        rakHargaSize: _ukuranTeks(_controllerRakHargaSize, 20),
        promoHeaderSize: _ukuranTeks(_controllerPromoHeaderSize, 20),
        promoTokoSize: _ukuranTeks(_controllerPromoTokoSize, 9),
        promoProdukSize: _ukuranTeks(_controllerPromoProdukSize, 7.5),
        promoHargaAsliSize: _ukuranTeks(_controllerPromoHargaAsliSize, 7.5),
        promoHargaSize: _ukuranTeks(_controllerPromoHargaSize, 47),
        promoKodeSize: _ukuranTeks(_controllerPromoKodeSize, 7),
        rakHeaderTinggiMm:
            _tinggiOpsional(_controllerRakHeaderTinggi, _rakHeaderTinggiAutoMm),
        rakStripTinggiMm:
            _tinggiOpsional(_controllerRakStripTinggi, _rakStripTinggiAutoMm),
        promoHeaderTinggiPt: _tinggiOpsional(
            _controllerPromoHeaderTinggi, _promoHeaderTinggiAutoPt),
        promoStripTinggiPt: _tinggiOpsional(
            _controllerPromoStripTinggi, _promoStripTinggiAutoPt),
      );
      final bytes = await builder.bangun();
      if (!mounted) return;
      await Printing.layoutPdf(
        format: _formatKertasPdfAktif,
        dynamicLayout: false,
        onLayout: (_) async => bytes,
        name: 'price-tag.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  Future<Uint8List?> _muatLogoBytes() async {
    if (!_tampilLogo || _model == ModelPriceTag.produk) return null;
    final path = _logoPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    }
    if (AppVariant.logoAsset.isEmpty) return null;
    final data = await rootBundle.load(AppVariant.logoAsset);
    return data.buffer.asUint8List();
  }

  Color _warnaRak(TextEditingController controller, Color fallback) {
    final normalized = _normalisasiHex(controller.text);
    if (normalized == null) return fallback;
    final hex = normalized.substring(1);
    final value = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
    return value == null ? fallback : Color(value);
  }

  String _hexPdf(TextEditingController controller, String fallback) {
    return _normalisasiHex(controller.text) ?? fallback;
  }

  /// Baca ukuran teks (pt, dipakai PDF) dari [controller] -- input kosong/
  /// tidak valid fallback ke [fallback] (bukan error) supaya field boleh
  /// dikosongkan pengguna tanpa merusak cetakan. Di-clamp [min]/[max] supaya
  /// salah ketik (mis. "800") tidak menghasilkan tag tak terbaca/pecah layout.
  double _ukuranTeks(
    TextEditingController controller,
    double fallback, {
    double min = 2,
    double max = 120,
  }) {
    final normalized = controller.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalized) ?? fallback;
    return parsed.clamp(min, max).toDouble();
  }

  /// Sama spt [_ukuranTeks] TAPI [controller] boleh KOSONG (bukan cuma
  /// invalid) -- dipakai utk tinggi Header/Strip Produk yang otomatisnya
  /// bergantung ukuran tag terpilih (beda formula per model), jadi tidak
  /// bisa diberi satu default angka tetap spt ukuran teks. Kosong = ikut
  /// [auto]; isi angka = override manual pengguna.
  double _tinggiOpsional(
    TextEditingController controller,
    double auto, {
    double min = 2,
    double max = 100,
  }) {
    final text = controller.text.trim().replaceAll(',', '.');
    if (text.isEmpty) return auto;
    final parsed = double.tryParse(text);
    if (parsed == null) return auto;
    return parsed.clamp(min, max).toDouble();
  }

  /// Formula bawaan (sebelum fitur custom tinggi ini ada) -- dipertahankan
  /// sbg fallback SUPAYA tag yang belum pernah diutak-atik pengguna tetap
  /// tampil identik spt sebelumnya, hanya sekarang bisa dioverride.
  double get _rakHeaderTinggiAutoMm => min(18.0, _ukuranAktif.tinggiMm * 0.28);
  double get _rakStripTinggiAutoMm => min(11.0, _ukuranAktif.tinggiMm * 0.2);
  double get _promoHeaderTinggiAutoPt =>
      28 * (_ukuranAktif.id == 'promo_a5' ? 1.25 : 1.0);
  double get _promoStripTinggiAutoPt =>
      17 * (_ukuranAktif.id == 'promo_a5' ? 1.25 : 1.0);

  String? _normalisasiHex(String input) {
    var value = input.trim().toUpperCase();
    if (value.isEmpty) return null;
    if (!value.startsWith('#')) value = '#$value';
    final hex = value.substring(1);
    final valid = RegExp(r'^[0-9A-F]{6}([0-9A-F]{2})?$').hasMatch(hex);
    return valid ? value : null;
  }

  String get _teksRakHeader {
    final custom = _controllerRakHeader.text.trim();
    if (custom.isNotEmpty) return custom;
    final toko = Sesi.instance.tokoNama.trim();
    if (toko.isNotEmpty) return toko.toLowerCase();
    return AppVariant.namaAplikasi.toLowerCase();
  }

  String _teksRakProduk(String nama) {
    final custom = _controllerRakProduk.text.trim();
    return custom.isNotEmpty ? custom : nama.toUpperCase();
  }

  String _teksRakHarga(String harga) {
    final custom = _controllerRakHarga.text.trim();
    return custom.isNotEmpty ? custom : harga.replaceFirst('Rp ', 'Rp. ');
  }

  String get _tanggalCetakText =>
      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

  int _idProduk(Map<String, dynamic> p) => (p['id'] as num?)?.toInt() ?? -1;

  String _teksPromoUntuk(Map<String, dynamic> p) {
    final custom = _promoTeksPerProduk[_idProduk(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final global = _controllerPromo.text.trim();
    return global.isEmpty ? 'PROMO' : global;
  }

  String? _hargaAsliPromoUntuk(Map<String, dynamic> p) {
    final id = _idProduk(p);
    final custom = _promoHargaAsliPerProduk[id]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final defaultPromo = _promoHargaAsliDefaultPerProduk[id]?.trim();
    if (defaultPromo != null && defaultPromo.isNotEmpty) return defaultPromo;
    return _formatRupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  String _hargaPromoUntuk(Map<String, dynamic> p) {
    final id = _idProduk(p);
    final custom = _promoHargaPromoPerProduk[id]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final defaultPromo = _promoHargaPromoDefaultPerProduk[id]?.trim();
    if (defaultPromo != null && defaultPromo.isNotEmpty) return defaultPromo;
    final hargaPromo = p['hargaPromoTag'];
    if (hargaPromo is num) {
      return _formatRupiah(hargaPromo).replaceFirst('Rp ', 'Rp. ');
    }
    return _formatRupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  String? _masaPromoUntuk(Map<String, dynamic> p) {
    final custom = _promoMasaPerProduk[_idProduk(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final value =
        '${p['masaPromoTag'] ?? p['masaPromo'] ?? p['masa_promo'] ?? ''}'
            .trim();
    return value.isEmpty ? null : value;
  }

  TextEditingController _controllerPromoManual(
    int id,
    String field,
    String initialValue,
  ) {
    final key = '$id-$field';
    final controller = _controllerPromoItem.putIfAbsent(
      key,
      () => TextEditingController(text: initialValue),
    );
    if (controller.text.isEmpty && initialValue.isNotEmpty) {
      controller.text = initialValue;
    }
    return controller;
  }

  List<Map<String, dynamic>> get _produkPromoEditor {
    final dipilih =
        _produkSumberModel.where((p) => _idTerpilih.contains(_idProduk(p)));
    final daftar = dipilih.take(8).toList();
    if (daftar.isNotEmpty) return daftar;
    final preview = _produkPreview;
    return preview == null ? [] : [preview];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(
        title: const Text('Cetak Price Tag'),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Gagal memuat: $_pesanError'),
                  AppDetailGalatOpsional(detail: detailUntuk(_pesanError)),
                ]))
              : Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _panelDaftarProduk()),
                          const VerticalDivider(width: 1),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _panelOpsi(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _barCetak(),
                  ],
                ),
    );
  }

  Widget _barCetak() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _salinanBerbedaPerProduk
                    ? '${_idTerpilih.length} produk dipilih - $_totalTagTerpilih tag - ${_ukuranAktif.label}'
                    : '${_idTerpilih.length} produk dipilih - $_copies salinan - ${_ukuranAktif.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            SizedBox(
              height: 38,
              child: ElevatedButton.icon(
                onPressed: _memproses ? null : _cetak,
                icon: _memproses
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.print, size: 18),
                label: Text('Cetak (${_idTerpilih.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ubahKategoriProduk(String? key) {
    setStateIfMounted(() {
      _kategoriTerpilihKey = key;
      if (key != null) {
        final ids = _produkSumberModel
            .where((p) => _kategoriKeyProduk(p) == key)
            .map(_idProduk)
            .where((id) => id > 0);
        _idTerpilih
          ..clear()
          ..addAll(ids);
      }
    });
  }

  Widget _filterKategoriProduk() {
    final kategori = _daftarKategoriProduk;
    final selectedValid = _kategoriTerpilihKey == null ||
        kategori.any((k) => k.key == _kategoriTerpilihKey);
    final value = selectedValid ? _kategoriTerpilihKey : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DropdownButtonFormField<String?>(
        value: value,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Kategori Barang',
          helperText: 'Pilih kategori untuk otomatis memilih semua itemnya.',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Semua Kategori'),
          ),
          ...kategori.map((k) => DropdownMenuItem<String?>(
                value: k.key,
                child: Text('${k.label} (${k.jumlah})'),
              )),
        ],
        onChanged: _ubahKategoriProduk,
      ),
    );
  }

  Widget _fieldSalinanItem(int id) {
    return SizedBox(
      width: 74,
      child: TextField(
        controller: _controllerSalinanProduk(id),
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Salinan',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (v) => _ubahSalinanProduk(id, v),
        onSubmitted: (v) => _ubahSalinanProduk(id, v),
      ),
    );
  }

  Widget _headerTabelProduk(
    List<Map<String, dynamic>> terfilter,
    bool semuaTercentang,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        border: Border(
          top: BorderSide(color: AppColors.border),
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          _selTabelHeader('Produk', flex: 4),
          _selTabelHeader('Kode', flex: 2),
          _selTabelHeader('Kategori', flex: 2),
          _selTabelHeader('Harga', flex: 2, align: TextAlign.right),
          if (_salinanBerbedaPerProduk)
            const SizedBox(
              width: 86,
              child: Text(
                'SALINAN',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          SizedBox(
            width: 48,
            child: Tooltip(
              message: 'Pilih Semua (${terfilter.length})',
              child: Checkbox(
                value: semuaTercentang,
                onChanged: (v) => _pilihSemua(v ?? false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selTabelHeader(
    String label, {
    int flex = 1,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _selTabelTeks(
    String value, {
    int flex = 1,
    TextAlign align = TextAlign.left,
    TextStyle? style,
    int maxLines = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: align,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style ?? const TextStyle(fontSize: 12.5),
      ),
    );
  }

  Widget _barisTabelProduk(Map<String, dynamic> p, int index) {
    final id = _idProduk(p);
    final terpilih = _idTerpilih.contains(id);
    final bg = terpilih
        ? AppColors.primary.withValues(alpha: 0.06)
        : (index.isOdd
            ? AppColors.pageBg.withValues(alpha: 0.55)
            : Colors.white);
    final nama = p['nama'] as String? ?? '-';
    final kode = '${p['kode'] ?? '-'}';
    final kategori = _labelKategoriProduk(p);
    final harga = _formatRupiah(p['hargaJual'] as num?);

    return InkWell(
      onTap: () => setStateIfMounted(() {
        if (terpilih) {
          _idTerpilih.remove(id);
        } else {
          _idTerpilih.add(id);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            _selTabelTeks(
              nama,
              flex: 4,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: terpilih ? FontWeight.w700 : FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            _selTabelTeks(
              kode,
              flex: 2,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
            _selTabelTeks(
              kategori,
              flex: 2,
              style: const TextStyle(fontSize: 12.5),
            ),
            _selTabelTeks(
              harga,
              flex: 2,
              align: TextAlign.right,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
            if (_salinanBerbedaPerProduk)
              SizedBox(
                width: 86,
                child: terpilih
                    ? Align(
                        alignment: Alignment.center,
                        child: _fieldSalinanItem(id),
                      )
                    : const SizedBox.shrink(),
              ),
            SizedBox(
              width: 48,
              child: Center(
                child: Checkbox(
                  value: terpilih,
                  onChanged: (v) => setStateIfMounted(() =>
                      v == true ? _idTerpilih.add(id) : _idTerpilih.remove(id)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelDaftarProduk() {
    final terfilter = _terfilter;
    final tampil = _daftarProdukTampil;
    final semuaTercentang = terfilter.isNotEmpty &&
        terfilter.every((p) => _idTerpilih.contains(_idProduk(p)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: AppSearchField(
            controller: _controllerCari,
            hintText: 'Cari nama/kode/barcode produk...',
            scanProduk: true,
            focusNode: _fokusCari,
            debounce: Duration.zero,
            onChanged: (_) => setStateIfMounted(() {}),
            onSubmitted: _submitCariProduk,
          ),
        ),
        _filterKategoriProduk(),
        if (_model == ModelPriceTag.promo) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: CheckboxListTile(
              value: _promoTampilkanSemuaProduk,
              onChanged: (v) => _aturPromoTampilkanSemuaProduk(v ?? false),
              title: const Text('Tampilkan semua barang'),
              subtitle:
                  const Text('Termasuk barang yang tidak terkait promo aktif.'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                if (_memuatProdukPromo)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.local_offer_outlined,
                      size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      _memuatProdukPromo
                          ? 'Memuat produk yang terhubung promo...'
                          : _pesanProdukPromo != null
                              ? 'Gagal memuat produk promo: $_pesanProdukPromo'
                              : _promoTampilkanSemuaProduk
                                  ? 'Menampilkan semua produk: ${_semuaProduk.length} - promo aktif: ${_promoProdukIds?.length ?? 0}'
                                  : 'Produk promo aktif: ${_promoProdukIds?.length ?? 0}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                    AppDetailGalatOpsional(
                        detail: detailUntuk(_pesanProdukPromo)),
                  ]),
                ),
                IconButton(
                  onPressed: _memuatProdukPromo
                      ? null
                      : () => unawaited(_muatProdukPromoJikaPerlu(paksa: true)),
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Muat ulang produk promo',
                ),
              ],
            ),
          ),
        ],
        _headerTabelProduk(terfilter, semuaTercentang),
        Expanded(
          child: tampil.isEmpty
              ? const Center(
                  child: Text(
                    'Tidak ada produk.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: tampil.length,
                  itemBuilder: (context, i) => _barisTabelProduk(tampil[i], i),
                ),
        ),
      ],
    );
  }

  Widget _panelOpsi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Model Layout',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<ModelPriceTag>(
          segments: const [
            ButtonSegment(value: ModelPriceTag.rak, label: Text('Rak')),
            ButtonSegment(value: ModelPriceTag.produk, label: Text('Produk')),
            ButtonSegment(value: ModelPriceTag.promo, label: Text('Promo')),
          ],
          selected: {_model},
          onSelectionChanged: (s) => _ubahModel(s.first),
        ),
        const SizedBox(height: 16),
        Text('Ukuran ${_model.label}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _tombolPilihUkuran(),
        ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Kertas Cetak',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              if (_kertasCetak == KertasCetak.thermal) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: _infoPrinterTsc,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.info_outline,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<KertasCetak>(
            segments: KertasCetak.values
                .map((k) => ButtonSegment(value: k, label: Text(k.label)))
                .toList(),
            selected: {_kertasCetak},
            onSelectionChanged: (s) {
              setStateIfMounted(() => _kertasCetak = s.first);
              unawaited(_simpanPengaturanModel(_model));
            },
          ),
          const SizedBox(height: 4),
          Text(
            _kertasCetak == KertasCetak.thermal
                ? 'Tag ditata berjajar melintasi lebar roll, tinggi halaman menyesuaikan jumlah tag (roll maju terus).'
                : 'Tag ditata berjajar (grid) di atas kertas ${_kertasCetak.label}.',
            style:
                const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          if (_kertasCetak == KertasCetak.thermal) ...[
            const SizedBox(height: 12),
            const Text('Lebar Roll',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _daftarLebarRoll
                  .map((r) => ChoiceChip(
                        label: Text(r.populer ? '${r.label} ⭐' : r.label),
                        selected: _lebarRollId == r.id,
                        onSelected: (_) {
                          setStateIfMounted(() => _lebarRollId = r.id);
                          unawaited(_simpanPengaturanModel(_model));
                        },
                      ))
                  .toList(),
            ),
            if (_lebarRollAktif.lebarMm < _ukuranAktif.lebarMm) ...[
              const SizedBox(height: 6),
              Text(
                'Lebar roll (${_lebarRollAktif.lebarMm.toStringAsFixed(0)} mm) lebih sempit dari ukuran tag (${_ukuranAktif.lebarMm.toStringAsFixed(0)} mm) -- tag akan terpotong. Pilih roll yang lebih lebar atau ukuran tag yang lebih sempit.',
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ],
          ],
        ],
        if (_modelBolehMarginIndependen) ...[
          const SizedBox(height: 16),
          const Text('Margin Antar Kotak',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Atur horizontal & vertikal terpisah supaya grid label bisa '
            'disesuaikan langsung dgn ketersediaan kertas/roll di lapangan. '
            'Nilai awal ikut Margin Antar Kotak di Konfigurasi, tapi '
            'perubahan di sini hanya berlaku utk ${_model.label}.',
            style:
                const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          _sliderMarginKotak(
            label: 'Horizontal',
            value: _marginHorizontalMm,
            onChanged: (v) {
              setStateIfMounted(() => _marginHorizontalMm = v);
              unawaited(_simpanPengaturanModel(_model));
            },
          ),
          _sliderMarginKotak(
            label: 'Vertikal',
            value: _marginVerticalMm,
            onChanged: (v) {
              setStateIfMounted(() => _marginVerticalMm = v);
              unawaited(_simpanPengaturanModel(_model));
            },
          ),
        ],
        const SizedBox(height: 16),
        const Text('Salinan per Produk',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _salinanBerbedaPerProduk,
          onChanged: (v) {
            setStateIfMounted(() => _salinanBerbedaPerProduk = v ?? false);
            unawaited(_simpanPengaturanModel(_model));
          },
          title: const Text('Atur salinan berbeda tiap produk'),
          subtitle: const Text(
              'Saat aktif, isi jumlah salinan dari daftar produk yang dipilih.'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (!_salinanBerbedaPerProduk)
          Row(
            children: [
              IconButton(
                onPressed: _copies > 1 ? () => _ubahCopies(_copies - 1) : null,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Kurangi salinan',
              ),
              SizedBox(
                width: 76,
                child: TextField(
                  controller: _controllerCopies,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  ),
                  onChanged: (v) {
                    final nilai = int.tryParse(v);
                    if (nilai != null && nilai > 0) {
                      setStateIfMounted(() => _copies = nilai.clamp(1, 999));
                    }
                  },
                  onSubmitted: (v) => _ubahCopies(int.tryParse(v) ?? _copies),
                ),
              ),
              IconButton(
                onPressed: () => _ubahCopies(_copies + 1),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Tambah salinan',
              ),
            ],
          )
        else
          Text(
            '$_totalTagTerpilih tag akan dicetak dari ${_idTerpilih.length} produk terpilih.',
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        const SizedBox(height: 16),
        if (_model != ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilToko,
            onChanged: (v) {
              setStateIfMounted(() => _tampilToko = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Tampilkan Nama Toko'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model != ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilLogo,
            onChanged: (v) {
              setStateIfMounted(() => _tampilLogo = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Tampilkan Logo Toko'),
            subtitle: const Text('Menggunakan logo dari Konfigurasi Price Tag'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model != ModelPriceTag.produk && _tampilLogo) ...[
          CheckboxListTile(
            value: _bungkusLogo,
            onChanged: (v) {
              setStateIfMounted(() => _bungkusLogo = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Bungkus Logo Dengan Warna'),
            subtitle:
                const Text('Agar logo tetap terlihat pada background gelap'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          if (_bungkusLogo)
            _fieldWarna('Warna Bungkus Logo', _controllerLogoWrapBg),
        ],
        CheckboxListTile(
          value: _tampilBarcode,
          onChanged: (v) {
            setStateIfMounted(() => _tampilBarcode = v ?? false);
            unawaited(_simpanPengaturanModel(_model));
          },
          title: const Text('Tampilkan Barcode'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          value: _tampilKode,
          onChanged: (v) {
            setStateIfMounted(() => _tampilKode = v ?? false);
            unawaited(_simpanPengaturanModel(_model));
          },
          title: const Text('Tampilkan Kode'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_model != ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilBarcodeTeks,
            onChanged: (v) {
              setStateIfMounted(() => _tampilBarcodeTeks = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Tampilkan Barcode dalam Teks'),
            subtitle: const Text(
                'Barcode produk sbg teks; kosong = pakai Kode Produk'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model != ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilTanggalCetak,
            onChanged: (v) {
              setStateIfMounted(() => _tampilTanggalCetak = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Tampilkan Tanggal Cetak'),
            subtitle: const Text('Ditampilkan kecil di pojok kiri bawah'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model == ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilHargaProduk,
            onChanged: (v) {
              setStateIfMounted(() => _tampilHargaProduk = v ?? false);
              unawaited(_simpanPengaturanModel(_model));
            },
            title: const Text('Tampilkan Harga'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model == ModelPriceTag.promo) _opsiPromoKustom(),
        if (_model == ModelPriceTag.rak) _opsiRakKustom(),
        const SizedBox(height: 18),
        _previewTag(),
      ],
    );
  }

  Widget _opsiRakKustom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text('Kustom Price Tag Rak',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _fieldKustomRak(
          'Teks Header',
          _controllerRakHeader,
          'Kosong = nama toko',
        ),
        _fieldKustomRak(
          'Teks Nama Produk',
          _controllerRakProduk,
          'Kosong = nama produk',
        ),
        _fieldKustomRak(
          'Teks Harga',
          _controllerRakHarga,
          'Kosong = harga produk',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldWarna('Header', _controllerRakHeaderBg),
            _fieldWarna('Teks Header', _controllerRakHeaderText),
            _fieldWarna('Strip Produk', _controllerRakStripBg),
            _fieldWarna('Teks Produk', _controllerRakStripText),
            _fieldWarna('Teks Kode', _controllerRakKodeText),
            _fieldWarna('Latar Harga', _controllerRakBodyBg),
            _fieldWarna('Teks Harga', _controllerRakHargaText),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Ukuran Teks (pt, default = ukuran saat ini)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldUkuranTeks('Header', _controllerRakHeaderSize),
            _fieldUkuranTeks('Nama Produk', _controllerRakProdukSize),
            _fieldUkuranTeks('Kode', _controllerRakKodeSize),
            _fieldUkuranTeks('Harga', _controllerRakHargaSize),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Tinggi Kotak (mm, kosong = otomatis ikut ukuran tag)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldTinggiKotak('Header', _controllerRakHeaderTinggi,
                satuan: 'mm', otomatis: _rakHeaderTinggiAutoMm),
            _fieldTinggiKotak('Strip Produk', _controllerRakStripTinggi,
                satuan: 'mm', otomatis: _rakStripTinggiAutoMm),
          ],
        ),
      ],
    );
  }

  Widget _fieldTinggiKotak(
    String label,
    TextEditingController controller, {
    required String satuan,
    required double otomatis,
  }) {
    return SizedBox(
      width: 168,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Otomatis (${otomatis.toStringAsFixed(1)})',
          suffixText: satuan,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setStateIfMounted(() {}),
      ),
    );
  }

  Widget _sliderMarginKotak({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final nilai = value.clamp(0, 8).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Slider(
            value: nilai,
            min: 0,
            max: 8,
            divisions: 80,
            label: '${nilai.toStringAsFixed(1)} mm',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text('${nilai.toStringAsFixed(1)} mm',
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _fieldUkuranTeks(String label, TextEditingController controller) {
    return SizedBox(
      width: 128,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'pt',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setStateIfMounted(() {}),
      ),
    );
  }

  Widget _fieldKustomRak(
    String label,
    TextEditingController controller,
    String hint,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setStateIfMounted(() {}),
      ),
    );
  }

  Widget _fieldWarna(String label, TextEditingController controller) {
    final warna = _warnaRak(controller, Colors.transparent);
    return SizedBox(
      width: 168,
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(8),
            child: InkWell(
              onTap: () => _pilihWarna(controller),
              borderRadius: BorderRadius.circular(6),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: warna,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SizedBox(width: 22, height: 22),
              ),
            ),
          ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setStateIfMounted(() {}),
      ),
    );
  }

  Widget _opsiPromoKustom() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text('Kustom Promo Tag',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _fieldKustomRak(
          'Teks Promo Default',
          _controllerPromo,
          'mis. PROMO/DISKON/HEMAT',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldWarna('Header Promo', _controllerPromoHeaderBg),
            _fieldWarna('Teks Header', _controllerPromoHeaderText),
            _fieldWarna('Strip Produk', _controllerPromoStripBg),
            _fieldWarna('Teks Produk', _controllerPromoStripText),
            _fieldWarna('Harga Coret', _controllerPromoHargaAsliText),
            _fieldWarna('Latar Harga', _controllerPromoBodyBg),
            _fieldWarna('Harga Promo', _controllerPromoHargaText),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Ukuran Teks (pt, default = ukuran saat ini)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldUkuranTeks('Judul Promo', _controllerPromoHeaderSize),
            _fieldUkuranTeks('Nama Toko', _controllerPromoTokoSize),
            _fieldUkuranTeks('Nama Produk', _controllerPromoProdukSize),
            _fieldUkuranTeks('Harga Coret', _controllerPromoHargaAsliSize),
            _fieldUkuranTeks('Harga Promo', _controllerPromoHargaSize),
            _fieldUkuranTeks('Kode', _controllerPromoKodeSize),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Tinggi Kotak (pt, kosong = otomatis ikut ukuran kertas)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _fieldTinggiKotak('Header', _controllerPromoHeaderTinggi,
                satuan: 'pt', otomatis: _promoHeaderTinggiAutoPt),
            _fieldTinggiKotak('Strip Produk', _controllerPromoStripTinggi,
                satuan: 'pt', otomatis: _promoStripTinggiAutoPt),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Teks Manual per Item',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ..._produkPromoEditor.map(_editorPromoProduk),
      ],
    );
  }

  Widget _editorPromoProduk(Map<String, dynamic> p) {
    final id = _idProduk(p);
    final nama = '${p['nama'] ?? '-'}';
    final masaPromo = _masaPromoUntuk(p);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (masaPromo != null) ...[
            const SizedBox(height: 4),
            Text('Masa Promo: $masaPromo',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 8),
          _fieldPromoItem(
            label: 'Teks Promo',
            controller: _controllerPromoManual(
              id,
              'teks',
              _promoTeksPerProduk[id] ?? '',
            ),
            hint: _controllerPromo.text.trim().isEmpty
                ? 'PROMO'
                : _controllerPromo.text.trim(),
            onChanged: (v) => _promoTeksPerProduk[id] = v,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _fieldPromoItem(
                  label: 'Harga Asli Coret',
                  controller: _controllerPromoManual(
                    id,
                    'hargaAsli',
                    _promoHargaAsliPerProduk[id] ??
                        _hargaAsliPromoUntuk(p) ??
                        '',
                  ),
                  hint: _hargaAsliPromoUntuk(p) ?? 'Opsional',
                  onChanged: (v) => _promoHargaAsliPerProduk[id] = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _fieldPromoItem(
                  label: 'Harga Promo',
                  controller: _controllerPromoManual(
                    id,
                    'hargaPromo',
                    _promoHargaPromoPerProduk[id] ?? _hargaPromoUntuk(p),
                  ),
                  hint: _hargaPromoUntuk(p),
                  onChanged: (v) => _promoHargaPromoPerProduk[id] = v,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldPromoItem({
    required String label,
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        onChanged(v);
        setStateIfMounted(() {});
      },
    );
  }

  Future<void> _pilihWarna(TextEditingController controller) async {
    final pilihan = <Color>[
      Colors.white,
      Colors.black,
      const Color(0xFF505B54),
      const Color(0xFF64605A),
      const Color(0xFFE6B742),
      const Color(0xFFE7B640),
      const Color(0xFF5F5555),
      const Color(0xFF514B4B),
      const Color(0xFFC62828),
      AppColors.primary,
      AppColors.danger,
      Colors.green.shade700,
      Colors.blueGrey.shade700,
      Colors.orange.shade700,
    ];
    final warna = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pilih Warna'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: pilihan
              .map((c) => InkWell(
                    onTap: () => Navigator.pop(context, c),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
    if (warna == null) return;
    controller.text = _colorToHex(warna);
    setStateIfMounted(() {});
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    final value = (r << 16) | (g << 8) | b;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Widget _previewTag() {
    final produk = _produkPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preview', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: produk == null
              ? const Text('Pilih produk untuk melihat preview.')
              : Center(child: _previewIsi(produk)),
        ),
        const SizedBox(height: 14),
        const Text('Preview Kertas Cetak',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: produk == null
              ? const Text('Pilih produk untuk melihat preview kertas.')
              : _previewKertas(produk),
        ),
      ],
    );
  }

  Widget _previewKertas(Map<String, dynamic> produk) {
    final paperWidth = _lebarKertasAktifMm;
    final paperHeight = _tinggiKertasAktifMm;
    final pageLabel = _labelKertasPreviewAktif;
    final paperRatio = paperWidth / paperHeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pageLabel,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: paperRatio,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.textSecondary),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _previewIsiKertas(produk),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewIsiKertas(Map<String, dynamic> produk) {
    final ukuran = _ukuranAktif;
    // Roll thermal: lebar tetap (mengikuti lebar roll dipilih), tinggi
    // representatif beberapa baris saja (roll sungguhan maju terus-menerus,
    // tidak dibatasi tinggi tetap spt A4/F4 -- lihat [_isiGridLabel] utk
    // logika PDF sesungguhnya). A4/F4 dikurangi [_marginCetakAmanMm] di
    // kedua sisi supaya jumlah kolom/baris preview ini SAMA dgn PDF
    // sesungguhnya (yang jg sudah pakai margin aman itu, bukan 0).
    final lebarKertas = _kertasCetak == KertasCetak.thermal
        ? _lebarKertasAktifMm
        : _lebarKertasAktifMm - 2 * _marginCetakAmanMm;
    final tinggiKertas = _kertasCetak == KertasCetak.thermal
        ? _tinggiKertasAktifMm
        : _tinggiKertasAktifMm - 2 * _marginCetakAmanMm;
    // Pakai margin H/V sungguhan (bukan hardcode) supaya preview ini benar-
    // benar mencerminkan slider Margin Antar Kotak -- kalau tidak, user
    // menggeser slider tapi preview-nya diam saja, jadi tidak berguna utk
    // menyesuaikan ke ketersediaan kertas di lapangan.
    final gutterHMm = _marginHorizontalAktifMm;
    final gutterVMm = _marginVerticalAktifMm;
    final kolom =
        max(1, (lebarKertas + gutterHMm) ~/ (ukuran.lebarMm + gutterHMm));
    final baris = _kertasCetak == KertasCetak.thermal
        ? 4
        : max(1, (tinggiKertas + gutterVMm) ~/ (ukuran.tinggiMm + gutterVMm));
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kolom,
        childAspectRatio: ukuran.lebarMm / ukuran.tinggiMm,
        crossAxisSpacing: gutterHMm,
        mainAxisSpacing: gutterVMm,
      ),
      itemCount: min(kolom * baris, 36),
      itemBuilder: (_, i) => Opacity(
        opacity: i == 0 ? 1 : 0.28,
        child: Padding(
          padding: EdgeInsets.all((min(gutterHMm, gutterVMm) / 2).clamp(0, 4)),
          child: _previewTagMini(produk),
        ),
      ),
    );
  }

  Widget _previewTagMini(Map<String, dynamic> p) {
    final nama = p['nama'] as String? ?? '-';
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final harga = _formatRupiah(p['hargaJual'] as num?);
    final bulat = _model == ModelPriceTag.produk && _ukuranAktif.bulat;
    final isi = switch (_model) {
      ModelPriceTag.produk => _previewProdukMini(nama, kode, barcode, harga),
      ModelPriceTag.promo => _previewPromo(p),
      ModelPriceTag.rak => _previewRakMini(nama, kode, barcode, harga),
    };
    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: bulat ? null : BorderRadius.circular(2),
        shape: bulat ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: bulat ? ClipOval(child: isi) : isi,
    );
  }

  Widget _previewRakMini(
      String nama, String kode, String barcode, String harga) {
    final headerBg = _warnaRak(_controllerRakHeaderBg, const Color(0xFF505B54));
    final stripBg = _warnaRak(_controllerRakStripBg, const Color(0xFFE6B742));
    final stripText =
        _warnaRak(_controllerRakStripText, const Color(0xFF111827));
    final kodeText = _warnaRak(_controllerRakKodeText, const Color(0xFF4D403C));
    final bodyBg = _warnaRak(_controllerRakBodyBg, Colors.white);
    final hargaText =
        _warnaRak(_controllerRakHargaText, const Color(0xFF514B4B));
    final produkSize = _ukuranTeks(_controllerRakProdukSize, 5.8) * (3.2 / 5.8);
    final kodeSize = _ukuranTeks(_controllerRakKodeSize, 7) * (3.2 / 7);
    final hargaSize = _ukuranTeks(_controllerRakHargaSize, 26) * (9 / 26);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 7, color: headerBg),
        Container(
          height: 5,
          color: stripBg,
          child: Row(
            children: [
              Expanded(
                child: Text(_teksRakProduk(nama),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: produkSize,
                        color: stripText,
                        fontWeight: FontWeight.w800)),
              ),
              if (_tampilKode)
                Flexible(
                  child: Text(kode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: kodeSize, color: kodeText)),
                ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: bodyBg,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_teksRakHarga(harga),
                    style: TextStyle(
                        fontSize: hargaSize,
                        color: hargaText,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          ),
        ),
        if (_tampilBarcode) _PreviewBarcode(data: barcode, height: 4),
      ],
    );
  }

  Widget _previewProdukMini(
      String nama, String kode, String barcode, String harga) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(nama,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 4.5, fontWeight: FontWeight.w800)),
        if (_tampilBarcode)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _PreviewBarcode(data: barcode, height: double.infinity),
            ),
          ),
        if (_tampilKode)
          Text(barcode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 3.8, letterSpacing: 0.6)),
        if (_tampilHargaProduk)
          Text(harga,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 4.2, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _previewIsi(Map<String, dynamic> p) {
    final ukuran = _ukuranAktif;
    final ratio = ukuran.lebarMm / ukuran.tinggiMm;
    final nama = p['nama'] as String? ?? '-';
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final harga = _formatRupiah(p['hargaJual'] as num?);

    final maxWidth = switch (_model) {
      ModelPriceTag.rak => 380.0,
      ModelPriceTag.produk => 320.0,
      ModelPriceTag.promo => 520.0,
    };
    final bulat = _model == ModelPriceTag.produk && ukuran.bulat;
    final isi = _model == ModelPriceTag.produk
        ? _previewProduk(nama, kode, barcode, harga)
        : _model == ModelPriceTag.promo
            ? _previewPromo(p)
            : _previewRak(nama, kode, barcode, harga);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Container(
          padding: EdgeInsets.all(_model == ModelPriceTag.rak
              ? 0
              : _model == ModelPriceTag.produk
                  ? 4
                  : 7),
          decoration: BoxDecoration(
            color: _model == ModelPriceTag.promo
                ? const Color(0xFFFFF3D6)
                : Colors.white,
            border: Border.all(
                color: _model == ModelPriceTag.rak
                    ? AppColors.textSecondary
                    : AppColors.primary,
                style: _model == ModelPriceTag.rak
                    ? BorderStyle.solid
                    : BorderStyle.solid),
            borderRadius: bulat
                ? null
                : BorderRadius.circular(_model == ModelPriceTag.produk ? 4 : 8),
            shape: bulat ? BoxShape.circle : BoxShape.rectangle,
          ),
          child: bulat ? ClipOval(child: isi) : isi,
        ),
      ),
    );
  }

  Widget _previewRak(String nama, String kode, String barcode, String harga) {
    final headerBg = _warnaRak(_controllerRakHeaderBg, const Color(0xFF505B54));
    final headerText = _warnaRak(_controllerRakHeaderText, Colors.white);
    final stripBg = _warnaRak(_controllerRakStripBg, const Color(0xFFE6B742));
    final stripText =
        _warnaRak(_controllerRakStripText, const Color(0xFF111827));
    final kodeText = _warnaRak(_controllerRakKodeText, const Color(0xFF4D403C));
    final bodyBg = _warnaRak(_controllerRakBodyBg, Colors.white);
    final hargaText =
        _warnaRak(_controllerRakHargaText, const Color(0xFF514B4B));
    final produkSize = _ukuranTeks(_controllerRakProdukSize, 5.8) * (12 / 5.8);
    final kodeSize = _ukuranTeks(_controllerRakKodeSize, 7) * 2;
    final hargaSize = _ukuranTeks(_controllerRakHargaSize, 26) * (42 / 26);
    // Proporsi header:strip:body preview mengikuti tinggi (mm) yang SAMA
    // dgn hasil cetak PDF (bukan flex tetap spt sebelumnya) -- supaya
    // custom tinggi Header/Strip Produk kelihatan efeknya di preview juga.
    final headerMm =
        _tinggiOpsional(_controllerRakHeaderTinggi, _rakHeaderTinggiAutoMm);
    final stripMm =
        _tinggiOpsional(_controllerRakStripTinggi, _rakStripTinggiAutoMm);
    final bodyMm =
        (_ukuranAktif.tinggiMm - headerMm - stripMm).clamp(2.0, 999.0);
    final flexHeader = (headerMm * 10).round().clamp(1, 999999);
    final flexStrip = (stripMm * 10).round().clamp(1, 999999);
    final flexBody = (bodyMm * 10).round().clamp(1, 999999);
    final tampilAreaBarcode =
        _tampilBarcode || (_tampilBarcodeTeks && barcode.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: flexHeader,
          child: Container(
            color: headerBg,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Center(
              child: _tampilLogo
                  ? _previewLogo(maxHeight: 30, bottom: 0)
                  : (_tampilToko
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_teksRakHeader,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: headerText,
                                  fontWeight: FontWeight.w900)),
                        )
                      : const SizedBox.shrink()),
            ),
          ),
        ),
        Flexible(
          flex: flexStrip,
          child: Container(
            color: stripBg,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_teksRakProduk(nama),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: produkSize,
                            color: stripText,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
                if (_tampilKode)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(kode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: kodeSize,
                                fontStyle: FontStyle.italic,
                                color: kodeText)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: flexBody,
          child: ColoredBox(
            color: bodyBg,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        8,
                        4,
                        tampilAreaBarcode ? 86 : 8,
                        _tampilTanggalCetak ? 18 : 6),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_teksRakHarga(harga),
                            style: TextStyle(
                                fontSize: hargaSize,
                                fontWeight: FontWeight.w900,
                                color: hargaText)),
                      ),
                    ),
                  ),
                ),
                if (_tampilTanggalCetak)
                  Positioned(
                    left: 6,
                    bottom: 4,
                    child: Text(_tanggalCetakText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: kodeSize * 0.45,
                            fontWeight: FontWeight.w600,
                            color: kodeText)),
                  ),
                if (tampilAreaBarcode)
                  Positioned(
                    right: 6,
                    bottom: 4,
                    width: 72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_tampilBarcode)
                          SizedBox(
                            height: 18,
                            child: _PreviewBarcode(
                                data: barcode, height: double.infinity),
                          ),
                        if ((_tampilBarcode || _tampilBarcodeTeks) &&
                            barcode.isNotEmpty)
                          Text(barcode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: kodeSize * 0.45,
                                  letterSpacing: 0.5,
                                  color: kodeText)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewProduk(
      String nama, String kode, String barcode, String harga) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(nama,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        if (_tampilBarcode)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _PreviewBarcode(data: barcode, height: double.infinity),
            ),
          )
        else
          const Spacer(),
        // Cuma SATU kode -- barcode kalau kolom Barcode produk terisi,
        // fallback ke Kode Produk kalau kosong (lihat [_kodeBarcode]).
        if (_tampilKode)
          Text(barcode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600)),
        if (_tampilHargaProduk)
          Text(harga,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary)),
      ],
    );
  }

  Widget _previewPromo(Map<String, dynamic> p) {
    final nama = p['nama'] as String? ?? '-';
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final promo = _teksPromoUntuk(p);
    final hargaLama = _hargaAsliPromoUntuk(p);
    final harga = _hargaPromoUntuk(p);
    final masaPromo = _masaPromoUntuk(p);
    final headerBg =
        _warnaRak(_controllerPromoHeaderBg, const Color(0xFF64605A));
    final headerText = _warnaRak(_controllerPromoHeaderText, Colors.white);
    final stripBg = _warnaRak(_controllerPromoStripBg, const Color(0xFFE7B640));
    final stripText =
        _warnaRak(_controllerPromoStripText, const Color(0xFF111827));
    final hargaAsliText =
        _warnaRak(_controllerPromoHargaAsliText, AppColors.danger);
    final bodyBg = _warnaRak(_controllerPromoBodyBg, Colors.white);
    final hargaText =
        _warnaRak(_controllerPromoHargaText, const Color(0xFF5F5555));
    final headerSize = _ukuranTeks(_controllerPromoHeaderSize, 20) * 1.2;
    final tokoSize = _ukuranTeks(_controllerPromoTokoSize, 9) * (12 / 9);
    final produkSize =
        _ukuranTeks(_controllerPromoProdukSize, 7.5) * (10 / 7.5);
    final hargaAsliSize =
        _ukuranTeks(_controllerPromoHargaAsliSize, 7.5) * (10 / 7.5);
    final hargaSize = _ukuranTeks(_controllerPromoHargaSize, 47) * (56 / 47);
    final kodeSize = _ukuranTeks(_controllerPromoKodeSize, 7) * (10 / 7);
    // Skala 1.5x cocok dgn tinggi bawaan lama (28pt*1.5=42px) -- custom
    // tinggi Header/Strip Produk ikut skala yang sama di preview.
    final headerTinggiPx = _tinggiOpsional(
            _controllerPromoHeaderTinggi, _promoHeaderTinggiAutoPt) *
        1.5;
    final stripTinggiPx =
        _tinggiOpsional(_controllerPromoStripTinggi, _promoStripTinggiAutoPt) *
            1.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: headerTinggiPx,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: headerBg,
          child: Row(
            children: [
              Expanded(
                child: Text(promo.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: headerText,
                        fontSize: headerSize,
                        fontWeight: FontWeight.w900)),
              ),
              if (_tampilLogo)
                Flexible(child: _previewLogo(maxHeight: 30, bottom: 0)),
              if (!_tampilLogo &&
                  _tampilToko &&
                  Sesi.instance.tokoNama.isNotEmpty)
                Flexible(
                  child: Text(Sesi.instance.tokoNama.toLowerCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: headerText,
                          fontSize: tokoSize,
                          fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
        Container(
          height: stripTinggiPx,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: stripBg,
          child: Row(
            children: [
              Expanded(
                child: Text(nama.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: stripText,
                        fontSize: produkSize,
                        fontWeight: FontWeight.w800)),
              ),
              if (hargaLama != null)
                Flexible(
                  child: Text(hargaLama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: hargaAsliSize,
                        color: hargaAsliText,
                        decoration: TextDecoration.lineThrough,
                        fontWeight: FontWeight.w700,
                      )),
                ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: bodyBg,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(harga,
                    style: TextStyle(
                        fontSize: hargaSize,
                        fontWeight: FontWeight.w900,
                        color: hargaText)),
              ),
            ),
          ),
        ),
        if (masaPromo != null)
          ColoredBox(
            color: bodyBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(masaPromo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: kodeSize,
                      fontWeight: FontWeight.w700,
                      color: stripText)),
            ),
          ),
        if (_tampilTanggalCetak)
          ColoredBox(
            color: bodyBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_tanggalCetakText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: kodeSize * 0.8,
                        fontWeight: FontWeight.w600,
                        color: stripText)),
              ),
            ),
          ),
        if (_tampilBarcode)
          ColoredBox(
            color: bodyBg,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _PreviewBarcode(data: barcode, height: 18),
            ),
          ),
        if (_tampilBarcodeTeks && barcode.isNotEmpty)
          ColoredBox(
            color: bodyBg,
            child: Center(
                child: Text(barcode,
                    style: TextStyle(fontSize: kodeSize, letterSpacing: 1))),
          ),
        if (_tampilKode)
          ColoredBox(
            color: bodyBg,
            child:
                Center(child: Text(kode, style: TextStyle(fontSize: kodeSize))),
          ),
      ],
    );
  }

  Widget _previewLogo({required double maxHeight, double bottom = 4}) {
    final path = _logoPath;
    if (path == null && AppVariant.logoAsset.isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget logo = path != null
        ? Image.file(File(path), fit: BoxFit.contain)
        : Image.asset(AppVariant.logoAsset, fit: BoxFit.contain);
    final child = SizedBox(height: maxHeight, child: logo);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: _bungkusLogo
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: _warnaRak(_controllerLogoWrapBg, Colors.white),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: child,
              ),
            )
          : child,
    );
  }
}

class _PreviewBarcode extends StatelessWidget {
  final String data;
  final double height;
  const _PreviewBarcode({required this.data, required this.height});

  @override
  Widget build(BuildContext context) {
    final bars = max(18, min(42, data.length * 3));
    final barcode = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(bars, (i) {
        final wide = (i + data.length) % 5 == 0 || i % 7 == 0;
        return Container(
          width: wide ? 2 : 1,
          margin: const EdgeInsets.symmetric(horizontal: 0.7),
          color: i.isEven || wide ? Colors.black87 : Colors.transparent,
        );
      }),
    );
    // Row(stretch) diberi tinggi TEGAS dulu (bukan langsung infinite) supaya
    // selalu punya batas jelas utk mengukur diri, baru FittedBox di luar
    // menyusutkannya ke ruang yang BENAR-BENAR tersedia (lebar box tag +
    // tinggi sisa setelah header/strip/harga) -- mencegah barcode melebar
    // keluar garis tepi tag (lebar sebelumnya sama sekali tak dibatasi)
    // ATAUPUN terpotong di bawah (tinggi sebelumnya hardcode/tetap).
    final tinggiUkur = height.isFinite ? height : 20.0;
    return SizedBox(
      width: double.infinity,
      height: height.isFinite ? height : null,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(height: tinggiUkur, child: barcode),
      ),
    );
  }
}

class _PriceTagPdfBuilder {
  final ModelPriceTag model;
  final _UkuranTag ukuran;
  final KertasCetak kertasCetak;
  final double lebarRollMm;
  final List<Map<String, dynamic>> tag;
  final bool tampilBarcode;
  final bool tampilKode;
  final bool tampilBarcodeTeks;
  final bool tampilTanggalCetak;
  final String tanggalCetakText;
  final bool tampilToko;
  final bool tampilHargaProduk;
  final String promo;
  final String tokoNama;
  final Uint8List? logoBytes;
  final String rakHeaderText;
  final String rakProdukText;
  final String rakHargaText;
  final String rakHeaderBgHex;
  final String rakHeaderTextHex;
  final String rakStripBgHex;
  final String rakStripTextHex;
  final String rakKodeTextHex;
  final String rakBodyBgHex;
  final String rakHargaTextHex;
  final Map<int, String> promoTeksPerProduk;
  final Map<int, String> promoHargaAsliPerProduk;
  final Map<int, String> promoHargaPromoPerProduk;
  final Map<int, String> promoMasaPerProduk;
  final String promoHeaderBgHex;
  final String promoHeaderTextHex;
  final String promoStripBgHex;
  final String promoStripTextHex;
  final String promoHargaAsliTextHex;
  final String promoBodyBgHex;
  final String promoHargaTextHex;
  final bool bungkusLogo;
  final String logoWrapBgHex;
  final double marginHorizontalMm;
  final double marginVerticalMm;
  final double rakHeaderSize;
  final double rakProdukSize;
  final double rakKodeSize;
  final double rakHargaSize;
  final double promoHeaderSize;
  final double promoTokoSize;
  final double promoProdukSize;
  final double promoHargaAsliSize;
  final double promoHargaSize;
  final double promoKodeSize;
  final double rakHeaderTinggiMm;
  final double rakStripTinggiMm;
  final double promoHeaderTinggiPt;
  final double promoStripTinggiPt;

  _PriceTagPdfBuilder({
    required this.model,
    required this.ukuran,
    required this.kertasCetak,
    required this.lebarRollMm,
    required this.tag,
    required this.tampilBarcode,
    required this.tampilKode,
    required this.tampilBarcodeTeks,
    required this.tampilTanggalCetak,
    required this.tanggalCetakText,
    required this.tampilToko,
    required this.tampilHargaProduk,
    required this.promo,
    required this.tokoNama,
    required this.logoBytes,
    required this.rakHeaderText,
    required this.rakProdukText,
    required this.rakHargaText,
    required this.rakHeaderBgHex,
    required this.rakHeaderTextHex,
    required this.rakStripBgHex,
    required this.rakStripTextHex,
    required this.rakKodeTextHex,
    required this.rakBodyBgHex,
    required this.rakHargaTextHex,
    required this.promoTeksPerProduk,
    required this.promoHargaAsliPerProduk,
    required this.promoHargaPromoPerProduk,
    required this.promoMasaPerProduk,
    required this.promoHeaderBgHex,
    required this.promoHeaderTextHex,
    required this.promoStripBgHex,
    required this.promoStripTextHex,
    required this.promoHargaAsliTextHex,
    required this.promoBodyBgHex,
    required this.promoHargaTextHex,
    required this.bungkusLogo,
    required this.logoWrapBgHex,
    required this.marginHorizontalMm,
    required this.marginVerticalMm,
    required this.rakHeaderSize,
    required this.rakProdukSize,
    required this.rakKodeSize,
    required this.rakHargaSize,
    required this.promoHeaderSize,
    required this.promoTokoSize,
    required this.promoProdukSize,
    required this.promoHargaAsliSize,
    required this.promoHargaSize,
    required this.promoKodeSize,
    required this.rakHeaderTinggiMm,
    required this.rakStripTinggiMm,
    required this.promoHeaderTinggiPt,
    required this.promoStripTinggiPt,
  });

  Future<Uint8List> bangun() async {
    final doc = pw.Document();
    switch (model) {
      case ModelPriceTag.rak:
        _isiGridLabel(doc, _kotakRak);
        break;
      case ModelPriceTag.produk:
        _isiGridLabel(doc, _kotakProduk);
        break;
      case ModelPriceTag.promo:
        _isiGridLabel(doc, _kotakPromo);
        break;
    }
    return doc.save();
  }

  String _rupiah(num? v) => _formatRupiah(v);

  /// [width] WAJIB diisi kalau widget ini akan dibungkus [pw.FittedBox]
  /// (spt di [_kotakRak]) -- `pw.BarcodeWidget` tanpa `width` eksplisit
  /// membiarkan lebarnya mengikuti constraint dari parent, dan `FittedBox`
  /// SELALU mengukur anaknya dgn constraint TAK TERBATAS (`BoxConstraints()`)
  /// utk cari ukuran alaminya -- tanpa width tetap, lebar "alami" barcode
  /// jadi `double.infinity`, yang bikin `FittedBox` menghitung rasio skala
  /// `sesuatu / Infinity` (jadi NaN) lalu `doc.save()` gagal dgn
  /// `Failed assertion: '!value.isNaN'`. Ini bukan bug spesifik ukuran tag
  /// tertentu -- SELALU terjadi begitu ada barcode di dalam FittedBox tanpa
  /// width, makanya sebelumnya tombol Cetak di Rak SELALU gagal.
  pw.Widget? _barcode(String kode, {double height = 40, double? width}) {
    if (!tampilBarcode || kode.isEmpty) return null;
    try {
      return pw.BarcodeWidget(
          barcode: bc.Barcode.code128(),
          data: kode,
          drawText: false,
          height: height,
          width: width);
    } catch (_) {
      return null;
    }
  }

  void _isiGridLabel(
    pw.Document doc,
    pw.Widget Function(Map<String, dynamic>) builder,
  ) {
    final lebar = ukuran.lebarMm * PdfPageFormat.mm;
    final tinggi = ukuran.tinggiMm * PdfPageFormat.mm;
    // Horizontal & vertikal SENGAJA independen (lihat
    // [_PriceTagScreenState._marginHorizontalAktifMm]/[_marginVerticalAktifMm])
    // supaya grid bisa disesuaikan langsung dgn ketersediaan kertas/roll di
    // lapangan (mis. roll agak sempit cukup kecilkan margin horizontal tanpa
    // ikut mengubah jarak antar baris).
    final marginH = marginHorizontalMm.clamp(0, 8).toDouble();
    final marginV = marginVerticalMm.clamp(0, 8).toDouble();
    final gutterH = marginH * PdfPageFormat.mm;
    final gutterV = marginV * PdfPageFormat.mm;
    final innerPadding = (min(marginH, marginV) * 0.25).clamp(0, 1).toDouble() *
        PdfPageFormat.mm;

    if (kertasCetak == KertasCetak.thermal) {
      // Roll thermal: LEBAR halaman tetap (mengikuti lebar roll dipilih --
      // mis. 110mm utk TSC TTP-244 Pro), tag ditata berjajar (grid) spt
      // kertas umum SUPAYA lebar roll tidak terbuang percuma kalau tag-nya
      // lebih sempit dari roll (mis. tag 50mm di roll 110mm -> 2 kolom).
      // TINGGI halaman dinamis mengikuti isi (bukan tetap spt A4) krn roll
      // maju terus-menerus -- dibatasi [maxTinggiRollMm] per halaman PDF
      // murni supaya satu job cetak tidak melebihi panjang label maksimal
      // printer thermal pada umumnya (mis. TTP-244 Pro: 2.286mm/90").
      final lebarRoll = lebarRollMm * PdfPageFormat.mm;
      final kolom = max(1, (lebarRoll + gutterH) ~/ (lebar + gutterH));
      const maxTinggiRollMm = 2000.0;
      final barisMaks = max(
          1,
          ((maxTinggiRollMm * PdfPageFormat.mm) + gutterV) ~/
              (tinggi + gutterV));
      final perHalamanMaks = kolom * barisMaks;

      for (var start = 0; start < tag.length; start += perHalamanMaks) {
        final slice = tag.skip(start).take(perHalamanMaks).toList();
        final baris = (slice.length / kolom).ceil();
        final tinggiHalaman = baris * tinggi + max(0, baris - 1) * gutterV;
        final pageRoll = PdfPageFormat(lebarRoll, tinggiHalaman, marginAll: 0);
        doc.addPage(
          pw.Page(
            pageFormat: pageRoll,
            build: (_) => pw.Wrap(
              spacing: gutterH,
              runSpacing: gutterV,
              children: slice
                  .map((p) => pw.SizedBox(
                        width: lebar,
                        height: tinggi,
                        child: pw.Padding(
                          padding: pw.EdgeInsets.all(innerPadding),
                          child: builder(p),
                        ),
                      ))
                  .toList(),
            ),
          ),
        );
      }
      return;
    }

    // Margin halaman aman (lihat JavaDoc [_marginCetakAmanMm]) -- BUKAN
    // margin 0 spt sebelumnya, supaya grid tag tak nempel ke tepi mutlak
    // kertas & tak terpotong saat dicetak langsung ke printer fisik umum.
    final marginAman = _marginCetakAmanMm * PdfPageFormat.mm;
    final basePage = model == ModelPriceTag.promo && ukuran.pageFormat != null
        ? ukuran.pageFormat!
        : (kertasCetak.pageFormat ?? PdfPageFormat.a4);
    final page = basePage.copyWith(
      marginLeft: marginAman,
      marginTop: marginAman,
      marginRight: marginAman,
      marginBottom: marginAman,
    );
    final usableWidth = page.availableWidth;
    final usableHeight = page.availableHeight;
    final kolom = max(1, (usableWidth + gutterH) ~/ (lebar + gutterH));
    final baris = max(1, (usableHeight + gutterV) ~/ (tinggi + gutterV));
    final perHalaman = max(1, kolom * baris);

    for (var start = 0; start < tag.length; start += perHalaman) {
      final slice = tag.skip(start).take(perHalaman).toList();
      doc.addPage(
        pw.Page(
          pageFormat: page,
          build: (_) => pw.Wrap(
            spacing: gutterH,
            runSpacing: gutterV,
            children: slice
                .map((p) => pw.SizedBox(
                      width: lebar,
                      height: tinggi,
                      child: pw.Padding(
                        padding: pw.EdgeInsets.all(innerPadding),
                        child: builder(p),
                      ),
                    ))
                .toList(),
          ),
        ),
      );
    }
  }

  String _teksProdukRakPdf(Map<String, dynamic> p) {
    final custom = rakProdukText.trim();
    return custom.isNotEmpty ? custom : '${p['nama'] ?? '-'}'.toUpperCase();
  }

  String _teksHargaRakPdf(Map<String, dynamic> p) {
    final custom = rakHargaText.trim();
    if (custom.isNotEmpty) return custom;
    return _rupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  pw.Widget _kotakRak(Map<String, dynamic> p) {
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    // width WAJIB diisi krn bcw dibungkus FittedBox di bawah -- lihat
    // JavaDoc [_barcode]. Nilai persisnya tidak krusial (FittedBox tetap
    // menyusutkannya proporsional ke ruang yang benar-benar tersedia),
    // cukup ikut lebar tag sbg ukuran "alami" sebelum diskalakan.
    final bcw = _barcode(barcode,
        height: min(9, ukuran.tinggiMm * 0.2),
        width: ukuran.lebarMm * PdfPageFormat.mm);
    // Area gambar+teks barcode tampil kalau salah satu toggle-nya aktif --
    // supaya user bisa pilih gambar saja, teks saja, keduanya, atau tak
    // satu pun (lihat gap-closure "Tampilkan Barcode dalam Teks"). Teks
    // pakai [barcode] yg SAMA dgn gambar (barcode asli produk, fallback ke
    // Kode Produk kalau kosong) -- BUKAN barcode mentah tanpa fallback.
    final tampilAreaBarcode =
        bcw != null || (tampilBarcodeTeks && barcode.isNotEmpty);
    final headerH = rakHeaderTinggiMm * PdfPageFormat.mm;
    final stripH = rakStripTinggiMm * PdfPageFormat.mm;
    final skala = (ukuran.tinggiMm / 30).clamp(0.7, 1.8);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey600, width: 0.7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: headerH,
            color: PdfColor.fromHex(rakHeaderBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: pw.Center(
              child: logoBytes != null
                  ? _logoPdf(headerH - 3)
                  : (tampilToko && rakHeaderText.isNotEmpty
                      ? pw.Text(rakHeaderText,
                          maxLines: 1,
                          style: pw.TextStyle(
                              fontSize: rakHeaderSize * skala,
                              color: PdfColor.fromHex(rakHeaderTextHex),
                              fontWeight: pw.FontWeight.bold))
                      : pw.SizedBox()),
            ),
          ),
          pw.Container(
            height: stripH,
            color: PdfColor.fromHex(rakStripBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 3),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(_teksProdukRakPdf(p),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: rakProdukSize * skala,
                          color: PdfColor.fromHex(rakStripTextHex),
                          fontWeight: pw.FontWeight.bold)),
                ),
                if (tampilKode)
                  pw.Flexible(
                    child: pw.Text(kode,
                        maxLines: 1,
                        style: pw.TextStyle(
                            fontSize: rakKodeSize * skala,
                            color: PdfColor.fromHex(rakKodeTextHex),
                            fontStyle: pw.FontStyle.italic)),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              color: PdfColor.fromHex(rakBodyBgHex),
              child: pw.Stack(
                children: [
                  pw.Positioned.fill(
                    child: pw.Padding(
                      padding: pw.EdgeInsets.fromLTRB(
                          4,
                          2,
                          tampilAreaBarcode ? 34 : 4,
                          tampilTanggalCetak ? 9 : 3),
                      child: pw.Center(
                        child: pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          child: pw.Text(
                            _teksHargaRakPdf(p),
                            style: pw.TextStyle(
                              fontSize: rakHargaSize * skala,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex(rakHargaTextHex),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (tampilTanggalCetak)
                    pw.Positioned(
                      left: 3,
                      bottom: 2,
                      child: pw.Text(tanggalCetakText,
                          maxLines: 1,
                          style: pw.TextStyle(
                              fontSize: rakKodeSize * skala * 0.45,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex(rakKodeTextHex))),
                    ),
                  if (tampilAreaBarcode)
                    pw.Positioned(
                      right: 3,
                      bottom: 2,
                      child: pw.SizedBox(
                        width: ukuran.lebarMm * PdfPageFormat.mm * 0.34,
                        child: bcw == null
                            ? pw.Text(barcode,
                                maxLines: 1,
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                    fontSize: rakKodeSize * skala * 0.45,
                                    letterSpacing: 0.5,
                                    color: PdfColor.fromHex(rakKodeTextHex)))
                            : pw.Column(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  if (tampilBarcode)
                                    pw.SizedBox(
                                      height: 8,
                                      child: pw.FittedBox(
                                          fit: pw.BoxFit.scaleDown, child: bcw),
                                    ),
                                  if ((tampilBarcode || tampilBarcodeTeks) &&
                                      barcode.isNotEmpty)
                                    pw.Text(barcode,
                                        maxLines: 1,
                                        textAlign: pw.TextAlign.center,
                                        style: pw.TextStyle(
                                            fontSize:
                                                rakKodeSize * skala * 0.45,
                                            letterSpacing: 0.5,
                                            color: PdfColor.fromHex(
                                                rakKodeTextHex))),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _kotakProduk(Map<String, dynamic> p) {
    final barcode = _kodeBarcode(p);
    final bcw =
        _barcode(barcode, height: ukuran.tinggiMm * PdfPageFormat.mm * 0.48);
    final skala = (ukuran.tinggiMm / 25).clamp(0.75, 1.45);
    final bulat = ukuran.bulat;
    final isi = pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('${p['nama'] ?? '-'}',
              maxLines: 1,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: 7 * skala, fontWeight: pw.FontWeight.bold)),
          if (bcw != null)
            pw.Expanded(
              child: pw.Padding(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: bcw,
              ),
            )
          else
            pw.Spacer(),
          // Cuma SATU kode -- barcode kalau kolom Barcode produk terisi,
          // fallback ke Kode Produk kalau kosong (lihat [_kodeBarcode]).
          if (tampilKode)
            pw.Text(barcode,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 6 * skala,
                    letterSpacing: 1.5,
                    fontWeight: pw.FontWeight.bold)),
          if (tampilHargaProduk)
            pw.Text(_rupiah(p['hargaJual'] as num?),
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 7.5 * skala, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
        borderRadius: bulat ? null : pw.BorderRadius.circular(2),
        shape: bulat ? pw.BoxShape.circle : pw.BoxShape.rectangle,
      ),
      child: bulat ? pw.ClipOval(child: isi) : isi,
    );
  }

  int _idProdukPdf(Map<String, dynamic> p) => (p['id'] as num?)?.toInt() ?? -1;

  String _teksPromoPdf(Map<String, dynamic> p) {
    final custom = promoTeksPerProduk[_idProdukPdf(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return promo.isEmpty ? 'PROMO' : promo;
  }

  String? _hargaAsliPromoPdf(Map<String, dynamic> p) {
    final custom = promoHargaAsliPerProduk[_idProdukPdf(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _rupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  String _hargaPromoPdf(Map<String, dynamic> p) {
    final custom = promoHargaPromoPerProduk[_idProdukPdf(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final hargaPromo = p['hargaPromoTag'];
    if (hargaPromo is num) {
      return _rupiah(hargaPromo).replaceFirst('Rp ', 'Rp. ');
    }
    return _rupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  String? _masaPromoPdf(Map<String, dynamic> p) {
    final custom = promoMasaPerProduk[_idProdukPdf(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final value =
        '${p['masaPromoTag'] ?? p['masaPromo'] ?? p['masa_promo'] ?? ''}'
            .trim();
    return value.isEmpty ? null : value;
  }

  pw.Widget _logoPdf(double height) {
    final image = pw.Image(
      pw.MemoryImage(logoBytes!),
      height: height,
      fit: pw.BoxFit.contain,
    );
    if (!bungkusLogo) return image;
    return pw.Container(
      color: PdfColor.fromHex(logoWrapBgHex),
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
      child: image,
    );
  }

  pw.Widget _kotakPromo(Map<String, dynamic> p) {
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final bcw = _barcode(barcode, height: 18);
    final teksPromo = _teksPromoPdf(p);
    final skala = ukuran.id == 'promo_a5' ? 1.25 : 1.0;
    final hargaLama = _hargaAsliPromoPdf(p);
    final masaPromo = _masaPromoPdf(p);
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex(promoBodyBgHex),
        border: pw.Border.all(color: PdfColors.grey700, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            height: promoHeaderTinggiPt * skala,
            color: PdfColor.fromHex(promoHeaderBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(teksPromo.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: promoHeaderSize * skala,
                          color: PdfColor.fromHex(promoHeaderTextHex),
                          fontWeight: pw.FontWeight.bold)),
                ),
                if (logoBytes != null)
                  pw.Flexible(child: _logoPdf(22 * skala))
                else if (tampilToko && tokoNama.isNotEmpty)
                  pw.Flexible(
                    child: pw.Text(tokoNama.toLowerCase(),
                        maxLines: 1,
                        style: pw.TextStyle(
                            fontSize: promoTokoSize * skala,
                            color: PdfColor.fromHex(promoHeaderTextHex),
                            fontWeight: pw.FontWeight.bold)),
                  ),
              ],
            ),
          ),
          pw.Container(
            height: promoStripTinggiPt * skala,
            color: PdfColor.fromHex(promoStripBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text('${p['nama'] ?? '-'}'.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: promoProdukSize * skala,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex(promoStripTextHex))),
                ),
                if (hargaLama != null)
                  pw.Flexible(
                    child: pw.Text(hargaLama,
                        style: pw.TextStyle(
                            fontSize: promoHargaAsliSize * skala,
                            color: PdfColor.fromHex(promoHargaAsliTextHex),
                            decoration: pw.TextDecoration.lineThrough)),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              child: pw.Center(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    _hargaPromoPdf(p),
                    style: pw.TextStyle(
                      fontSize: promoHargaSize * skala,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex(promoHargaTextHex),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (masaPromo != null)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: pw.Center(
                child: pw.Text(masaPromo,
                    maxLines: 1,
                    style: pw.TextStyle(
                        fontSize: promoKodeSize * skala,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex(promoStripTextHex))),
              ),
            ),
          if (tampilTanggalCetak)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(tanggalCetakText,
                    maxLines: 1,
                    style: pw.TextStyle(
                        fontSize: promoKodeSize * skala * 0.8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex(promoStripTextHex))),
              ),
            ),
          if (bcw != null)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              padding: const pw.EdgeInsets.symmetric(horizontal: 24),
              child: bcw,
            ),
          if (tampilBarcodeTeks && barcode.isNotEmpty)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              child: pw.Center(
                child: pw.Text(barcode,
                    style: pw.TextStyle(
                        fontSize: promoKodeSize * skala, letterSpacing: 1)),
              ),
            ),
          if (tampilKode)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              child: pw.Center(
                child: pw.Text(kode,
                    style: pw.TextStyle(fontSize: promoKodeSize * skala)),
              ),
            ),
          pw.SizedBox(height: 3),
        ],
      ),
    );
  }
}

String _kodeBarcode(Map<String, dynamic> p) {
  final barcode = '${p['barcode'] ?? ''}'.trim();
  if (barcode.isNotEmpty) return barcode;
  return '${p['kode'] ?? ''}'.trim();
}

String _formatRupiah(num? v) {
  final n = (v ?? 0).round();
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return 'Rp $buf,-';
}
