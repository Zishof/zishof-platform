import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../struk_screen.dart';

final _formatTanggalServer = DateFormat('yyyy-MM-dd');

String _formatWaktu(dynamic raw) {
  final s = raw?.toString() ?? '';
  if (s.isEmpty) return '-';
  try {
    return DateFormat('dd-MM-yyyy HH:mm').format(DateTime.parse(s));
  } catch (_) {
    return s;
  }
}

class _TabelTransaksiUmum extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>) onLongPress;
  final void Function(Map<String, dynamic>) onLayani;

  const _TabelTransaksiUmum({
    required this.data,
    required this.onTap,
    required this.onLongPress,
    required this.onLayani,
  });

  @override
  Widget build(BuildContext context) {
    final gayaHeaderTabel = _gayaHeaderTabelUmum(context);
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.pageBgOf(context),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('WAKTU', style: gayaHeaderTabel)),
                Expanded(
                    flex: 4,
                    child: Text('PEMBELI / BARANG', style: gayaHeaderTabel)),
                Expanded(
                    flex: 2, child: Text('METODE', style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('TOTAL',
                        textAlign: TextAlign.right, style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('STATUS',
                        textAlign: TextAlign.center, style: gayaHeaderTabel)),
                SizedBox(
                    width: 88,
                    child: Text('AKSI',
                        textAlign: TextAlign.center, style: gayaHeaderTabel)),
              ],
            ),
          ),
          for (final row in data)
            _BarisTabelTransaksiUmum(
              row: row,
              onTap: () => onTap(row),
              onLongPress: () => onLongPress(row),
              onLayani: () => onLayani(row),
            ),
        ],
      ),
    );
  }
}

TextStyle _gayaHeaderTabelUmum(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      color: AppColors.textSecondaryOf(context),
      letterSpacing: 0.4,
    );

class _BarisTabelTransaksiUmum extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onLayani;

  const _BarisTabelTransaksiUmum({
    required this.row,
    required this.onTap,
    required this.onLongPress,
    required this.onLayani,
  });

  @override
  Widget build(BuildContext context) {
    final terlayani = row['terlayani'] == true;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderOf(context))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                _formatWaktu(row['waktu']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context)),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['pembeli'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    '${row['barang'] ?? '-'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                StrukScreen.labelPembayaran(row),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                formatRupiahDasbor.format(row['total'] ?? 0),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: StatusPill(
                  label: terlayani ? 'Terlayani' : 'Menunggu',
                  warna: terlayani ? AppColors.success : AppColors.warning,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Center(
                child: terlayani
                    ? IconButton(
                        icon: const Icon(Icons.more_horiz),
                        tooltip: 'Aksi',
                        onPressed: onLongPress,
                      )
                    : TextButton(
                        onPressed: onLayani,
                        child: const Text('Layani'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab 1/9 "Ringkasan Umum" -- aksi `dashboard_umum`: 4 KPI (hari/minggu/bulan/
/// semester), tren omzet (periode dipilih), omzet per kategori, komposisi
/// metode bayar, jam sibuk, dan tabel transaksi (filter tanggal+pembeli,
/// paginasi server-side, tombol Layani/Layani Semua).
class RingkasanTabUmum extends StatefulWidget {
  const RingkasanTabUmum({super.key});
  @override
  State<RingkasanTabUmum> createState() => _RingkasanTabUmumState();
}

class _RingkasanTabUmumState extends State<RingkasanTabUmum> {
  final Map<String, String> _kunciPembatalan = {};
  static const _pageSize = 15;
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  String _periodeTren = 'harian';
  DateTime _tanggalAcuan =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime? _mulai;
  DateTime? _sampai;
  String _cariPembeli = '';
  String _kodeTransaksi = '';
  String? _metodeBayar;
  final _pembeliController = TextEditingController();
  final _kodeTransaksiController = TextEditingController();
  int _halaman = 1;
  bool _detailTerlihat = false;
  bool _grafikTerlihat = false;
  String? _logApiTerakhir;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _pembeliController.dispose();
    _kodeTransaksiController.dispose();
    super.dispose();
  }

  Map<String, String> _payloadRentangTanggal() {
    final mulai = _mulai;
    final sampai = _sampai;
    if (mulai == null && sampai == null) return {};

    final awal = mulai ?? sampai!;
    final akhir = sampai ?? mulai!;
    final tanggalAwal = awal.isAfter(akhir) ? akhir : awal;
    final tanggalAkhir = awal.isAfter(akhir) ? awal : akhir;
    return {
      'tglMulai': _formatTanggalServer.format(tanggalAwal),
      'tglSampai': _formatTanggalServer.format(tanggalAkhir),
    };
  }

  Map<String, dynamic> _payloadDashboardUmum() {
    return {
      'periodeTren': _periodeTren,
      'tanggalAcuan': _formatTanggalServer.format(_tanggalAcuan),
      ..._payloadRentangTanggal(),
      if (_cariPembeli.isNotEmpty) 'cariPembeli': _cariPembeli,
      if (_kodeTransaksi.isNotEmpty) ...{
        'kodeTransaksi': _kodeTransaksi,
        'kode': _kodeTransaksi,
      },
      if (_metodeBayar != null && _metodeBayar!.isNotEmpty)
        'metodeBayar': _metodeBayar,
      'includePembayaran': true,
      'includeSplitPembayaran': true,
      'sertakanPembayaran': true,
      'withPayments': true,
      'page': _halaman,
      'pageSize': _pageSize,
    };
  }

  Future<void> _muat({bool simpanLog = false}) async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    final namaApi = 'dashboard_umum';
    final payload = _payloadDashboardUmum();
    Map<String, dynamic>? response;
    Object? error;
    try {
      final hasil = await ApiClient.instance.aksi(namaApi, payload);
      response = hasil;
      if (!mounted) return;
      setStateIfMounted(() => _d = hasil);
    } catch (e) {
      error = e;
      if (!mounted) return;
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
    if (simpanLog && mounted) {
      setStateIfMounted(() {
        _logApiTerakhir = _formatLogApi(
          namaApi: namaApi,
          payload: payload,
          response: response,
          error: error,
        );
      });
    }
  }

  List<String> _analisisPintar(Map<String, dynamic> d) {
    final tren = ((d['tren'] as List?) ?? []).cast<Map<String, dynamic>>();
    final kategori =
        ((d['omzetKategori'] as List?) ?? []).cast<Map<String, dynamic>>();
    final jam = ((d['jamSibuk'] as List?) ?? []).cast<Map<String, dynamic>>();
    final hasil = <String>[];
    if (tren.length >= 2) {
      final awal = (tren.first['omzet'] as num?)?.toDouble() ?? 0;
      final akhir = (tren.last['omzet'] as num?)?.toDouble() ?? 0;
      final perubahan = awal == 0 ? 0 : (akhir - awal) * 100 / awal;
      hasil.add(
          'Tren omzet ${perubahan >= 0 ? "naik" : "turun"} ${perubahan.abs().toStringAsFixed(1)}% dari periode pertama ke periode terakhir.');
    }
    if (kategori.isNotEmpty) {
      hasil.add(
          'Kategori terkuat adalah ${kategori.first['label'] ?? '-'} dengan omzet ${formatRupiahDasbor.format(kategori.first['nilai'] ?? 0)}.');
    }
    if (jam.isNotEmpty) {
      hasil.add(
          'Jam tersibuk berada pada ${jam.first['label'] ?? '-'}; siapkan kasir dan stok sebelum rentang ini.');
    }
    if (hasil.isEmpty) {
      hasil.add('Data belum cukup untuk menghasilkan rekomendasi operasional.');
    }
    return hasil;
  }

  Future<void> _cetakDashboardPdf() async {
    final d = _d;
    if (d == null) return;
    final kpi = (d['kpi'] as Map<String, dynamic>?) ?? {};
    final tren = ((d['tren'] as List?) ?? []).cast<Map<String, dynamic>>();
    final kategori =
        ((d['omzetKategori'] as List?) ?? []).cast<Map<String, dynamic>>();
    final metode =
        ((d['metodeBayar'] as List?) ?? []).cast<Map<String, dynamic>>();
    final doc = pw.Document();
    pw.Widget bar(String judul, List<Map<String, dynamic>> rows,
        {String nilaiKey = 'nilai'}) {
      final max = rows.fold<double>(0, (m, e) {
        final v = (e[nilaiKey] as num?)?.toDouble() ?? 0;
        return v > m ? v : m;
      });
      return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(judul,
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            ...rows.take(6).map((e) {
              final v = (e[nilaiKey] as num?)?.toDouble() ?? 0;
              return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(children: [
                    pw.SizedBox(
                        width: 70,
                        child: pw.Text('${e['label'] ?? '-'}',
                            maxLines: 1,
                            style: const pw.TextStyle(fontSize: 6.5))),
                    pw.Container(
                        width: max <= 0 ? 1 : 100 * v / max,
                        height: 6,
                        color: PdfColors.blue700),
                    pw.SizedBox(width: 3),
                    pw.Text(formatRupiahDasbor.format(v),
                        style: const pw.TextStyle(fontSize: 6.5)),
                  ]));
            }),
          ]);
    }

    Map<String, dynamic> kk(String key) =>
        (kpi[key] as Map<String, dynamic>?) ?? {};
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(18),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Dashboard Bisnis · ${Sesi.instance.tokoNama}',
                    style: pw.TextStyle(
                        fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Acuan ${DateFormat('dd-MM-yyyy').format(_tanggalAcuan)} · Dicetak ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 8)),
              ]),
          pw.SizedBox(height: 8),
          pw.Row(children: [
            _kpiPdf('Transaksi Tanggal Acuan', '${kk('hariIni')['trx'] ?? 0}'),
            _kpiPdf('Omzet Tanggal Acuan',
                formatRupiahDasbor.format(kk('hariIni')['rp'] ?? 0)),
            _kpiPdf('Omzet Minggu Acuan',
                formatRupiahDasbor.format(kk('mingguIni')['rp'] ?? 0)),
            _kpiPdf('Omzet Bulan Acuan',
                formatRupiahDasbor.format(kk('bulanIni')['rp'] ?? 0)),
          ]),
          pw.SizedBox(height: 10),
          pw.Expanded(
              child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                pw.Expanded(child: bar('Tren Omzet', tren, nilaiKey: 'omzet')),
                pw.SizedBox(width: 14),
                pw.Expanded(child: bar('Omzet per Kategori', kategori)),
                pw.SizedBox(width: 14),
                pw.Expanded(child: bar('Komposisi Pembayaran', metode)),
              ])),
          pw.Container(
            padding: const pw.EdgeInsets.all(7),
            decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Analisis Pintar',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ..._analisisPintar(d).map((e) => pw.Text('• $e',
                      style: const pw.TextStyle(fontSize: 7.5))),
                ]),
          ),
        ],
      ),
    ));
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(),
        name:
            'dashboard-bisnis-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.pdf');
  }

  pw.Widget _kpiPdf(String label, String nilai) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.all(7),
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(nilai,
                  style: pw.TextStyle(
                      fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
            ]),
      ),
    );
  }

  Future<void> _terapkan({bool simpanLog = false}) async {
    _halaman = 1;
    await _muat(simpanLog: simpanLog);
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _terapkanRentangKartu(DateTime mulai, DateTime sampai) async {
    setStateIfMounted(() {
      _mulai = DateTime(mulai.year, mulai.month, mulai.day);
      _sampai = DateTime(sampai.year, sampai.month, sampai.day);
      _metodeBayar = null;
    });
    await _terapkan();
  }

  Future<void> _pilihMetodeBayar(String metode) async {
    final sekarang = DateTime.now();
    setStateIfMounted(() {
      _metodeBayar = _metodeBayar == metode ? null : metode;
      // Angka kartu metode pembayaran berasal dari 30 hari terakhir ketika
      // pengguna belum memilih tanggal. Samakan rentang tabel saat kartu diklik.
      if (_mulai == null && _sampai == null) {
        _mulai = DateTime(sekarang.year, sekarang.month, sekarang.day)
            .subtract(const Duration(days: 29));
        _sampai = DateTime(sekarang.year, sekarang.month, sekarang.day);
      }
    });
    await _terapkan();
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final v = await showDatePicker(
        context: context,
        initialDate: (mulai ? _mulai : _sampai) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (v == null) return;
    if (!mounted) return;
    setStateIfMounted(() {
      if (mulai) {
        _mulai = v;
        if (_sampai != null && _sampai!.isBefore(v)) _sampai = v;
      } else {
        _sampai = v;
        if (_mulai != null && _mulai!.isAfter(v)) _mulai = v;
      }
    });
    await _terapkan(simpanLog: true);
  }

  Future<void> _pilihTanggalAcuan() async {
    final v = await showDatePicker(
      context: context,
      initialDate: _tanggalAcuan,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal acuan dashboard',
    );
    if (v == null || !mounted) return;
    setStateIfMounted(() {
      _tanggalAcuan = DateTime(v.year, v.month, v.day);
      _halaman = 1;
    });
    await _muat(simpanLog: true);
  }

  Widget _inputTanggalAcuan({bool ringkas = false}) {
    final tombol = OutlinedButton.icon(
      onPressed: _memuat ? null : _pilihTanggalAcuan,
      icon: const Icon(Icons.event_available_outlined, size: 18),
      label: Text(_formatTanggalServer.format(_tanggalAcuan)),
    );
    if (ringkas) return tombol;
    return AppSectionCard(
      child: Row(
        children: [
          Icon(Icons.today_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tanggal Acuan',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Kartu KPI dan rekap tujuh hari dihitung sampai tanggal ini.',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          tombol,
        ],
      ),
    );
  }

  String _formatLogApi({
    required String namaApi,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? response,
    Object? error,
  }) {
    final encoder = const JsonEncoder.withIndent('  ');
    final request = {'action': namaApi, ...payload};
    return (StringBuffer()
          ..writeln('API')
          ..writeln(namaApi)
          ..writeln()
          ..writeln('URL')
          ..writeln(ApiClient.baseUrl)
          ..writeln()
          ..writeln('REQUEST')
          ..writeln(encoder.convert(request))
          ..writeln()
          ..writeln(error == null ? 'RESPONSE' : 'ERROR')
          ..writeln(
              error == null ? encoder.convert(response) : error.toString()))
        .toString();
  }

  Future<void> _tampilkanLogApi() async {
    final isi = _logApiTerakhir;
    if (isi == null || isi.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log API Dashboard Umum'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: SelectableText(
              isi,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _statusMuatDenganLog() {
    if (_memuat) {
      return statusMuatDasbor(
        memuat: true,
        error: _error,
        onCoba: () => _muat(),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 8),
            Text(_error ?? 'Gagal memuat.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _muat(simpanLog: true),
                  child: const Text('Coba Lagi'),
                ),
                OutlinedButton.icon(
                  onPressed: _logApiTerakhir == null ? null : _tampilkanLogApi,
                  icon: const Icon(Icons.article_outlined, size: 18),
                  label: const Text('Lihat Log'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _terapkanPencarianPembelian() async {
    _cariPembeli = _pembeliController.text.trim();
    _kodeTransaksi = _kodeTransaksiController.text.trim();
    await _terapkan();
  }

  Future<void> _layani(dynamic id) async {
    try {
      await ApiClient.instance.aksi('layani_transaksi', {'id': id});
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _layaniSemua() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Layani Semua?'),
        content: const Text(
            'Semua transaksi pada rentang filter ini akan ditandai terlayani.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      final hasil = await ApiClient.instance.aksi('layani_semua_transaksi', {
        ..._payloadRentangTanggal(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${hasil['jumlahBarisDiperbarui'] ?? 0} transaksi ditandai terlayani.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Cetak Struk dari baris transaksi Ringkasan Umum. Layout sengaja reuse
  /// [StrukScreen] supaya sama dengan cetak dari Kasir, Pesanan, dan Riwayat.
  Future<void> _cetakStruk(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      final struk = StrukScreen(
        kode:
            '${hasil['kode'] ?? row['nomorNota'] ?? row['kode'] ?? row['kodeTransaksi'] ?? ''}',
        waktu: _formatWaktu(row['waktu'] ?? hasil['waktu']),
        item: items
            .map((i) => {
                  'nama': i['nama'],
                  'qty': i['qty'],
                  'harga': i['harga'],
                })
            .toList(),
        total: (hasil['totalBiaya'] as num?)?.toDouble() ??
            (row['totalBiaya'] as num?)?.toDouble() ??
            0,
        metode: '${hasil['metode'] ?? row['metode'] ?? ''}',
        pembayaran: StrukScreen.pembayaranDariSumber(hasil, row),
        pajak: (hasil['pajak'] as num?)?.toDouble() ??
            (row['pajak'] as num?)?.toDouble() ??
            0,
        pelanggan: '${hasil['pembeli'] ?? row['pembeli'] ?? ''}',
        modeCetakUlang: true,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => struk),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal membuka preview struk: $e')));
      }
    }
  }

  Future<void> _batalkan(Map<String, dynamic> row) async {
    final alasanController = TextEditingController();
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Batalkan Transaksi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${row['pembeli']} · ${_formatWaktu(row['waktu'])} akan dibatalkan permanen.'),
            const SizedBox(height: 12),
            TextField(
                controller: alasanController,
                decoration: const InputDecoration(
                    labelText: 'Alasan Pembatalan *',
                    border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    if (alasanController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alasan pembatalan wajib diisi.')));
      }
      return;
    }
    try {
      final id = '${row['idTransaksi']}';
      final key = _kunciPembatalan.putIfAbsent(
          id, () => 'BATAL-$id-${DateTime.now().microsecondsSinceEpoch}');
      await ApiClient.instance.aksi('batalkan_transaksi', {
        'id': row['idTransaksi'],
        'alasan': alasanController.text.trim(),
        'idempotency_key': key
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transaksi dibatalkan.')));
      }
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _tampilkanAksi(Map<String, dynamic> row) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Detail'),
                onTap: () {
                  Navigator.of(context).pop();
                  _lihatDetail(row);
                }),
            ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Cetak Struk'),
                onTap: () {
                  Navigator.of(context).pop();
                  _cetakStruk(row);
                }),
            if (Sesi.instance.bolehKelola)
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                title: const Text('Batalkan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _batalkan(row);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _lihatDetail(Map<String, dynamic> row) async {
    try {
      final hasil = await ApiClient.instance
          .aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items =
          ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Detail ${hasil['kode'] ?? ''}'),
          content: SizedBox(
            width: 820,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ringkasanDetailTransaksi(row, hasil),
                    const SizedBox(height: 12),
                    _tabelDetailTransaksi(items),
                    const SizedBox(height: 12),
                    _totalDetailTransaksi(hasil),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup')),
            // Cetak Struk & Batalkan langsung di sini -- gap-closure: sebelumnya
            // HANYA lewat menu tekan-tahan (_tampilkanAksi), tak lazim dipakai
            // mouse desktop sehingga terkesan "cuma popup tanpa aksi" (bahkan
            // utk supervisor yang harusnya boleh Batalkan).
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _cetakStruk(row);
              },
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Cetak Struk'),
            ),
            if (Sesi.instance.bolehKelola)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _batalkan(row);
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Batalkan'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _ringkasanDetailTransaksi(
    Map<String, dynamic> row,
    Map<String, dynamic> hasil,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chipDetailTransaksi(
            Icons.schedule_outlined, 'Waktu: ${_formatWaktu(row['waktu'])}'),
        _chipDetailTransaksi(Icons.person_outline,
            'Pembeli: ${row['pembeli'] ?? hasil['pembeli'] ?? '-'}'),
        _chipDetailTransaksi(Icons.payments_outlined,
            'Metode: ${StrukScreen.labelPembayaran(hasil, row)}'),
        _chipDetailTransaksi(
          row['terlayani'] == true
              ? Icons.check_circle_outline
              : Icons.hourglass_empty,
          row['terlayani'] == true ? 'Terlayani' : 'Menunggu',
        ),
      ],
    );
  }

  Widget _chipDetailTransaksi(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.pageBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondaryOf(context)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelDetailTransaksi(List<Map<String, dynamic>> items) {
    String formatQty(dynamic raw) {
      final qty = (raw as num?)?.toDouble() ?? 0;
      return qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2);
    }

    return AppDataTable(
      minWidth: 760,
      emptyText: 'Tidak ada item transaksi.',
      columns: const [
        AppTableColumn('Produk', flex: 4),
        AppTableColumn('Kode', flex: 2),
        AppTableColumn('Qty', width: 72, align: TextAlign.center),
        AppTableColumn('Harga', flex: 2, align: TextAlign.right),
        AppTableColumn('Diskon', flex: 2, align: TextAlign.right),
        AppTableColumn('Subtotal', flex: 2, align: TextAlign.right),
      ],
      rows: items.map((item) {
        final qty = (item['qty'] as num?) ?? 0;
        final harga = (item['harga'] as num?) ?? 0;
        final diskon = (item['diskon'] as num?) ?? 0;
        final subtotal = harga * qty - diskon;
        return AppTableRowData(cells: [
          AppTableCell.text(
            '${item['nama'] ?? '-'}',
            flex: 4,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          AppTableCell.text(
            '${item['kode'] ?? '-'}',
            flex: 2,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryOf(context),
              fontFamily: 'monospace',
            ),
          ),
          AppTableCell.text(
            formatQty(item['qty']),
            width: 72,
            align: TextAlign.center,
          ),
          AppTableCell.text(
            formatRupiahDasbor.format(harga),
            flex: 2,
            align: TextAlign.right,
          ),
          AppTableCell.text(
            diskon == 0 ? '-' : formatRupiahDasbor.format(diskon),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              color: diskon == 0
                  ? AppColors.textSecondaryOf(context)
                  : AppColors.warning,
            ),
          ),
          AppTableCell.text(
            formatRupiahDasbor.format(subtotal),
            flex: 2,
            align: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        ]);
      }).toList(),
    );
  }

  Widget _totalDetailTransaksi(Map<String, dynamic> hasil) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: _barisTotalDetailTransaksi(
            'Total',
            formatRupiahDasbor.format(hasil['totalBiaya'] ?? 0),
            tebal: true,
          ),
        ),
      ),
    );
  }

  Widget _barisTotalDetailTransaksi(
    String label,
    String nilai, {
    bool tebal = false,
  }) {
    final gaya = TextStyle(
      fontSize: tebal ? 16 : 12.5,
      fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
      color: AppColors.textPrimaryOf(context),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: gaya),
          Text(nilai, style: gaya),
        ],
      ),
    );
  }

  Widget _bangunPanelFilterPembelian() {
    final warnaTeks = Theme.of(context).colorScheme.primary;
    final warnaBorder = Theme.of(context).colorScheme.outline;
    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data Pembelian',
            style: TextStyle(
              color: warnaTeks,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_metodeBayar != null) ...[
            const SizedBox(height: 8),
            InputChip(
              avatar:
                  const Icon(Icons.account_balance_wallet_outlined, size: 17),
              label: Text('Jenis pembayaran: $_metodeBayar'),
              onDeleted: () async {
                setStateIfMounted(() => _metodeBayar = null);
                await _terapkan();
              },
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 820;
              final controls = <Widget>[
                _tombolTanggalPembelian(
                  label: _mulai == null
                      ? 'Dari Tanggal'
                      : _formatTanggalServer.format(_mulai!),
                  onPressed: () => _pilihTanggal(mulai: true),
                  warnaTeks: warnaTeks,
                  warnaBorder: warnaBorder,
                ),
                _tombolTanggalPembelian(
                  label: _sampai == null
                      ? 'Sampai Tanggal'
                      : _formatTanggalServer.format(_sampai!),
                  onPressed: () => _pilihTanggal(mulai: false),
                  warnaTeks: warnaTeks,
                  warnaBorder: warnaBorder,
                ),
              ];

              if (compact) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...controls,
                    SizedBox(
                      width: constraints.maxWidth,
                      child: _fieldCariPembeli(
                        warnaBorder: warnaBorder,
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: _fieldCariKodeTransaksi(
                        warnaBorder: warnaBorder,
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth,
                      child: _tombolLayaniSemuaPembelian(
                        warnaTeks: warnaTeks,
                      ),
                    ),
                  ],
                );
              }

              final dateControls = <Widget>[];
              for (final control in controls) {
                if (dateControls.isNotEmpty) {
                  dateControls.add(const SizedBox(width: 8));
                }
                dateControls.add(control);
              }

              return Row(
                children: [
                  ...dateControls,
                  const SizedBox(width: 16),
                  Expanded(
                    child: _fieldCariPembeli(
                      warnaBorder: warnaBorder,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _fieldCariKodeTransaksi(
                      warnaBorder: warnaBorder,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _tombolLayaniSemuaPembelian(
                    warnaTeks: warnaTeks,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tombolTanggalPembelian({
    required String label,
    required VoidCallback onPressed,
    required Color warnaTeks,
    required Color warnaBorder,
  }) {
    return SizedBox(
      width: 150,
      height: 38,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: warnaTeks,
          side: BorderSide(color: warnaBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _fieldCariPembeli({
    required Color warnaBorder,
  }) {
    return _fieldCariPembelian(
      controller: _pembeliController,
      hintText: 'Cari Pembeli',
      icon: Icons.search,
      warnaBorder: warnaBorder,
    );
  }

  Widget _fieldCariKodeTransaksi({
    required Color warnaBorder,
  }) {
    return _fieldCariPembelian(
      controller: _kodeTransaksiController,
      hintText: 'Cari Kode Transaksi',
      icon: Icons.receipt_long_outlined,
      warnaBorder: warnaBorder,
    );
  }

  Widget _fieldCariPembelian({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required Color warnaBorder,
  }) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: warnaBorder),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: warnaBorder),
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
        ),
        onSubmitted: (_) => _terapkanPencarianPembelian(),
      ),
    );
  }

  Widget _tombolLayaniSemuaPembelian({
    required Color warnaTeks,
  }) {
    return SizedBox(
      height: 38,
      child: TextButton(
        onPressed: _layaniSemua,
        style: TextButton.styleFrom(
          foregroundColor: warnaTeks,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        child: const Text('Layani Semua'),
      ),
    );
  }

  Future<void> _lihatRingkasanKartu(
      String judul, Map<String, dynamic> baris) async {
    final label = '${baris['label'] ?? 'Tidak diketahui'}';
    final qty = (baris['qty'] as num?)?.toDouble();
    final trx = (baris['trx'] as num?)?.toInt();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(judul),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('Omzet: ${formatRupiahDasbor.format(baris['nilai'] ?? 0)}'),
            if (trx != null) Text('Jumlah transaksi: $trx'),
            if (qty != null)
              Text(
                  'Jumlah barang: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}'),
            const SizedBox(height: 12),
            Text(
              'Angka mengikuti periode, toko, dan filter yang sedang dipilih pada dashboard.',
              style: TextStyle(color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  Widget _kartuAnalitik({
    required String judul,
    required List<Map<String, dynamic>> data,
    required IconData ikon,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();
    final warna = [
      AppColors.primary,
      AppColors.success,
      AppColors.info,
      AppColors.warning,
      AppColors.teal,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(judul,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final kolom = c.maxWidth >= 1000 ? 4 : (c.maxWidth >= 700 ? 3 : 2);
            final lebarKolom = (c.maxWidth - (12 * (kolom - 1))) / kolom;
            return GridView.count(
              crossAxisCount: kolom,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: lebarKolom / 102,
              children: [
                for (var i = 0; i < data.length; i++)
                  AppKpiCard(
                    icon: ikon,
                    warna: warna[i % warna.length],
                    nilai: formatRupiahDasbor.format(data[i]['nilai'] ?? 0),
                    label: '${data[i]['label'] ?? 'Tidak diketahui'}'
                        '${data[i]['trx'] != null ? ' • ${data[i]['trx']} trx' : ''}'
                        '${data[i]['qty'] != null ? ' • ${(data[i]['qty'] as num).toStringAsFixed(0)} item' : ''}',
                    tooltip: 'Klik untuk melihat ringkasan $judul',
                    onTap: () => _lihatRingkasanKartu(judul, data[i]),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null) {
      return _statusMuatDenganLog();
    }
    final d = _d!;
    final kpi = (d['kpi'] as Map<String, dynamic>?) ?? {};
    final transaksi = (d['transaksi'] as Map<String, dynamic>?) ?? {};
    final data =
        ((transaksi['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    final total = (transaksi['total'] as num?)?.toInt() ?? 0;
    final totalHalaman = (total / _pageSize).ceil().clamp(1, 999999);
    final metodePembayaran =
        ((d['metodeBayar'] as List?) ?? []).cast<Map<String, dynamic>>();
    final omzetKasir =
        ((d['omzetKasir'] as List?) ?? []).cast<Map<String, dynamic>>();
    final omzetKategori =
        ((d['omzetKategori'] as List?) ?? []).cast<Map<String, dynamic>>();
    final produkTerlaris =
        ((d['produkTerlaris'] as List?) ?? []).cast<Map<String, dynamic>>();
    final omzetToko =
        ((d['omzetToko'] as List?) ?? []).cast<Map<String, dynamic>>();
    final tren = ((d['tren'] as List?) ?? []).cast<Map<String, dynamic>>();
    final heatmap =
        ((d['heatmap'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rekap7Hari =
        ((d['rekap7Hari'] as List?) ?? []).cast<Map<String, dynamic>>();
    final maksKategori = omzetKategori.fold<double>(0, (m, e) {
      final v = (e['nilai'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });
    final radar = omzetKategori
        .take(6)
        .map((e) => (
              label: '${e['label'] ?? '-'}',
              nilai: maksKategori <= 0
                  ? 0.0
                  : (((e['nilai'] as num?)?.toDouble() ?? 0) *
                      100 /
                      maksKategori)
            ))
        .toList();
    final lilin = tren
        .map((e) => (
              label: '${e['label'] ?? '-'}',
              buka: (e['open'] as num?)?.toDouble() ?? 0,
              tinggi: (e['high'] as num?)?.toDouble() ?? 0,
              rendah: (e['low'] as num?)?.toDouble() ?? 0,
              tutup: (e['close'] as num?)?.toDouble() ?? 0,
            ))
        .toList();

    Map<String, dynamic> k(String key) =>
        (kpi[key] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (d['semuaToko'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Menampilkan data SEMUA toko (akun admin).',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondaryOf(context),
                      fontStyle: FontStyle.italic)),
            ),
          _inputTanggalAcuan(),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            final lebar = c.maxWidth;
            final kolom = lebar >= 1000 ? 5 : (lebar >= 700 ? 3 : 2);
            final lebarKolom = (lebar - (12 * (kolom - 1))) / kolom;
            return GridView.count(
              crossAxisCount: kolom,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: lebarKolom / 96,
              children: [
                AppKpiCard(
                    icon: Icons.receipt_long,
                    warna: AppColors.primary,
                    nilai: '${k('hariIni')['trx'] ?? 0}',
                    label:
                        'Transaksi ${DateFormat('dd-MM-yyyy').format(_tanggalAcuan)}',
                    tooltip:
                        'Klik untuk menampilkan transaksi pada tanggal acuan',
                    onTap: () {
                      _terapkanRentangKartu(_tanggalAcuan, _tanggalAcuan);
                    }),
                AppKpiCard(
                    icon: Icons.payments_outlined,
                    warna: AppColors.success,
                    nilai: formatRupiahDasbor.format(k('hariIni')['rp'] ?? 0),
                    label:
                        'Omzet ${DateFormat('dd-MM-yyyy').format(_tanggalAcuan)}',
                    tooltip: 'Klik untuk menampilkan omzet pada tanggal acuan',
                    onTap: () {
                      _terapkanRentangKartu(_tanggalAcuan, _tanggalAcuan);
                    }),
                AppKpiCard(
                    icon: Icons.calendar_view_week_outlined,
                    warna: AppColors.info,
                    nilai: formatRupiahDasbor.format(k('mingguIni')['rp'] ?? 0),
                    label: 'Omzet Minggu Acuan',
                    tooltip:
                        'Klik untuk menampilkan transaksi dari awal minggu sampai tanggal acuan',
                    onTap: () {
                      final n = _tanggalAcuan;
                      final awal = n.subtract(Duration(days: n.weekday - 1));
                      _terapkanRentangKartu(awal, n);
                    }),
                AppKpiCard(
                    icon: Icons.calendar_month_outlined,
                    warna: AppColors.warning,
                    nilai: formatRupiahDasbor.format(k('bulanIni')['rp'] ?? 0),
                    label: 'Omzet Bulan Acuan',
                    tooltip:
                        'Klik untuk menampilkan transaksi dari awal bulan sampai tanggal acuan',
                    onTap: () {
                      final n = _tanggalAcuan;
                      _terapkanRentangKartu(DateTime(n.year, n.month, 1), n);
                    }),
                AppKpiCard(
                    icon: Icons.stacked_line_chart,
                    warna: AppColors.teal,
                    nilai:
                        formatRupiahDasbor.format(k('semesterIni')['rp'] ?? 0),
                    label: 'Omzet 6 Bulan Acuan',
                    tooltip:
                        'Klik untuk menampilkan transaksi enam bulan sampai tanggal acuan',
                    onTap: () {
                      final n = _tanggalAcuan;
                      _terapkanRentangKartu(
                          DateTime(n.year, n.month - 6, n.day), n);
                    }),
              ],
            );
          }),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: Icon(
                  _detailTerlihat
                      ? Icons.expand_less_outlined
                      : Icons.list_alt_outlined,
                  size: 18),
              label: Text(_detailTerlihat ? 'Sembunyikan Detail' : 'Detail'),
              onPressed: () =>
                  setStateIfMounted(() => _detailTerlihat = !_detailTerlihat),
            ),
          ),
          if (_detailTerlihat && metodePembayaran.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Omzet per Jenis Pembayaran',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final kolom =
                  c.maxWidth >= 1000 ? 5 : (c.maxWidth >= 700 ? 3 : 2);
              final lebarKolom = (c.maxWidth - (12 * (kolom - 1))) / kolom;
              final warna = [
                AppColors.primary,
                AppColors.success,
                AppColors.info,
                AppColors.warning,
                AppColors.teal,
              ];
              return GridView.count(
                crossAxisCount: kolom,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: lebarKolom / 96,
                children: [
                  for (var i = 0; i < metodePembayaran.length; i++)
                    AppKpiCard(
                      icon: Icons.account_balance_wallet_outlined,
                      warna: warna[i % warna.length],
                      nilai: formatRupiahDasbor
                          .format(metodePembayaran[i]['nilai'] ?? 0),
                      label: '${metodePembayaran[i]['label'] ?? 'Lainnya'}'
                          '${_metodeBayar == '${metodePembayaran[i]['label'] ?? 'Lainnya'}' ? ' • Aktif' : ''}',
                      tooltip:
                          'Klik untuk menyaring transaksi dengan jenis pembayaran ${metodePembayaran[i]['label'] ?? 'Lainnya'}',
                      onTap: () => _pilihMetodeBayar(
                          '${metodePembayaran[i]['label'] ?? 'Lainnya'}'),
                    ),
                ],
              );
            }),
          ],
          if (_detailTerlihat) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text('Rekap 7 Hari Terakhir',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondaryOf(context))),
                ),
                _inputTanggalAcuan(ringkas: true),
              ],
            ),
            const SizedBox(height: 8),
            if (rekap7Hari.isEmpty)
              const AppInfoBanner(
                icon: Icons.info_outline,
                text:
                    'Rekap tujuh hari belum tersedia. Muat ulang setelah server diperbarui.',
              )
            else
              LayoutBuilder(builder: (context, c) {
                final kolom = c.maxWidth >= 1100
                    ? 7
                    : (c.maxWidth >= 760 ? 4 : (c.maxWidth >= 480 ? 2 : 1));
                final lebarKolom = (c.maxWidth - (12 * (kolom - 1))) / kolom;
                return GridView.count(
                  crossAxisCount: kolom,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: lebarKolom / 104,
                  children: [
                    for (final rekap in rekap7Hari)
                      AppKpiCard(
                        icon: rekap['tanggalAcuan'] == true
                            ? Icons.today
                            : Icons.calendar_today_outlined,
                        warna: rekap['tanggalAcuan'] == true
                            ? AppColors.primary
                            : AppColors.info,
                        nilai: formatRupiahDasbor.format(rekap['rp'] ?? 0),
                        label: '${rekap['tanggal'] ?? '-'}'
                            ' • ${rekap['trx'] ?? 0} trx'
                            '${rekap['tanggalAcuan'] == true ? ' • Acuan' : ''}',
                        tooltip:
                            'Klik untuk menampilkan transaksi tanggal ${rekap['tanggal'] ?? '-'}',
                        onTap: () {
                          final tanggal =
                              DateTime.tryParse('${rekap['tanggal'] ?? ''}');
                          if (tanggal != null) {
                            _terapkanRentangKartu(tanggal, tanggal);
                          }
                        },
                      ),
                  ],
                );
              }),
          ],
          if (_detailTerlihat) ...[
            _kartuAnalitik(
                judul: 'Omzet per Kasir',
                data: omzetKasir,
                ikon: Icons.badge_outlined),
            _kartuAnalitik(
                judul: 'Omzet per Jenis Produk',
                data: omzetKategori,
                ikon: Icons.category_outlined),
            _kartuAnalitik(
                judul: 'Produk Terlaris',
                data: produkTerlaris,
                ikon: Icons.local_fire_department_outlined),
            _kartuAnalitik(
                judul: 'Omzet per Toko',
                data: omzetToko,
                ikon: Icons.storefront_outlined),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: Icon(
                      _grafikTerlihat
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18),
                  label: Text(_grafikTerlihat
                      ? 'Sembunyikan Grafik'
                      : 'Tampilkan Grafik'),
                  onPressed: () => setStateIfMounted(
                      () => _grafikTerlihat = !_grafikTerlihat),
                ),
                FilledButton.icon(
                  onPressed: _cetakDashboardPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Cetak Analitik 1 Halaman'),
                ),
              ],
            ),
          ),
          if (_grafikTerlihat) ...[
            const SizedBox(height: 16),
            AppSectionCard(
              judul: 'Tren Omzet',
              aksiJudul: Wrap(
                spacing: 6,
                children: ['harian', 'mingguan', 'bulanan']
                    .map((p) => ChoiceChip(
                          label: Text(p),
                          selected: _periodeTren == p,
                          onSelected: (_) {
                            setStateIfMounted(() => _periodeTren = p);
                            _muat();
                          },
                        ))
                    .toList(),
              ),
              child: GarisTren(
                  data: titikDariList(d['tren'] as List?,
                      labelKey: 'label', nilaiKey: 'omzet')),
            ),
            const SizedBox(height: 16),
            AppSectionCard(
                judul: 'Omzet per Kategori',
                child: BarHorizontal(
                    data: titikDariList(d['omzetKategori'] as List?),
                    formatNilai: formatRupiahDasbor.format)),
            const SizedBox(height: 16),
            AppSectionCard(
                judul: 'Komposisi Metode Bayar',
                child: StackProporsional(
                    data: titikDariList(d['metodeBayar'] as List?))),
            const SizedBox(height: 16),
            AppSectionCard(
                judul: 'Jam Sibuk',
                child: BarHorizontal(
                    data: titikDariList(d['jamSibuk'] as List?),
                    warna: AppColors.warning,
                    tampilkanPeringkat: false)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final duaKolom = c.maxWidth >= 850;
              final panels = <Widget>[
                AppSectionCard(
                    judul: 'Radar Kinerja Kategori',
                    child: RadarKinerja(data: radar)),
                AppSectionCard(
                    judul: 'Candlestick Nilai Transaksi',
                    child: CandlestickOmzet(data: lilin)),
              ];
              return duaKolom
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: panels[0]),
                        const SizedBox(width: 16),
                        Expanded(child: panels[1]),
                      ],
                    )
                  : Column(children: [
                      panels[0],
                      const SizedBox(height: 16),
                      panels[1]
                    ]);
            }),
            const SizedBox(height: 16),
            AppSectionCard(
                judul: 'Heatmap Aktivitas Hari & Jam',
                child: HeatmapAktivitas(data: titikDariList(heatmap))),
            const SizedBox(height: 16),
            AppSectionCard(
              judul: 'Analisis Pintar & Rekomendasi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _analisisPintar(d)
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.auto_awesome,
                                    size: 16, color: AppColors.warning),
                                const SizedBox(width: 7),
                                Expanded(child: Text(e)),
                              ]),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _bangunPanelFilterPembelian(),
          const SizedBox(height: 8),
          if (data.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('Belum ada transaksi.')))
          else
            _TabelTransaksiUmum(
              data: data,
              onTap: _lihatDetail,
              onLongPress: _tampilkanAksi,
              onLayani: (row) => _layani(row['idTransaksi']),
            ),
          if (total > _pageSize)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed:
                          _halaman > 1 ? () => _pindah(_halaman - 1) : null),
                  Text('Halaman $_halaman / $totalHalaman'),
                  IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _halaman < totalHalaman
                          ? () => _pindah(_halaman + 1)
                          : null),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
