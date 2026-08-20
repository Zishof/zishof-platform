import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../services/simple_xlsx.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';

final _mutasiRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _mutasiAngka = NumberFormat('#,##0.##', 'id_ID');
final _mutasiTanggal = DateFormat('yyyy-MM-dd');

class ProdukMutasiBarangTab extends StatefulWidget {
  const ProdukMutasiBarangTab({super.key});

  @override
  State<ProdukMutasiBarangTab> createState() => _ProdukMutasiBarangTabState();
}

class _ProdukMutasiBarangTabState extends State<ProdukMutasiBarangTab> with JejakGalat {
  static const _pageSize = 15;
  late DateTime _dari;
  late DateTime _sampai;
  int _halaman = 1;
  int _total = 0;
  bool _memuat = true;
  bool _mengekspor = false;
  String? _error;
  String _keyword = '';
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _summary = {};

  /// Diff emisi "lokal dulu" -- menggerakkan animasi kilau baris yang
  /// baru/berubah di server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dari = DateTime(now.year, now.month, 1);
    _sampai = now;
    _muat();
  }

  Map<String, dynamic> _payload({int? page, int? pageSize}) => {
        'dari': _mutasiTanggal.format(_dari),
        'sampai': _mutasiTanggal.format(_sampai),
        'page': page ?? _halaman,
        'page_size': pageSize ?? _pageSize,
        if (_keyword.trim().isNotEmpty) 'keyword': _keyword.trim(),
      };

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU (MasterOffline.daftarCacheDulu): tabel tampil seketika
      // dari cache, hasil server menyusul + diff utk kilau baris. Cache
      // dipisah per rentang tanggal karena seluruh kolom saldo/nilai baris
      // hanya sahih untuk periode itu.
      await MasterOffline.daftarCacheDulu(
        'produk_mutasi_ringkasan',
        _payload(),
        'master:mutasi_barang:${_mutasiTanggal.format(_dari)}_${_mutasiTanggal.format(_sampai)}',
        // Baris ringkasan mutasi tidak ber-'id'; satu-satunya kolom identitas
        // yang dikirim server adalah kode barang (unik per produk). Baris yang
        // kebetulan tanpa kode tetap aman: MasterOffline memperlakukannya
        // sebagai "baris tanpa kunci" (tidak digandakan di cache), hanya saja
        // tidak ikut berkilau.
        kolomKunci: 'kode',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data = _diff.terapkan(hasil);
            _total = _diff.total ?? _data.length;
            // Baris TOTAL memakai summary server -- hanya ada pada emisi
            // server, jadi nilai terakhir dipertahankan saat emisi lokal.
            if (_diff.dariServer) {
              _summary =
                  (hasil['summary'] as Map?)?.cast<String, dynamic>() ?? {};
            }
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal(bool mulai) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: mulai ? _dari : _sampai,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      if (mulai) {
        _dari = hasil;
        if (_sampai.isBefore(_dari)) _sampai = _dari;
      } else {
        _sampai = hasil;
        if (_dari.isAfter(_sampai)) _dari = _sampai;
      }
      _halaman = 1;
    });
    await _muat();
  }

  Future<List<Map<String, dynamic>>> _ambilSemua() async {
    final semua = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final hasil = await ApiClient.instance
          .aksi('produk_mutasi_ringkasan', _payload(page: page, pageSize: 500));
      final bagian =
          ((hasil['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      semua.addAll(bagian);
      final total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      if (bagian.isEmpty || semua.length >= total) break;
      page++;
    }
    return semua;
  }

  static const _headers = [
    'Kategori Barang',
    'Kode Barang',
    'UPC/Barcode',
    'Nama Barang & Jasa',
    'Saldo Awal',
    'Nilai Awal',
    'Masuk',
    'Nilai Masuk',
    'Keluar',
    'Nilai Keluar',
    'Saldo Akhir',
    'Nilai Akhir',
  ];

  List<dynamic> _baris(Map<String, dynamic> r) => [
        r['kategori'] ?? '',
        r['kode'] ?? '',
        r['barcode'] ?? '',
        r['nama'] ?? '',
        r['saldoAwal'] ?? 0,
        r['nilaiAwal'] ?? 0,
        r['masuk'] ?? 0,
        r['nilaiMasuk'] ?? 0,
        r['keluar'] ?? 0,
        r['nilaiKeluar'] ?? 0,
        r['saldoAkhir'] ?? 0,
        r['nilaiAkhir'] ?? 0,
      ];

  List<dynamic> _barisTotal() => [
        'TOTAL',
        '',
        '',
        '',
        _summary['saldoAwal'] ?? 0,
        _summary['nilaiAwal'] ?? 0,
        _summary['masuk'] ?? 0,
        _summary['nilaiMasuk'] ?? 0,
        _summary['keluar'] ?? 0,
        _summary['nilaiKeluar'] ?? 0,
        _summary['saldoAkhir'] ?? 0,
        _summary['nilaiAkhir'] ?? 0,
      ];

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      final bytes = buildSimpleXlsx(
        sheetName: 'Mutasi Barang',
        headers: _headers,
        rows: [...semua.map(_baris), _barisTotal()],
      );
      final nama =
          'Mutasi_Barang_${_mutasiTanggal.format(_dari)}_sd_${_mutasiTanggal.format(_sampai)}.xlsx';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Ringkasan Mutasi Barang',
        fileName: nama,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null) await File(path).writeAsBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat Excel: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(children: [
          pw.Text('Ringkasan Mutasi Gudang',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              '${_mutasiTanggal.format(_dari)} s/d ${_mutasiTanggal.format(_sampai)}'),
          pw.SizedBox(height: 10),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: [...semua.map(_baris), _barisTotal()].map((row) {
              return row.asMap().entries.map((e) {
                if (e.key >= 4 && e.value is num) {
                  return e.key.isOdd
                      ? _mutasiRp.format(e.value)
                      : _mutasiAngka.format(e.value);
                }
                return '${e.value}';
              }).toList();
            }).toList(),
            headerStyle:
                pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerLeft,
            },
          ),
        ],
      ));
      await Printing.layoutPdf(
          name:
              'Mutasi_Barang_${_mutasiTanggal.format(_dari)}_${_mutasiTanggal.format(_sampai)}.pdf',
          onLayout: (_) => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  AppTableCell _angkaCell(dynamic v, {bool rupiah = false}) =>
      AppTableCell.text(
        rupiah
            ? _mutasiRp.format((v as num?) ?? 0)
            : _mutasiAngka.format((v as num?) ?? 0),
        width: 105,
        align: TextAlign.right,
        style: const TextStyle(fontSize: 11.5),
      );

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 999999);
    final rows = _data.map((r) => AppTableRowData(cells: [
          AppTableCell(
            width: 130,
            child: KilauBaris(
              kunci: MasterOffline.kunciBaris(r, 'kode'),
              idBaru: _diff.idBaru,
              idBerubah: _diff.idBerubah,
              child: Text('${r['kategori'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          AppTableCell.text('${r['kode'] ?? '-'}', width: 95),
          AppTableCell.text('${r['barcode'] ?? '-'}', width: 110),
          AppTableCell.text('${r['nama'] ?? '-'}', width: 220),
          _angkaCell(r['saldoAwal']),
          _angkaCell(r['nilaiAwal'], rupiah: true),
          _angkaCell(r['masuk']),
          _angkaCell(r['nilaiMasuk'], rupiah: true),
          _angkaCell(r['keluar']),
          _angkaCell(r['nilaiKeluar'], rupiah: true),
          _angkaCell(r['saldoAkhir']),
          _angkaCell(r['nilaiAkhir'], rupiah: true),
        ]));
    final totalRow = AppTableRowData(cells: [
      const AppTableCell(
          width: 130,
          child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
      const AppTableCell(width: 95, child: SizedBox.shrink()),
      const AppTableCell(width: 110, child: SizedBox.shrink()),
      const AppTableCell(width: 220, child: SizedBox.shrink()),
      _angkaCell(_summary['saldoAwal']),
      _angkaCell(_summary['nilaiAwal'], rupiah: true),
      _angkaCell(_summary['masuk']),
      _angkaCell(_summary['nilaiMasuk'], rupiah: true),
      _angkaCell(_summary['keluar']),
      _angkaCell(_summary['nilaiKeluar'], rupiah: true),
      _angkaCell(_summary['saldoAkhir']),
      _angkaCell(_summary['nilaiAkhir'], rupiah: true),
    ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => _pilihTanggal(true),
              icon: const Icon(Icons.calendar_today_outlined, size: 17),
              label: Text('Dari ${_mutasiTanggal.format(_dari)}')),
          OutlinedButton.icon(
              onPressed: () => _pilihTanggal(false),
              icon: const Icon(Icons.event_outlined, size: 17),
              label: Text('Sampai ${_mutasiTanggal.format(_sampai)}')),
          FilledButton.tonalIcon(
              onPressed: _mengekspor ? null : _unduhExcel,
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Download Excel')),
          FilledButton.tonalIcon(
              onPressed: _mengekspor ? null : _cetakPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Cetak PDF')),
          IconButton(onPressed: _muat, icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 10),
        AppSearchField(
          hintText: 'Cari kategori / kode / barcode / nama barang...',
          debounce: const Duration(milliseconds: 400),
          onChanged: (v) {
            _keyword = v;
            _halaman = 1;
            _muat();
          },
        ),
        if (_mengekspor) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 42),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      AppDetailGalatOpsional(detail: detailUntuk(_error)),
                      TextButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]))
                  : SingleChildScrollView(
                      child: AppDataTable(
                        minWidth: 1460,
                        emptyText: 'Belum ada data mutasi barang.',
                        columns: const [
                          AppTableColumn('Kategori Barang', width: 130),
                          AppTableColumn('Kode Barang', width: 95),
                          AppTableColumn('UPC/Barcode', width: 110),
                          AppTableColumn('Nama Barang & Jasa', width: 220),
                          AppTableColumn('Saldo Awal',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Nilai Awal',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Masuk',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Nilai Masuk',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Keluar',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Nilai Keluar',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Saldo Akhir',
                              width: 105, align: TextAlign.right),
                          AppTableColumn('Nilai Akhir',
                              width: 105, align: TextAlign.right),
                        ],
                        rows: [...rows, if (_data.isNotEmpty) totalRow],
                        pagination: AppTablePagination(
                          halaman: _halaman,
                          totalHalaman: totalHalaman,
                          totalData: _total,
                          labelData: 'produk',
                          onSebelumnya: _halaman > 1
                              ? () {
                                  _halaman--;
                                  _muat();
                                }
                              : null,
                          onBerikutnya: _halaman < totalHalaman
                              ? () {
                                  _halaman++;
                                  _muat();
                                }
                              : null,
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}
