import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/rincian_intip_dialog.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');

enum PresetPergerakanStok {
  hariIni('Hari Ini'),
  kemarin('Kemarin'),
  tujuhHari('7 Hari Terakhir'),
  tigaPuluhHari('30 Hari Terakhir'),
  bulanIni('Bulan Ini'),
  bulanLalu('Bulan Lalu'),
  kustom('Kustom');

  final String label;
  const PresetPergerakanStok(this.label);
}

class TabPergerakanStok extends StatefulWidget {
  const TabPergerakanStok({super.key});

  @override
  State<TabPergerakanStok> createState() => _TabPergerakanStokState();
}

class _TabPergerakanStokState extends State<TabPergerakanStok> {
  PresetPergerakanStok _preset = PresetPergerakanStok.bulanIni;
  late DateTime _tglMulai;
  late DateTime _tglSampai;

  final TextEditingController _cariController = TextEditingController();
  String _statusFilter = '';
  bool _memuat = false;
  String? _pesanError;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic>? _ringkasanTotal;

  @override
  void initState() {
    super.initState();
    _terapkanPreset(PresetPergerakanStok.bulanIni, panggilMuat: false);
    _muatData();
  }

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  void _terapkanPreset(PresetPergerakanStok preset, {bool panggilMuat = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _preset = preset;

    switch (preset) {
      case PresetPergerakanStok.hariIni:
        _tglMulai = today;
        _tglSampai = today;
        break;
      case PresetPergerakanStok.kemarin:
        final kem = today.subtract(const Duration(days: 1));
        _tglMulai = kem;
        _tglSampai = kem;
        break;
      case PresetPergerakanStok.tujuhHari:
        _tglMulai = today.subtract(const Duration(days: 6));
        _tglSampai = today;
        break;
      case PresetPergerakanStok.tigaPuluhHari:
        _tglMulai = today.subtract(const Duration(days: 29));
        _tglSampai = today;
        break;
      case PresetPergerakanStok.bulanIni:
        _tglMulai = DateTime(now.year, now.month, 1);
        _tglSampai = today;
        break;
      case PresetPergerakanStok.bulanLalu:
        final firstDayThisMonth = DateTime(now.year, now.month, 1);
        final lastDayPrevMonth = firstDayThisMonth.subtract(const Duration(days: 1));
        _tglMulai = DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, 1);
        _tglSampai = lastDayPrevMonth;
        break;
      case PresetPergerakanStok.kustom:
        break;
    }

    if (panggilMuat) {
      _muatData();
    }
  }

  String _formatTglParam(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
  String _formatTglTampilan(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);

  Future<void> _pilihRentangKustom() async {
    final hasil = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _tglMulai, end: _tglSampai),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (hasil != null) {
      setStateIfMounted(() {
        _preset = PresetPergerakanStok.kustom;
        _tglMulai = hasil.start;
        _tglSampai = hasil.end;
      });
      _muatData();
    }
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_rekap', {
        'dari': _formatTglParam(_tglMulai),
        'sampai': _formatTglParam(_tglSampai),
        'q': _cariController.text.trim(),
        'status_filter': _statusFilter,
        'limit': 500,
      });

      if (!mounted) return;

      final List list = (res['data'] as List?) ?? [];
      final ringkasan = (res['ringkasan'] as Map?)?.cast<String, dynamic>();

      setStateIfMounted(() {
        _data = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _ringkasanTotal = ringkasan;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = 'Gagal memuat pergerakan stok: $e';
      });
    }
  }

  Future<void> _eksporExcel() async {
    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
        'dari': _formatTglParam(_tglMulai),
        'sampai': _formatTglParam(_tglSampai),
        'q': _cariController.text.trim(),
        'status_filter': _statusFilter,
      });

      final b64 = res['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan file.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (res['namaFile'] as String?) ??
          'Pergerakan_Stok_${_formatTglParam(_tglMulai)}_${_formatTglParam(_tglSampai)}.xlsx';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Rekap Pergerakan Stok',
        fileName: namaFile,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File Excel berhasil disimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor Excel: $e')),
      );
    }
  }

  Future<void> _cetakPdfRekap() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data pergerakan stok untuk dicetak.')),
      );
      return;
    }
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Rekap Pergerakan & Audit Stok · ${Sesi.instance.tokoNama}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Periode: ${_formatTglTampilan(_tglMulai)} s/d ${_formatTglTampilan(_tglSampai)} · Dicetak: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: const [
                'Grup',
                'Kode',
                'Nama Produk',
                'Saldo Awal',
                'Masuk',
                'Retur',
                'Penjualan',
                'Keluar',
                'Opname (+)',
                'Opname (-)',
                'Saldo Akhir',
                'Status Audit',
              ],
              data: _data.map((item) {
                return [
                  '${item['kategori'] ?? '-'}',
                  '${item['kode'] ?? '-'}',
                  '${item['nama'] ?? '-'}',
                  _formatAngka.format((item['awal'] as num?) ?? 0),
                  _formatAngka.format((item['masuk'] as num?) ?? 0),
                  _formatAngka.format((item['retur'] as num?) ?? 0),
                  _formatAngka.format((item['penjualan'] as num?) ?? 0),
                  _formatAngka.format((item['keluar'] as num?) ?? 0),
                  _formatAngka.format((item['opnameMasuk'] as num?) ?? 0),
                  _formatAngka.format((item['opnameKeluar'] as num?) ?? 0),
                  _formatAngka.format((item['sisa'] as num?) ?? 0),
                  '${item['statusAudit'] ?? 'Normal'}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'Rekap_Pergerakan_Stok_${_formatTglParam(_tglMulai)}_${_formatTglParam(_tglSampai)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak PDF: $e')),
      );
    }
  }

  void _intipRingkasanKategori(String judul, bool Function(Map<String, dynamic>) predikat) {
    final cocok = _data.where(predikat).toList();
    tampilkanRincianKlikDialog(
      context,
      judul: 'Rincian $judul',
      subjudul:
          'Periode ${_formatTglTampilan(_tglMulai)} - ${_formatTglTampilan(_tglSampai)} (${cocok.length} Produk)',
      kolom: const [
        'Grup',
        'Kode',
        'Nama Produk',
        'Saldo Awal',
        'Masuk',
        'Retur',
        'Penjualan',
        'Keluar',
        'Opname (+)',
        'Opname (-)',
        'Saldo Akhir',
        'Status Audit',
      ],
      baris: cocok
          .map((item) => <Object?>[
                item['kategori'] ?? '-',
                item['kode'] ?? '-',
                item['nama'] ?? '-',
                _formatAngka.format((item['awal'] as num?) ?? 0),
                _formatAngka.format((item['masuk'] as num?) ?? 0),
                _formatAngka.format((item['retur'] as num?) ?? 0),
                _formatAngka.format((item['penjualan'] as num?) ?? 0),
                _formatAngka.format((item['keluar'] as num?) ?? 0),
                _formatAngka.format((item['opnameMasuk'] as num?) ?? 0),
                _formatAngka.format((item['opnameKeluar'] as num?) ?? 0),
                _formatAngka.format((item['sisa'] as num?) ?? 0),
                item['statusAudit'] ?? 'Normal',
              ])
          .toList(),
    );
  }

  void _bukaDetailProduk(Map<String, dynamic> item) {
    final idProduk = (item['id'] as num?)?.toInt() ?? 0;
    if (idProduk <= 0) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogDetailPergerakanStok(
        idProduk: idProduk,
        namaProduk: (item['nama'] as String?) ?? 'Produk',
        kodeProduk: (item['kode'] as String?) ?? '',
        kategori: (item['kategori'] as String?) ?? '-',
        tglMulai: _tglMulai,
        tglSampai: _tglSampai,
      ),
    );
  }

  void _bukaAnalisisCerdasProduk(Map<String, dynamic> item) {
    final idProduk = (item['id'] as num?)?.toInt() ?? 0;
    if (idProduk <= 0) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogAnalisisCerdasStok(
        idProduk: idProduk,
        namaProduk: (item['nama'] as String?) ?? 'Produk',
        kodeProduk: (item['kode'] as String?) ?? '',
        tglMulai: _tglMulai,
        tglSampai: _tglSampai,
      ),
    );
  }

  void _bukaAnalisisCerdasToko() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogAnalisisCerdasStok(
        idProduk: null,
        namaProduk: 'Seluruh Produk Toko',
        kodeProduk: '',
        tglMulai: _tglMulai,
        tglSampai: _tglSampai,
      ),
    );
  }

  Widget _buildSummaryMini(String title, num val, Color color, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            Text(
              _formatAngka.format(val),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 11, color: color.withValues(alpha: 0.7)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar
        Card(
          margin: const EdgeInsets.all(12),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Preset Dropdown
                DropdownButton<PresetPergerakanStok>(
                  value: _preset,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(8),
                  items: PresetPergerakanStok.values.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        p.label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    if (val == PresetPergerakanStok.kustom) {
                      _pilihRentangKustom();
                    } else {
                      setStateIfMounted(() {
                        _terapkanPreset(val);
                      });
                    }
                  },
                ),

                // Indikator tanggal
                InkWell(
                  onTap: _pilihRentangKustom,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.date_range, size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatTglTampilan(_tglMulai)} - ${_formatTglTampilan(_tglSampai)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),

                // Pencarian
                SizedBox(
                  width: 200,
                  height: 36,
                  child: TextField(
                    controller: _cariController,
                    decoration: InputDecoration(
                      hintText: 'Cari produk / kode...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _muatData(),
                  ),
                ),

                // Filter Status Audit / Selisih
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      borderRadius: BorderRadius.circular(8),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Semua Status Barang')),
                        DropdownMenuItem(value: 'ADA_MUTASI', child: Text('Ada Mutasi / Loncat')),
                        DropdownMenuItem(value: 'DINOLKAN_SO', child: Text('Dinolkan saat Opname (SO -> 0)')),
                        DropdownMenuItem(value: 'STOK_MINUS', child: Text('Stok Akhir Minus (< 0)')),
                        DropdownMenuItem(value: 'ADA_OPNAME', child: Text('Ada Koreksi Opname (+/-)')),
                        DropdownMenuItem(value: 'KODE_GANDA', child: Text('Kode Barang Ganda / Duplikat')),
                      ],
                      onChanged: (val) {
                        if (val == null) return;
                        setStateIfMounted(() {
                          _statusFilter = val;
                        });
                        _muatData();
                      },
                    ),
                  ),
                ),

                // Tombol Cari
                ElevatedButton.icon(
                  onPressed: _memuat ? null : _muatData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Cari / Muat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Tombol Analisis Cerdas Toko
                ElevatedButton.icon(
                  onPressed: _memuat ? null : _bukaAnalisisCerdasToko,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Analisis Cerdas Toko'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Tombol Unduh Excel
                OutlinedButton.icon(
                  onPressed: _memuat ? null : _eksporExcel,
                  icon: const Icon(Icons.file_download, size: 16, color: Colors.green),
                  label: const Text('Download Excel', style: TextStyle(color: Colors.green)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Tombol Cetak PDF
                OutlinedButton.icon(
                  onPressed: _memuat ? null : _cetakPdfRekap,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Colors.redAccent),
                  label: const Text('Cetak PDF', style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                if (_ringkasanTotal != null) ...[
                  _buildSummaryMini(
                    'Masuk',
                    (_ringkasanTotal!['masuk'] as num?) ?? 0,
                    Colors.green,
                    onTap: () => _intipRingkasanKategori(
                        'Barang Masuk', (i) => ((i['masuk'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Retur',
                    (_ringkasanTotal!['retur'] as num?) ?? 0,
                    Colors.blue,
                    onTap: () => _intipRingkasanKategori(
                        'Retur Penjualan', (i) => ((i['retur'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Penjualan',
                    (_ringkasanTotal!['penjualan'] as num?) ?? 0,
                    Colors.orange,
                    onTap: () => _intipRingkasanKategori(
                        'Penjualan Kasir', (i) => ((i['penjualan'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Keluar',
                    (_ringkasanTotal!['keluar'] as num?) ?? 0,
                    Colors.red,
                    onTap: () => _intipRingkasanKategori(
                        'Total Barang Keluar', (i) => ((i['keluar'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Opname (+)',
                    (_ringkasanTotal!['opnameMasuk'] as num?) ?? 0,
                    Colors.purple,
                    onTap: () => _intipRingkasanKategori(
                        'Koreksi Opname (+)', (i) => ((i['opnameMasuk'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Opname (-)',
                    (_ringkasanTotal!['opnameKeluar'] as num?) ?? 0,
                    Colors.pink,
                    onTap: () => _intipRingkasanKategori(
                        'Koreksi Opname (-)', (i) => ((i['opnameKeluar'] as num?) ?? 0) > 0),
                  ),
                  if (((_ringkasanTotal!['jmlDinolkanSo'] as num?) ?? 0) > 0)
                    _buildSummaryMini(
                      'SO->0',
                      (_ringkasanTotal!['jmlDinolkanSo'] as num?) ?? 0,
                      Colors.deepOrange,
                      onTap: () => _intipRingkasanKategori(
                          'Barang Dinolkan saat SO', (i) => i['statusKode'] == 'DINOLKAN_SO'),
                    ),
                  if (((_ringkasanTotal!['jmlStokMinus'] as num?) ?? 0) > 0)
                    _buildSummaryMini(
                      'Stok Minus',
                      (_ringkasanTotal!['jmlStokMinus'] as num?) ?? 0,
                      Colors.red.shade900,
                      onTap: () => _intipRingkasanKategori(
                          'Barang Stok Minus (< 0)', (i) => ((i['sisa'] as num?) ?? 0) < 0),
                    ),
                ],
              ],
            ),
          ),
        ),

        // Konten Tabel / Loading / Error
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _pesanError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 40),
                          const SizedBox(height: 8),
                          Text(_pesanError!),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _muatData, child: const Text('Coba Lagi')),
                        ],
                      ),
                    )
                  : _data.isEmpty
                      ? const Center(child: Text('Tidak ada pergerakan stok pada periode ini.'))
                      : Card(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                                  ),
                                  columnSpacing: 18,
                                  columns: const [
                                    DataColumn(label: Text('Grup', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Produk', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(numeric: true, label: Text('Awal', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(numeric: true, label: Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                    DataColumn(numeric: true, label: Text('Pengembalian', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                    DataColumn(numeric: true, label: Text('Penjualan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                                    DataColumn(numeric: true, label: Text('Keluar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                                    DataColumn(numeric: true, label: Text('Opname (+)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple))),
                                    DataColumn(numeric: true, label: Text('Opname (-)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.pink))),
                                    DataColumn(numeric: true, label: Text('Sisa', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Status / Jejak Selisih', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _data.map((item) {
                                    final awal = (item['awal'] as num?)?.toDouble() ?? 0;
                                    final masuk = (item['masuk'] as num?)?.toDouble() ?? 0;
                                    final retur = (item['retur'] as num?)?.toDouble() ?? 0;
                                    final penjualan = (item['penjualan'] as num?)?.toDouble() ?? 0;
                                    final keluar = (item['keluar'] as num?)?.toDouble() ?? 0;
                                    final opnameMasuk = (item['opnameMasuk'] as num?)?.toDouble() ?? 0;
                                    final opnameKeluar = (item['opnameKeluar'] as num?)?.toDouble() ?? 0;
                                    final sisa = (item['sisa'] as num?)?.toDouble() ?? 0;
                                    final statusKode = (item['statusKode'] as String?) ?? 'NORMAL';
                                    final statusAudit = (item['statusAudit'] as String?) ?? 'Normal';

                                    Color statusColor = Colors.teal.shade700;
                                    if (statusKode == 'DINOLKAN_SO' ||
                                        statusKode == 'STOK_MINUS' ||
                                        statusKode == 'SELISIH_FORMULA') {
                                      statusColor = Colors.red.shade800;
                                    } else if (statusKode == 'KOREKSI_SO') {
                                      statusColor = Colors.deepOrange.shade800;
                                    } else if (statusKode == 'PULIH_SO' || statusKode == 'HABIS_TERJUAL') {
                                      statusColor = Colors.blue.shade800;
                                    }

                                    return DataRow(
                                      onSelectChanged: (_) => _bukaDetailProduk(item),
                                      cells: [
                                        DataCell(Text((item['kategori'] as String?) ?? '-')),
                                        DataCell(
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                (item['nama'] as String?) ?? '-',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                              if ((item['kode'] as String?)?.isNotEmpty == true)
                                                Text(
                                                  '${item['kode']}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                            ],
                                          ),
                                        ),
                                        DataCell(Text(_formatAngka.format(awal))),
                                        DataCell(Text(
                                          _formatAngka.format(masuk),
                                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(retur),
                                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(penjualan),
                                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(keluar),
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          opnameMasuk > 0 ? '+${_formatAngka.format(opnameMasuk)}' : '0',
                                          style: TextStyle(
                                            color: opnameMasuk > 0 ? Colors.purple.shade700 : Colors.grey,
                                            fontWeight: opnameMasuk > 0 ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(Text(
                                          opnameKeluar > 0 ? '-${_formatAngka.format(opnameKeluar)}' : '0',
                                          style: TextStyle(
                                            color: opnameKeluar > 0 ? Colors.pink.shade700 : Colors.grey,
                                            fontWeight: opnameKeluar > 0 ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(
                                          Text(
                                            _formatAngka.format(sisa),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: sisa < 0 ? Colors.red.shade800 : null,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            constraints: const BoxConstraints(maxWidth: 260),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              statusAudit,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          AksiBarisMenu(aksi: [
                                            AksiBaris(
                                              ikon: Icons.auto_awesome_outlined,
                                              label: 'Analisis Cerdas Produk (Siap WA)',
                                              onTap: () => _bukaAnalisisCerdasProduk(item),
                                            ),
                                            AksiBaris(
                                              ikon: Icons.receipt_long_outlined,
                                              label: 'Lihat Buku Besar Mutasi',
                                              onTap: () => _bukaDetailProduk(item),
                                            ),
                                          ]),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class DialogDetailPergerakanStok extends StatefulWidget {
  final int idProduk;
  final String namaProduk;
  final String kodeProduk;
  final String kategori;
  final DateTime tglMulai;
  final DateTime tglSampai;

  const DialogDetailPergerakanStok({
    super.key,
    required this.idProduk,
    required this.namaProduk,
    required this.kodeProduk,
    required this.kategori,
    required this.tglMulai,
    required this.tglSampai,
  });

  @override
  State<DialogDetailPergerakanStok> createState() => _DialogDetailPergerakanStokState();
}

class _DialogDetailPergerakanStokState extends State<DialogDetailPergerakanStok> {
  bool _memuat = true;
  String? _pesanError;
  Map<String, dynamic>? _ringkasan;
  List<Map<String, dynamic>> _mutasi = [];

  @override
  void initState() {
    super.initState();
    _muatDetail();
  }

  String _formatTglParam(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
  String _formatTglTampilan(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);

  Future<void> _muatDetail() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_detail', {
        'id': widget.idProduk,
        'dari': _formatTglParam(widget.tglMulai),
        'sampai': _formatTglParam(widget.tglSampai),
      });

      if (!mounted) return;

      final ringkasanData = (res['ringkasan'] as Map?)?.cast<String, dynamic>();
      final List mutasiList = (res['mutasi'] as List?) ?? [];

      setStateIfMounted(() {
        _ringkasan = ringkasanData;
        _mutasi = mutasiList.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = 'Gagal memuat detail pergerakan: $e';
      });
    }
  }

  Future<void> _eksporExcelProduk() async {
    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
        'id': widget.idProduk,
        'dari': _formatTglParam(widget.tglMulai),
        'sampai': _formatTglParam(widget.tglSampai),
      });

      final b64 = res['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan file.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (res['namaFile'] as String?) ??
          'Buku_Besar_${widget.namaProduk}_${_formatTglParam(widget.tglMulai)}.xlsx';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Buku Besar Produk',
        fileName: namaFile,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Buku besar disimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor: $e')),
      );
    }
  }

  Future<void> _cetakPdfProduk() async {
    try {
      final awal = (_ringkasan?['awal'] as num?)?.toDouble() ?? 0;
      final sisa = (_ringkasan?['sisa'] as num?)?.toDouble() ?? 0;
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Buku Besar Pergerakan Stok · ${widget.namaProduk}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Kode: ${widget.kodeProduk.isEmpty ? '-' : widget.kodeProduk} | Grup: ${widget.kategori} | Periode: ${_formatTglTampilan(widget.tglMulai)} - ${_formatTglTampilan(widget.tglSampai)} | Saldo Awal: ${_formatAngka.format(awal)} | Saldo Akhir: ${_formatAngka.format(sisa)}',
                style: const pw.TextStyle(fontSize: 8.5),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: const [
                'No',
                'Tanggal & Jam',
                'No Faktur',
                'Kode Mutasi',
                'ID Pelanggan',
                'Pelanggan / Petugas',
                'Saldo Awal',
                'Masuk',
                'Keluar',
                'Saldo Akhir',
                'Rincian Audit / Keterangan',
              ],
              data: [
                [
                  '1',
                  '${_formatTglTampilan(widget.tglMulai)} 00:00',
                  'SA-001',
                  '100',
                  '-',
                  'Saldo awal',
                  '-',
                  '-',
                  '-',
                  _formatAngka.format(awal),
                  'Saldo awal periode',
                ],
                ..._mutasi.asMap().entries.map((entry) {
                  final idx = entry.key + 2;
                  final m = entry.value;
                  final tAwal = (m['awal'] as num?)?.toDouble() ?? 0;
                  final tMasuk = (m['masuk'] as num?)?.toDouble() ?? 0;
                  final tKeluar = (m['keluar'] as num?)?.toDouble() ?? 0;
                  final tSisa = (m['sisa'] as num?)?.toDouble() ?? 0;
                  final namaPel = (m['namaPelanggan'] as String?) ?? '';
                  final oleh = (m['oleh'] as String?) ?? '';
                  final tipe = (m['tipe'] as String?) ?? '';
                  final pelaku = namaPel.isNotEmpty
                      ? (oleh.isNotEmpty && oleh != namaPel ? '$namaPel ($oleh)' : namaPel)
                      : (oleh.isNotEmpty ? oleh : (tipe.isNotEmpty ? tipe : '-'));
                  return [
                    '$idx',
                    '${m['tanggal'] ?? '-'}',
                    '${m['referensi'] ?? '-'}',
                    '${m['kodeMutasi'] ?? '000'}',
                    '${m['idPelanggan'] ?? '-'}',
                    pelaku,
                    _formatAngka.format(tAwal),
                    tMasuk > 0 ? '+${_formatAngka.format(tMasuk)}' : '-',
                    tKeluar > 0 ? '-${_formatAngka.format(tKeluar)}' : '-',
                    _formatAngka.format(tSisa),
                    '${(m['keterangan'] as String?)?.isNotEmpty == true ? m['keterangan'] : tipe}',
                  ];
                }),
              ],
              headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name: 'Buku_Besar_${widget.kodeProduk.isEmpty ? widget.idProduk : widget.kodeProduk}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak PDF: $e')),
      );
    }
  }

  void _bukaAnalisisCerdas() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogAnalisisCerdasStok(
        idProduk: widget.idProduk,
        namaProduk: widget.namaProduk,
        kodeProduk: widget.kodeProduk,
        tglMulai: widget.tglMulai,
        tglSampai: widget.tglSampai,
      ),
    );
  }

  Widget _buildSummaryCard(String title, num val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _formatAngka.format(val),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// Saldo pembuka ditampilkan sebagai baris agar cocok dengan format buku besar Al-Bahjah.
  DataRow _barisSaldoAwal(double saldo) => DataRow(cells: [
        const DataCell(Text('1')),
        DataCell(Text('${_formatTglTampilan(widget.tglMulai)} 00:00')),
        const DataCell(Text('SA-001')),
        const DataCell(Text('100')),
        const DataCell(Text('-')),
        const DataCell(Text('Saldo awal')),
        const DataCell(Text('-')),
        const DataCell(Text('-')),
        const DataCell(Text('-')),
        DataCell(Text(_formatAngka.format(saldo),
            style: const TextStyle(fontWeight: FontWeight.bold))),
        const DataCell(Text('Saldo awal periode')),
      ]);

  @override
  Widget build(BuildContext context) {
    final awal = (_ringkasan?['awal'] as num?)?.toDouble() ?? 0;
    final masuk = (_ringkasan?['masuk'] as num?)?.toDouble() ?? 0;
    final retur = (_ringkasan?['retur'] as num?)?.toDouble() ?? 0;
    final penjualan = (_ringkasan?['penjualan'] as num?)?.toDouble() ?? 0;
    final keluar = (_ringkasan?['keluar'] as num?)?.toDouble() ?? 0;
    final opnameMasuk = (_ringkasan?['opnameMasuk'] as num?)?.toDouble() ?? 0;
    final opnameKeluar = (_ringkasan?['opnameKeluar'] as num?)?.toDouble() ?? 0;
    final sisa = (_ringkasan?['sisa'] as num?)?.toDouble() ?? 0;

    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.95).clamp(360.0, 1680.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(360.0, 960.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.namaProduk,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kode: ${widget.kodeProduk.isNotEmpty ? widget.kodeProduk : '-'} | Grup: ${widget.kategori} | Periode: ${_formatTglTampilan(widget.tglMulai)} - ${_formatTglTampilan(widget.tglSampai)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _eksporExcelProduk,
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Download Excel'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _cetakPdfProduk,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Cetak PDF'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _bukaAnalisisCerdas,
                    icon: const Icon(Icons.auto_awesome, size: 17),
                    label: const Text('Analisis Cerdas'),
                  ),
                  const SizedBox(width: 8),
                  AksiBarisMenu(tooltip: 'Aksi rincian mutasi', aksi: [
                    AksiBaris(
                      ikon: Icons.auto_awesome_outlined,
                      label: 'Analisis Cerdas Produk (Siap WA)',
                      onTap: _bukaAnalisisCerdas,
                    ),
                    AksiBaris(
                      ikon: Icons.file_download_outlined,
                      label: 'Download Excel',
                      onTap: _eksporExcelProduk,
                    ),
                    AksiBaris(
                      ikon: Icons.picture_as_pdf_outlined,
                      label: 'Cetak PDF',
                      onTap: _cetakPdfProduk,
                    ),
                    AksiBaris(
                      ikon: Icons.close,
                      label: 'Tutup rincian',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 16),

              // 8 Summary Cards (termasuk Opname + dan Opname -)
              Row(
                children: [
                  _buildSummaryCard('Saldo Awal', awal, Colors.blueGrey),
                  _buildSummaryCard('Masuk', masuk, Colors.green),
                  _buildSummaryCard('Pengembalian', retur, Colors.blue),
                  _buildSummaryCard('Penjualan', penjualan, Colors.orange),
                  _buildSummaryCard('Keluar', keluar, Colors.red),
                  _buildSummaryCard('Opname (+)', opnameMasuk, Colors.purple),
                  _buildSummaryCard('Opname (-)', opnameKeluar, Colors.pink),
                  _buildSummaryCard('Saldo Akhir', sisa, Colors.indigo),
                ],
              ),
              const SizedBox(height: 16),

              // Tabel Rincian Buku Besar Mutasi
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _pesanError != null
                        ? Center(child: Text(_pesanError!, style: const TextStyle(color: Colors.red)))
                        : _ringkasan == null
                            ? const Center(child: Text('Belum ada catatan mutasi transaksi pada rentang ini.'))
                            : Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                        columnSpacing: 22,
                                        columns: const [
                                          DataColumn(label: Text('No', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Tanggal & Jam', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('No Faktur', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Kode Mutasi', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('ID Pelanggan', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Pelanggan / Petugas', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(numeric: true, label: Text('Saldo Awal', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(numeric: true, label: Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                          DataColumn(numeric: true, label: Text('Keluar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                                          DataColumn(numeric: true, label: Text('Saldo Akhir', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Rincian Audit / Keterangan', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: [
                                          _barisSaldoAwal(awal),
                                          ..._mutasi.asMap().entries.map((entry) {
                                            final idx = entry.key + 2;
                                            final m = entry.value;
                                            final tAwal = (m['awal'] as num?)?.toDouble() ?? 0;
                                            final tMasuk = (m['masuk'] as num?)?.toDouble() ?? 0;
                                            final tKeluar = (m['keluar'] as num?)?.toDouble() ?? 0;
                                            final tSisa = (m['sisa'] as num?)?.toDouble() ?? 0;
                                            final tipe = (m['tipe'] as String?) ?? '';
                                            final ref = (m['referensi'] as String?) ?? '';
                                            final kodeMutasi = (m['kodeMutasi'] as String?) ?? '000';
                                            final idPel = (m['idPelanggan'] as String?) ?? '';
                                            final namaPel = (m['namaPelanggan'] as String?) ?? '';
                                            final oleh = (m['oleh'] as String?) ?? '';
                                            final ket = (m['keterangan'] as String?) ?? '';

                                            Color badgeColor = Colors.grey.shade700;
                                            if (tipe.contains('Penjualan')) {
                                              badgeColor = Colors.orange.shade800;
                                            } else if (tipe.contains('Pembelian')) {
                                              badgeColor = Colors.green.shade800;
                                            } else if (tipe.contains('Retur')) {
                                              badgeColor = Colors.blue.shade800;
                                            } else if (tipe.contains('Opname') ||
                                                tipe.contains('Penyesuaian')) {
                                              badgeColor = Colors.purple.shade800;
                                            }

                                            final String pelaku = namaPel.isNotEmpty
                                                ? (oleh.isNotEmpty && oleh != namaPel ? '$namaPel ($oleh)' : namaPel)
                                                : (oleh.isNotEmpty ? oleh : (tipe.isNotEmpty ? tipe : '-'));

                                            return DataRow(
                                              cells: [
                                                DataCell(Text('$idx')),
                                                DataCell(Text((m['tanggal'] as String?) ?? '-')),
                                                DataCell(Text(ref.isEmpty ? '-' : ref)),
                                                DataCell(Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: badgeColor.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    kodeMutasi,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                      color: badgeColor,
                                                    ),
                                                  ),
                                                )),
                                                DataCell(Text(idPel.isEmpty ? '-' : idPel)),
                                                DataCell(Text(pelaku)),
                                                DataCell(Text(_formatAngka.format(tAwal))),
                                                DataCell(Text(
                                                  tMasuk > 0 ? '+${_formatAngka.format(tMasuk)}' : '-',
                                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                                )),
                                                DataCell(Text(
                                                  tKeluar > 0 ? '-${_formatAngka.format(tKeluar)}' : '-',
                                                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                                )),
                                                DataCell(Text(
                                                  _formatAngka.format(tSisa),
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                )),
                                                DataCell(
                                                  ConstrainedBox(
                                                    constraints: const BoxConstraints(maxWidth: 320),
                                                    child: Text(
                                                      ket.isNotEmpty ? ket : tipe,
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 2,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: tipe.contains('Opname')
                                                            ? Colors.purple.shade900
                                                            : Colors.grey.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog Menu Cerdas Analisis Otomatis Pergerakan & Selisih Stok (Per Produk maupun Seluruh Toko).
/// Menghasilkan kronologi lengkap penyebab stok berubah/loncat beserta rekomendasi penyelesaian
/// tanpa istilah teknis yang siap disalin langsung ke WhatsApp.
class DialogAnalisisCerdasStok extends StatefulWidget {
  final int? idProduk;
  final String namaProduk;
  final String kodeProduk;
  final DateTime tglMulai;
  final DateTime tglSampai;

  const DialogAnalisisCerdasStok({
    super.key,
    required this.idProduk,
    required this.namaProduk,
    required this.kodeProduk,
    required this.tglMulai,
    required this.tglSampai,
  });

  @override
  State<DialogAnalisisCerdasStok> createState() => _DialogAnalisisCerdasStokState();
}

class _DialogAnalisisCerdasStokState extends State<DialogAnalisisCerdasStok> {
  bool _memuat = true;
  String? _error;
  String _judulDiagnosis = '';
  String _penjelasanUtama = '';
  String _teksWa = '';
  List<String> _kronologi = [];
  List<String> _solusi = [];

  @override
  void initState() {
    super.initState();
    _muatAnalisis();
  }

  String _formatTglParam(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

  Future<void> _muatAnalisis() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final bool perProduk = widget.idProduk != null && widget.idProduk! > 0;
      final res = await ApiClient.instance.aksi(
        perProduk ? 'stok_analisis_cerdas_produk' : 'stok_analisis_cerdas_toko',
        {
          if (perProduk) 'id': widget.idProduk,
          'dari': _formatTglParam(widget.tglMulai),
          'sampai': _formatTglParam(widget.tglSampai),
        },
      );
      if (!mounted) return;
      setStateIfMounted(() {
        _judulDiagnosis = (res['judulDiagnosis'] as String?) ??
            'Ringkasan Eksekutif Audit Pergerakan & Selisih Stok ${res['namaToko'] ?? 'Toko'}';
        _penjelasanUtama = (res['penjelasanUtama'] as String?) ??
            'Ditemukan ${res['totalProdukDinolkan'] ?? 0} jenis barang sempat dinolkan saat Stok Opname (Sudah pulih: ${res['jmlSudahPulih'] ?? 0}, Masih 0/minus: ${res['jmlMasihTerdampak'] ?? 0}) serta ${res['totalStokMinus'] ?? 0} barang berstok minus.';
        _teksWa = (res['teksAnalisisWa'] as String?) ?? '';
        _kronologi = ((res['kronologiPoin'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _solusi = ((res['langkahSolusi'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _error = 'Gagal menyusun analisis otomatis: $e';
      });
    }
  }

  Future<void> _salinWa() async {
    if (_teksWa.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _teksWa));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Naskah analisis berhasil disalin ke Clipboard (siap ditempel ke WhatsApp).'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool perProduk = widget.idProduk != null && widget.idProduk! > 0;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.indigo, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          perProduk
                              ? 'Analisis Cerdas Produk: ${widget.kodeProduk.isNotEmpty ? "${widget.kodeProduk} - " : ""}${widget.namaProduk}'
                              : 'Analisis Cerdas Pergerakan & Selisih Stok Toko',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Laporan otomatis kronologi penyebab perubahan stok & rekomendasi solusi (tanpa istilah teknis)',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _judulDiagnosis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        _penjelasanUtama,
                                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_kronologi.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Kronologi Kejadian Tercatat:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 6),
                                  ..._kronologi.take(8).map((k) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                                            Expanded(child: Text(k, style: const TextStyle(fontSize: 12))),
                                          ],
                                        ),
                                      )),
                                ],
                                if (_solusi.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Langkah Penyelesaian:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(height: 6),
                                  ..._solusi.map((s) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Icon(Icons.check_circle_outline,
                                                size: 15, color: Colors.green),
                                            const SizedBox(width: 6),
                                            Expanded(child: Text(s, style: const TextStyle(fontSize: 12))),
                                          ],
                                        ),
                                      )),
                                ],
                                const SizedBox(height: 14),
                                const Text(
                                  'Naskah Lengkap Siap Kirim WhatsApp (Non-Teknis):',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: SelectableText(
                                    _teksWa,
                                    style: const TextStyle(
                                      fontFamily: 'Consolas',
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: _memuat ? null : _salinWa,
                    icon: const Icon(Icons.copy, size: 17),
                    label: const Text('Salin Naskah WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
