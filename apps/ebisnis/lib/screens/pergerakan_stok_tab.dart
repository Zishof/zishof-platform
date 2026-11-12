import '../widgets/app_components.dart';
import 'dart:convert';
import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
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
        final lastDayPrevMonth =
            firstDayThisMonth.subtract(const Duration(days: 1));
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
      // Fallback ke produk_mutasi_ringkasan atau cache lokal bila server sedang sibuk / belum memuat stok_pergerakan_rekap
      try {
        final fallback = await StokAnalisisCerdasLokal.muatRekapFallback(
          tglMulai: _tglMulai,
          tglSampai: _tglSampai,
          keyword: _cariController.text.trim(),
          statusFilter: _statusFilter,
        );
        if (!mounted) return;
        setStateIfMounted(() {
          _data = (fallback['data'] as List<Map<String, dynamic>>);
          _ringkasanTotal = fallback['ringkasan'] as Map<String, dynamic>;
          _memuat = false;
        });
      } catch (_) {
        if (!mounted) return;
        setStateIfMounted(() {
          _memuat = false;
          _pesanError = 'Gagal memuat pergerakan stok: $e';
        });
      }
    }
  }

  Future<void> _eksporExcel() async {
    try {
      Uint8List bytes;
      String namaFile =
          'Pergerakan_Stok_${_formatTglParam(_tglMulai)}_${_formatTglParam(_tglSampai)}.xlsx';
      try {
        final res =
            await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
          'dari': _formatTglParam(_tglMulai),
          'sampai': _formatTglParam(_tglSampai),
          'q': _cariController.text.trim(),
          'status_filter': _statusFilter,
        });

        final b64 = res['fileBase64'] as String?;
        if (b64 == null || b64.isEmpty) {
          throw Exception('Server tidak mengembalikan file.');
        }
        bytes = base64Decode(b64);
        namaFile = (res['namaFile'] as String?) ?? namaFile;
      } catch (_) {
        // Fallback ekspor Excel lokal dari _data yang sedang tampil
        bytes = buildSimpleXlsx(
          sheetName: 'Pergerakan & Audit Stok',
          headers: const [
            'Grup / Kategori',
            'Kode Barang',
            'Nama Produk',
            'Stok Awal',
            'Masuk (+)',
            'Retur (+)',
            'Penjualan (-)',
            'Keluar Lain (-)',
            'Opname (+)',
            'Opname (-)',
            'Stok Akhir (Sisa)',
            'Status Audit',
          ],
          rows: _data
              .map((item) => [
                    item['kategori'] ?? '-',
                    item['kode'] ?? '-',
                    item['nama'] ?? '-',
                    item['awal'] ?? 0,
                    item['masuk'] ?? 0,
                    item['retur'] ?? 0,
                    item['penjualan'] ?? 0,
                    item['keluar'] ?? 0,
                    item['opnameMasuk'] ?? 0,
                    item['opnameKeluar'] ?? 0,
                    item['sisa'] ?? 0,
                    item['statusAudit'] ?? 'Normal',
                  ])
              .toList(),
        );
      }

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
        const SnackBar(
            content: Text('Tidak ada data pergerakan stok untuk dicetak.')),
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
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
              headerStyle:
                  pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name:
            'Rekap_Pergerakan_Stok_${_formatTglParam(_tglMulai)}_${_formatTglParam(_tglSampai)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak PDF: $e')),
      );
    }
  }

  void _intipRingkasanKategori(
      String judul, bool Function(Map<String, dynamic>) predikat) {
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

    // The stock table already contains a period summary. Use it immediately
    // so an older server that does not recognize the optional analysis action
    // cannot leave the operator with an empty analysis window.
    final ringkasanAwal = <String, dynamic>{
      for (final key in const [
        'awal',
        'masuk',
        'retur',
        'penjualan',
        'keluar',
        'opnameMasuk',
        'opnameKeluar',
        'sisa',
      ])
        if (item.containsKey(key)) key: item[key],
    };
    final analisisAwal = StokAnalisisCerdasLokal.susunAnalisisProdukDariData(
      namaProduk: (item['nama'] as String?) ?? 'Produk',
      kodeProduk: (item['kode'] as String?) ?? '',
      kategori: (item['kategori'] as String?) ?? '-',
      tglMulai: _tglMulai,
      tglSampai: _tglSampai,
      ringkasan: ringkasanAwal,
      mutasi: const [],
      hargaBeli: (item['hargaBeli'] as num?)?.toDouble() ?? 0,
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogAnalisisCerdasStok(
        idProduk: idProduk,
        namaProduk: (item['nama'] as String?) ?? 'Produk',
        kodeProduk: (item['kode'] as String?) ?? '',
        tglMulai: _tglMulai,
        tglSampai: _tglSampai,
        hasilAnalisisAwal: analisisAwal,
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

  Widget _buildSummaryMini(String title, num val, Color color,
      {VoidCallback? onTap}) {
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
            Text('$title: ',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            Text(
              _formatAngka.format(val),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.open_in_new,
                  size: 11, color: color.withValues(alpha: 0.7)),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.date_range,
                            size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatTglTampilan(_tglMulai)} - ${_formatTglTampilan(_tglSampai)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
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
                        DropdownMenuItem(
                            value: '', child: Text('Semua Status Barang')),
                        DropdownMenuItem(
                            value: 'ADA_MUTASI',
                            child: Text('Ada Mutasi / Loncat')),
                        DropdownMenuItem(
                            value: 'DINOLKAN_SO',
                            child: Text('Dinolkan saat Opname (SO -> 0)')),
                        DropdownMenuItem(
                            value: 'STOK_MINUS',
                            child: Text('Stok Akhir Minus (< 0)')),
                        DropdownMenuItem(
                            value: 'ADA_OPNAME',
                            child: Text('Ada Koreksi Opname (+/-)')),
                        DropdownMenuItem(
                            value: 'KODE_GANDA',
                            child: Text('Kode Barang Ganda / Duplikat')),
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

                AksiToolbarMenu(
                  tooltip: 'Aksi pergerakan stok',
                  aksi: [
                    AksiBaris(
                      ikon: Icons.refresh,
                      label: 'Cari / Muat',
                      onTap: () {
                        if (!_memuat) _muatData();
                      },
                    ),
                    AksiBaris(
                      ikon: Icons.auto_awesome,
                      label: 'Analisis Cerdas Toko',
                      onTap: () {
                        if (!_memuat) _bukaAnalisisCerdasToko();
                      },
                    ),
                    AksiBaris(
                      ikon: Icons.file_download_outlined,
                      label: 'Download Excel',
                      onTap: () {
                        if (!_memuat) _eksporExcel();
                      },
                    ),
                    AksiBaris(
                      ikon: Icons.picture_as_pdf_outlined,
                      label: 'Cetak PDF',
                      onTap: () {
                        if (!_memuat) _cetakPdfRekap();
                      },
                    ),
                  ],
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
                    onTap: () => _intipRingkasanKategori('Retur Penjualan',
                        (i) => ((i['retur'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Penjualan',
                    (_ringkasanTotal!['penjualan'] as num?) ?? 0,
                    Colors.orange,
                    onTap: () => _intipRingkasanKategori('Penjualan Kasir',
                        (i) => ((i['penjualan'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Keluar',
                    (_ringkasanTotal!['keluar'] as num?) ?? 0,
                    Colors.red,
                    onTap: () => _intipRingkasanKategori('Total Barang Keluar',
                        (i) => ((i['keluar'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Opname (+)',
                    (_ringkasanTotal!['opnameMasuk'] as num?) ?? 0,
                    Colors.purple,
                    onTap: () => _intipRingkasanKategori('Koreksi Opname (+)',
                        (i) => ((i['opnameMasuk'] as num?) ?? 0) > 0),
                  ),
                  _buildSummaryMini(
                    'Opname (-)',
                    (_ringkasanTotal!['opnameKeluar'] as num?) ?? 0,
                    Colors.pink,
                    onTap: () => _intipRingkasanKategori('Koreksi Opname (-)',
                        (i) => ((i['opnameKeluar'] as num?) ?? 0) > 0),
                  ),
                  if (((_ringkasanTotal!['jmlDinolkanSo'] as num?) ?? 0) > 0)
                    _buildSummaryMini(
                      'SO->0',
                      (_ringkasanTotal!['jmlDinolkanSo'] as num?) ?? 0,
                      Colors.deepOrange,
                      onTap: () => _intipRingkasanKategori(
                          'Barang Dinolkan saat SO',
                          (i) => i['statusKode'] == 'DINOLKAN_SO'),
                    ),
                  if (((_ringkasanTotal!['jmlStokMinus'] as num?) ?? 0) > 0)
                    _buildSummaryMini(
                      'Stok Minus',
                      (_ringkasanTotal!['jmlStokMinus'] as num?) ?? 0,
                      Colors.red.shade900,
                      onTap: () => _intipRingkasanKategori(
                          'Barang Stok Minus (< 0)',
                          (i) => ((i['sisa'] as num?) ?? 0) < 0),
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
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 40),
                          const SizedBox(height: 8),
                          Text(_pesanError!),
                          const SizedBox(height: 8),
                          ElevatedButton(
                              onPressed: _muatData,
                              child: const Text('Coba Lagi')),
                        ],
                      ),
                    )
                  : _data.isEmpty
                      ? const Center(
                          child: Text(
                              'Tidak ada pergerakan stok pada periode ini.'))
                      : Card(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: AppPagedDataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    isDark
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade100,
                                  ),
                                  columnSpacing: 18,
                                  columns: const [
                                    DataColumn(
                                        label: Text('Grup',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    DataColumn(
                                        label: Text('Produk',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Awal',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Masuk',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Pengembalian',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Penjualan',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.orange))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Keluar',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Opname (+)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.purple))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Opname (-)',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.pink))),
                                    DataColumn(
                                        numeric: true,
                                        label: Text('Sisa',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    DataColumn(
                                        label: Text('Status / Jejak Selisih',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                    DataColumn(
                                        label: Text('Aksi',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _data.map((item) {
                                    final awal =
                                        (item['awal'] as num?)?.toDouble() ?? 0;
                                    final masuk =
                                        (item['masuk'] as num?)?.toDouble() ??
                                            0;
                                    final retur =
                                        (item['retur'] as num?)?.toDouble() ??
                                            0;
                                    final penjualan =
                                        (item['penjualan'] as num?)
                                                ?.toDouble() ??
                                            0;
                                    final keluar =
                                        (item['keluar'] as num?)?.toDouble() ??
                                            0;
                                    final opnameMasuk =
                                        (item['opnameMasuk'] as num?)
                                                ?.toDouble() ??
                                            0;
                                    final opnameKeluar =
                                        (item['opnameKeluar'] as num?)
                                                ?.toDouble() ??
                                            0;
                                    final sisa =
                                        (item['sisa'] as num?)?.toDouble() ?? 0;
                                    final statusKode =
                                        (item['statusKode'] as String?) ??
                                            'NORMAL';
                                    final statusAudit =
                                        (item['statusAudit'] as String?) ??
                                            'Normal';

                                    Color statusColor = Colors.teal.shade700;
                                    if (statusKode == 'DINOLKAN_SO' ||
                                        statusKode == 'STOK_MINUS' ||
                                        statusKode == 'SELISIH_FORMULA') {
                                      statusColor = Colors.red.shade800;
                                    } else if (statusKode == 'KOREKSI_SO') {
                                      statusColor = Colors.deepOrange.shade800;
                                    } else if (statusKode == 'PULIH_SO' ||
                                        statusKode == 'HABIS_TERJUAL') {
                                      statusColor = Colors.blue.shade800;
                                    }

                                    return DataRow(
                                      onSelectChanged: (_) =>
                                          _bukaDetailProduk(item),
                                      cells: [
                                        DataCell(Text(
                                            (item['kategori'] as String?) ??
                                                '-')),
                                        DataCell(
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                (item['nama'] as String?) ??
                                                    '-',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                              if ((item['kode'] as String?)
                                                      ?.isNotEmpty ==
                                                  true)
                                                Text(
                                                  '${item['kode']}',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.grey.shade600),
                                                ),
                                            ],
                                          ),
                                        ),
                                        DataCell(
                                            Text(_formatAngka.format(awal))),
                                        DataCell(Text(
                                          _formatAngka.format(masuk),
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(retur),
                                          style: const TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(penjualan),
                                          style: const TextStyle(
                                              color: Colors.orange,
                                              fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(keluar),
                                          style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          opnameMasuk > 0
                                              ? '+${_formatAngka.format(opnameMasuk)}'
                                              : '0',
                                          style: TextStyle(
                                            color: opnameMasuk > 0
                                                ? Colors.purple.shade700
                                                : Colors.grey,
                                            fontWeight: opnameMasuk > 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(Text(
                                          opnameKeluar > 0
                                              ? '-${_formatAngka.format(opnameKeluar)}'
                                              : '0',
                                          style: TextStyle(
                                            color: opnameKeluar > 0
                                                ? Colors.pink.shade700
                                                : Colors.grey,
                                            fontWeight: opnameKeluar > 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        )),
                                        DataCell(
                                          Text(
                                            _formatAngka.format(sisa),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: sisa < 0
                                                  ? Colors.red.shade800
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Container(
                                            constraints: const BoxConstraints(
                                                maxWidth: 260),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                  color: statusColor.withValues(
                                                      alpha: 0.3)),
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
                                              label:
                                                  'Analisis Cerdas Produk (Siap WA)',
                                              onTap: () =>
                                                  _bukaAnalisisCerdasProduk(
                                                      item),
                                            ),
                                            AksiBaris(
                                              ikon: Icons.receipt_long_outlined,
                                              label: 'Lihat Buku Besar Mutasi',
                                              onTap: () =>
                                                  _bukaDetailProduk(item),
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
  State<DialogDetailPergerakanStok> createState() =>
      _DialogDetailPergerakanStokState();
}

class _DialogDetailPergerakanStokState
    extends State<DialogDetailPergerakanStok> {
  bool _memuat = true;
  String? _pesanError;
  Map<String, dynamic>? _ringkasan;
  List<Map<String, dynamic>> _mutasi = [];
  Map<String, dynamic>? _analisisProduk;
  String _filterKartuAktif = 'SEMUA';

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
      Map<String, dynamic>? ringkasanData;
      List<Map<String, dynamic>> mutasiList = [];
      double hargaBeli = 0;

      try {
        final res = await ApiClient.instance.aksi('stok_pergerakan_detail', {
          'id': widget.idProduk,
          'dari': _formatTglParam(widget.tglMulai),
          'sampai': _formatTglParam(widget.tglSampai),
        });
        ringkasanData = (res['ringkasan'] as Map?)?.cast<String, dynamic>();
        final List rawMutasi = (res['mutasi'] as List?) ?? [];
        mutasiList =
            rawMutasi.map((e) => (e as Map).cast<String, dynamic>()).toList();
        final pObj = (res['produk'] as Map?)?.cast<String, dynamic>();
        hargaBeli = (pObj?['hargaBeli'] as num?)?.toDouble() ?? 0;
      } catch (_) {
        // Fallback tangguh apabila server sedang restart (HTTP 503) atau belum memuat stok_pergerakan_detail
        final fb = await StokAnalisisCerdasLokal.muatDetailProdukFallback(
          idProduk: widget.idProduk,
          namaProduk: widget.namaProduk,
          kodeProduk: widget.kodeProduk,
          kategori: widget.kategori,
          tglMulai: widget.tglMulai,
          tglSampai: widget.tglSampai,
        );
        ringkasanData = fb['ringkasan'] as Map<String, dynamic>?;
        mutasiList = (fb['mutasi'] as List<Map<String, dynamic>>?) ?? [];
        hargaBeli = (fb['hargaBeli'] as num?)?.toDouble() ?? 0;
      }

      if (!mounted) return;

      final analisisLokal = StokAnalisisCerdasLokal.susunAnalisisProdukDariData(
        namaProduk: widget.namaProduk,
        kodeProduk: widget.kodeProduk,
        kategori: widget.kategori,
        tglMulai: widget.tglMulai,
        tglSampai: widget.tglSampai,
        ringkasan: ringkasanData ?? const {},
        mutasi: mutasiList,
        hargaBeli: hargaBeli,
      );

      setStateIfMounted(() {
        _ringkasan = ringkasanData;
        _mutasi = mutasiList;
        _analisisProduk = analisisLokal;
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

  Future<void> _salinAnalisisWaProduk() async {
    final teks = (_analisisProduk?['teksAnalisisWa'] as String?) ?? '';
    if (teks.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: teks));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Naskah hasil analisis cerdas berhasil disalin ke Clipboard (siap ditempel ke WhatsApp).'),
      ),
    );
  }

  Future<void> _eksporExcelProduk() async {
    try {
      final res =
          await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
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
                style:
                    pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
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
                      ? (oleh.isNotEmpty && oleh != namaPel
                          ? '$namaPel ($oleh)'
                          : namaPel)
                      : (oleh.isNotEmpty
                          ? oleh
                          : (tipe.isNotEmpty ? tipe : '-'));
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
              headerStyle:
                  pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        onLayout: (_) async => doc.save(),
        name:
            'Buku_Besar_${widget.kodeProduk.isEmpty ? widget.idProduk : widget.kodeProduk}.pdf',
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
        hasilAnalisisAwal: _analisisProduk,
        gunakanHasilAwalSaja: true,
      ),
    );
  }

  static final NumberFormat _fmtRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _cocokFilterKartu(Map<String, dynamic> m) {
    if (_filterKartuAktif == 'SEMUA') return true;
    final kode = '${m['kodeMutasi'] ?? ''}';
    final masuk = (m['masuk'] as num?)?.toDouble() ?? 0;
    final keluar = (m['keluar'] as num?)?.toDouble() ?? 0;
    switch (_filterKartuAktif) {
      case 'MASUK':
        return (kode == '101' || kode == '102' || kode == '105') && masuk > 0;
      case 'RETUR':
        return kode == '103';
      case 'PENJUALAN':
        return kode == '200';
      case 'KELUAR':
        return (kode == '201' || kode == '202' || kode == '203' || kode == '105') &&
            keluar > 0;
      case 'OPNAME_PLUS':
        return kode == '104' && masuk > 0;
      case 'OPNAME_MINUS':
        return kode == '104' && keluar > 0;
      default:
        return true;
    }
  }

  /// Membuka rincian faktur pembelian, faktur penjualan kasir POS, bukti stok
  /// opname, retur, maupun transfer antar outlet saat salah satu angka / baris
  /// pada Rincian Mutasi diklik pengguna.
  Future<void> _bukaBuktiMutasi(Map<String, dynamic> m) async {
    final kode = '${m['kodeMutasi'] ?? ''}';
    final sumberId = (m['sumberId'] as num?)?.toInt() ?? 0;
    final dokumenId = (m['dokumenId'] as num?)?.toInt() ?? 0;
    final ref = '${m['referensi'] ?? m['noFaktur'] ?? ''}'.trim();
    final tokoId = Sesi.instance.idTokoTerpilih;

    try {
      // 1. Faktur Penjualan Kasir POS (kode 200)
      if (kode == '200' && (dokumenId > 0 || ref.isNotEmpty)) {
        final res = await ApiClient.instance.aksi('detail_transaksi', {
          if (tokoId != null && tokoId > 0) 'toko_id': tokoId,
          if (dokumenId > 0) 'id': dokumenId,
          if (ref.isNotEmpty) 'kode': ref,
        });
        if (!mounted) return;
        final items = ((res['item'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (items.isNotEmpty) {
          final kodeNota = '${res['kode'] ?? ref}';
          final waktu = '${res['waktu'] ?? m['tanggal'] ?? ''}';
          final kasir = '${res['kasirNama'] ?? res['kasirUserId'] ?? '-'}';
          final caraBayar = '${res['caraBayarNama'] ?? '-'}';
          final totalBiaya = (res['totalBiaya'] as num?)?.toDouble() ?? 0;
          await tampilkanRincianKlikDialog(
            context,
            judul: 'Faktur Penjualan Kasir · $kodeNota',
            subjudul:
                'Waktu: $waktu | Kasir: $kasir | Pembayaran: $caraBayar | Pelanggan: ${m['namaPelanggan'] ?? 'Umum'}',
            ringkasanTeks:
                'Total Nota: ${_fmtRupiah.format(totalBiaya)} · Bayar Tunai: ${_fmtRupiah.format((res['bayarTunai'] as num?) ?? 0)} · Non-Tunai: ${_fmtRupiah.format((res['bayarNonTunai'] as num?) ?? 0)}',
            kolom: const [
              'No',
              'Nama Barang',
              'Rak',
              'Qty',
              'Harga Satuan',
              'Diskon',
              'Subtotal',
            ],
            baris: [
              for (var i = 0; i < items.length; i++)
                [
                  i + 1,
                  items[i]['nama'] ?? '-',
                  items[i]['rakNama'] ?? '-',
                  _formatAngka.format((items[i]['qty'] as num?) ?? 0),
                  _fmtRupiah.format((items[i]['harga'] as num?) ?? 0),
                  _fmtRupiah.format((items[i]['diskon'] as num?) ?? 0),
                  _fmtRupiah.format(
                    (((items[i]['qty'] as num?)?.toDouble() ?? 0) *
                            ((items[i]['harga'] as num?)?.toDouble() ?? 0)) -
                        ((items[i]['diskon'] as num?)?.toDouble() ?? 0),
                  ),
                ],
            ],
          );
          return;
        }
      }

      // 2. Faktur Pembelian / Pengadaan / BAST (kode 101 atau acuan retur beli 201)
      if ((kode == '101' || kode == '201') && dokumenId > 0) {
        final res = await ApiClient.instance.aksi('kulakan_faktur_detail', {
          if (tokoId != null && tokoId > 0) 'toko_id': tokoId,
          'faktur_id': dokumenId,
        });
        if (!mounted) return;
        final header = (res['header'] as Map?)?.cast<String, dynamic>() ?? {};
        final items = ((res['items'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (items.isNotEmpty) {
          final noFak = '${header['nomorFaktur'] ?? ref}';
          await tampilkanRincianKlikDialog(
            context,
            judul: 'Faktur Pembelian / Pengadaan · $noFak',
            subjudul:
                'Tanggal: ${header['tanggalFaktur'] ?? m['tanggal'] ?? '-'} | Supplier: ${header['namaSupplier'] ?? m['namaPelanggan'] ?? '-'} | Status: ${header['jenisPembayaran'] ?? '-'}',
            ringkasanTeks:
                'Total Bersih Faktur: ${_fmtRupiah.format((header['totalBersih'] as num?) ?? 0)}',
            kolom: const [
              'No',
              'Nama Barang',
              'Qty Masuk',
              'Harga Beli',
              'Diskon',
              'Subtotal',
            ],
            baris: [
              for (var i = 0; i < items.length; i++)
                [
                  i + 1,
                  items[i]['namaProduk'] ?? items[i]['nama'] ?? '-',
                  _formatAngka.format((items[i]['qty'] as num?) ?? 0),
                  _fmtRupiah.format((items[i]['hargaBeli'] as num?) ?? 0),
                  _fmtRupiah.format((items[i]['diskon'] as num?) ?? 0),
                  _fmtRupiah.format((items[i]['subtotal'] as num?) ?? 0),
                ],
            ],
          );
          return;
        }
      }

      // 3. Bukti Stok Opname (104), Retur (103/201), Transfer (102/203), Bahan/Produksi (202/105), atau Pengadaan legacy
      if (sumberId > 0 && kode.isNotEmpty && kode != '100') {
        final res = await ApiClient.instance.aksi('stok_mutasi_bukti_detail', {
          if (tokoId != null && tokoId > 0) 'toko_id': tokoId,
          'kodeMutasi': kode,
          'sumberId': sumberId,
        });
        if (!mounted) return;
        final barisServer = ((res['baris'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (barisServer.isNotEmpty) {
          await tampilkanRincianKlikDialog(
            context,
            judul: '${res['judul'] ?? 'Bukti Transaksi'} · ${widget.namaProduk}',
            subjudul:
                'Kode Produk: ${widget.kodeProduk} | Referensi: ${ref.isEmpty ? '-' : ref}',
            kolom: const ['Informasi', 'Rincian Bukti Tercatat'],
            baris: [
              for (final b in barisServer) [b['label'] ?? '-', b['nilai'] ?? '-'],
              ['Stok Sebelum Transaksi', _formatAngka.format((m['awal'] as num?) ?? 0)],
              ['Perubahan Masuk', _formatAngka.format((m['masuk'] as num?) ?? 0)],
              ['Perubahan Keluar', _formatAngka.format((m['keluar'] as num?) ?? 0)],
              ['Saldo Stok Sesudah', _formatAngka.format((m['sisa'] as num?) ?? 0)],
            ],
          );
          return;
        }
      }
    } catch (_) {
      // Jatuh ke ringkasan lokal di bawah bila offline atau endpoint belum tersedia
    }

    if (!mounted) return;
    await tampilkanRincianKlikDialog(
      context,
      judul: '${m['tipe'] ?? 'Rincian Mutasi'} · ${widget.namaProduk}',
      subjudul: 'Waktu: ${m['tanggal'] ?? '-'} | Referensi: ${ref.isEmpty ? '-' : ref}',
      kolom: const ['Informasi', 'Nilai'],
      baris: [
        ['Jenis Transaksi', '${m['tipe'] ?? '-'} (Kode $kode)'],
        ['Nomor Referensi / Faktur', ref.isEmpty ? '-' : ref],
        ['Pelanggan / Supplier / Petugas', m['namaPelanggan'] ?? m['oleh'] ?? '-'],
        ['Saldo Sebelum', _formatAngka.format((m['awal'] as num?) ?? 0)],
        ['Masuk (+)', _formatAngka.format((m['masuk'] as num?) ?? 0)],
        ['Keluar (-)', _formatAngka.format((m['keluar'] as num?) ?? 0)],
        ['Saldo Akhir', _formatAngka.format((m['sisa'] as num?) ?? 0)],
        ['Keterangan Audit', m['keterangan'] ?? '-'],
      ],
    );
  }

  void _klikKartuRingkasan(String kunciFilter, String judul, num nilai) {
    if (kunciFilter == 'SALDO_AWAL' || kunciFilter == 'SALDO_AKHIR') {
      final awal = (_ringkasan?['awal'] as num?)?.toDouble() ?? 0;
      final masuk = (_ringkasan?['masuk'] as num?)?.toDouble() ?? 0;
      final retur = (_ringkasan?['retur'] as num?)?.toDouble() ?? 0;
      final penjualan = (_ringkasan?['penjualan'] as num?)?.toDouble() ?? 0;
      final keluar = (_ringkasan?['keluar'] as num?)?.toDouble() ?? 0;
      final opPlus = (_ringkasan?['opnameMasuk'] as num?)?.toDouble() ?? 0;
      final opMin = (_ringkasan?['opnameKeluar'] as num?)?.toDouble() ?? 0;
      final sisa = (_ringkasan?['sisa'] as num?)?.toDouble() ?? 0;
      tampilkanRincianKlikDialog(
        context,
        judul: '$judul · ${widget.namaProduk}',
        subjudul:
            'Periode ${_formatTglTampilan(widget.tglMulai)} s/d ${_formatTglTampilan(widget.tglSampai)}',
        kolom: const ['Komponen Perhitungan Stok', 'Kuantitas'],
        baris: [
          ['Saldo Awal Periode (${_formatTglTampilan(widget.tglMulai)} 00:00)', _formatAngka.format(awal)],
          ['(+) Pengadaan / Masuk', '+${_formatAngka.format(masuk)}'],
          ['(+) Pengembalian (Retur Penjualan)', '+${_formatAngka.format(retur)}'],
          ['(-) Penjualan Kasir POS', '-${_formatAngka.format(penjualan)}'],
          ['(-) Pengeluaran Lain (Retur Beli / Transfer / Bahan)', '-${_formatAngka.format(keluar)}'],
          ['(+) Penyesuaian Stok Opname (+)', '+${_formatAngka.format(opPlus)}'],
          ['(-) Penyesuaian Stok Opname (-)', '-${_formatAngka.format(opMin)}'],
          ['(=) Saldo Akhir Periode', _formatAngka.format(sisa)],
        ],
      );
      return;
    }
    setStateIfMounted(() {
      _filterKartuAktif =
          _filterKartuAktif == kunciFilter ? 'SEMUA' : kunciFilter;
    });
  }

  Widget _buildSummaryCard(
      String title, num val, Color color, String kunciFilter) {
    final aktif = _filterKartuAktif == kunciFilter;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: color.withValues(alpha: aktif ? 0.18 : 0.08),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _klikKartuRingkasan(kunciFilter, title, val),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: aktif ? color : color.withValues(alpha: 0.3),
                  width: aktif ? 2.0 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatAngka.format(val),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                      decoration: TextDecoration.underline,
                      decorationColor: color.withValues(alpha: 0.5),
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
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kode: ${widget.kodeProduk.isNotEmpty ? widget.kodeProduk : '-'} | Grup: ${widget.kategori} | Periode: ${_formatTglTampilan(widget.tglMulai)} - ${_formatTglTampilan(widget.tglSampai)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  AksiToolbarMenu(tooltip: 'Aksi rincian mutasi', aksi: [
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

              // 8 Summary Cards (semua angka dapat diklik untuk filter / rincian)
              Row(
                children: [
                  _buildSummaryCard(
                      'Saldo Awal', awal, Colors.blueGrey, 'SALDO_AWAL'),
                  _buildSummaryCard('Masuk', masuk, Colors.green, 'MASUK'),
                  _buildSummaryCard(
                      'Pengembalian', retur, Colors.blue, 'RETUR'),
                  _buildSummaryCard(
                      'Penjualan', penjualan, Colors.orange, 'PENJUALAN'),
                  _buildSummaryCard('Keluar', keluar, Colors.red, 'KELUAR'),
                  _buildSummaryCard(
                      'Opname (+)', opnameMasuk, Colors.purple, 'OPNAME_PLUS'),
                  _buildSummaryCard(
                      'Opname (-)', opnameKeluar, Colors.pink, 'OPNAME_MINUS'),
                  _buildSummaryCard(
                      'Saldo Akhir', sisa, Colors.indigo, 'SALDO_AKHIR'),
                ],
              ),
              if (_filterKartuAktif != 'SEMUA') ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    label: Text('Filter aktif: $_filterKartuAktif (Klik untuk tampilkan semua)'),
                    onDeleted: () =>
                        setStateIfMounted(() => _filterKartuAktif = 'SEMUA'),
                    onPressed: () =>
                        setStateIfMounted(() => _filterKartuAktif = 'SEMUA'),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Tabel Rincian Buku Besar Mutasi
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _pesanError != null
                        ? Center(
                            child: Text(_pesanError!,
                                style: const TextStyle(color: Colors.red)))
                        : _ringkasan == null
                            ? const Center(
                                child: Text(
                                    'Belum ada catatan mutasi transaksi pada rentang ini.'))
                            : Container(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: AppPagedDataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                                Colors.grey.shade100),
                                        columnSpacing: 22,
                                        columns: const [
                                          DataColumn(
                                              label: Text('No',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Tanggal & Jam',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('No Faktur',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Kode Mutasi',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('ID Pelanggan',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Pelanggan / Petugas',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Saldo Awal',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Masuk',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.green))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Keluar',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.red))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Saldo Akhir',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text(
                                                  'Rincian Audit / Keterangan',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                        ],
                                        rows: [
                                          if (_filterKartuAktif == 'SEMUA')
                                            _barisSaldoAwal(awal),
                                          ..._mutasi
                                              .where(_cocokFilterKartu)
                                              .toList()
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            final idx = entry.key + 2;
                                            final m = entry.value;
                                            final tAwal = (m['awal'] as num?)
                                                    ?.toDouble() ??
                                                0;
                                            final tMasuk = (m['masuk'] as num?)
                                                    ?.toDouble() ??
                                                0;
                                            final tKeluar =
                                                (m['keluar'] as num?)
                                                        ?.toDouble() ??
                                                    0;
                                            final tSisa = (m['sisa'] as num?)
                                                    ?.toDouble() ??
                                                0;
                                            final tipe =
                                                (m['tipe'] as String?) ?? '';
                                            final ref =
                                                (m['referensi'] as String?) ??
                                                    '';
                                            final kodeMutasi =
                                                (m['kodeMutasi'] as String?) ??
                                                    '000';
                                            final idPel =
                                                (m['idPelanggan'] as String?) ??
                                                    '';
                                            final namaPel = (m['namaPelanggan']
                                                    as String?) ??
                                                '';
                                            final oleh =
                                                (m['oleh'] as String?) ?? '';
                                            final ket =
                                                (m['keterangan'] as String?) ??
                                                    '';

                                            Color badgeColor =
                                                Colors.grey.shade700;
                                            if (tipe.contains('Penjualan')) {
                                              badgeColor =
                                                  Colors.orange.shade800;
                                            } else if (tipe
                                                .contains('Pembelian')) {
                                              badgeColor =
                                                  Colors.green.shade800;
                                            } else if (tipe.contains('Retur')) {
                                              badgeColor = Colors.blue.shade800;
                                            } else if (tipe
                                                    .contains('Opname') ||
                                                tipe.contains('Penyesuaian')) {
                                              badgeColor =
                                                  Colors.purple.shade800;
                                            }

                                            final String pelaku =
                                                namaPel.isNotEmpty
                                                    ? (oleh.isNotEmpty &&
                                                            oleh != namaPel
                                                        ? '$namaPel ($oleh)'
                                                        : namaPel)
                                                    : (oleh.isNotEmpty
                                                        ? oleh
                                                        : (tipe.isNotEmpty
                                                            ? tipe
                                                            : '-'));

                                            return DataRow(
                                              cells: [
                                                DataCell(Text('$idx'),
                                                    onTap: () =>
                                                        _bukaBuktiMutasi(m)),
                                                DataCell(
                                                    Text(
                                                        (m['tanggal']
                                                                as String?) ??
                                                            '-'),
                                                    onTap: () =>
                                                        _bukaBuktiMutasi(m)),
                                                DataCell(
                                                  Text(
                                                    ref.isEmpty ? '-' : ref,
                                                    style: TextStyle(
                                                      color: Colors.blue.shade800,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          badgeColor.withValues(
                                                              alpha: 0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      kodeMutasi,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: badgeColor,
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                    Text(idPel.isEmpty
                                                        ? '-'
                                                        : idPel),
                                                    onTap: () =>
                                                        _bukaBuktiMutasi(m)),
                                                DataCell(Text(pelaku),
                                                    onTap: () =>
                                                        _bukaBuktiMutasi(m)),
                                                DataCell(
                                                  Text(
                                                    _formatAngka.format(tAwal),
                                                    style: const TextStyle(
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                  Text(
                                                    tMasuk > 0
                                                        ? '+${_formatAngka.format(tMasuk)}'
                                                        : '-',
                                                    style: TextStyle(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: tMasuk > 0
                                                          ? TextDecoration
                                                              .underline
                                                          : null,
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                  Text(
                                                    tKeluar > 0
                                                        ? '-${_formatAngka.format(tKeluar)}'
                                                        : '-',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      decoration: tKeluar > 0
                                                          ? TextDecoration
                                                              .underline
                                                          : null,
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                  Text(
                                                    _formatAngka.format(tSisa),
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      decoration: TextDecoration
                                                          .underline,
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
                                                ),
                                                DataCell(
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                            maxWidth: 320),
                                                    child: Text(
                                                      ket.isNotEmpty
                                                          ? ket
                                                          : tipe,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 2,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                        color: tipe.contains(
                                                                'Opname')
                                                            ? Colors
                                                                .purple.shade900
                                                            : Colors
                                                                .grey.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () =>
                                                      _bukaBuktiMutasi(m),
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
              if (!_memuat &&
                  _pesanError == null &&
                  _analisisProduk != null) ...[
                const SizedBox(height: 12),
                Container(
                  constraints:
                      const BoxConstraints(minHeight: 165, maxHeight: 235),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.indigo.withValues(alpha: 0.28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: Colors.indigo, size: 19),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Hasil Analisis Cerdas: ${(_analisisProduk?['judulDiagnosis'] as String?) ?? 'Ringkasan Mutasi Produk'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AksiToolbarMenu(
                            tooltip: 'Aksi hasil analisis',
                            aksi: [
                              AksiBaris(
                                ikon: Icons.copy,
                                label: 'Salin Naskah WhatsApp',
                                onTap: _salinAnalisisWaProduk,
                              ),
                              AksiBaris(
                                ikon: Icons.open_in_full,
                                label: 'Buka Analisis Lengkap',
                                onTap: _bukaAnalisisCerdas,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                (_analisisProduk?['penjelasanUtama']
                                        as String?) ??
                                    '',
                                style: const TextStyle(
                                    fontSize: 12.2, height: 1.4),
                              ),
                              if (((_analisisProduk?['kronologiPoin']
                                          as List?) ??
                                      const [])
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Kronologi Kejadian Tercatat:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                ...((_analisisProduk?['kronologiPoin']
                                            as List?) ??
                                        const [])
                                    .map((k) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 3),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text('• ',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 11.5)),
                                              Expanded(
                                                child: Text('$k',
                                                    style: const TextStyle(
                                                        fontSize: 11.5)),
                                              ),
                                            ],
                                          ),
                                        )),
                              ],
                              if (((_analisisProduk?['langkahSolusi']
                                          as List?) ??
                                      const [])
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Rekomendasi & Langkah Penyelesaian:',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                ...((_analisisProduk?['langkahSolusi']
                                            as List?) ??
                                        const [])
                                    .map((s) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 3),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                  Icons.check_circle_outline,
                                                  size: 14,
                                                  color: Colors.green),
                                              const SizedBox(width: 5),
                                              Expanded(
                                                child: Text('$s',
                                                    style: const TextStyle(
                                                        fontSize: 11.5)),
                                              ),
                                            ],
                                          ),
                                        )),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  /// Reuses a diagnosis already built from the visible, period-scoped ledger.
  /// This keeps the analysis useful when the optional server analysis action
  /// is unavailable and avoids repeating a request for data already loaded.
  final Map<String, dynamic>? hasilAnalisisAwal;

  /// When true, the parent supplied the complete ledger-based diagnosis, so
  /// this dialog must not issue another request or replace it with stale data.
  final bool gunakanHasilAwalSaja;

  const DialogAnalisisCerdasStok({
    super.key,
    required this.idProduk,
    required this.namaProduk,
    required this.kodeProduk,
    required this.tglMulai,
    required this.tglSampai,
    this.hasilAnalisisAwal,
    this.gunakanHasilAwalSaja = false,
  });

  @override
  State<DialogAnalisisCerdasStok> createState() =>
      _DialogAnalisisCerdasStokState();
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
    if (widget.gunakanHasilAwalSaja && widget.hasilAnalisisAwal != null) {
      _terapkanAnalisisKeState(widget.hasilAnalisisAwal!);
      _memuat = false;
      return;
    }
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    final bool perProduk = widget.idProduk != null && widget.idProduk! > 0;
    Map<String, dynamic> res;
    try {
      res = await ApiClient.instance.aksi(
        perProduk ? 'stok_analisis_cerdas_produk' : 'stok_analisis_cerdas_toko',
        {
          if (perProduk) 'id': widget.idProduk,
          'dari': _formatTglParam(widget.tglMulai),
          'sampai': _formatTglParam(widget.tglSampai),
        },
      );
    } catch (e) {
      if (!_bolehPakaiFallbackAnalisis(e)) {
        final awal = widget.hasilAnalisisAwal;
        if (awal != null) {
          _terapkanAnalisis(awal);
          return;
        }
        if (!mounted) return;
        setStateIfMounted(() {
          _memuat = false;
          _error =
              'Analisis belum dapat dimuat untuk akun dan toko ini. Periksa akses, lalu coba lagi.';
        });
        return;
      }
      // Fallback otomatis multi-lapis agar pengguna TIDAK PERNAH melihat pesan
      // "Aksi tidak dikenal" atau "HTTP 503" saat server sedang restart/belum update.
      try {
        res = perProduk
            ? await StokAnalisisCerdasLokal.susunAnalisisProdukFallback(
                idProduk: widget.idProduk!,
                namaProduk: widget.namaProduk,
                kodeProduk: widget.kodeProduk,
                tglMulai: widget.tglMulai,
                tglSampai: widget.tglSampai,
              )
            : await StokAnalisisCerdasLokal.susunAnalisisTokoFallback(
                tglMulai: widget.tglMulai,
                tglSampai: widget.tglSampai,
              );
      } catch (eFallback) {
        final hasilAwal = widget.hasilAnalisisAwal;
        if (hasilAwal != null) {
          if (!mounted) return;
          setStateIfMounted(() {
            _terapkanAnalisisKeState(hasilAwal);
            _memuat = false;
            _error = null;
          });
          return;
        }
        if (!mounted) return;
        setStateIfMounted(() {
          _memuat = false;
          // Do not expose transport/server internals to the operator. Keep the
          // action recoverable from the kebab menu and state the next step.
          _error =
              'Analisis belum dapat disusun dari data yang tersedia. Periksa koneksi, lalu pilih Coba Lagi.';
        });
        return;
      }
    }

    if (!mounted) return;
    setStateIfMounted(() {
      _terapkanAnalisisKeState(res);
      _memuat = false;
    });
  }

  /// Only transport outages and a server that explicitly lacks this optional
  /// read action may use a local/alternate read fallback. Authentication,
  /// permission, and business-rule rejections must remain visible and must not
  /// be disguised as successful analysis from a different data source.
  bool _bolehPakaiFallbackAnalisis(Object error) {
    if (error is! ApiException) return true;
    if (error.offline) return true;
    final pesan = error.pesan.toLowerCase();
    return pesan.contains('aksi tidak dikenal') ||
        pesan.contains('fitur belum tersedia') ||
        pesan.contains('action not found');
  }

  /// Applies the same result shape from either the server or local ledger.
  /// Keeping one mapper prevents an offline fallback from silently omitting
  /// chronology, suggested checks, or the copy-ready operator message.
  void _terapkanAnalisisKeState(Map<String, dynamic> res) {
    _judulDiagnosis = (res['judulDiagnosis'] as String?) ??
        'Ringkasan Eksekutif Audit Pergerakan & Selisih Stok ${res['namaToko'] ?? 'Toko'}';
    _penjelasanUtama = (res['penjelasanUtama'] as String?) ??
        'Ditemukan ${res['totalProdukDinolkan'] ?? 0} jenis barang sempat dinolkan saat Stok Opname (Sudah pulih: ${res['jmlSudahPulih'] ?? 0}, Masih 0/minus: ${res['jmlMasihTerdampak'] ?? 0}) serta ${res['totalStokMinus'] ?? 0} barang berstok minus.';
    _teksWa = (res['teksAnalisisWa'] as String?) ?? '';
    _kronologi =
        ((res['kronologiPoin'] as List?) ?? const []).map((e) => '$e').toList();
    _solusi =
        ((res['langkahSolusi'] as List?) ?? const []).map((e) => '$e').toList();
  }

  void _terapkanAnalisis(Map<String, dynamic> res) {
    if (!mounted) return;
    setStateIfMounted(() {
      _terapkanAnalisisKeState(res);
      _memuat = false;
      _error = null;
    });
  }

  Future<void> _salinWa() async {
    if (_teksWa.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _teksWa));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Naskah analisis berhasil disalin ke Clipboard (siap ditempel ke WhatsApp).'),
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
                  const Icon(Icons.auto_awesome,
                      color: Colors.indigo, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          perProduk
                              ? 'Analisis Cerdas Produk: ${widget.kodeProduk.isNotEmpty ? "${widget.kodeProduk} - " : ""}${widget.namaProduk}'
                              : 'Analisis Cerdas Pergerakan & Selisih Stok Toko',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Laporan otomatis kronologi penyebab perubahan stok & rekomendasi solusi (tanpa istilah teknis)',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red)))
                        : SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.indigo.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: Colors.indigo
                                            .withValues(alpha: 0.3)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        style: const TextStyle(
                                            fontSize: 12.5, height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_kronologi.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Kronologi Kejadian Tercatat:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 6),
                                  ..._kronologi.map((k) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('• ',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Expanded(
                                                child: Text(k,
                                                    style: const TextStyle(
                                                        fontSize: 12))),
                                          ],
                                        ),
                                      )),
                                ],
                                if (_solusi.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Langkah Penyelesaian:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 6),
                                  ..._solusi.map((s) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                                Icons.check_circle_outline,
                                                size: 15,
                                                color: Colors.green),
                                            const SizedBox(width: 6),
                                            Expanded(
                                                child: Text(s,
                                                    style: const TextStyle(
                                                        fontSize: 12))),
                                          ],
                                        ),
                                      )),
                                ],
                                const SizedBox(height: 14),
                                const Text(
                                  'Naskah Lengkap Siap Kirim WhatsApp (Non-Teknis):',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
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
              Align(
                alignment: Alignment.centerRight,
                child: AksiToolbarMenu(
                  tooltip: 'Aksi analisis stok',
                  aksi: [
                    if (_error != null)
                      AksiBaris(
                        ikon: Icons.refresh,
                        label: 'Coba Lagi',
                        onTap: _muatAnalisis,
                      ),
                    AksiBaris(
                      ikon: Icons.copy,
                      label: 'Salin Naskah WhatsApp',
                      onTap: _memuat || _teksWa.isEmpty ? null : _salinWa,
                    ),
                    AksiBaris(
                      ikon: Icons.close,
                      label: 'Tutup Analisis',
                      onTap: () => Navigator.of(context).pop(),
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

/// Mesin Analisis Cerdas Pergerakan & Selisih Stok di Sisi Klien (Fallback Multi-Lapis & Offline-Ready).
///
/// Tujuan:
/// 1. Menyusun hasil analisis cerdas otomatis secara instan di dalam [DialogDetailPergerakanStok]
///    ("Tambahkan hasil analysis cerdas di sini") tepat di bawah tabel buku besar produk tanpa
///    membutuhkan round-trip jaringan tambahan.
/// 2. Menjamin [DialogAnalisisCerdasStok] (baik per-produk maupun seluruh toko) TIDAK PERNAH
///    menampilkan error "Aksi tidak dikenal" atau "HTTP 503" apabila server sedang restart
///    atau belum di-deploy versi terbaru, karena sistem otomatis menyintesis diagnosis,
///    kronologi, langkah solusi, dan naskah WhatsApp dari endpoint pendamping (`stok_pergerakan_detail`,
///    `stok_pergerakan_rekap`, `stok_mutasi_ledger`, `produk_mutasi_ringkasan`) maupun cache SQLite lokal (`CoreDb`).
class StokAnalisisCerdasLokal {
  StokAnalisisCerdasLokal._();

  static final _fmtTgl = DateFormat('yyyy-MM-dd');
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  static String _angka(num v) => _formatAngka.format(v);
  static String _rupiah(num v) => _fmtRp.format(v.round());

  /// menyusun diagnosis, kronologi lengkap (menampilkan prioritas kejadian penting
  /// di awal + seluruh daftar kronologis), langkah solusi, dan naskah WhatsApp.
  static Map<String, dynamic> susunAnalisisProdukDariData({
    required String namaProduk,
    required String kodeProduk,
    required String kategori,
    required DateTime tglMulai,
    required DateTime tglSampai,
    required Map<String, dynamic> ringkasan,
    required List<Map<String, dynamic>> mutasi,
    double hargaBeli = 0,
  }) {
    const kolomRingkasanWajib = [
      'awal',
      'masuk',
      'retur',
      'penjualan',
      'keluar',
      'opnameMasuk',
      'opnameKeluar',
      'sisa',
    ];
    final ringkasanLengkap =
        kolomRingkasanWajib.every((key) => ringkasan[key] is num);
    if (!ringkasanLengkap && mutasi.isEmpty) {
      const judul = 'Data Pergerakan Belum Cukup untuk Menentukan Penyebab';
      const penjelasan =
          'Rincian saldo dan transaksi untuk produk ini belum berhasil dimuat. Penyebab perubahan stok belum dapat dipastikan, sehingga belum ada angka atau kesimpulan yang kami buat-buat.';
      const solusi = [
        'Coba buka kembali rincian pergerakan produk setelah data berhasil dimuat.',
        'Jangan melakukan koreksi jumlah stok hanya berdasarkan hasil yang belum lengkap.',
      ];
      final wa = StringBuffer()
        ..writeln('HASIL PEMERIKSAAN PERGERAKAN STOK')
        ..writeln(
            'Barang: ${kodeProduk.trim().isEmpty ? '-' : kodeProduk.trim()} - $namaProduk')
        ..writeln(
            'Periode: ${_fmtTgl.format(tglMulai)} s/d ${_fmtTgl.format(tglSampai)}')
        ..writeln(penjelasan)
        ..writeln('Langkah berikutnya:')
        ..writeln('1. Muat ulang rincian pergerakan produk.')
        ..writeln(
            '2. Tunda koreksi stok sampai saldo dan catatan transaksinya tampil lengkap.');
      return {
        'dataMemadai': false,
        'judulDiagnosis': judul,
        'penjelasanUtama': penjelasan,
        'kronologiPoin': const <String>[],
        'kronologiPenting': const <String>[],
        'langkahSolusi': solusi,
        'teksAnalisisWa': wa.toString().trim(),
      };
    }
    final namaToko = Sesi.instance.tokoNama.isNotEmpty
        ? Sesi.instance.tokoNama
        : 'Toko Al-Bahjah';
    final kd = kodeProduk.trim().isEmpty ? '-' : kodeProduk.trim();
    final kat = kategori.trim().isEmpty ? 'Lain-lain' : kategori.trim();
    final mulaiStr = _fmtTgl.format(tglMulai);
    final sampaiStr = _fmtTgl.format(tglSampai);

    final awal = (ringkasan['awal'] as num?)?.toDouble() ?? 0;
    final masuk = (ringkasan['masuk'] as num?)?.toDouble() ?? 0;
    final retur = (ringkasan['retur'] as num?)?.toDouble() ?? 0;
    final penjualan = (ringkasan['penjualan'] as num?)?.toDouble() ?? 0;
    final keluar = (ringkasan['keluar'] as num?)?.toDouble() ?? 0;
    final opnameMasuk = (ringkasan['opnameMasuk'] as num?)?.toDouble() ?? 0;
    final opnameKeluar = (ringkasan['opnameKeluar'] as num?)?.toDouble() ?? 0;
    final sisa = (ringkasan['sisa'] as num?)?.toDouble() ?? 0;

    bool pernahDinolkanSo = false;
    String waktuDinolkanSo = '';
    String petugasDinolkanSo = '';
    String ketDinolkanSo = '';
    double stokSebelumDinolkan = 0;

    bool pernahPulihSo = false;
    String waktuPulihSo = '';
    double qtyPulihSo = 0;

    bool pernahSoTambahSetelahHabis = false;
    String waktuSoTambahTerakhir = '';
    String petugasSoTambahTerakhir = '';
    String ketSoTambahTerakhir = '';
    double stokSebelumSoTambahTerakhir = 0;
    double stokSesudahSoTambahTerakhir = 0;
    double selisihSoTambahTerakhir = 0;
    // ignore: unused_local_variable
    int jmlPenjualanSetelahSoTerakhir = 0;

    int jmlTransaksiPos = 0;
    int jmlOpname = 0;
    final kronologiSemua = <String>[];
    final kronologiPenting = <String>[];

    for (final m in mutasi) {
      final tgl = '${m['tanggal'] ?? m['waktu'] ?? '-'}';
      final tipe = '${m['tipe'] ?? m['jenis'] ?? ''}';
      final ref = '${m['referensi'] ?? m['noFaktur'] ?? '-'}';
      final pihak = '${m['namaPelanggan'] ?? ''}';
      final oleh = '${m['oleh'] ?? ''}';
      final mAwal = (m['awal'] as num?)?.toDouble() ?? 0;
      final mMasuk = (m['masuk'] as num?)?.toDouble() ?? 0;
      final mKeluar = (m['keluar'] as num?)?.toDouble() ?? 0;
      final mSisa = (m['sisa'] as num?)?.toDouble() ?? 0;

      if (tipe.contains('Penjualan')) {
        jmlTransaksiPos++;
        if (waktuSoTambahTerakhir.isNotEmpty) {
          jmlPenjualanSetelahSoTerakhir++;
        }
        final poin =
            '$tgl WIB: Terjual di Kasir (Nota: $ref) sebanyak ${_angka(mKeluar)} Pcs -> Stok berubah dari ${_angka(mAwal)} menjadi ${_angka(mSisa)} Pcs.';
        kronologiSemua.add(poin);
        if (mSisa <= 0 || jmlTransaksiPos == 1) {
          kronologiPenting.add(poin);
        }
      } else if (tipe.contains('Pengadaan') || tipe.contains('Kulakan')) {
        final poin =
            '$tgl WIB: Barang masuk dari Pengadaan ($ref${pihak.isNotEmpty && pihak != tipe ? " - $pihak" : ""}) sebanyak +${_angka(mMasuk)} Pcs -> Stok berubah dari ${_angka(mAwal)} menjadi ${_angka(mSisa)} Pcs.';
        kronologiSemua.add(poin);
        kronologiPenting.add('⭐ [PENGADAAN] $poin');
      } else if (tipe.contains('Opname') || tipe.contains('Penyesuaian')) {
        jmlOpname++;
        final pelaku = (oleh.isNotEmpty && !oleh.startsWith('Stok Opname'))
            ? oleh
            : ((pihak.isNotEmpty && !pihak.startsWith('Stok Opname'))
                ? pihak
                : 'Petugas Toko');
        final ketBersih =
            (ref.isNotEmpty && ref != 'Stok Opname' && ref != 'OPNAME')
                ? ref
                : 'Tanpa Keterangan';
        if (tipe.contains('Dinolkan') ||
            (mAwal > 0 && mSisa == 0 && mKeluar > 0)) {
          pernahDinolkanSo = true;
          waktuDinolkanSo = tgl;
          petugasDinolkanSo = pelaku;
          ketDinolkanSo = ketBersih;
          stokSebelumDinolkan = mAwal;
          final poin =
              '$tgl WIB: Stok Opname oleh $pelaku (Ket: "$ketBersih") mengubah stok dari ${_angka(mAwal)} Pcs (senilai ${_rupiah(mAwal * hargaBeli)}) menjadi 0 Pcs (berkurang -${_angka(mKeluar)} Pcs).';
          kronologiSemua.add(poin);
          kronologiPenting.add('⚠️ [STOK OPNAME -> 0] $poin');
        } else if (mMasuk > 0) {
          if (pernahDinolkanSo) {
            pernahPulihSo = true;
            waktuPulihSo = tgl;
            qtyPulihSo = mMasuk;
          }
          pernahSoTambahSetelahHabis = true;
          waktuSoTambahTerakhir = tgl;
          petugasSoTambahTerakhir = pelaku;
          ketSoTambahTerakhir = ketBersih;
          stokSebelumSoTambahTerakhir = mAwal;
          stokSesudahSoTambahTerakhir = mSisa;
          selisihSoTambahTerakhir = mMasuk;
          jmlPenjualanSetelahSoTerakhir = 0;
          final poin =
              '$tgl WIB: Penyesuaian Stok Opname (+) oleh $pelaku (Ket: "$ketBersih") mengubah stok dari ${_angka(mAwal)} Pcs menjadi ${_angka(mSisa)} Pcs (bertambah +${_angka(mMasuk)} Pcs).';
          kronologiSemua.add(poin);
          kronologiPenting.add('📌 [STOK OPNAME (+)] $poin');
        } else if (mKeluar > 0) {
          final poin =
              '$tgl WIB: Penyesuaian Stok Opname (-) oleh $pelaku (Ket: "$ketBersih") mengubah stok dari ${_angka(mAwal)} Pcs menjadi ${_angka(mSisa)} Pcs (berkurang -${_angka(mKeluar)} Pcs).';
          kronologiSemua.add(poin);
          kronologiPenting.add('📌 [STOK OPNAME (-)] $poin');
        } else {
          final poin =
              '$tgl WIB: Pencatatan Stok Opname oleh $pelaku (Ket: "$ketBersih") tanpa perubahan jumlah (tetap ${_angka(mSisa)} Pcs).';
          kronologiSemua.add(poin);
          kronologiPenting.add('ℹ️ [STOK OPNAME (=)] $poin');
        }
      } else {
        final poin =
            '$tgl WIB: $tipe ($ref) ${mMasuk > 0 ? "+${_angka(mMasuk)}" : "-${_angka(mKeluar)}"} Pcs -> Stok berubah dari ${_angka(mAwal)} menjadi ${_angka(mSisa)} Pcs.';
        kronologiSemua.add(poin);
        kronologiPenting.add(poin);
      }
    }

    // Susun daftar kronologi terpadu: dahulukan ringkasan Tonggak Kejadian Penting (Pengadaan, Stok Opname,
    // Transaksi yang menghabiskan stok) agar pengguna langsung melihat mengapa saldo berubah tanpa terpotong
    // puluhan baris penjualan kasir, lalu diikuti Rincian Urutan Kronologis Lengkap seluruh transaksi.
    final kronologiPoin = <String>[];
    if (kronologiPenting.isNotEmpty && kronologiSemua.length > 6) {
      kronologiPoin.add(
          '=== RINGKASAN KEJADIAN PENTING (PENGADAAN, STOK OPNAME & TITIK PERUBAHAN STOK) ===');
      kronologiPoin.addAll(kronologiPenting);
      if (jmlTransaksiPos > 0) {
        kronologiPoin.add(
            '🛒 Total Penjualan di Kasir selama periode ini: -${_angka(penjualan)} Pcs dalam $jmlTransaksiPos nota transaksi.');
      }
      kronologiPoin.add(
          '=== RINCIAN URUTAN KRONOLOGIS LENGKAP (${kronologiSemua.length} KEJADIAN) ===');
    }
    kronologiPoin.addAll(kronologiSemua);

    String judulDiagnosis;
    String penjelasanUtama;
    final langkahSolusi = <String>[];

    final double saldoTanpaOpname = awal + masuk + retur - penjualan - keluar;

    if (pernahDinolkanSo && sisa < 0) {
      judulDiagnosis =
          'Stok Tergencet Menjadi 0 saat Unggah Stok Opname, Lalu Terjual di Kasir sehingga Menjadi Minus (${_angka(sisa)} Pcs)';
      penjelasanUtama =
          'Barang ini awalnya memiliki stok ${_angka(stokSebelumDinolkan)} Pcs (senilai ${_rupiah(stokSebelumDinolkan * hargaBeli)}). Namun pada tanggal $waktuDinolkanSo WIB, tercatat Stok Opname ("$ketDinolkanSo") oleh $petugasDinolkanSo dengan angka fisik 0, sehingga stok berubah menjadi 0 Pcs. Setelah itu, barang fisiknya yang masih ada di rak toko terjual di kasir sebanyak ${_angka(penjualan)} Pcs, sehingga stok akhir menjadi minus ${_angka(sisa)} Pcs.';
      langkahSolusi.add(
          'Hitung jumlah fisik $namaProduk yang saat ini benar-benar ada di rak toko.');
      langkahSolusi.add(
          'Inputkan jumlah fisik sebenarnya melalui menu Stok Opname agar angka minus (${_angka(sisa)}) kembali sesuai fisik rak.');
      final estimasi = (stokSebelumDinolkan - penjualan) > 0
          ? (stokSebelumDinolkan - penjualan)
          : 0;
      langkahSolusi.add(
          'Jika barang belum sempat dihitung fisiknya, stok sebelum tergencet opname adalah ${_angka(stokSebelumDinolkan)} Pcs dikurangi penjualan ${_angka(penjualan)} Pcs = ${_angka(estimasi)} Pcs.');
    } else if (pernahDinolkanSo && sisa == 0) {
      judulDiagnosis =
          'Stok Berubah Menjadi 0 karena Tertimpa Angka Fisik 0 saat Stok Opname';
      penjelasanUtama =
          'Barang ini tidak hilang karena kesalahan perhitungan, melainkan pada tanggal $waktuDinolkanSo WIB tercatat Stok Opname ("$ketDinolkanSo") oleh $petugasDinolkanSo yang mengisi Stok Fisik = 0 Pcs (padahal stok sebelumnya tercatat ${_angka(stokSebelumDinolkan)} Pcs senilai ${_rupiah(stokSebelumDinolkan * hargaBeli)}).';
      langkahSolusi.add(
          'Periksa apakah barang $namaProduk masih ada fisiknya di rak/gudang toko.');
      langkahSolusi.add(
          'Apabila barang tersebut belum sempat dihitung saat unggah Excel Stok Opname, silakan input ulang jumlah fisik sebenarnya (stok sebelum dinolkan adalah ${_angka(stokSebelumDinolkan)} Pcs).');
    } else if (pernahDinolkanSo && pernahPulihSo && sisa > 0) {
      judulDiagnosis =
          'Stok Sempat Menjadi 0 saat Stok Opname, Namun Sudah Dipulihkan Kembali (${_angka(sisa)} Pcs)';
      penjelasanUtama =
          'Barang ini sempat berubah menjadi 0 Pcs pada $waktuDinolkanSo WIB saat Stok Opname ("$ketDinolkanSo"), tetapi sudah diinput ulang penghitungan fisiknya pada $waktuPulihSo WIB sebanyak +${_angka(qtyPulihSo)} Pcs. Stok akhir saat ini adalah ${_angka(sisa)} Pcs.';
      langkahSolusi.add(
          'Data stok barang ini sudah pulih. Pastikan jumlah ${_angka(sisa)} Pcs sudah sama dengan jumlah fisik di rak.');
    } else if (penjualan > 0 && sisa == 0 && opnameKeluar == 0) {
      judulDiagnosis =
          'Barang Habis Terjual Secara Sah di Kasir (Bukan Kesalahan Sistem)';
      penjelasanUtama =
          'Stok barang ini berubah menjadi 0 Pcs karena memang terjual habis di kasir sebanyak ${_angka(penjualan)} Pcs${jmlTransaksiPos > 0 ? " dalam $jmlTransaksiPos transaksi penjualan" : ""} selama periode ini.';
      langkahSolusi.add(
          'Tidak diperlukan koreksi data karena seluruh pengurangan stok berasal dari transaksi penjualan resmi di kasir.');
      langkahSolusi.add(
          'Silakan lakukan pengadaan/kulakan kembali apabila barang akan dijual lagi.');
    } else if (sisa < 0) {
      judulDiagnosis =
          'Stok Akhir Bernilai Minus (${_angka(sisa)} Pcs) karena Penjualan Melebihi Stok Tercatat';
      penjelasanUtama =
          'Tercatat penjualan sebesar ${_angka(penjualan)} Pcs atau pengurangan sebesar ${_angka(keluar + opnameKeluar)} Pcs saat stok awal tercatat ${_angka(awal)} Pcs dan barang masuk ${_angka(masuk)} Pcs (kemungkinan barang fisik sudah datang di rak dan langsung terjual di kasir sebelum faktur pengadaannya diinput).';
      langkahSolusi.add(
          'Periksa apakah ada faktur pengadaan/kulakan barang masuk untuk $namaProduk yang belum diinput.');
      langkahSolusi.add(
          'Jika pengadaan sudah lengkap, lakukan Stok Opname sesuai jumlah fisik yang ada di rak saat ini.');
    } else if (pernahSoTambahSetelahHabis &&
        saldoTanpaOpname <= 0 &&
        sisa > 0) {
      judulDiagnosis =
          'Barang Sebenarnya Sudah Habis Terjual (${_angka(penjualan)} dari ${_angka(awal + masuk)} Pcs = ${_angka(saldoTanpaOpname)} Pcs), Namun Tertambah +${_angka(opnameMasuk)} Pcs dari Input Stok Opname';
      penjelasanUtama =
          'Secara riwayat transaksi keluar-masuk murni, barang ini memiliki Saldo Awal ${_angka(awal)} Pcs + Pengadaan Masuk ${_angka(masuk)} Pcs - Terjual di Kasir ${_angka(penjualan)} Pcs ($jmlTransaksiPos transaksi) = ${_angka(saldoTanpaOpname)} Pcs (habis terjual). '
          'Alasan mengapa Saldo Akhir saat ini masih tertulis ${_angka(sisa)} Pcs adalah karena adanya pencatatan Stok Opname sebanyak $jmlOpname kali yang menambah stok sebesar +${_angka(opnameMasuk)} Pcs '
          '(terakhir pada $waktuSoTambahTerakhir WIB oleh $petugasSoTambahTerakhir, Ket: "$ketSoTambahTerakhir", yang mengubah stok dari ${_angka(stokSebelumSoTambahTerakhir)} menjadi ${_angka(stokSesudahSoTambahTerakhir)} Pcs / +${_angka(selisihSoTambahTerakhir)} Pcs, dan setelah itu belum ada transaksi penjualan lagi).';
      langkahSolusi.add(
          'Apabila aktual fisik $namaProduk di rak toko saat ini benar-benar sudah 0 (habis), penyebab angka ${_angka(sisa)} Pcs di aplikasi adalah input Stok Opname pada $waktuSoTambahTerakhir WIB oleh $petugasSoTambahTerakhir yang mengisi Stok Fisik = ${_angka(stokSesudahSoTambahTerakhir)} Pcs.');
      langkahSolusi.add(
          'Untuk menyamakan saldo aplikasi dengan fisik di rak yang sudah kosong (0 Pcs), silakan buka menu Stok Opname, pilih produk "$kd - $namaProduk", isi Stok Fisik = 0, lalu Simpan.');
      langkahSolusi.add(
          'Pastikan saat mengunggah/menginput Stok Opname berikutnya, angka Stok Fisik yang dimasukkan adalah sisa fisik nyata pada hari itu (bukan angka stok awal sebelum barang terjual).');
    } else if (opnameMasuk > 0 || opnameKeluar > 0) {
      judulDiagnosis =
          'Terdapat Penyesuaian Stok Opname (+${_angka(opnameMasuk)} / -${_angka(opnameKeluar)} Pcs)';
      penjelasanUtama =
          'Perubahan stok pada barang ini dipengaruhi oleh penyesuaian Stok Opname${jmlOpname > 0 ? " sebanyak $jmlOpname kali" : ""} pada periode ini (bertambah +${_angka(opnameMasuk)} Pcs, berkurang -${_angka(opnameKeluar)} Pcs; saldo murni tanpa Opname adalah ${_angka(saldoTanpaOpname)} Pcs), sehingga sisa stok akhir menjadi ${_angka(sisa)} Pcs.';
      langkahSolusi.add(
          'Periksa rincian jam dan nama petugas Stok Opname pada daftar kronologi di atas untuk memastikan koreksi fisik sudah sesuai dengan kondisi rak saat ini.');
      langkahSolusi.add(
          'Jika jumlah aktual fisik di toko berbeda dengan Saldo Akhir (${_angka(sisa)} Pcs), silakan lakukan input Stok Opname sesuai jumlah fisik terbaru di rak.');
    } else {
      judulDiagnosis = 'Pergerakan Stok Normal & Sesuai Riwayat Transaksi';
      penjelasanUtama =
          'Seluruh keluar-masuk barang tercatat normal (Saldo Awal: ${_angka(awal)} Pcs, Masuk: +${_angka(masuk)} Pcs, Retur: +${_angka(retur)} Pcs, Terjual: -${_angka(penjualan)} Pcs, Keluar Lain: -${_angka(keluar)} Pcs, Sisa Akhir: ${_angka(sisa)} Pcs).';
      langkahSolusi.add(
          'Stok sudah sesuai dengan catatan transaksi keluar-masuk barang.');
    }

    final wa = StringBuffer()
      ..writeln('📋 *HASIL ANALISIS OTOMATIS PERGERAKAN & SELISIH STOK PRODUK*')
      ..writeln('🏪 Unit/Cabang: *$namaToko*')
      ..writeln('📦 Nama Barang: *$kd - $namaProduk*')
      ..writeln('🗂️ Kategori: $kat | Periode: $mulaiStr s/d $sampaiStr\n')
      ..writeln('🔍 *1. KESIMPULAN PENYEBAB UTAMA:*')
      ..writeln('*$judulDiagnosis*')
      ..writeln('$penjelasanUtama\n')
      ..writeln('📊 *2. RINGKASAN PERHITUNGAN STOK:*')
      ..writeln(
          '• Saldo Awal Periode: *${_angka(awal)} Pcs* (${_rupiah(awal * hargaBeli)})')
      ..writeln('• Barang Masuk (Pengadaan/Transfer): *+${_angka(masuk)} Pcs*')
      ..writeln('• Pengembalian / Retur Pelanggan: *+${_angka(retur)} Pcs*')
      ..writeln(
          '• Terjual di Kasir: *-${_angka(penjualan)} Pcs* ($jmlTransaksiPos transaksi)')
      ..writeln(
          '• Keluar Lainnya (Retur Beli/Transfer/Bahan): *-${_angka(keluar)} Pcs*')
      ..writeln(
          '• Saldo Murni (Tanpa Stok Opname): *${_angka(saldoTanpaOpname)} Pcs*')
      ..writeln(
          '• Koreksi Stok Opname Bertambah (+): *+${_angka(opnameMasuk)} Pcs*')
      ..writeln(
          '• Koreksi Stok Opname Berkurang (-): *-${_angka(opnameKeluar)} Pcs*')
      ..writeln(
          '• *Sisa Stok Akhir Tercatat: ${_angka(sisa)} Pcs* (Nilai Modal: ${_rupiah(sisa * hargaBeli)})\n')
      ..writeln('🕒 *3. KRONOLOGI LENGKAP KELUAR-MASUK & STOK OPNAME:*');

    if (kronologiSemua.isEmpty) {
      wa.writeln(
          '• Tidak ada perubahan/transaksi pada periode tanggal ini (Stok tetap ${_angka(sisa)} Pcs).');
    } else {
      for (var i = 0; i < kronologiSemua.length; i++) {
        wa.writeln('${i + 1}. ${kronologiSemua[i]}');
      }
    }

    wa.writeln('\n✅ *4. REKOMENDASI & LANGKAH PENYELESAIAN:*');
    for (var i = 0; i < langkahSolusi.length; i++) {
      wa.writeln('${i + 1}. ${langkahSolusi[i]}');
    }

    return {
      'dataMemadai': true,
      'judulDiagnosis': judulDiagnosis,
      'penjelasanUtama': penjelasanUtama,
      'kronologiPoin': kronologiPoin,
      'kronologiPenting': kronologiPenting,
      'langkahSolusi': langkahSolusi,
      'teksAnalisisWa': wa.toString().trim(),
    };
  }

  /// Fallback untuk memuat rincian buku besar produk jika `stok_pergerakan_detail` belum tersedia
  /// atau server sedang sibuk (menggunakan `stok_mutasi_ledger` + `produk_mutasi_ringkasan` + `CoreDb`).
  static Future<Map<String, dynamic>> muatDetailProdukFallback({
    required int idProduk,
    required String namaProduk,
    required String kodeProduk,
    required String kategori,
    required DateTime tglMulai,
    required DateTime tglSampai,
  }) async {
    double hargaBeli = 0;
    double stokSaatIni = 0;
    try {
      final lokalProduk =
          await CoreDb.instance.produkCache(keyword: '', limit: 100000);
      for (final p in lokalProduk) {
        if (p['id'] == idProduk ||
            (kodeProduk.isNotEmpty && '${p['kode'] ?? ''}' == kodeProduk)) {
          hargaBeli = (p['harga_beli'] as num?)?.toDouble() ?? 0;
          stokSaatIni = (p['stok'] as num?)?.toDouble() ?? 0;
          break;
        }
      }
    } catch (_) {}

    double awal = 0;
    double masuk = 0;
    double retur = 0;
    double penjualan = 0;
    double keluar = 0;
    double opnameMasuk = 0;
    double opnameKeluar = 0;
    double sisa = stokSaatIni;

    try {
      final resRingkas =
          await ApiClient.instance.aksi('produk_mutasi_ringkasan', {
        'dari': _fmtTgl.format(tglMulai),
        'sampai': _fmtTgl.format(tglSampai),
        'page': 1,
        'page_size': 50,
        if (kodeProduk.trim().isNotEmpty)
          'keyword': kodeProduk.trim()
        else if (namaProduk.trim().isNotEmpty)
          'keyword': namaProduk.trim(),
      });
      final list = (resRingkas['data'] as List?) ?? const [];
      for (final item in list.whereType<Map>()) {
        final itemId = (item['id'] as num?)?.toInt() ?? 0;
        final itemKode = '${item['kode'] ?? ''}';
        if (itemId == idProduk ||
            (kodeProduk.isNotEmpty && itemKode == kodeProduk)) {
          awal = (item['saldoAwal'] as num?)?.toDouble() ?? 0;
          masuk = (item['masuk'] as num?)?.toDouble() ?? 0;
          retur = (item['retur'] as num?)?.toDouble() ?? 0;
          penjualan = (item['keluar'] as num?)?.toDouble() ?? 0;
          final penyesuaian = (item['penyesuaian'] as num?)?.toDouble() ?? 0;
          if (penyesuaian > 0) {
            opnameMasuk = penyesuaian;
          } else if (penyesuaian < 0) {
            opnameKeluar = penyesuaian.abs();
          }
          sisa = (item['saldoAkhir'] as num?)?.toDouble() ?? stokSaatIni;
          if (hargaBeli <= 0 && sisa > 0) {
            final nilaiAkhir = (item['nilaiAkhir'] as num?)?.toDouble() ?? 0;
            if (nilaiAkhir > 0) hargaBeli = nilaiAkhir / sisa;
          }
          break;
        }
      }
    } catch (_) {}

    final mutasi = <Map<String, dynamic>>[];
    try {
      final resLedger = await ApiClient.instance.aksi('stok_mutasi_ledger', {
        'produk_id': idProduk,
        'tanggalMulai': _fmtTgl.format(tglMulai),
        'tanggalSampai': _fmtTgl.format(tglSampai),
        'limit': 300,
        'offset': 0,
      });
      final rows = ((resLedger['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
          .reversed
          .toList();
      // Hitung secara akurat dari baris buku besar agar masuk, penjualan, opnameMasuk, dan opnameKeluar
      // tidak tercampur dengan nilai bersih dari produk_mutasi_ringkasan.
      double calcMasuk = 0;
      double calcRetur = 0;
      double calcPenjualan = 0;
      double calcKeluar = 0;
      double calcOpnameMasuk = 0;
      double calcOpnameKeluar = 0;
      double running = awal;
      for (final r in rows) {
        final qty = (r['qty'] as num?)?.toDouble() ?? 0;
        final jenis = '${r['jenis'] ?? 'Mutasi'}';
        final ket = '${r['keterangan'] ?? ''}';
        final waktu = '${r['waktu'] ?? '-'}';
        final mAwal = running;
        final mMasuk = qty > 0 ? qty : 0.0;
        final mKeluar = qty < 0 ? qty.abs() : 0.0;
        running += qty;
        String kodeMutasi = '100';
        String tipeTampil = jenis;
        if (jenis.contains('Pengadaan') || jenis.contains('Kulakan')) {
          kodeMutasi = '101';
          calcMasuk += mMasuk;
        } else if (jenis.contains('Retur Penjualan')) {
          kodeMutasi = '103';
          calcRetur += mMasuk;
        } else if (jenis.contains('Opname')) {
          kodeMutasi = '104';
          if (mMasuk > 0) {
            calcOpnameMasuk += mMasuk;
            tipeTampil = 'Stok Opname (+)';
          } else if (mKeluar > 0) {
            calcOpnameKeluar += mKeluar;
            tipeTampil = (mAwal > 0 && running == 0)
                ? 'Stok Opname (Dinolkan)'
                : 'Stok Opname (-)';
          } else {
            tipeTampil = 'Stok Opname (=)';
          }
        } else if (jenis.contains('Penjualan')) {
          kodeMutasi = '200';
          calcPenjualan += mKeluar;
        } else if (jenis.contains('Mutasi Masuk')) {
          kodeMutasi = '102';
          calcMasuk += mMasuk;
        } else {
          if (mMasuk > 0) calcMasuk += mMasuk;
          if (mKeluar > 0) calcKeluar += mKeluar;
        }
        mutasi.add({
          'tanggal': waktu,
          'tipe': tipeTampil,
          'kodeMutasi': kodeMutasi,
          'referensi': ket.isNotEmpty ? ket : tipeTampil,
          'idPelanggan': '-',
          'namaPelanggan': tipeTampil,
          'oleh': '',
          'awal': mAwal,
          'masuk': mMasuk,
          'keluar': mKeluar,
          'sisa': running,
          'keterangan': ket.isNotEmpty ? ket : tipeTampil,
        });
      }
      if (rows.isNotEmpty) {
        masuk = calcMasuk;
        retur = calcRetur;
        penjualan = calcPenjualan;
        keluar = calcKeluar;
        opnameMasuk = calcOpnameMasuk;
        opnameKeluar = calcOpnameKeluar;
        sisa = running;
      }
    } catch (_) {}

    return {
      'hargaBeli': hargaBeli,
      'ringkasan': {
        'awal': awal,
        'masuk': masuk,
        'retur': retur,
        'penjualan': penjualan,
        'keluar': keluar,
        'opnameMasuk': opnameMasuk,
        'opnameKeluar': opnameKeluar,
        'sisa': sisa,
      },
      'mutasi': mutasi,
    };
  }

  /// Fallback lengkap untuk `DialogAnalisisCerdasStok` mode per-produk.
  static Future<Map<String, dynamic>> susunAnalisisProdukFallback({
    required int idProduk,
    required String namaProduk,
    required String kodeProduk,
    required DateTime tglMulai,
    required DateTime tglSampai,
  }) async {
    try {
      final detail = await ApiClient.instance.aksi('stok_pergerakan_detail', {
        'id': idProduk,
        'dari': _fmtTgl.format(tglMulai),
        'sampai': _fmtTgl.format(tglSampai),
      });
      final pObj = (detail['produk'] as Map?)?.cast<String, dynamic>();
      final ringkasan =
          (detail['ringkasan'] as Map?)?.cast<String, dynamic>() ?? const {};
      final mutasi = ((detail['mutasi'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return susunAnalisisProdukDariData(
        namaProduk: '${pObj?['nama'] ?? namaProduk}',
        kodeProduk: '${pObj?['kode'] ?? kodeProduk}',
        kategori: '${pObj?['kategori'] ?? 'Lain-lain'}',
        tglMulai: tglMulai,
        tglSampai: tglSampai,
        ringkasan: ringkasan,
        mutasi: mutasi,
        hargaBeli: (pObj?['hargaBeli'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      final fb = await muatDetailProdukFallback(
        idProduk: idProduk,
        namaProduk: namaProduk,
        kodeProduk: kodeProduk,
        kategori: 'Lain-lain',
        tglMulai: tglMulai,
        tglSampai: tglSampai,
      );
      return susunAnalisisProdukDariData(
        namaProduk: namaProduk,
        kodeProduk: kodeProduk,
        kategori: 'Lain-lain',
        tglMulai: tglMulai,
        tglSampai: tglSampai,
        ringkasan: (fb['ringkasan'] as Map<String, dynamic>?) ?? const {},
        mutasi: (fb['mutasi'] as List<Map<String, dynamic>>?) ?? const [],
        hargaBeli: (fb['hargaBeli'] as num?)?.toDouble() ?? 0,
      );
    }
  }

  /// Fallback rekap pergerakan stok toko dari `produk_mutasi_ringkasan` atau cache produk lokal.
  static Future<Map<String, dynamic>> muatRekapFallback({
    required DateTime tglMulai,
    required DateTime tglSampai,
    String keyword = '',
    String statusFilter = '',
  }) async {
    List<Map<String, dynamic>> rawRows = [];
    try {
      final res = await ApiClient.instance.aksi('produk_mutasi_ringkasan', {
        'dari': _fmtTgl.format(tglMulai),
        'sampai': _fmtTgl.format(tglSampai),
        'page': 1,
        'page_size': 500,
        if (keyword.isNotEmpty) 'keyword': keyword,
      });
      rawRows = ((res['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      final lokal =
          await CoreDb.instance.produkCache(keyword: '', limit: 100000);
      rawRows = lokal.map((p) {
        final stok = (p['stok'] as num?)?.toDouble() ?? 0;
        final hb = (p['harga_beli'] as num?)?.toDouble() ?? 0;
        return <String, dynamic>{
          'id': p['id'],
          'kategori': p['jenis_nama'] ?? '-',
          'kode': p['kode'] ?? '',
          'barcode': p['barcode'] ?? '',
          'nama': p['nama'] ?? '-',
          'saldoAwal': stok,
          'nilaiAwal': stok * hb,
          'masuk': 0.0,
          'keluar': 0.0,
          'retur': 0.0,
          'penyesuaian': 0.0,
          'saldoAkhir': stok,
          'nilaiAkhir': stok * hb,
          'hargaBeli': hb,
        };
      }).toList();
    }

    final kodeCount = <String, int>{};
    for (final r in rawRows) {
      final kd = '${r['kode'] ?? ''}'.trim();
      if (kd.isNotEmpty) kodeCount[kd] = (kodeCount[kd] ?? 0) + 1;
    }

    int jmlDinolkanSo = 0;
    int jmlStokMinus = 0;
    int jmlKoreksiOpname = 0;
    int jmlKodeDuplikat = 0;
    double totalAwal = 0;
    double totalMasuk = 0;
    double totalRetur = 0;
    double totalPenjualan = 0;
    double totalOpnameMasuk = 0;
    double totalOpnameKeluar = 0;
    double totalSisa = 0;

    final data = <Map<String, dynamic>>[];
    for (final r in rawRows) {
      final awal = (r['saldoAwal'] as num?)?.toDouble() ?? 0;
      final masuk = (r['masuk'] as num?)?.toDouble() ?? 0;
      final retur = (r['retur'] as num?)?.toDouble() ?? 0;
      final penjualan = (r['keluar'] as num?)?.toDouble() ?? 0;
      final penyesuaian = (r['penyesuaian'] as num?)?.toDouble() ?? 0;
      final opMasuk = penyesuaian > 0 ? penyesuaian : 0.0;
      final opKeluar = penyesuaian < 0 ? penyesuaian.abs() : 0.0;
      final sisa = (r['saldoAkhir'] as num?)?.toDouble() ?? 0;
      final kd = '${r['kode'] ?? ''}'.trim();
      final isDup = kd.isNotEmpty && (kodeCount[kd] ?? 0) > 1;

      String statusKode = 'NORMAL';
      String statusAudit = 'Normal';
      if (awal > 0 && opKeluar > 0 && sisa <= 0) {
        statusKode = 'DINOLKAN_SO';
        statusAudit =
            'Dinolkan saat Opname (${_angka(awal)} -> ${_angka(sisa)})';
        jmlDinolkanSo++;
      } else if (sisa < 0) {
        statusKode = 'STOK_MINUS';
        statusAudit = 'Stok Minus (${_angka(sisa)})';
        jmlStokMinus++;
      } else if (opMasuk > 0 || opKeluar > 0) {
        statusKode = 'KOREKSI_SO';
        statusAudit =
            'Koreksi Opname (${opMasuk > 0 ? "+${_angka(opMasuk)}" : "-${_angka(opKeluar)}"})';
        jmlKoreksiOpname++;
      } else if (penjualan > 0 && sisa == 0) {
        statusKode = 'HABIS_TERJUAL';
        statusAudit = 'Habis Terjual di Kasir';
      }
      if (isDup) {
        jmlKodeDuplikat++;
        statusAudit = '$statusAudit · Kode Ganda';
      }

      if (statusFilter == 'dinolkan_so' && statusKode != 'DINOLKAN_SO') {
        continue;
      }
      if (statusFilter == 'stok_minus' && sisa >= 0) continue;
      if (statusFilter == 'koreksi_opname' && opMasuk == 0 && opKeluar == 0) {
        continue;
      }
      if (statusFilter == 'kode_duplikat' && !isDup) continue;

      totalAwal += awal;
      totalMasuk += masuk;
      totalRetur += retur;
      totalPenjualan += penjualan;
      totalOpnameMasuk += opMasuk;
      totalOpnameKeluar += opKeluar;
      totalSisa += sisa;

      data.add({
        'id': r['id'] ?? 0,
        'kategori': r['kategori'] ?? '-',
        'kode': kd,
        'nama': r['nama'] ?? '-',
        'awal': awal,
        'masuk': masuk,
        'retur': retur,
        'penjualan': penjualan,
        'keluar': 0.0,
        'opnameMasuk': opMasuk,
        'opnameKeluar': opKeluar,
        'sisa': sisa,
        'nilaiAkhir': r['nilaiAkhir'] ?? 0.0,
        'nilaiAwal': r['nilaiAwal'] ?? 0.0,
        'statusKode': statusKode,
        'statusAudit': statusAudit,
      });
    }

    return {
      'data': data,
      'ringkasan': {
        'totalProduk': data.length,
        'awal': totalAwal,
        'masuk': totalMasuk,
        'retur': totalRetur,
        'penjualan': totalPenjualan,
        'keluar': 0.0,
        'opnameMasuk': totalOpnameMasuk,
        'opnameKeluar': totalOpnameKeluar,
        'sisa': totalSisa,
        'jmlDinolkanSo': jmlDinolkanSo,
        'jmlStokMinus': jmlStokMinus,
        'jmlKoreksiOpname': jmlKoreksiOpname,
        'jmlKodeDuplikat': jmlKodeDuplikat,
      },
    };
  }

  /// Fallback lengkap untuk `DialogAnalisisCerdasStok` mode seluruh toko bila server mengembalikan
  /// HTTP 503 atau belum memuat `stok_analisis_cerdas_toko`.
  static Future<Map<String, dynamic>> susunAnalisisTokoFallback({
    required DateTime tglMulai,
    required DateTime tglSampai,
  }) async {
    final namaToko = Sesi.instance.tokoNama.isNotEmpty
        ? Sesi.instance.tokoNama
        : 'Toko Al-Bahjah';
    final mulaiStr = _fmtTgl.format(tglMulai);
    final sampaiStr = _fmtTgl.format(tglSampai);

    List<Map<String, dynamic>> rows = [];
    Map<String, dynamic> rk = {};
    try {
      final resRekap = await ApiClient.instance.aksi('stok_pergerakan_rekap', {
        'dari': mulaiStr,
        'sampai': sampaiStr,
        'limit': 1000,
      });
      rows = ((resRekap['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      rk = (resRekap['ringkasan'] as Map?)?.cast<String, dynamic>() ?? {};
    } catch (_) {
      final fb = await muatRekapFallback(
        tglMulai: tglMulai,
        tglSampai: tglSampai,
      );
      rows = fb['data'] as List<Map<String, dynamic>>;
      rk = fb['ringkasan'] as Map<String, dynamic>;
    }

    final jmlDinolkan = (rk['jmlDinolkanSo'] as num?)?.toInt() ?? 0;
    final jmlMinus = (rk['jmlStokMinus'] as num?)?.toInt() ?? 0;
    final jmlOpname = (rk['jmlKoreksiOpname'] as num?)?.toInt() ?? 0;
    final jmlDuplikat = (rk['jmlKodeDuplikat'] as num?)?.toInt() ?? 0;

    final contohDinolkan = <String>[];
    final contohHabisTerjual = <String>[];
    final contohMinus = <String>[];

    for (final r in rows) {
      final kd = '${r['kode'] ?? '-'}';
      final nm = '${r['nama'] ?? '-'}';
      final awal = (r['awal'] as num?)?.toDouble() ?? 0;
      final penjualan = (r['penjualan'] as num?)?.toDouble() ?? 0;
      final opKeluar = (r['opnameKeluar'] as num?)?.toDouble() ?? 0;
      final sisa = (r['sisa'] as num?)?.toDouble() ?? 0;
      final statusKode = '${r['statusKode'] ?? ''}';

      if ((statusKode == 'DINOLKAN_SO' ||
              (awal > 0 && opKeluar > 0 && sisa <= 0)) &&
          contohDinolkan.length < 6) {
        contohDinolkan.add(
            '$kd - $nm: Stok awal ${_angka(awal)} Pcs -> berkurang pada Stok Opname (-${_angka(opKeluar)} Pcs) -> Stok akhir ${_angka(sisa)} Pcs.');
      } else if ((statusKode == 'HABIS_TERJUAL' ||
              (penjualan > 0 && sisa == 0 && opKeluar == 0)) &&
          contohHabisTerjual.length < 5) {
        contohHabisTerjual.add(
            '$kd - $nm: Terjual habis di kasir sebanyak ${_angka(penjualan)} Pcs -> Sisa stok sah menjadi 0 Pcs.');
      } else if (sisa < 0 && contohMinus.length < 5) {
        contohMinus
            .add('$kd - $nm: Stok akhir bernilai minus (${_angka(sisa)} Pcs).');
      }
    }

    String judulDiagnosis;
    String penjelasanUtama;
    if (jmlDinolkan > 0) {
      judulDiagnosis =
          'Terdeteksi ${_angka(jmlDinolkan)} Jenis Barang Dinolkan saat Stok Opname & ${_angka(jmlMinus)} Barang Berstok Minus';
      penjelasanUtama =
          'Pada periode $mulaiStr s/d $sampaiStr di $namaToko, ditemukan ${_angka(jmlDinolkan)} jenis barang berstok positif yang berubah menjadi 0 atau minus karena koreksi Stok Opname, ${_angka(jmlOpname)} jenis barang mengalami koreksi opname (+/-), dan ${_angka(jmlMinus)} jenis barang berstok akhir minus.';
    } else if (jmlMinus > 0) {
      judulDiagnosis =
          'Terdapat ${_angka(jmlMinus)} Jenis Barang Berstok Akhir Minus (< 0) di $namaToko';
      penjelasanUtama =
          'Pada periode $mulaiStr s/d $sampaiStr, terdapat ${_angka(jmlMinus)} jenis barang yang stok akhirnya bernilai minus karena penjualan di kasir melebihi stok tercatat.';
    } else {
      judulDiagnosis =
          'Pergerakan & Rekonsiliasi Stok $namaToko Terpantau Normal (${_angka(rows.length)} Produk)';
      penjelasanUtama =
          'Seluruh mutasi barang masuk, penjualan kasir, retur, dan Stok Opname pada periode $mulaiStr s/d $sampaiStr tercatat wajar.';
    }

    final kronologi = <String>[
      ...contohHabisTerjual.map((e) => '[Habis Terjual Sah] $e'),
      ...contohDinolkan.map((e) => '[Dinolkan saat SO] $e'),
      ...contohMinus.map((e) => '[Stok Minus] $e'),
    ];

    final solusi = <String>[
      'Buka menu Pergerakan Stok, pilih filter "Dinolkan saat Opname (SO -> 0)" atau "Stok Akhir Minus (< 0)", lalu klik Unduh Excel untuk melihat daftar barang terdampak.',
      'Masukkan jumlah fisik sebenarnya melalui menu Stok Opname untuk barang-barang yang belum sempat dihitung ulang.',
      if (jmlDuplikat > 0)
        'Pilih filter "Kode Barang Ganda / Duplikat" dan berikan kode unik pada salah satu barang yang berbagi kode yang sama.',
      'Saat mengunggah Excel Stok Opname bertahap per rak/kategori, hapus baris barang yang belum dihitung agar tidak terisi angka 0.',
    ];

    final wa = StringBuffer()
      ..writeln('Assalamu’alaikum Warahmatullahi Wabarakatuh,\n')
      ..writeln(
          'Berikut adalah *Hasil Analisis Otomatis Pergerakan & Selisih Stok* pada *$namaToko* untuk periode *$mulaiStr s/d $sampaiStr*:\n')
      ..writeln('📋 *A. RINGKASAN & PENYEBAB PERUBAHAN STOK*')
      ..writeln('• *$judulDiagnosis*')
      ..writeln('• $penjelasanUtama\n');

    if (contohHabisTerjual.isNotEmpty) {
      wa.writeln(
          '*1. Contoh Barang yang Berubah Menjadi 0 karena Sah Terjual Habis di Kasir:*');
      for (final c in contohHabisTerjual) {
        wa.writeln('• $c');
      }
      wa.writeln();
    }
    if (contohDinolkan.isNotEmpty) {
      wa.writeln(
          '*2. Contoh Barang yang Berubah Menjadi 0 atau Minus saat Stok Opname:*');
      for (final c in contohDinolkan) {
        wa.writeln('• $c');
      }
      wa.writeln();
    }
    if (contohMinus.isNotEmpty) {
      wa.writeln('*3. Contoh Barang Berstok Akhir Minus (< 0):*');
      for (final c in contohMinus) {
        wa.writeln('• $c');
      }
      wa.writeln();
    }

    wa.writeln('✅ *B. LANGKAH PENYELESAIAN PRAKTIS UNTUK TIM TOKO*');
    for (var i = 0; i < solusi.length; i++) {
      wa.writeln('${i + 1}. ${solusi[i]}');
    }
    wa.writeln('\nWassalamu’alaikum Warahmatullahi Wabarakatuh.');

    return {
      'namaToko': namaToko,
      'judulDiagnosis': judulDiagnosis,
      'penjelasanUtama': penjelasanUtama,
      'kronologiPoin': kronologi,
      'langkahSolusi': solusi,
      'totalProdukDinolkan': jmlDinolkan,
      'totalStokMinus': jmlMinus,
      'teksAnalisisWa': wa.toString().trim(),
    };
  }
}
