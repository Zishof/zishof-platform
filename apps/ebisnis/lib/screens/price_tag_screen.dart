import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';

/// Cetak Price Tag / label harga (padanan produk-renderer.js Electron,
/// fungsi `bangunHtmlPriceTag`/`...Sticker`/`...TextLabel`) -- 3 template:
/// "POP" (ukuran kertas A2/A4/A5 + 1/2/4 label/halaman, kotak putus-putus),
/// "Stiker" (selalu A4, grid 5x8=40/lembar, warna-warni), "Label Teks"
/// (selalu A4, 2 kolom mengalir, teks polos serif). Dibangun sbg PDF native
/// (bukan HTML->cetak spt Electron) lalu dibuka lewat `Printing.layoutPdf`
/// yg otomatis kasih pratinjau+cetak/simpan/bagikan di Android maupun
/// Windows sekaligus -- tak perlu jalur kode terpisah per platform.
class PriceTagScreen extends StatefulWidget {
  const PriceTagScreen({super.key});

  @override
  State<PriceTagScreen> createState() => _PriceTagScreenState();
}

enum TemplatePriceTag { pop, stiker, textLabel }

class _PriceTagScreenState extends State<PriceTagScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _semuaProduk = [];
  final _controllerCari = TextEditingController();
  final Set<int> _idTerpilih = {};

  TemplatePriceTag _template = TemplatePriceTag.pop;
  String _ukuranKertas = 'A4';
  int _labelPerHalaman = 4;
  int _copies = 1;
  bool _tampilBarcode = true;
  bool _tampilKode = true;
  bool _tampilToko = true;
  final _controllerPromo = TextEditingController(text: 'PROMO');
  bool _memproses = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _controllerCari.dispose();
    _controllerPromo.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('price_tag_list_produk', {});
      final arr = (hasil['data'] as List?) ?? [];
      setState(() {
        _semuaProduk = arr.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  List<Map<String, dynamic>> get _terfilter {
    final kw = _controllerCari.text.trim().toLowerCase();
    if (kw.isEmpty) return _semuaProduk;
    return _semuaProduk.where((p) {
      final nama = (p['nama'] as String? ?? '').toLowerCase();
      final kode = (p['kode'] as String? ?? '').toLowerCase();
      return nama.contains(kw) || kode.contains(kw);
    }).toList();
  }

  void _pilihSemua(bool centang) {
    setState(() {
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
    final terpilih = _semuaProduk.where((p) => _idTerpilih.contains(p['id'] as int)).toList();
    if (terpilih.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih minimal satu produk.')));
      return;
    }
    setState(() => _memproses = true);
    try {
      final semuaTag = <Map<String, dynamic>>[];
      for (final p in terpilih) {
        for (var i = 0; i < _copies; i++) {
          semuaTag.add(p);
        }
      }
      final Uint8ListBuilder builder = Uint8ListBuilder(
        template: _template,
        tag: semuaTag,
        ukuranKertas: _ukuranKertas,
        labelPerHalaman: _labelPerHalaman,
        tampilBarcode: _tampilBarcode,
        tampilKode: _tampilKode,
        tampilToko: _tampilToko,
        promo: _controllerPromo.text.trim(),
        tokoNama: Sesi.instance.tokoNama,
      );
      final bytes = await builder.bangun();
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'price-tag.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBg,
      appBar: AppBar(title: const Text('Cetak Price Tag'), backgroundColor: AppColors.sidebarBg, foregroundColor: Colors.white),
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
                          Expanded(flex: 2, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: _panelOpsi())),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _memproses ? null : _cetak,
                            icon: _memproses
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.print),
                            label: Text('Cetak (${_idTerpilih.length} produk dipilih)'),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _panelDaftarProduk() {
    final tampil = _terfilter;
    final semuaTercentang = tampil.isNotEmpty && tampil.every((p) => _idTerpilih.contains(p['id'] as int));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controllerCari,
            decoration: const InputDecoration(hintText: 'Cari nama/kode produk...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        CheckboxListTile(
          value: semuaTercentang,
          onChanged: (v) => _pilihSemua(v ?? false),
          title: Text('Pilih Semua (${tampil.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                onChanged: (v) => setState(() => v == true ? _idTerpilih.add(id) : _idTerpilih.remove(id)),
                title: Text(p['nama'] as String? ?? '-'),
                subtitle: Text('${p['kode'] ?? '-'} · Rp ${p['hargaJual'] ?? 0}'),
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
        const Text('Template', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SegmentedButton<TemplatePriceTag>(
          segments: const [
            ButtonSegment(value: TemplatePriceTag.pop, label: Text('POP')),
            ButtonSegment(value: TemplatePriceTag.stiker, label: Text('Stiker')),
            ButtonSegment(value: TemplatePriceTag.textLabel, label: Text('Label Teks')),
          ],
          selected: {_template},
          onSelectionChanged: (s) => setState(() => _template = s.first),
        ),
        const SizedBox(height: 20),
        if (_template == TemplatePriceTag.pop) ...[
          const Text('Ukuran Kertas', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'A2', label: Text('A2')),
              ButtonSegment(value: 'A4', label: Text('A4')),
              ButtonSegment(value: 'A5', label: Text('A5')),
            ],
            selected: {_ukuranKertas},
            onSelectionChanged: (s) => setState(() => _ukuranKertas = s.first),
          ),
          const SizedBox(height: 16),
          const Text('Label per Halaman', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {_labelPerHalaman},
            onSelectionChanged: (s) => setState(() => _labelPerHalaman = s.first),
          ),
          const SizedBox(height: 16),
        ],
        const Text('Salinan per Produk', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(onPressed: _copies > 1 ? () => setState(() => _copies--) : null, icon: const Icon(Icons.remove_circle_outline)),
            Text('$_copies', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => setState(() => _copies++), icon: const Icon(Icons.add_circle_outline)),
          ],
        ),
        const SizedBox(height: 16),
        if (_template != TemplatePriceTag.textLabel)
          CheckboxListTile(value: _tampilToko, onChanged: (v) => setState(() => _tampilToko = v ?? false), title: const Text('Tampilkan Nama Toko'), contentPadding: EdgeInsets.zero, dense: true),
        CheckboxListTile(value: _tampilBarcode, onChanged: (v) => setState(() => _tampilBarcode = v ?? false), title: const Text('Tampilkan Barcode'), contentPadding: EdgeInsets.zero, dense: true),
        CheckboxListTile(value: _tampilKode, onChanged: (v) => setState(() => _tampilKode = v ?? false), title: const Text('Tampilkan Kode'), contentPadding: EdgeInsets.zero, dense: true),
        if (_template != TemplatePriceTag.textLabel) ...[
          const SizedBox(height: 8),
          const Text('Teks Promo', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _controllerPromo, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'mis. PROMO/DISKON')),
        ],
      ],
    );
  }
}

/// Rakit dokumen PDF sesuai template+opsi terpilih. Dipisah dari State
/// supaya logika layout murni testable/tidak tercampur widget tree.
class Uint8ListBuilder {
  final TemplatePriceTag template;
  final List<Map<String, dynamic>> tag;
  final String ukuranKertas;
  final int labelPerHalaman;
  final bool tampilBarcode;
  final bool tampilKode;
  final bool tampilToko;
  final String promo;
  final String tokoNama;

  Uint8ListBuilder({
    required this.template,
    required this.tag,
    required this.ukuranKertas,
    required this.labelPerHalaman,
    required this.tampilBarcode,
    required this.tampilKode,
    required this.tampilToko,
    required this.promo,
    required this.tokoNama,
  });

  static const _ukuranHalaman = {
    'A2': PdfPageFormat(1190.6, 1683.8, marginAll: 22.7),
    'A4': PdfPageFormat.a4,
    'A5': PdfPageFormat(419.5, 595.3, marginAll: 22.7),
  };

  Future<Uint8List> bangun() async {
    final doc = pw.Document();
    switch (template) {
      case TemplatePriceTag.pop:
        _isiPop(doc);
        break;
      case TemplatePriceTag.stiker:
        _isiStiker(doc);
        break;
      case TemplatePriceTag.textLabel:
        _isiTextLabel(doc);
        break;
    }
    return doc.save();
  }

  String _rupiah(num? v) {
    final n = (v ?? 0).round();
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return 'Rp $buf';
  }

  pw.Widget? _barcode(String kode, {double height = 40}) {
    if (!tampilBarcode || kode.isEmpty) return null;
    try {
      return pw.BarcodeWidget(barcode: bc.Barcode.code128(), data: kode, drawText: false, height: height);
    } catch (_) {
      return null;
    }
  }

  void _isiPop(pw.Document doc) {
    final format = _ukuranHalaman[ukuranKertas] ?? PdfPageFormat.a4;
    final skalaKertas = ukuranKertas == 'A2' ? 2.0 : (ukuranKertas == 'A5' ? 0.6 : 1.0);
    final skalaPer = labelPerHalaman == 1 ? 1.0 : (labelPerHalaman == 2 ? 0.62 : 0.46);
    final skala = skalaKertas * skalaPer;
    final kolom = labelPerHalaman == 4 ? 2 : 1;

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        build: (context) => [
          pw.GridView(
            crossAxisCount: kolom,
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: tag.map((p) => _kotakPop(p, skala)).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _kotakPop(Map<String, dynamic> p, double skala) {
    final kode = (p['kode'] as String?) ?? '';
    final bcw = _barcode(kode, height: 30 * skala);
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 1.2, style: pw.BorderStyle.dashed), borderRadius: pw.BorderRadius.circular(8)),
      padding: const pw.EdgeInsets.all(10),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (tampilToko && tokoNama.isNotEmpty) pw.Text(tokoNama.toUpperCase(), style: pw.TextStyle(fontSize: 9 * skala, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          if (promo.isNotEmpty)
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 3),
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: pw.BoxDecoration(color: PdfColors.red700, borderRadius: pw.BorderRadius.circular(20)),
              child: pw.Text(promo, style: pw.TextStyle(fontSize: 9 * skala, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            ),
          pw.Text(p['nama'] as String? ?? '-', style: pw.TextStyle(fontSize: 13 * skala, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
          pw.SizedBox(height: 4),
          pw.Text(_rupiah(p['hargaJual'] as num?), style: pw.TextStyle(fontSize: 20 * skala, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
          if (bcw != null || tampilKode) pw.SizedBox(height: 4),
          if (bcw != null) bcw,
          if (tampilKode) pw.Text(kode, style: pw.TextStyle(fontSize: 8 * skala, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  void _isiStiker(pw.Document doc) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 8 * PdfPageFormat.mm,
          marginTop: 8 * PdfPageFormat.mm,
          marginRight: 8 * PdfPageFormat.mm,
          marginBottom: 8 * PdfPageFormat.mm,
        ),
        build: (context) => [
          pw.GridView(
            crossAxisCount: 5,
            childAspectRatio: 0.85,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
            children: tag.map(_kotakStiker).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _kotakStiker(Map<String, dynamic> p) {
    final kode = (p['kode'] as String?) ?? '';
    final bcw = _barcode(kode, height: 12);
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: 0.5), borderRadius: pw.BorderRadius.circular(2)),
      child: pw.Column(
        children: [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            color: PdfColors.red700,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(promo.isEmpty ? 'PROMO' : promo, style: pw.TextStyle(fontSize: 6, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                  color: PdfColors.white,
                  child: pw.Text('Rp', style: pw.TextStyle(fontSize: 5, color: PdfColors.red700)),
                ),
              ],
            ),
          ),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            color: PdfColors.yellow700,
            child: pw.Text(p['nama'] as String? ?? '-', maxLines: 1, overflow: pw.TextOverflow.clip, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Center(
              child: pw.Text(_rupiah(p['hargaJual'] as num?), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
            ),
          ),
          if (bcw != null || tampilKode)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: pw.Column(children: [
                if (bcw != null) bcw,
                if (tampilKode) pw.Text(kode, style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
        ],
      ),
    );
  }

  void _isiTextLabel(pw.Document doc) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 12 * PdfPageFormat.mm,
          marginTop: 12 * PdfPageFormat.mm,
          marginRight: 12 * PdfPageFormat.mm,
          marginBottom: 12 * PdfPageFormat.mm,
        ),
        build: (context) => [
          pw.GridView(
            crossAxisCount: 2,
            childAspectRatio: 2.6,
            crossAxisSpacing: 14,
            mainAxisSpacing: 10,
            children: tag.map(_baitTextLabel).toList(),
          ),
        ],
      ),
    );
  }

  pw.Widget _baitTextLabel(Map<String, dynamic> p) {
    final kode = (p['kode'] as String?) ?? '';
    final bcw = _barcode(kode, height: 16);
    final font = pw.Font.times();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Nama Produk : ${p['nama'] ?? '-'}', style: pw.TextStyle(font: font, fontSize: 11)),
        pw.Text('Harga : ${_rupiah(p['hargaJual'] as num?)}', style: pw.TextStyle(font: font, fontSize: 11, fontWeight: pw.FontWeight.bold)),
        if (bcw != null) pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: bcw),
        if (tampilKode) pw.Text('Kode : $kode', style: pw.TextStyle(font: font, fontSize: 11)),
      ],
    );
  }
}
