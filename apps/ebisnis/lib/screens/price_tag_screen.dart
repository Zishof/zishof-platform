import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:barcode/barcode.dart' as bc;
import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../app_variant.dart';
import '../api_client.dart';
import '../services/pengaturan_price_tag.dart';
import '../services/pengaturan_struk.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

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
/// Promo TIDAK memakai ini -- ukurannya (A5/A4/F4) sudah sekaligus jadi
/// ukuran kertas.
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
      id: 'promo_a5',
      label: 'Setengah A4',
      detail: '148 x 210 mm',
      kategori: _kategoriKertasBesar,
      lebarMm: 148,
      tinggiMm: 210,
      pageFormat: PdfPageFormat.a5),
  _UkuranTag(
      id: 'promo_a4',
      label: 'A4 - 3 Panel',
      detail: '210 x 297 mm',
      kategori: _kategoriKertasBesar,
      lebarMm: 210,
      tinggiMm: 297,
      pageFormat: PdfPageFormat.a4),
  _UkuranTag(
      id: 'promo_f4',
      label: 'F4 - 3 Panel',
      detail: '210 x 330 mm',
      kategori: _kategoriKertasBesar,
      lebarMm: 210,
      tinggiMm: 330,
      pageFormat:
          PdfPageFormat(210 * PdfPageFormat.mm, 330 * PdfPageFormat.mm)),
];

class _PriceTagScreenState extends State<PriceTagScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _semuaProduk = [];
  final _controllerCari = TextEditingController();
  final _controllerPromo = TextEditingController(text: 'PROMO');
  final _controllerCopies = TextEditingController(text: '1');
  final _controllerRakHeader = TextEditingController();
  final _controllerRakProduk = TextEditingController();
  final _controllerRakHarga = TextEditingController();
  final _controllerRakHeaderSize = TextEditingController(text: '8');
  final _controllerRakProdukSize = TextEditingController(text: '5.8');
  final _controllerRakKodeSize = TextEditingController(text: '7');
  final _controllerRakHargaSize = TextEditingController(text: '26');
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
  final Map<String, TextEditingController> _controllerPromoItem = {};
  final Set<int> _idTerpilih = {};

  ModelPriceTag _model = ModelPriceTag.rak;
  KertasCetak _kertasCetak = KertasCetak.a4;
  String _lebarRollId = 'roll_58';
  String _ukuranId = 'rak_50x30';
  int _copies = 1;
  bool _tampilBarcode = true;
  bool _tampilKode = true;
  // Khusus Rak & Promo -- teks angka barcode (BUKAN kolom Kode Produk),
  // independen dari [_tampilBarcode] (gambar batang) supaya bisa
  // ditampilkan salah satu, keduanya, atau tak satu pun.
  bool _tampilBarcodeTeks = false;
  bool _tampilToko = true;
  bool _tampilLogo = false;
  bool _tampilHargaProduk = true;
  bool _bungkusLogo = false;
  bool _memproses = false;
  String? _logoPath;
  double _marginKotakMm = 2;
  // Khusus model Produk -- horizontal/vertikal bisa diatur terpisah supaya
  // grid label bisa disesuaikan lebih dinamis dgn ketersediaan kertas/roll
  // di lapangan (mis. roll agak sempit butuh margin horizontal lebih kecil
  // spy tetap muat 3 kolom, tanpa perlu mengubah margin vertikal). Rak &
  // Promo TETAP pakai [_marginKotakMm] tunggal (dari Konfigurasi) spt semula.
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
      await _lengkapiBarcodeDariCacheLokal(produk);
      setStateIfMounted(() {
        _semuaProduk = produk;
        _logoPath = PengaturanStruk.instance.priceTagLogoPath;
        _marginKotakMm = PengaturanStruk.instance.priceTagMarginKotakMm;
        _model = _modelDari(PengaturanPriceTag.instance.modelTerakhir) ?? _model;
        _terapkanPengaturanModel(_model);
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  /// Gap-closure "barcode dalam teks masih Kode Produk walau data Barcode
  /// terisi": aksi server `price_tag_list_produk` ternyata TIDAK selalu
  /// mengirim kolom `barcode` tiap produk -- padahal katalog offline-first
  /// Kasir (`produk_cache`, disinkron via aksi katalog terpisah utk scan
  /// barcode sehari-hari) SUDAH andal menyimpannya. Lengkapi [produk] dari
  /// cache lokal itu (join by id) SEBELUM kode manapun (mis. [_kodeBarcode])
  /// sempat membaca `p['barcode']`, spy fallback ke Kode Produk cuma
  /// terjadi kalau memang benar-benar tak ada barcode di mana pun -- bukan
  /// krn endpoint ini saja yang kebetulan tak mengirimnya.
  Future<void> _lengkapiBarcodeDariCacheLokal(
      List<Map<String, dynamic>> produk) async {
    try {
      final cache = await CoreDb.instance.produkCache();
      final barcodePerId = <int, String>{};
      for (final row in cache) {
        final id = (row['id'] as num?)?.toInt();
        final barcode = '${row['barcode'] ?? ''}'.trim();
        if (id != null && barcode.isNotEmpty) barcodePerId[id] = barcode;
      }
      if (barcodePerId.isEmpty) return;
      for (final p in produk) {
        if ('${p['barcode'] ?? ''}'.trim().isNotEmpty) continue;
        final id = (p['id'] as num?)?.toInt();
        final barcode = id == null ? null : barcodePerId[id];
        if (barcode != null) p['barcode'] = barcode;
      }
    } catch (_) {
      // Cache lokal gagal dibaca (mis. belum pernah sinkron) -- bukan
      // blocker, price tag tetap bisa dicetak, cuma fallback ke Kode
      // Produk spt sebelum gap-closure ini ada.
    }
  }

  List<Map<String, dynamic>> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    if (kw.isEmpty) return _semuaProduk;
    return _semuaProduk.where((p) {
      final nama = (p['nama'] as String? ?? '').toLowerCase();
      final kode = '${p['kode'] ?? ''}'.toLowerCase();
      final barcode = '${p['barcode'] ?? ''}'.toLowerCase();
      return nama.contains(kw) || kode.contains(kw) || barcode.contains(kw);
    }).toList();
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

  _LebarRoll get _lebarRollAktif => _daftarLebarRoll.firstWhere(
      (r) => r.id == _lebarRollId,
      orElse: () => _daftarLebarRoll.first);

  /// Margin horizontal/vertikal yang benar-benar dipakai saat ini -- Produk
  /// pakai [_marginHorizontalMm]/[_marginVerticalMm] independen (lihat
  /// deklarasinya), model lain tetap pakai [_marginKotakMm] tunggal utk
  /// kedua arah spt semula (dari Konfigurasi > Profil Toko).
  double get _marginHorizontalAktifMm =>
      _model == ModelPriceTag.produk ? _marginHorizontalMm : _marginKotakMm;
  double get _marginVerticalAktifMm =>
      _model == ModelPriceTag.produk ? _marginVerticalMm : _marginKotakMm;

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
            const Icon(Icons.unfold_more, size: 18, color: AppColors.textSecondary),
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
                                color:
                                    terpilih ? AppColors.primary : null)),
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
      ('Kapasitas roll (OD) opsional', '214 mm (8,4") - dgn external roll mount, core 1" atau 3"'),
      ('Diameter core roll', '25,4 - 76,2 mm (1" - 3")'),
      ('Jenis media', 'Continuous, die-cut, black mark, fan-fold, notched'),
      ('Ribbon (thermal transfer)', 'lebar 40 - 110 mm, maks. panjang 300 m, core 1"'),
      ('Resolusi / kecepatan', '203 dpi (8 dot/mm), maks. 127 mm (5") per detik'),
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
                const Text('Printer thermal transfer + direct thermal, 203 dpi.',
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
    for (final p in _semuaProduk) {
      if (_idTerpilih.contains(p['id'] as int)) return p;
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
          'tampilToko': _tampilToko,
          'tampilLogo': _tampilLogo,
          'bungkusLogo': _bungkusLogo,
          'logoWrapBg': _controllerLogoWrapBg.text,
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
          'tampilBarcode': _tampilBarcode,
          'tampilKode': _tampilKode,
          'tampilBarcodeTeks': _tampilBarcodeTeks,
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
    _controllerCopies.text = _copies.toString();

    _tampilBarcode = boolean('tampilBarcode', true);
    _tampilKode = boolean('tampilKode', true);
    _tampilBarcodeTeks = boolean('tampilBarcodeTeks', false);

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
        _controllerRakHargaSize.text = teks('rakHargaSize', '26');
        _controllerRakHeaderTinggi.text = teks('rakHeaderTinggi', '');
        _controllerRakStripTinggi.text = teks('rakStripTinggi', '');
        _controllerRakHeaderBg.text = teks('rakHeaderBg', '#505B54');
        _controllerRakHeaderText.text = teks('rakHeaderTextColor', '#FFFFFF');
        _controllerRakStripBg.text = teks('rakStripBg', '#E6B742');
        _controllerRakStripText.text = teks('rakStripText', '#111827');
        _controllerRakKodeText.text = teks('rakKodeText', '#4D403C');
        _controllerRakBodyBg.text = teks('rakBodyBg', '#FFFFFF');
        _controllerRakHargaText.text = teks('rakHargaTextColor', '#514B4B');
      case ModelPriceTag.produk:
        _kertasCetak = _kertasCetakDari(data?['kertasCetak']) ?? KertasCetak.a4;
        _lebarRollId = teks('lebarRollId', 'roll_58');
        _tampilHargaProduk = boolean('tampilHargaProduk', true);
        _tampilToko = false;
        _tampilLogo = false;
        _tampilBarcodeTeks = false;
        // Belum pernah diutak-atik -> ikut Margin Antar Kotak global
        // (Konfigurasi > Profil Toko, sudah kebaca ke [_marginKotakMm] di
        // [_muat] sebelum method ini jalan) spy tampilan awal tak berubah;
        // begitu disentuh sekali, tersimpan independen spt field lainnya.
        _marginHorizontalMm = ((data?['marginHorizontalMm'] as num?)
                    ?.toDouble() ??
                _marginKotakMm)
            .clamp(0, 8)
            .toDouble();
        _marginVerticalMm = ((data?['marginVerticalMm'] as num?)?.toDouble() ??
                _marginKotakMm)
            .clamp(0, 8)
            .toDouble();
      case ModelPriceTag.promo:
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
        _controllerPromoHargaText.text =
            teks('promoHargaTextColor', '#5F5555');
        _controllerPromoHeaderSize.text = teks('promoHeaderSize', '20');
        _controllerPromoTokoSize.text = teks('promoTokoSize', '9');
        _controllerPromoProdukSize.text = teks('promoProdukSize', '7.5');
        _controllerPromoHargaAsliSize.text =
            teks('promoHargaAsliSize', '7.5');
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
    _ubahCopies(int.tryParse(_controllerCopies.text) ?? _copies);
    setStateIfMounted(() => _memproses = true);
    try {
      final semuaTag = <Map<String, dynamic>>[];
      for (final p in terpilih) {
        for (var i = 0; i < _copies; i++) {
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
        rakHargaSize: _ukuranTeks(_controllerRakHargaSize, 26),
        promoHeaderSize: _ukuranTeks(_controllerPromoHeaderSize, 20),
        promoTokoSize: _ukuranTeks(_controllerPromoTokoSize, 9),
        promoProdukSize: _ukuranTeks(_controllerPromoProdukSize, 7.5),
        promoHargaAsliSize: _ukuranTeks(_controllerPromoHargaAsliSize, 7.5),
        promoHargaSize: _ukuranTeks(_controllerPromoHargaSize, 47),
        promoKodeSize: _ukuranTeks(_controllerPromoKodeSize, 7),
        rakHeaderTinggiMm: _tinggiOpsional(
            _controllerRakHeaderTinggi, _rakHeaderTinggiAutoMm),
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
          onLayout: (_) async => bytes, name: 'price-tag.pdf');
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

  int _idProduk(Map<String, dynamic> p) => (p['id'] as num?)?.toInt() ?? -1;

  String _teksPromoUntuk(Map<String, dynamic> p) {
    final custom = _promoTeksPerProduk[_idProduk(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final global = _controllerPromo.text.trim();
    return global.isEmpty ? 'PROMO' : global;
  }

  String? _hargaAsliPromoUntuk(Map<String, dynamic> p) {
    final custom = _promoHargaAsliPerProduk[_idProduk(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final nilai = _hargaLama(p);
    return nilai == null ? null : _formatRupiah(nilai);
  }

  String _hargaPromoUntuk(Map<String, dynamic> p) {
    final custom = _promoHargaPromoPerProduk[_idProduk(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _formatRupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
  }

  TextEditingController _controllerPromoManual(
    int id,
    String field,
    String initialValue,
  ) {
    final key = '$id-$field';
    return _controllerPromoItem.putIfAbsent(
      key,
      () => TextEditingController(text: initialValue),
    );
  }

  List<Map<String, dynamic>> get _produkPromoEditor {
    final dipilih = _semuaProduk.where((p) => _idTerpilih.contains(p['id']));
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
              ? Center(child: Text('Gagal memuat: $_pesanError'))
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
                '${_idTerpilih.length} produk dipilih - $_copies salinan - ${_ukuranAktif.label}',
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

  Widget _panelDaftarProduk() {
    final tampil = _terfilter;
    final semuaTercentang =
        tampil.isNotEmpty && tampil.every((p) => _idTerpilih.contains(p['id']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controllerCari,
            decoration: const InputDecoration(
              hintText: 'Cari nama/kode/barcode produk...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setStateIfMounted(() {}),
          ),
        ),
        CheckboxListTile(
          value: semuaTercentang,
          onChanged: (v) => _pilihSemua(v ?? false),
          title: Text('Pilih Semua (${tampil.length})',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          dense: true,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: tampil.length,
            itemBuilder: (context, i) {
              final p = tampil[i];
              final id = p['id'] as int;
              return CheckboxListTile(
                value: _idTerpilih.contains(id),
                onChanged: (v) => setStateIfMounted(() =>
                    v == true ? _idTerpilih.add(id) : _idTerpilih.remove(id)),
                title: Text(p['nama'] as String? ?? '-',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle:
                    Text('${p['kode'] ?? '-'} - Rp ${p['hargaJual'] ?? 0}'),
                dense: true,
              );
            },
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
        if (_model != ModelPriceTag.promo) ...[
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
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary),
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
        if (_model == ModelPriceTag.produk) ...[
          const SizedBox(height: 16),
          const Text('Margin Antar Kotak',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Atur horizontal & vertikal terpisah supaya grid label bisa '
            'disesuaikan langsung dgn ketersediaan kertas/roll di lapangan. '
            'Nilai awal ikut Margin Antar Kotak di Konfigurasi, tapi '
            'perubahan di sini hanya berlaku utk Stiker Produk.',
            style: const TextStyle(
                fontSize: 11.5, color: AppColors.textSecondary),
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
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Slider(
            value: nilai,
            min: 0,
            max: 8,
            divisions: 16,
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
                    _promoHargaAsliPerProduk[id] ?? '',
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
                    _promoHargaPromoPerProduk[id] ?? '',
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
    final ukuran = _ukuranAktif;
    double paperWidth;
    double paperHeight;
    String pageLabel;
    if (_model == ModelPriceTag.promo) {
      paperWidth = ukuran.lebarMm;
      paperHeight = ukuran.tinggiMm;
      pageLabel = '${ukuran.label} (${ukuran.detail})';
    } else if (_kertasCetak == KertasCetak.thermal) {
      paperWidth = _lebarRollAktif.lebarMm;
      // Tinggi cuma representatif (beberapa baris) -- roll sungguhan maju
      // terus tanpa batas tinggi tetap spt A4/F4, lihat [_previewIsiKertas].
      paperHeight = ukuran.tinggiMm * 4;
      pageLabel = 'Roll ${_lebarRollAktif.label} - tag ${ukuran.detail}';
    } else if (_kertasCetak == KertasCetak.f4) {
      paperWidth = 210;
      paperHeight = 330;
      pageLabel = 'F4 (210 x 330 mm) - tag ${ukuran.detail}';
    } else {
      paperWidth = 210;
      paperHeight = 297;
      pageLabel = 'A4 (210 x 297 mm) - tag ${ukuran.detail}';
    }
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
    if (_model == ModelPriceTag.promo) {
      final panelCount = _ukuranAktif.id == 'promo_a5' ? 1 : 3;
      return Column(
        children: [
          for (var i = 0; i < panelCount; i++) ...[
            Expanded(child: _previewPromoPanelKecil(produk)),
            if (i != panelCount - 1) const SizedBox(height: 4),
          ],
        ],
      );
    }

    final ukuran = _ukuranAktif;
    // Roll thermal: lebar tetap (mengikuti lebar roll dipilih), tinggi
    // representatif beberapa baris saja (roll sungguhan maju terus-menerus,
    // tidak dibatasi tinggi tetap spt A4/F4 -- lihat [_isiGridLabel] utk
    // logika PDF sesungguhnya).
    final lebarKertas =
        _kertasCetak == KertasCetak.thermal ? _lebarRollAktif.lebarMm : 210.0;
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
        : max(
            1,
            ((_kertasCetak == KertasCetak.f4 ? 330.0 : 297.0) + gutterVMm) ~/
                (ukuran.tinggiMm + gutterVMm));
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
          padding:
              EdgeInsets.all((min(gutterHMm, gutterVMm) / 2).clamp(0, 4)),
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
    final isi = _model == ModelPriceTag.produk
        ? _previewProdukMini(nama, kode, barcode, harga)
        : _previewRakMini(nama, kode, barcode, harga);
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
              style: const TextStyle(fontSize: 4.2, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _previewPromoPanelKecil(Map<String, dynamic> p) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
      child: _previewPromo(p),
    );
  }

  Widget _previewIsi(Map<String, dynamic> p) {
    final ukuran = _ukuranAktif;
    final ratio = _model == ModelPriceTag.promo && ukuran.id != 'promo_a5'
        ? ukuran.lebarMm / (ukuran.tinggiMm / 3)
        : ukuran.lebarMm / ukuran.tinggiMm;
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
                : BorderRadius.circular(
                    _model == ModelPriceTag.produk ? 4 : 8),
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
            child: Column(
              children: [
                Expanded(
                  // Harga dominan (flex 3), barcode kebagian flex 1 -- BUKAN
                  // tinggi tetap spt sebelumnya, jadi selalu pas dgn sisa
                  // ruang body (yang kini bisa berubah krn tinggi Header/
                  // Strip Produk bisa dikustom), tak lagi terpotong.
                  flex: tampilAreaBarcode ? 3 : 1,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                if (tampilAreaBarcode)
                  Expanded(
                    flex: 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_tampilBarcode)
                            Expanded(
                              child: _PreviewBarcode(
                                  data: barcode, height: double.infinity),
                            ),
                          if (_tampilBarcodeTeks && barcode.isNotEmpty)
                            Text(barcode,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: kodeSize * 0.7,
                                    letterSpacing: 1,
                                    color: kodeText)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewProduk(String nama, String kode, String barcode, String harga) {
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
        if (_tampilKode)
          Text(barcode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600)),
        if (_tampilKode && kode != barcode)
          Text(kode,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10)),
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
    final headerTinggiPx =
        _tinggiOpsional(_controllerPromoHeaderTinggi, _promoHeaderTinggiAutoPt) *
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
        _isiPromo(doc);
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
    final innerPadding =
        (min(marginH, marginV) * 0.25).clamp(0, 1).toDouble() *
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

    final page = (kertasCetak.pageFormat ?? PdfPageFormat.a4).copyWith(
      marginLeft: 0,
      marginTop: 0,
      marginRight: 0,
      marginBottom: 0,
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
              // Harga (flex 3) + barcode (flex 1) berbagi Expanded yang
              // SAMA -- bukan barcode ditaruh sbg sibling tetap di luar
              // Expanded spt sebelumnya (bisa memaksa total tinggi melebihi
              // kotak & terpotong di margin bawah kalau tinggi Header/Strip
              // Produk dikustom lebih besar). FittedBox pada barcode jadi
              // jaring pengaman kedua thd lebar yang melebihi kotak.
              child: pw.Column(
                children: [
                  pw.Expanded(
                    flex: tampilAreaBarcode ? 3 : 1,
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
                  if (tampilAreaBarcode)
                    pw.Expanded(
                      flex: 1,
                      child: pw.Padding(
                        padding:
                            const pw.EdgeInsets.symmetric(horizontal: 8),
                        child: bcw == null
                            ? pw.Center(
                                child: pw.Text(barcode,
                                    maxLines: 1,
                                    style: pw.TextStyle(
                                        fontSize: rakKodeSize * skala,
                                        letterSpacing: 1,
                                        color:
                                            PdfColor.fromHex(rakKodeTextHex))),
                              )
                            : pw.Column(
                                children: [
                                  pw.Expanded(
                                    child: pw.FittedBox(
                                        fit: pw.BoxFit.scaleDown, child: bcw),
                                  ),
                                  if (tampilBarcodeTeks && barcode.isNotEmpty)
                                    pw.Text(barcode,
                                        maxLines: 1,
                                        style: pw.TextStyle(
                                            fontSize: rakKodeSize * skala,
                                            letterSpacing: 1,
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
    final kode = '${p['kode'] ?? ''}';
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
          if (tampilKode)
            pw.Text(barcode,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: 6 * skala,
                    letterSpacing: 1.5,
                    fontWeight: pw.FontWeight.bold)),
          if (tampilKode && kode != barcode)
            pw.Text(kode,
                maxLines: 1,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 5 * skala)),
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

  void _isiPromo(pw.Document doc) {
    final page = ukuran.pageFormat ?? PdfPageFormat.a4.landscape;
    final perHalaman = ukuran.id == 'promo_a5' ? 1 : 3;
    for (var start = 0; start < tag.length; start += perHalaman) {
      final slice = tag.skip(start).take(perHalaman).toList();
      doc.addPage(
        pw.Page(
          pageFormat: page.copyWith(
            marginLeft: 5 * PdfPageFormat.mm,
            marginTop: 5 * PdfPageFormat.mm,
            marginRight: 5 * PdfPageFormat.mm,
            marginBottom: 5 * PdfPageFormat.mm,
          ),
          build: (_) => pw.Column(
            children: [
              for (var i = 0; i < slice.length; i++) ...[
                pw.Expanded(child: _kotakPromo(slice[i], page)),
                if (i != slice.length - 1) pw.SizedBox(height: 8),
              ],
              for (var i = slice.length; i < perHalaman; i++)
                pw.Expanded(child: pw.SizedBox()),
            ],
          ),
        ),
      );
    }
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
    final nilai = _hargaLama(p);
    return nilai == null ? null : _rupiah(nilai);
  }

  String _hargaPromoPdf(Map<String, dynamic> p) {
    final custom = promoHargaPromoPerProduk[_idProdukPdf(p)]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _rupiah(p['hargaJual'] as num?).replaceFirst('Rp ', 'Rp. ');
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

  pw.Widget _kotakPromo(Map<String, dynamic> p, PdfPageFormat page) {
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final bcw = _barcode(barcode, height: 18);
    final teksPromo = _teksPromoPdf(p);
    final skala = ukuran.id == 'promo_a5' ? 1.25 : 1.0;
    final hargaLama = _hargaAsliPromoPdf(p);
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

num? _hargaLama(Map<String, dynamic> p) {
  final hargaKini = p['hargaJual'] as num?;
  const kandidat = [
    'hargaLama',
    'hargaNormal',
    'hargaSebelum',
    'hargaJualNormal',
    'hargaAsli',
    'hargaCoret',
  ];
  for (final key in kandidat) {
    final nilai = p[key];
    if (nilai is num && nilai > 0 && (hargaKini == null || nilai > hargaKini)) {
      return nilai;
    }
  }
  return null;
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
