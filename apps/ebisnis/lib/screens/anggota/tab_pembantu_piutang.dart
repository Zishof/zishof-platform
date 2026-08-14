import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../api_client.dart';
import '../../services/simple_xlsx.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import 'tab_mutasi_tabungan.dart' show PilihAnggotaSheet;

final _rpPembantuPiutang =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Buku Besar Pembantu Piutang per anggota. Data dipaging oleh server (15
/// customer per permintaan), bukan memuat seluruh ledger ke memori perangkat.
class AnggotaTabPembantuPiutang extends StatefulWidget {
  const AnggotaTabPembantuPiutang({super.key});

  @override
  State<AnggotaTabPembantuPiutang> createState() =>
      _AnggotaTabPembantuPiutangState();
}

class _AnggotaTabPembantuPiutangState extends State<AnggotaTabPembantuPiutang> {
  static const _pageSize = 15;
  final _cari = TextEditingController();
  late DateTime _dari;
  late DateTime _sampai;
  int _halaman = 1;
  int _totalHalaman = 1;
  int _totalData = 0;
  int? _idAnggota;
  String? _namaAnggota;
  bool _memuat = true;
  bool _mengekspor = false;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _total = {};

  @override
  void initState() {
    super.initState();
    final sekarang = DateTime.now();
    _dari = DateTime(sekarang.year, sekarang.month, 1);
    _sampai = sekarang;
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Map<String, dynamic> _parameter({int? page, int pageSize = _pageSize}) => {
        'dari': DateFormat('yyyy-MM-dd').format(_dari),
        'sampai': DateFormat('yyyy-MM-dd').format(_sampai),
        'page': page ?? _halaman,
        'page_size': pageSize,
        if (_idAnggota != null) 'id_anggota': _idAnggota,
        if (_cari.text.trim().isNotEmpty) 'q': _cari.text.trim(),
      };

  Future<void> _muat({int? halaman}) async {
    if (halaman != null) _halaman = halaman;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('pembantu_piutang_list', _parameter());
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _total = Map<String, dynamic>.from((hasil['total'] as Map?) ?? {});
        _totalData = (hasil['totalData'] as num?)?.toInt() ?? 0;
        _totalHalaman =
            ((hasil['totalPages'] as num?)?.toInt() ?? 1).clamp(1, 999999);
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal() async {
    final rentang = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
    );
    if (rentang == null) return;
    setStateIfMounted(() {
      _dari = rentang.start;
      _sampai = rentang.end;
    });
    await _muat(halaman: 1);
  }

  Future<void> _pilihAnggota() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PilihAnggotaSheet(),
    );
    if (dipilih == null) return;
    setStateIfMounted(() {
      _idAnggota = (dipilih['id'] as num).toInt();
      _namaAnggota = '${dipilih['nama']}';
    });
    await _muat(halaman: 1);
  }

  Future<List<Map<String, dynamic>>> _ambilSemua() async {
    final hasil = await ApiClient.instance
        .aksi('pembantu_piutang_list', _parameter(page: 1, pageSize: 5000));
    return ((hasil['data'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      if (semua.isEmpty) throw StateError('Tidak ada data untuk diunduh.');
      final total = _hitungTotal(semua);
      final rows = semua
          .map((r) => <Object?>[
                r['kodeAnggota'] ?? '',
                r['namaAnggota'] ?? '',
                _angka(r, 'saldoAwal'),
                _angka(r, 'faktur'),
                _angka(r, 'pembayaran'),
                _angka(r, 'retur'),
                _angka(r, 'uangMuka'),
                _angka(r, 'jurnalUmum'),
                _angka(r, 'saldoAkhir'),
              ])
          .toList()
        ..add(<Object?>[
          'TOTAL',
          '',
          total['saldoAwal'],
          total['faktur'],
          total['pembayaran'],
          total['retur'],
          total['uangMuka'],
          total['jurnalUmum'],
          total['saldoAkhir'],
        ]);
      final bytes = buildSimpleXlsx(
        sheetName: 'Pembantu Piutang',
        headers: const [
          'ID PELANGGAN',
          'NAMA PELANGGAN',
          'SALDO AWAL',
          'FAKTUR',
          'PEMBAYARAN',
          'RETUR',
          'UANG MUKA',
          'JURNAL UMUM',
          'SALDO AKHIR',
        ],
        rows: rows,
      );
      final nama =
          'Buku_Besar_Pembantu_Piutang_${DateFormat('yyyyMMdd').format(_dari)}_${DateFormat('yyyyMMdd').format(_sampai)}.xlsx';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Buku Besar Pembantu Piutang',
        fileName: nama,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path != null && !Platform.isAndroid && !Platform.isIOS) {
        await File(path).writeAsBytes(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _mengekspor = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      if (semua.isEmpty) throw StateError('Tidak ada data untuk dicetak.');
      final total = _hitungTotal(semua);
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: const PdfPageFormat(842, 595.2, marginAll: 20),
        header: (_) => pw.Column(children: [
          pw.Text('Buku Besar Pembantu Piutang',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              '${DateFormat('dd MMM yyyy').format(_dari)} s/d ${DateFormat('dd MMM yyyy').format(_sampai)}'),
          pw.SizedBox(height: 8),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: const [
              'ID Pelanggan',
              'Nama Pelanggan',
              'Saldo Awal',
              'Faktur',
              'Pembayaran',
              'Retur',
              'Uang Muka',
              'Jurnal Umum',
              'Saldo Akhir',
            ],
            data: [
              ...semua.map((r) => [
                    '${r['kodeAnggota'] ?? ''}',
                    '${r['namaAnggota'] ?? ''}',
                    _rpPembantuPiutang.format(_angka(r, 'saldoAwal')),
                    _rpPembantuPiutang.format(_angka(r, 'faktur')),
                    _rpPembantuPiutang.format(_angka(r, 'pembayaran')),
                    _rpPembantuPiutang.format(_angka(r, 'retur')),
                    _rpPembantuPiutang.format(_angka(r, 'uangMuka')),
                    _rpPembantuPiutang.format(_angka(r, 'jurnalUmum')),
                    _rpPembantuPiutang.format(_angka(r, 'saldoAkhir')),
                  ]),
              [
                'TOTAL',
                '',
                _rpPembantuPiutang.format(total['saldoAwal']),
                _rpPembantuPiutang.format(total['faktur']),
                _rpPembantuPiutang.format(total['pembayaran']),
                _rpPembantuPiutang.format(total['retur']),
                _rpPembantuPiutang.format(total['uangMuka']),
                _rpPembantuPiutang.format(total['jurnalUmum']),
                _rpPembantuPiutang.format(total['saldoAkhir']),
              ]
            ],
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerStyle:
                pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(), name: 'Pembantu_Piutang.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      setStateIfMounted(() => _mengekspor = false);
    }
  }

  static double _angka(Map<String, dynamic> r, String k) =>
      (r[k] as num?)?.toDouble() ?? 0;

  static Map<String, double> _hitungTotal(List<Map<String, dynamic>> data) {
    const keys = [
      'saldoAwal',
      'faktur',
      'pembayaran',
      'retur',
      'uangMuka',
      'jurnalUmum',
      'saldoAkhir'
    ];
    return {
      for (final k in keys) k: data.fold(0.0, (s, r) => s + _angka(r, k))
    };
  }

  AppTableCell _uang(Map<String, dynamic> r, String k,
          {Color? warna, bool tebal = false}) =>
      AppTableCell.text(
        _rpPembantuPiutang.format(_angka(r, k)),
        align: TextAlign.right,
        style: TextStyle(
            fontSize: 11.5,
            color: warna,
            fontWeight: tebal ? FontWeight.bold : FontWeight.normal),
      );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _muat(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _cari,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cari ID / nama pelanggan...',
                    isDense: true),
                onSubmitted: (_) => _muat(halaman: 1),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pilihAnggota,
              icon: const Icon(Icons.person_search, size: 18),
              label: Text(_namaAnggota ?? 'Semua Anggota'),
            ),
            if (_idAnggota != null)
              IconButton(
                  tooltip: 'Hapus filter anggota',
                  onPressed: () {
                    setStateIfMounted(() {
                      _idAnggota = null;
                      _namaAnggota = null;
                    });
                    _muat(halaman: 1);
                  },
                  icon: const Icon(Icons.close)),
            OutlinedButton.icon(
              onPressed: _pilihTanggal,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                  '${DateFormat('dd/MM/yy').format(_dari)} - ${DateFormat('dd/MM/yy').format(_sampai)}'),
            ),
            ElevatedButton.icon(
              onPressed: _memuat ? null : () => _muat(halaman: 1),
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Saring'),
            ),
            ElevatedButton.icon(
              onPressed: _mengekspor ? null : _unduhExcel,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Download Excel'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white),
            ),
            ElevatedButton.icon(
              onPressed: _mengekspor ? null : _cetakPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Cetak PDF'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textSecondary,
                  foregroundColor: Colors.white),
            ),
          ]),
          const SizedBox(height: 12),
          const Text('Buku Besar Pembantu Piutang',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text(
            'Saldo awal dihitung dari seluruh transaksi sebelum tanggal mulai. Saldo akhir = saldo awal + faktur − pembayaran − retur − uang muka + jurnal umum.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 10),
          if (_memuat)
            const SizedBox(
                height: 260, child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SizedBox(
              height: 260,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.danger),
                    const SizedBox(height: 10),
                    const Text('Laporan belum dapat dimuat',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _muat, child: const Text('Coba Lagi')),
                  ]),
                ),
              ),
            )
          else
            AppDataTable(
              minWidth: 1250,
              emptyText: 'Tidak ada data piutang pada filter ini.',
              columns: const [
                AppTableColumn('ID Pelanggan', flex: 1),
                AppTableColumn('Nama Pelanggan', flex: 2),
                AppTableColumn('Saldo Awal', align: TextAlign.right),
                AppTableColumn('Faktur', align: TextAlign.right),
                AppTableColumn('Pembayaran', align: TextAlign.right),
                AppTableColumn('Retur', align: TextAlign.right),
                AppTableColumn('Uang Muka', align: TextAlign.right),
                AppTableColumn('Jurnal Umum', align: TextAlign.right),
                AppTableColumn('Saldo Akhir', align: TextAlign.right),
              ],
              rows: [
                ..._data.map((r) => AppTableRowData(cells: [
                      AppTableCell.text('${r['kodeAnggota'] ?? '-'}'),
                      AppTableCell.text('${r['namaAnggota'] ?? '-'}', flex: 2),
                      _uang(r, 'saldoAwal'),
                      _uang(r, 'faktur', warna: AppColors.danger),
                      _uang(r, 'pembayaran', warna: AppColors.success),
                      _uang(r, 'retur'),
                      _uang(r, 'uangMuka'),
                      _uang(r, 'jurnalUmum'),
                      _uang(r, 'saldoAkhir',
                          warna: AppColors.warning, tebal: true),
                    ])),
                if (_data.isNotEmpty)
                  AppTableRowData(cells: [
                    AppTableCell.text('TOTAL',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    AppTableCell.text('$_totalData pelanggan', flex: 2),
                    _uang(_total, 'saldoAwal', tebal: true),
                    _uang(_total, 'faktur', tebal: true),
                    _uang(_total, 'pembayaran', tebal: true),
                    _uang(_total, 'retur', tebal: true),
                    _uang(_total, 'uangMuka', tebal: true),
                    _uang(_total, 'jurnalUmum', tebal: true),
                    _uang(_total, 'saldoAkhir',
                        warna: AppColors.warning, tebal: true),
                  ]),
              ],
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _totalData,
                labelData: 'pelanggan',
                onSebelumnya:
                    _halaman > 1 ? () => _muat(halaman: _halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () => _muat(halaman: _halaman + 1)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
