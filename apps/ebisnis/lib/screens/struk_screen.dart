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
  final double pajak;
  final bool tersinkron;
  final String? statusLabel;

  const StrukScreen({
    super.key,
    required this.kode,
    required this.waktu,
    required this.item,
    required this.total,
    required this.metode,
    this.pajak = 0,
    this.tersinkron = true,
    this.statusLabel,
  });

  double get _subtotalItem => item.fold<double>(
        0,
        (sum, i) => sum + _subtotalBaris(i),
      );

  double get _subtotal => pajak > 0 ? total - pajak : _subtotalItem;

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

  Future<void> _pastikanProfilToko() async {
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
    if (AppVariant.logoAsset == null) return null;
    try {
      final data = await rootBundle.load(AppVariant.logoAsset!);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  Future<void> _cetakStruk() async {
    await _pastikanProfilToko();
    final logo = await _logoPdf();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 6 * PdfPageFormat.mm,
        ),
        build: (_) => _strukPdf(logo),
      ),
    );
    await cetakLangsungKePrinterDefault(dokumen: doc, nama: 'struk-$kode.pdf');
  }

  pw.Widget _strukPdf(pw.ImageProvider? logo) {
    return pw.DefaultTextStyle(
      style: const pw.TextStyle(fontSize: 9),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(child: _logoPdfWidget(logo)),
          pw.SizedBox(height: 8),
          pw.Text(
            Sesi.instance.tokoNama.isEmpty ? 'Nama Toko' : Sesi.instance.tokoNama,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            Sesi.instance.pesanTerimaKasih.isEmpty
                ? 'Moto Bisnis atau Toko'
                : Sesi.instance.pesanTerimaKasih,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
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
          _totalPdf('Metode', metode),
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
        ],
      ),
    );
  }

  pw.Widget _logoPdfWidget(pw.ImageProvider? logo) {
    if (logo != null) {
      return pw.Container(
        width: 52,
        height: 52,
        child: pw.Image(logo, fit: pw.BoxFit.contain),
      );
    }
    return pw.Container(
      width: 52,
      height: 52,
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
        child: pw.Text(
          '--------------------------------',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 8),
        ),
      );

  pw.Widget _infoPdf(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 38, child: pw.Text(label)),
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
          pw.Text('${i['nama']}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
        title: const Text('Transaksi Berhasil'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: FutureBuilder<void>(
              future: _pastikanProfilToko(),
              builder: (context, _) => Column(
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
                    tersinkron: tersinkron,
                    subtotal: _subtotal,
                    jumlahItem: _jumlahItem,
                    kasir: _labelKasir(),
                    statusLabel: statusLabel,
                    formatUang: _formatUang,
                    formatAngka: (v) => _formatAngka.format(v),
                    formatQty: _formatQty,
                  ),
                  const SizedBox(height: 16),
                  _TombolStruk(
                    onCetak: _cetakStruk,
                    onTransaksiBaru: () =>
                        Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const KasirScreen()),
                    ),
                  ),
                ],
              ),
            ),
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
  final bool tersinkron;
  final double subtotal;
  final int jumlahItem;
  final String kasir;
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
    required this.tersinkron,
    required this.subtotal,
    required this.jumlahItem,
    required this.kasir,
    required this.statusLabel,
    required this.formatUang,
    required this.formatAngka,
    required this.formatQty,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 5,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
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
                Sesi.instance.pesanTerimaKasih.isEmpty
                    ? 'Moto Bisnis atau Toko'
                    : Sesi.instance.pesanTerimaKasih,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
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
              if (pajak > 0) _TotalStruk(label: 'Pajak', value: formatUang(pajak)),
              _TotalStruk(
                label: 'Grand Total',
                value: formatUang(total),
                emphasized: true,
              ),
              _TotalStruk(label: 'Metode', value: metode),
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
    if (AppVariant.logoAsset != null) {
      return Center(
        child: SizedBox(
          width: 78,
          height: 78,
          child: Image.asset(AppVariant.logoAsset!, fit: BoxFit.contain),
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

class _GarisStruk extends StatelessWidget {
  const _GarisStruk();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '--------------------------------',
        textAlign: TextAlign.center,
        style: TextStyle(letterSpacing: 0, color: Colors.black87),
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
          SizedBox(width: 54, child: Text(label)),
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

  const _TombolStruk({
    required this.onCetak,
    required this.onTransaksiBaru,
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
            if (defaultTargetPlatform == TargetPlatform.windows) ...[
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
        ElevatedButton(
          onPressed: onTransaksiBaru,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A5F),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Transaksi Baru'),
        ),
      ],
    );
  }
}
