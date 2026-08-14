import 'dart:io';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart' as bc;
import 'package:core_hw/core_hw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app_variant.dart';
import '../api_client.dart';
import '../services/pengaturan_laci.dart';
import '../services/pengaturan_struk.dart';
import '../services/print_util.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import 'kasir_screen.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');

/// Struk transaksi -- preview layar dan PDF cetak memakai struktur yang sama:
/// logo/toko di atas, informasi transaksi, daftar item, grand total, metode
/// pembayaran, lalu footer ucapan.
class StrukScreen extends StatelessWidget {
  final String kode;
  final String waktu;
  final List<Map<String, dynamic>> item;
  final double total;
  final String metode;
  final List<Map<String, dynamic>> pembayaran;
  final double pajak;
  final bool tersinkron;
  final String? statusLabel;
  final String? pelanggan;
  final double? uangDiterima;
  final double? kembalian;
  final double? saldo;
  final bool modeCetakUlang;

  const StrukScreen({
    super.key,
    required this.kode,
    required this.waktu,
    required this.item,
    required this.total,
    required this.metode,
    this.pembayaran = const [],
    this.pajak = 0,
    this.tersinkron = true,
    this.statusLabel,
    this.pelanggan,
    this.uangDiterima,
    this.kembalian,
    this.saldo,
    this.modeCetakUlang = false,
  });

  double get _subtotalItem => item.fold<double>(
        0,
        (sum, i) => sum + _subtotalBaris(i),
      );

  double get _subtotal => pajak > 0 ? total - pajak : _subtotalItem;

  List<Map<String, dynamic>> get _pembayaranEfektif =>
      _normalisasiDaftarPembayaran(pembayaran);

  static List<Map<String, dynamic>> pembayaranDariSumber(
    Map<String, dynamic> detail, [
    Map<String, dynamic>? row,
  ]) {
    const keys = [
      'pembayaran',
      'payments',
      'payment',
      'detailPembayaran',
      'rincianPembayaran',
      'metodePembayaranList',
      'splitPembayaran',
      'multiPembayaran',
      'splitPayment',
      'paymentList',
      'paymentDetails',
      'detailPayment',
      'daftarPembayaran',
      'caraBayarList',
      'transaksiPembayaran',
      'dataPembayaran',
    ];
    for (final sumber in [detail, if (row != null) row]) {
      for (final key in keys) {
        final value = sumber[key];
        final hasil = _normalisasiDaftarPembayaran(value);
        if (hasil.isNotEmpty) return hasil;
        if (value is Map) {
          for (final nestedKey in const ['data', 'items', 'list', 'rows']) {
            final nested = value[nestedKey];
            final nestedHasil = _normalisasiDaftarPembayaran(nested);
            if (nestedHasil.isNotEmpty) return nestedHasil;
          }
        }
      }
    }
    final dariTambahan = _pembayaranTambahanDariSumber(detail, row);
    if (dariTambahan.isNotEmpty) return dariTambahan;
    return const [];
  }

  static List<Map<String, dynamic>> _pembayaranTambahanDariSumber(
    Map<String, dynamic> detail, [
    Map<String, dynamic>? row,
  ]) {
    for (final sumber in [detail, if (row != null) row]) {
      for (final key in const [
        'caraBayarTambahan',
        'cara_bayar_tambahan',
        'pembayaranTambahan',
        'additionalPayments',
      ]) {
        final value = sumber[key];
        final tambahan = _normalisasiDaftarPembayaran(value);
        if (tambahan.isEmpty) continue;
        final total = _angkaDariKeys(sumber, const [
          'total',
          'totalBiaya',
          'grandTotal',
          'totalBayar',
          'totalPenjualan',
          'nilai',
        ]);
        final nominalTambahan = tambahan.fold<double>(0, (sum, pembayaran) {
          final nominal = pembayaran['nominal'];
          return sum + (nominal is num ? nominal.toDouble() : 0);
        });
        final nominalUtama = _angkaDariKeys(sumber, const [
              'caraBayarNominal',
              'nominalCaraBayar',
              'caraBayarUtamaNominal',
              'nominalPembayaranUtama',
            ]) ??
            (total == null ? null : (total - nominalTambahan).clamp(0, total));
        return [
          {
            'nama': _namaUtamaPembayaran(detail, row),
            'nominal': nominalUtama,
          },
          ...tambahan,
        ];
      }
    }
    return const [];
  }

  static String _namaUtamaPembayaran(
    Map<String, dynamic> detail, [
    Map<String, dynamic>? row,
  ]) {
    for (final sumber in [detail, if (row != null) row]) {
      for (final key in const [
        'metode',
        'metodePembayaran',
        'caraBayarNama',
        'namaCaraBayar',
        'jenisPembayaran',
      ]) {
        final value = sumber[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      final dariMap = _namaPembayaran(sumber);
      if (dariMap.isNotEmpty) return dariMap;
    }
    return 'Metode Utama';
  }

  static double? _angkaDariKeys(
      Map<String, dynamic> map, Iterable<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed =
            double.tryParse(value.replaceAll(RegExp('[^0-9.-]'), ''));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String labelPembayaran(
    Map<String, dynamic> detail, [
    Map<String, dynamic>? row,
  ]) {
    final daftar = pembayaranDariSumber(detail, row);
    if (daftar.length > 1) {
      final nama = daftar
          .map((p) => '${p['nama'] ?? ''}'.trim())
          .where((nama) => nama.isNotEmpty)
          .join(' + ');
      return nama.isEmpty ? 'Split (${daftar.length})' : 'Split: $nama';
    }
    if (daftar.length == 1) {
      final nama = '${daftar.first['nama'] ?? ''}'.trim();
      if (nama.isNotEmpty) return nama;
    }
    for (final sumber in [detail, if (row != null) row]) {
      for (final key in const [
        'metode',
        'metodePembayaran',
        'caraBayarNama',
        'namaCaraBayar',
        'jenisPembayaran',
        'cara_bayar',
      ]) {
        final value = sumber[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is Map) {
          final nama = _namaPembayaran(Map<String, dynamic>.from(value));
          if (nama.isNotEmpty) return nama;
        }
      }
    }
    return '-';
  }

  static List<Map<String, dynamic>> _normalisasiDaftarPembayaran(dynamic raw) {
    final sumber = raw is List
        ? raw
        : raw is Map
            ? [raw]
            : const [];
    final hasil = <Map<String, dynamic>>[];
    for (final item in sumber) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final nama = _namaPembayaran(map);
      if (nama.isEmpty) continue;
      hasil.add({'nama': nama, 'nominal': _nominalPembayaran(map)});
    }
    return hasil;
  }

  static String _namaPembayaran(Map<String, dynamic> map) {
    const directKeys = [
      'nama',
      'namaCaraBayar',
      'caraBayarNama',
      'metode',
      'metodePembayaran',
      'namaMetode',
      'label',
      'jenisPembayaran',
    ];
    for (final key in directKeys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    const nestedKeys = [
      'caraBayar',
      'cara_bayar',
      'paymentMethod',
      'metodeDetail',
    ];
    for (final key in nestedKeys) {
      final value = map[key];
      if (value is Map) {
        final nama = _namaPembayaran(Map<String, dynamic>.from(value));
        if (nama.isNotEmpty) return nama;
      }
    }
    for (final key in const ['caraBayar', 'caraBayarId', 'idCaraBayar']) {
      final nama = _namaCaraBayarDariId(map[key]);
      if (nama.isNotEmpty) return nama;
    }
    return '';
  }

  static String _namaCaraBayarDariId(dynamic value) {
    final id = value is num ? value.toInt() : int.tryParse('$value');
    if (id == null) return '';
    for (final caraBayar in Sesi.instance.caraBayar) {
      if (caraBayar.id == id) return caraBayar.nama;
    }
    return '';
  }

  static double? _nominalPembayaran(Map<String, dynamic> map) {
    const keys = [
      'nominal',
      'nominalBayar',
      'jumlah',
      'jumlahBayar',
      'amount',
      'nilai',
      'total',
      'bayar',
      'dibayar',
    ];
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed =
            double.tryParse(value.replaceAll(RegExp('[^0-9.-]'), ''));
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  int get _jumlahItem => item.fold<int>(
        0,
        (sum, i) => sum + (_qty(i)).round(),
      );

  double _harga(Map<String, dynamic> i) => (i['harga'] as num).toDouble();

  double _qty(Map<String, dynamic> i) => (i['qty'] as num).toDouble();

  double _subtotalBaris(Map<String, dynamic> i) => _harga(i) * _qty(i);

  String _formatUang(num nilai) => '${_formatAngka.format(nilai)},-';

  String _formatQty(num nilai) {
    final d = nilai.toDouble();
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _labelKasir() {
    final user = Sesi.instance.userId.trim();
    return user.isEmpty ? '-' : user;
  }

  String _labelPelanggan() {
    final nama = pelanggan?.trim() ?? '';
    return nama.isEmpty ? 'Umum' : nama;
  }

  Future<void> _pastikanProfilToko() async {
    await PengaturanStruk.instance.muat();
    if (Sesi.instance.tokoAlamat.trim().isNotEmpty &&
        Sesi.instance.tokoTelp.trim().isNotEmpty) {
      return;
    }
    try {
      final hasil = await ApiClient.instance.aksi('toko_profil_ambil');
      final data = (hasil['data'] as Map<String, dynamic>?) ?? {};
      final nama = '${data['nama'] ?? ''}'.trim();
      final alamat = '${data['alamat'] ?? ''}'.trim();
      final kota = '${data['kota'] ?? ''}'.trim();
      final kodePos = '${data['kodePos'] ?? ''}'.trim();
      final telp = '${data['telp'] ?? ''}'.trim();
      final picHp = '${data['picHp'] ?? ''}'.trim();
      final pesan = '${data['pesanTerimaKasih'] ?? ''}'.trim();
      if (nama.isNotEmpty) Sesi.instance.tokoNama = nama;
      Sesi.instance.tokoAlamat = [
        if (alamat.isNotEmpty) alamat,
        if (kota.isNotEmpty) kota,
        if (kodePos.isNotEmpty) kodePos,
      ].join(', ');
      Sesi.instance.tokoTelp = telp.isEmpty ? picHp : telp;
      if (pesan.isNotEmpty) Sesi.instance.pesanTerimaKasih = pesan;
    } catch (_) {
      // Struk tetap tampil dengan data sesi yang sudah ada jika profil gagal dimuat.
    }
  }

  Future<pw.ImageProvider?> _logoPdf() async {
    await PengaturanStruk.instance.muat();
    final path = PengaturanStruk.instance.logoPath;
    if (path != null) {
      try {
        return pw.MemoryImage(await File(path).readAsBytes());
      } catch (_) {
        // Fallback ke logo aplikasi kalau file lokal tidak bisa dibaca.
      }
    }
    try {
      final data = await rootBundle.load(AppVariant.logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  double _tinggiStrukPdfMm() {
    final lebarKertasMm = PengaturanStruk.instance.lebarKertasMm;
    final charsPerLine = lebarKertasMm <= 58
        ? 22
        : lebarKertasMm <= 72
            ? 27
            : 32;
    final logoSkala = PengaturanStruk.instance.logoSkala.clamp(0.8, 1.8);

    // Tinggi roll harus finite. Sebagian driver thermal Windows memotong PDF
    // dengan tinggi tak hingga, jadi tinggi dihitung longgar dari isi struk.
    var tinggi = 118.0 + (logoSkala - 1) * 12;

    if (Sesi.instance.tokoTelp.trim().isNotEmpty) tinggi += 4;
    if (statusLabel != null && statusLabel!.trim().isNotEmpty) tinggi += 5;

    for (final baris in item) {
      final nama = '${baris['nama'] ?? ''}'.trim();
      final lines = (nama.length / charsPerLine).ceil().clamp(1, 5);
      tinggi += 8.5 + (lines - 1) * 4.2;
    }

    final daftarPembayaran = _pembayaranEfektif;
    final jumlahBarisPembayaran = daftarPembayaran.isEmpty
        ? 1
        : daftarPembayaran.length == 1
            ? 1
            : daftarPembayaran.length + 1;
    tinggi += jumlahBarisPembayaran * 4.8;

    if (uangDiterima != null) tinggi += 4.8;
    if (kembalian != null) tinggi += 4.8;
    if (saldo != null) tinggi += 4.8;
    if (!tersinkron) tinggi += 8;
    if (kode.trim().isNotEmpty) tinggi += 19;

    return tinggi.clamp(130, 4800).toDouble();
  }

  Future<void> _cetakStruk() async {
    await _pastikanProfilToko();
    final logo = await _logoPdf();
    final lebarKertasMm = PengaturanStruk.instance.lebarKertasMm;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          lebarKertasMm * PdfPageFormat.mm,
          _tinggiStrukPdfMm() * PdfPageFormat.mm,
          marginLeft: 3 * PdfPageFormat.mm,
          marginRight: 3 * PdfPageFormat.mm,
          marginTop: 5 * PdfPageFormat.mm,
          marginBottom: 5 * PdfPageFormat.mm,
        ),
        build: (_) => _strukPdf(logo),
      ),
    );
    await cetakLangsungKePrinterDefault(dokumen: doc, nama: 'struk-$kode.pdf');
  }

  /// Dipakai halaman lain untuk mencetak ulang tanpa membuka preview, dengan
  /// layout yang sama persis seperti tombol Cetak Struk di layar ini.
  Future<void> cetakLangsung() => _cetakStruk();

  pw.Widget _strukPdf(pw.ImageProvider? logo) {
    return pw.DefaultTextStyle(
      style: const pw.TextStyle(fontSize: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: _logoPdfWidget(logo)),
          pw.SizedBox(height: 8),
          pw.Text(
            Sesi.instance.tokoNama.isEmpty
                ? 'Nama Toko'
                : Sesi.instance.tokoNama,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            Sesi.instance.tokoAlamat.isEmpty
                ? 'Alamat toko'
                : Sesi.instance.tokoAlamat,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
          if (Sesi.instance.tokoTelp.isNotEmpty)
            pw.Text(
              Sesi.instance.tokoTelp,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          _garisPdf(),
          _infoPdf('No', kode),
          _infoPdf('Tanggal', waktu),
          _infoPdf('Kasir', _labelKasir()),
          _infoPdf('Pelanggan', _labelPelanggan()),
          if (statusLabel != null && statusLabel!.trim().isNotEmpty)
            _infoPdf('Status', statusLabel!.trim()),
          _garisPdf(),
          ...item.map(_itemPdf),
          _garisPdf(),
          pw.Text('$_jumlahItem item', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 4),
          _totalPdf('Subtotal', _formatUang(_subtotal)),
          if (pajak > 0) _totalPdf('Pajak', _formatUang(pajak)),
          _totalPdf(
            'Grand Total',
            _formatUang(total),
            besar: true,
          ),
          if (uangDiterima != null)
            _totalPdf('Tunai', _formatUang(uangDiterima!)),
          if (kembalian != null) _totalPdf('Kembali', _formatUang(kembalian!)),
          ..._pembayaranPdf(),
          if (saldo != null) _totalPdf('Saldo', _formatUang(saldo!)),
          _garisPdf(),
          pw.SizedBox(height: 4),
          pw.Text(
            Sesi.instance.pesanTerimaKasih.isEmpty
                ? 'Ucapan Terima kasih yang sudah ada'
                : Sesi.instance.pesanTerimaKasih,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
          if (!tersinkron) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Transaksi tersimpan offline dan akan disinkronkan otomatis.',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
          pw.SizedBox(height: 8),
          _barcodePdf(),
        ],
      ),
    );
  }

  List<pw.Widget> _pembayaranPdf() {
    final daftar = _pembayaranEfektif;
    if (daftar.isEmpty) return [_totalPdf('Metode', metode)];
    if (daftar.length == 1) {
      return [_totalPdf('Metode', '${daftar.first['nama']}')];
    }
    return [
      _totalPdf('Metode', 'Split (${daftar.length})'),
      ...daftar.map((p) {
        final nominal = p['nominal'];
        return _totalPdf(
          '  ${p['nama']}',
          nominal is num ? _formatUang(nominal) : '-',
        );
      }),
    ];
  }

  pw.Widget _barcodePdf() {
    final data = kode.trim();
    if (data.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: bc.Barcode.code128(),
            data: data,
            drawText: false,
            width: 150,
            height: 34,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          data,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7),
        ),
      ],
    );
  }

  pw.Widget _logoPdfWidget(pw.ImageProvider? logo) {
    final landscape = PengaturanStruk.instance.logoLandscape;
    final skala = PengaturanStruk.instance.logoSkala.clamp(0.8, 1.8);
    final lebar = (landscape ? 112.0 : 52.0) * skala;
    final tinggi = (landscape ? 52.0 : 52.0) * skala;
    if (logo != null) {
      return pw.Container(
        width: lebar,
        height: tinggi,
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
    }
    return pw.Container(
      width: lebar,
      height: tinggi,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#4A78D0'),
        borderRadius: pw.BorderRadius.circular(26),
        border: pw.Border.all(width: 0.6),
      ),
      child: pw.Text(
        'LOGO',
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _garisPdf() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Container(
          height: 0.5,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.5, color: PdfColors.grey700),
            ),
          ),
        ),
      );

  pw.Widget _infoPdf(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 46, child: pw.Text(label)),
          pw.Text(':'),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  pw.Widget _itemPdf(Map<String, dynamic> i) {
    final qty = _qty(i);
    final harga = _harga(i);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text('${i['nama']}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 1),
          pw.Row(
            children: [
              pw.Text('${_formatQty(qty)}x'),
              pw.SizedBox(width: 8),
              pw.Text('@${_formatAngka.format(harga)}'),
              pw.Spacer(),
              pw.Text(_formatUang(_subtotalBaris(i))),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _totalPdf(String label, String value, {bool besar = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              '$label :',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: besar ? 13 : 9,
                fontWeight: besar ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.SizedBox(
            width: 68,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: besar ? 13 : 9,
                fontWeight: besar ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(modeCetakUlang ? 'Preview Cetak Struk' : 'Transaksi Berhasil'),
        automaticallyImplyLeading: modeCetakUlang,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<void>(
            future: _pastikanProfilToko(),
            builder: (context, _) {
              final lebarPreview = PengaturanStruk.instance.lebarPreviewPx;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: lebarPreview),
                child: Column(
                  children: [
                    _StatusTransaksi(tersinkron: tersinkron),
                    const SizedBox(height: 14),
                    _StrukPreview(
                      kode: kode,
                      waktu: waktu,
                      item: item,
                      total: total,
                      pajak: pajak,
                      metode: metode,
                      pembayaran: _pembayaranEfektif,
                      tersinkron: tersinkron,
                      subtotal: _subtotal,
                      jumlahItem: _jumlahItem,
                      kasir: _labelKasir(),
                      pelanggan: _labelPelanggan(),
                      uangDiterima: uangDiterima,
                      kembalian: kembalian,
                      saldo: saldo,
                      statusLabel: statusLabel,
                      formatUang: _formatUang,
                      formatAngka: (v) => _formatAngka.format(v),
                      formatQty: _formatQty,
                    ),
                    const SizedBox(height: 16),
                    _TombolStruk(
                      onCetak: _cetakStruk,
                      tampilkanTransaksiBaru: !modeCetakUlang,
                      tampilkanBukaLaci: !modeCetakUlang,
                      onTransaksiBaru: () =>
                          Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const KasirScreen()),
                      ),
                      // Alur pembayaran dari Pesanan membuka Kasir sebagai
                      // route sementara, lalu menggantinya dengan layar struk.
                      // Pop dari sini karena itu mengembalikan kasir ke daftar
                      // Pesanan asal tanpa membuat transaksi kosong baru.
                      onKembali: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatusTransaksi extends StatelessWidget {
  final bool tersinkron;

  const _StatusTransaksi({required this.tersinkron});

  @override
  Widget build(BuildContext context) {
    final warna = tersinkron ? AppColors.success : AppColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.latarLembut(warna),
        border: Border.all(color: warna.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(tersinkron ? Icons.check_circle : Icons.cloud_off, color: warna),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tersinkron
                  ? 'Berhasil & Tersinkron'
                  : 'Tersimpan Offline, akan disinkron otomatis saat online.',
              style: TextStyle(
                color: warna,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrukPreview extends StatelessWidget {
  final String kode;
  final String waktu;
  final List<Map<String, dynamic>> item;
  final double total;
  final double pajak;
  final String metode;
  final List<Map<String, dynamic>> pembayaran;
  final bool tersinkron;
  final double subtotal;
  final int jumlahItem;
  final String kasir;
  final String pelanggan;
  final double? uangDiterima;
  final double? kembalian;
  final double? saldo;
  final String? statusLabel;
  final String Function(num nilai) formatUang;
  final String Function(num nilai) formatAngka;
  final String Function(num nilai) formatQty;

  const _StrukPreview({
    required this.kode,
    required this.waktu,
    required this.item,
    required this.total,
    required this.pajak,
    required this.metode,
    required this.pembayaran,
    required this.tersinkron,
    required this.subtotal,
    required this.jumlahItem,
    required this.kasir,
    required this.pelanggan,
    required this.uangDiterima,
    required this.kembalian,
    required this.saldo,
    required this.statusLabel,
    required this.formatUang,
    required this.formatAngka,
    required this.formatQty,
  });

  List<Widget> _pembayaranPreview() {
    if (pembayaran.isEmpty) {
      return [_TotalStruk(label: 'Metode', value: metode)];
    }
    if (pembayaran.length == 1) {
      return [
        _TotalStruk(label: 'Metode', value: '${pembayaran.first['nama']}')
      ];
    }
    return [
      _TotalStruk(label: 'Metode', value: 'Split (${pembayaran.length})'),
      ...pembayaran.map((p) {
        final nominal = p['nominal'];
        return _TotalStruk(
          label: '  ${p['nama']}',
          value: nominal is num ? formatUang(nominal) : '-',
        );
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 20),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 13,
            height: 1.15,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _LogoToko(),
              const SizedBox(height: 12),
              Text(
                Sesi.instance.tokoNama.isEmpty
                    ? 'Nama Toko'
                    : Sesi.instance.tokoNama,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Sesi.instance.tokoAlamat.isEmpty
                    ? 'Alamat toko'
                    : Sesi.instance.tokoAlamat,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
              if (Sesi.instance.tokoTelp.isNotEmpty)
                Text(
                  Sesi.instance.tokoTelp,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              const _GarisStruk(),
              _InfoStruk(label: 'No', value: kode),
              _InfoStruk(label: 'Tanggal', value: waktu),
              _InfoStruk(label: 'Kasir', value: kasir),
              _InfoStruk(label: 'Pelanggan', value: pelanggan),
              if (statusLabel != null && statusLabel!.trim().isNotEmpty)
                _InfoStruk(label: 'Status', value: statusLabel!.trim()),
              const _GarisStruk(),
              ...item.map(
                (i) => _ItemStruk(
                  nama: '${i['nama']}',
                  qty: formatQty((i['qty'] as num)),
                  harga: '@${formatAngka(i['harga'] as num)}',
                  subtotal: formatUang(
                    (i['harga'] as num) * (i['qty'] as num),
                  ),
                ),
              ),
              const _GarisStruk(),
              Text('$jumlahItem item'),
              const SizedBox(height: 8),
              _TotalStruk(label: 'Subtotal', value: formatUang(subtotal)),
              if (pajak > 0)
                _TotalStruk(label: 'Pajak', value: formatUang(pajak)),
              _TotalStruk(
                label: 'Grand Total',
                value: formatUang(total),
                emphasized: true,
              ),
              if (uangDiterima != null)
                _TotalStruk(label: 'Tunai', value: formatUang(uangDiterima!)),
              if (kembalian != null)
                _TotalStruk(label: 'Kembali', value: formatUang(kembalian!)),
              ..._pembayaranPreview(),
              if (saldo != null)
                _TotalStruk(label: 'Saldo', value: formatUang(saldo!)),
              const _GarisStruk(),
              Text(
                Sesi.instance.pesanTerimaKasih.isEmpty
                    ? 'Ucapan Terima kasih yang sudah ada'
                    : Sesi.instance.pesanTerimaKasih,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
              if (!tersinkron) ...[
                const SizedBox(height: 6),
                const Text(
                  'Transaksi tersimpan offline dan akan disinkronkan otomatis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.warning),
                ),
              ],
              const SizedBox(height: 12),
              _BarcodeStruk(data: kode),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoToko extends StatelessWidget {
  const _LogoToko();

  @override
  Widget build(BuildContext context) {
    final path = PengaturanStruk.instance.logoPath;
    final landscape = PengaturanStruk.instance.logoLandscape;
    final skala = PengaturanStruk.instance.logoSkala.clamp(0.8, 1.8);
    final lebar = (landscape ? 170.0 : 78.0) * skala;
    final tinggi = (landscape ? 78.0 : 78.0) * skala;
    if (path != null) {
      return Center(
        child: SizedBox(
          width: lebar,
          height: tinggi,
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      );
    }
    if (AppVariant.logoAsset.isNotEmpty) {
      return Center(
        child: SizedBox(
          width: lebar,
          height: tinggi,
          child: Image.asset(AppVariant.logoAsset, fit: BoxFit.contain),
        ),
      );
    }
    return Center(
      child: Container(
        width: 70,
        height: 70,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF4A78D0),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF1E3A5F), width: 1.2),
        ),
        child: const Text(
          'LOGO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _BarcodeStruk extends StatelessWidget {
  final String data;

  const _BarcodeStruk({required this.data});

  @override
  Widget build(BuildContext context) {
    final nilai = data.trim();
    if (nilai.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          width: 220,
          height: 46,
          child: CustomPaint(
            painter: _BarcodePainter(nilai),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nilai,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.black,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _BarcodePainter extends CustomPainter {
  final String data;

  const _BarcodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    try {
      final barcode = bc.Barcode.code128();
      final elements = barcode.make(
        data,
        width: size.width,
        height: size.height,
        drawText: false,
      );
      for (final element in elements) {
        if (element is bc.BarcodeBar && element.black) {
          canvas.drawRect(
            Rect.fromLTWH(
              element.left,
              element.top,
              element.width,
              element.height,
            ),
            paint,
          );
        }
      }
    } catch (_) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'BARCODE',
          style: TextStyle(color: Colors.black, fontSize: 12),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: size.width);
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) {
    return oldDelegate.data != data;
  }
}

class _GarisStruk extends StatelessWidget {
  const _GarisStruk();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.black54,
      ),
    );
  }
}

class _InfoStruk extends StatelessWidget {
  final String label;
  final String value;

  const _InfoStruk({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 68, child: Text(label, softWrap: false)),
          const Text(':'),
          const SizedBox(width: 6),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _ItemStruk extends StatelessWidget {
  final String nama;
  final String qty;
  final String harga;
  final String subtotal;

  const _ItemStruk({
    required this.nama,
    required this.qty,
    required this.harga,
    required this.subtotal,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            nama,
            style: const TextStyle(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Text('${qty}x'),
              const SizedBox(width: 10),
              Text(harga),
              const Spacer(),
              Text(
                subtotal,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalStruk extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _TotalStruk({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: emphasized ? FontWeight.w900 : FontWeight.w500,
      fontSize: emphasized ? 20 : 13,
      color: Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label :',
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 105,
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _TombolStruk extends StatelessWidget {
  final VoidCallback onCetak;
  final VoidCallback onTransaksiBaru;
  final VoidCallback? onKembali;
  final bool tampilkanTransaksiBaru;
  final bool tampilkanBukaLaci;

  const _TombolStruk({
    required this.onCetak,
    required this.onTransaksiBaru,
    this.onKembali,
    this.tampilkanTransaksiBaru = true,
    this.tampilkanBukaLaci = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCetak,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Cetak Struk'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (tampilkanBukaLaci &&
                defaultTargetPlatform == TargetPlatform.windows) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await PengaturanLaci.instance.muat();
                      await bukaLaciKasir(
                        pinAlternatif: PengaturanLaci.instance.pinAlternatif,
                        namaPrinter: PengaturanLaci.instance.namaPrinter,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Gagal membuka laci: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.point_of_sale, size: 18),
                  label: const Text('Buka Laci'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (tampilkanTransaksiBaru) ...[
          ElevatedButton(
            onPressed: onTransaksiBaru,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Transaksi Baru'),
          ),
          const SizedBox(height: 8),
        ],
        if (onKembali != null || !tampilkanTransaksiBaru)
          OutlinedButton.icon(
            onPressed: onKembali ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_outlined, size: 18),
            label: const Text('Kembali ke Halaman Sebelumnya'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
      ],
    );
  }
}
