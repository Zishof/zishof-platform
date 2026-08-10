import 'dart:math';
import 'dart:io';

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../app_variant.dart';
import '../api_client.dart';
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

class _UkuranTag {
  final String id;
  final String label;
  final String detail;
  final double lebarMm;
  final double tinggiMm;
  final PdfPageFormat? pageFormat;

  const _UkuranTag({
    required this.id,
    required this.label,
    required this.detail,
    required this.lebarMm,
    required this.tinggiMm,
    this.pageFormat,
  });
}

const _ukuranRak = [
  _UkuranTag(
      id: 'rak_30x20',
      label: 'Rak Sempit',
      detail: '30 x 20 mm',
      lebarMm: 30,
      tinggiMm: 20),
  _UkuranTag(
      id: 'rak_50x30',
      label: 'Rak Gondola',
      detail: '50 x 30 mm',
      lebarMm: 50,
      tinggiMm: 30),
  _UkuranTag(
      id: 'rak_60x40',
      label: 'Rak Sedang',
      detail: '60 x 40 mm',
      lebarMm: 60,
      tinggiMm: 40),
  _UkuranTag(
      id: 'rak_80x50',
      label: 'Endcap Promo',
      detail: '80 x 50 mm',
      lebarMm: 80,
      tinggiMm: 50),
  _UkuranTag(
      id: 'rak_100x70',
      label: 'Hang Tag Besar',
      detail: '100 x 70 mm',
      lebarMm: 100,
      tinggiMm: 70),
  _UkuranTag(
      id: 'rak_40x60',
      label: 'Fashion Portrait',
      detail: '40 x 60 mm',
      lebarMm: 40,
      tinggiMm: 60),
  _UkuranTag(
      id: 'rak_a6',
      label: 'A6 Promo',
      detail: '105 x 148 mm',
      lebarMm: 105,
      tinggiMm: 148),
  _UkuranTag(
      id: 'rak_50x70',
      label: 'Menu Display',
      detail: '50 x 70 mm',
      lebarMm: 50,
      tinggiMm: 70),
];

const _ukuranProduk = [
  _UkuranTag(
      id: 'produk_40x20',
      label: 'Barcode Kecil',
      detail: '40 x 20 mm',
      lebarMm: 40,
      tinggiMm: 20),
  _UkuranTag(
      id: 'produk_50x25',
      label: 'Barcode Standar',
      detail: '50 x 25 mm',
      lebarMm: 50,
      tinggiMm: 25),
  _UkuranTag(
      id: 'produk_60x30',
      label: 'Barcode Besar',
      detail: '60 x 30 mm',
      lebarMm: 60,
      tinggiMm: 30),
  _UkuranTag(
      id: 'produk_52x29',
      label: 'A4 40 Label',
      detail: '52 x 29 mm',
      lebarMm: 52,
      tinggiMm: 29),
  _UkuranTag(
      id: 'produk_70x35',
      label: 'A4 24 Label',
      detail: '70 x 35 mm',
      lebarMm: 70,
      tinggiMm: 35),
];

final _ukuranPromo = [
  _UkuranTag(
      id: 'promo_a5',
      label: 'Setengah A4',
      detail: '148 x 210 mm',
      lebarMm: 148,
      tinggiMm: 210,
      pageFormat: PdfPageFormat.a5),
  _UkuranTag(
      id: 'promo_a4',
      label: 'A4 - 3 Panel',
      detail: '210 x 297 mm',
      lebarMm: 210,
      tinggiMm: 297,
      pageFormat: PdfPageFormat.a4),
  _UkuranTag(
      id: 'promo_f4',
      label: 'F4 - 3 Panel',
      detail: '210 x 330 mm',
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
  final _controllerLogoWrapBg = TextEditingController(text: '#FFFFFF');
  final Map<int, String> _promoTeksPerProduk = {};
  final Map<int, String> _promoHargaAsliPerProduk = {};
  final Map<int, String> _promoHargaPromoPerProduk = {};
  final Map<String, TextEditingController> _controllerPromoItem = {};
  final Set<int> _idTerpilih = {};

  ModelPriceTag _model = ModelPriceTag.rak;
  String _ukuranId = 'rak_50x30';
  int _copies = 1;
  bool _tampilBarcode = true;
  bool _tampilKode = true;
  bool _tampilToko = true;
  bool _tampilLogo = false;
  bool _bungkusLogo = false;
  bool _memproses = false;
  String? _logoPath;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    _controllerPromo.dispose();
    _controllerCopies.dispose();
    _controllerRakHeader.dispose();
    _controllerRakProduk.dispose();
    _controllerRakHarga.dispose();
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
      final hasil = await ApiClient.instance.aksi('price_tag_list_produk', {});
      final arr = (hasil['data'] as List?) ?? [];
      setStateIfMounted(() {
        _semuaProduk =
            arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _logoPath = PengaturanStruk.instance.logoPath;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
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

  Map<String, dynamic>? get _produkPreview {
    for (final p in _semuaProduk) {
      if (_idTerpilih.contains(p['id'] as int)) return p;
    }
    return _terfilter.isNotEmpty ? _terfilter.first : null;
  }

  void _ubahModel(ModelPriceTag model) {
    setStateIfMounted(() {
      _model = model;
      _ukuranId = _ukuranTersedia.first.id;
      if (_model == ModelPriceTag.produk) {
        _tampilBarcode = true;
        _tampilKode = true;
        _tampilToko = false;
        _tampilLogo = false;
      } else {
        _tampilToko = true;
      }
    });
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
        tag: semuaTag,
        tampilBarcode: _tampilBarcode,
        tampilKode: _tampilKode,
        tampilToko: _tampilToko,
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _ukuranTersedia
              .map((u) => ChoiceChip(
                    label: Text('${u.label} (P x L: ${u.detail})'),
                    selected: _ukuranId == u.id,
                    onSelected: (_) =>
                        setStateIfMounted(() => _ukuranId = u.id),
                  ))
              .toList(),
        ),
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
            onChanged: (v) => setStateIfMounted(() => _tampilToko = v ?? false),
            title: const Text('Tampilkan Nama Toko'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model != ModelPriceTag.produk)
          CheckboxListTile(
            value: _tampilLogo,
            onChanged: (v) => setStateIfMounted(() => _tampilLogo = v ?? false),
            title: const Text('Tampilkan Logo Toko'),
            subtitle: const Text('Menggunakan logo dari Konfigurasi Struk'),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        if (_model != ModelPriceTag.produk && _tampilLogo) ...[
          CheckboxListTile(
            value: _bungkusLogo,
            onChanged: (v) =>
                setStateIfMounted(() => _bungkusLogo = v ?? false),
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
          onChanged: (v) =>
              setStateIfMounted(() => _tampilBarcode = v ?? false),
          title: const Text('Tampilkan Barcode'),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        CheckboxListTile(
          value: _tampilKode,
          onChanged: (v) => setStateIfMounted(() => _tampilKode = v ?? false),
          title: const Text('Tampilkan Kode'),
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
      ],
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
    final paperWidth = _model == ModelPriceTag.promo ? ukuran.lebarMm : 210.0;
    final paperHeight = _model == ModelPriceTag.promo ? ukuran.tinggiMm : 297.0;
    final paperRatio = paperWidth / paperHeight;
    final pageLabel = _model == ModelPriceTag.promo
        ? '${ukuran.label} (${ukuran.detail})'
        : 'A4 (210 x 297 mm) - tag ${ukuran.detail}';
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
    const lebarA4 = 210.0;
    const tinggiA4 = 297.0;
    final kolom = max(1, lebarA4 ~/ ukuran.lebarMm);
    final baris = max(1, tinggiA4 ~/ ukuran.tinggiMm);
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kolom,
        childAspectRatio: ukuran.lebarMm / ukuran.tinggiMm,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
      ),
      itemCount: min(kolom * baris, 36),
      itemBuilder: (_, i) => Opacity(
        opacity: i == 0 ? 1 : 0.28,
        child: _previewTagMini(produk),
      ),
    );
  }

  Widget _previewTagMini(Map<String, dynamic> p) {
    final nama = p['nama'] as String? ?? '-';
    final kode = '${p['kode'] ?? ''}';
    final barcode = _kodeBarcode(p);
    final harga = _formatRupiah(p['hargaJual'] as num?);
    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: _model == ModelPriceTag.produk
          ? _previewProdukMini(nama, kode, barcode)
          : _previewRakMini(nama, kode, barcode, harga),
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
                        fontSize: 3.2,
                        color: stripText,
                        fontWeight: FontWeight.w800)),
              ),
              if (_tampilKode)
                Text(kode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 3.2, color: kodeText)),
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
                        fontSize: 9,
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

  Widget _previewProdukMini(String nama, String kode, String barcode) {
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
            borderRadius:
                BorderRadius.circular(_model == ModelPriceTag.produk ? 4 : 8),
          ),
          child: _model == ModelPriceTag.produk
              ? _previewProduk(nama, kode, barcode)
              : _model == ModelPriceTag.promo
                  ? _previewPromo(p)
                  : _previewRak(nama, kode, barcode, harga),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: 18,
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
          flex: 11,
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
                            fontSize: 12,
                            color: stripText,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
                if (_tampilKode)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(kode,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: kodeText)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 71,
          child: ColoredBox(
            color: bodyBg,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_teksRakHarga(harga),
                            style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: hargaText)),
                      ),
                    ),
                  ),
                ),
                if (_tampilBarcode)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                    child: _PreviewBarcode(data: barcode, height: 12),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewProduk(String nama, String kode, String barcode) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 42,
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
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
              ),
              if (_tampilLogo) _previewLogo(maxHeight: 30, bottom: 0),
              if (!_tampilLogo &&
                  _tampilToko &&
                  Sesi.instance.tokoNama.isNotEmpty)
                Text(Sesi.instance.tokoNama.toLowerCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: headerText, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        Container(
          height: 22,
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
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
              if (hargaLama != null)
                Text(hargaLama,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10,
                      color: hargaAsliText,
                      decoration: TextDecoration.lineThrough,
                      fontWeight: FontWeight.w700,
                    )),
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
                        fontSize: 56,
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
        if (_tampilKode)
          ColoredBox(
            color: bodyBg,
            child:
                Center(child: Text(kode, style: const TextStyle(fontSize: 10))),
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
    if (height.isInfinite) {
      return SizedBox.expand(child: barcode);
    }
    return SizedBox(
      height: height,
      child: barcode,
    );
  }
}

class _PriceTagPdfBuilder {
  final ModelPriceTag model;
  final _UkuranTag ukuran;
  final List<Map<String, dynamic>> tag;
  final bool tampilBarcode;
  final bool tampilKode;
  final bool tampilToko;
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

  _PriceTagPdfBuilder({
    required this.model,
    required this.ukuran,
    required this.tag,
    required this.tampilBarcode,
    required this.tampilKode,
    required this.tampilToko,
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

  pw.Widget? _barcode(String kode, {double height = 40}) {
    if (!tampilBarcode || kode.isEmpty) return null;
    try {
      return pw.BarcodeWidget(
          barcode: bc.Barcode.code128(),
          data: kode,
          drawText: false,
          height: height);
    } catch (_) {
      return null;
    }
  }

  void _isiGridLabel(
    pw.Document doc,
    pw.Widget Function(Map<String, dynamic>) builder,
  ) {
    final page = PdfPageFormat.a4.copyWith(
      marginLeft: 0,
      marginTop: 0,
      marginRight: 0,
      marginBottom: 0,
    );
    final lebar = ukuran.lebarMm * PdfPageFormat.mm;
    final tinggi = ukuran.tinggiMm * PdfPageFormat.mm;
    final usableWidth = page.availableWidth;
    final usableHeight = page.availableHeight;
    final kolom = max(1, usableWidth ~/ lebar);
    final baris = max(1, usableHeight ~/ tinggi);
    final perHalaman = max(1, kolom * baris);

    for (var start = 0; start < tag.length; start += perHalaman) {
      final slice = tag.skip(start).take(perHalaman).toList();
      doc.addPage(
        pw.Page(
          pageFormat: page,
          build: (_) => pw.Wrap(
            spacing: 0,
            runSpacing: 0,
            children: slice
                .map((p) => pw.SizedBox(
                      width: lebar,
                      height: tinggi,
                      child: builder(p),
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
    final bcw = _barcode(barcode, height: min(9, ukuran.tinggiMm * 0.2));
    final headerH = min(18.0, ukuran.tinggiMm * 0.28) * PdfPageFormat.mm;
    final stripH = min(11.0, ukuran.tinggiMm * 0.2) * PdfPageFormat.mm;
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
                              fontSize: 8 * skala,
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
                          fontSize: 5.8 * skala,
                          color: PdfColor.fromHex(rakStripTextHex),
                          fontWeight: pw.FontWeight.bold)),
                ),
                if (tampilKode)
                  pw.Text(kode,
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: 7 * skala,
                          color: PdfColor.fromHex(rakKodeTextHex),
                          fontStyle: pw.FontStyle.italic)),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              color: PdfColor.fromHex(rakBodyBgHex),
              child: pw.Center(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    _teksHargaRakPdf(p),
                    style: pw.TextStyle(
                      fontSize: 26 * skala,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex(rakHargaTextHex),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (bcw != null)
            pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                child: bcw),
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
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
        borderRadius: pw.BorderRadius.circular(2),
      ),
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
        ],
      ),
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
            height: 28 * skala,
            color: PdfColor.fromHex(promoHeaderBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(teksPromo.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: 20 * skala,
                          color: PdfColor.fromHex(promoHeaderTextHex),
                          fontWeight: pw.FontWeight.bold)),
                ),
                if (logoBytes != null)
                  _logoPdf(22 * skala)
                else if (tampilToko && tokoNama.isNotEmpty)
                  pw.Text(tokoNama.toLowerCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: 9 * skala,
                          color: PdfColor.fromHex(promoHeaderTextHex),
                          fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.Container(
            height: 17 * skala,
            color: PdfColor.fromHex(promoStripBgHex),
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text('${p['nama'] ?? '-'}'.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                          fontSize: 7.5 * skala,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex(promoStripTextHex))),
                ),
                if (hargaLama != null)
                  pw.Text(hargaLama,
                      style: pw.TextStyle(
                          fontSize: 7.5 * skala,
                          color: PdfColor.fromHex(promoHargaAsliTextHex),
                          decoration: pw.TextDecoration.lineThrough)),
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
                      fontSize: 47 * skala,
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
          if (tampilKode)
            pw.Container(
              color: PdfColor.fromHex(promoBodyBgHex),
              child: pw.Center(
                child: pw.Text(kode, style: pw.TextStyle(fontSize: 7 * skala)),
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
  return 'Rp $buf';
}
