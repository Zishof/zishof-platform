import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/dynamic_report.dart';
import '../../services/master_offline.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

/// Tab "Saldo Voucher" -- daftar SALDO AKHIR voucher/tabungan tiap anggota
/// (pegawai) pada rentang tanggal terpilih. Mengklik satu anggota membuka
/// riwayat transaksi voucher miliknya.
///
/// Sengaja TIDAK menambah aksi server baru: memakai `mutasi_tabungan_list`
/// yang sudah mengembalikan rekap per anggota sekaligus baris mutasinya,
/// sehingga saldo di halaman ini dijamin identik dengan tab Mutasi Voucher --
/// satu sumber angka, bukan dua rumus yang bisa berbeda.
///
/// Unduhan memakai DynamicReportDesigner yang sama dengan Laporan Transaksi
/// (Preview, Atur Model, PDF, Excel, Word) sehingga kolom dan judulnya dapat
/// dikustomisasi pengguna.
class AnggotaTabSaldoVoucher extends StatefulWidget {
  const AnggotaTabSaldoVoucher({super.key});

  @override
  State<AnggotaTabSaldoVoucher> createState() => _AnggotaTabSaldoVoucherState();
}

class _AnggotaTabSaldoVoucherState extends State<AnggotaTabSaldoVoucher> {
  static final _fmtRp =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final _fmtTgl = DateFormat('yyyy-MM-dd');
  static final _fmtTglTampil = DateFormat('dd/MM/yy');

  late DateTime _dari;
  late DateTime _sampai;
  bool _memuat = true;
  String? _galat;
  String _cari = '';
  bool _menyiapkanLaporan = false;
  DynamicReportModel? _modelLaporan;

  List<Map<String, dynamic>> _mutasi = [];

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _dari = DateTime(kini.year, kini.month, 1);
    _sampai = DateTime(kini.year, kini.month, kini.day);
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'mutasi_tabungan_list',
        {'dari': _fmtTgl.format(_dari), 'sampai': _fmtTgl.format(_sampai)},
        'master:saldo_voucher:${_fmtTgl.format(_dari)}-${_fmtTgl.format(_sampai)}',
        responsLengkap: true,
        onData: (res) {
          if (!mounted) return;
          final sukses = res['status'] == '00' || res['status'] == 'success';
          if (!sukses) {
            setStateIfMounted(() {
              _galat = '${res['description'] ?? 'Gagal memuat saldo voucher.'}';
              _memuat = false;
            });
            return;
          }
          setStateIfMounted(() {
            _mutasi = ((res['data'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  double _angka(dynamic v) => (v as num?)?.toDouble() ?? 0;

  /// Rekap per anggota: masuk/keluar dijumlahkan, saldo akhir diambil dari
  /// saldo berjalan baris terakhir milik anggota tsb.
  List<Map<String, dynamic>> get _saldoPerAnggota {
    final peta = <String, Map<String, dynamic>>{};
    for (final m in _mutasi) {
      final kunci = '${m['idAnggota'] ?? m['namaAnggota'] ?? '-'}';
      final entri = peta.putIfAbsent(
          kunci,
          () => <String, dynamic>{
                'idAnggota': m['idAnggota'],
                'namaAnggota': '${m['namaAnggota'] ?? '-'}',
                'saldoAwal': _angka(m['saldoAwal']),
                'masuk': 0.0,
                'keluar': 0.0,
                'saldoAkhir': 0.0,
                'jumlahTransaksi': 0,
              });
      entri['masuk'] = (entri['masuk'] as double) + _angka(m['masuk']);
      entri['keluar'] = (entri['keluar'] as double) + _angka(m['keluar']);
      entri['saldoAkhir'] = _angka(m['saldoPerPenabung']);
      entri['jumlahTransaksi'] = (entri['jumlahTransaksi'] as int) + 1;
    }
    final daftar = peta.values.toList();
    final kunciCari = _cari.trim().toLowerCase();
    final hasil = kunciCari.isEmpty
        ? daftar
        : daftar
            .where((r) => '${r['namaAnggota']}'.toLowerCase().contains(kunciCari))
            .toList();
    hasil.sort((a, b) =>
        (b['saldoAkhir'] as double).compareTo(a['saldoAkhir'] as double));
    return hasil;
  }

  DynamicReportData _dataLaporan() => DynamicReportData(
        title: 'Saldo Voucher Anggota',
        subtitle:
            'Periode ${_fmtTglTampil.format(_dari)} s.d. ${_fmtTglTampil.format(_sampai)}',
        columns: const [
          DynamicReportColumn('namaAnggota', 'Anggota'),
          DynamicReportColumn('saldoAwal', 'Saldo Awal', numeric: true),
          DynamicReportColumn('masuk', 'Masuk', numeric: true),
          DynamicReportColumn('keluar', 'Keluar', numeric: true),
          DynamicReportColumn('saldoAkhir', 'Saldo Akhir', numeric: true),
          DynamicReportColumn('jumlahTransaksi', 'Jml Transaksi', numeric: true),
        ],
        rows: _saldoPerAnggota,
      );

  Future<void> _aturAtauPreview({required bool preview}) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final model = await DynamicReportDesigner.show(context,
          data: _dataLaporan(),
          initial: _modelLaporan,
          initialTab: preview ? 0 : 1);
      if (model != null) setStateIfMounted(() => _modelLaporan = model);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyiapkan laporan: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  Future<void> _ekspor(String format) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final data = _dataLaporan();
      final model = _modelLaporan ?? DynamicReportModel.fromData(data);
      _modelLaporan = model;
      const slug = 'saldo-voucher-anggota';
      if (format == 'pdf') {
        await DynamicReportDesigner.exportPdf(data, model, '$slug.pdf');
      } else if (format == 'excel') {
        if (!mounted) return;
        await DynamicReportDesigner.exportExcel(context, data, model, '$slug.xlsx');
      } else {
        if (!mounted) return;
        await DynamicReportDesigner.exportWord(context, data, model, '$slug.doc');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  Future<void> _pilihRentang() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      _dari = hasil.start;
      _sampai = hasil.end;
    });
    await _muat();
  }

  /// Riwayat transaksi voucher SATU anggota -- diambil dari baris mutasi yang
  /// sudah dimuat, jadi tidak menembak server lagi saat baris diklik.
  void _bukaRiwayat(Map<String, dynamic> anggota) {
    final id = anggota['idAnggota'];
    final nama = '${anggota['namaAnggota'] ?? '-'}';
    final riwayat = _mutasi
        .where((m) => id == null
            ? '${m['namaAnggota']}' == nama
            : '${m['idAnggota']}' == '$id')
        .toList()
      ..sort((a, b) => '${a['waktu']}'.compareTo('${b['waktu']}'));
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Riwayat Voucher: $nama'),
        content: SizedBox(
          width: 760,
          height: 440,
          child: riwayat.isEmpty
              ? const Center(child: Text('Belum ada transaksi pada rentang ini.'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                        'Saldo akhir ${_fmtRp.format(anggota['saldoAkhir'] ?? 0)}  -  ${riwayat.length} transaksi',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 20,
                        columns: const [
                          DataColumn(label: Text('Waktu')),
                          DataColumn(label: Text('Jenis')),
                          DataColumn(label: Text('Keterangan')),
                          DataColumn(label: Text('Masuk'), numeric: true),
                          DataColumn(label: Text('Keluar'), numeric: true),
                          DataColumn(label: Text('Saldo'), numeric: true),
                        ],
                        rows: [
                          for (final m in riwayat)
                            DataRow(cells: [
                              DataCell(Text('${m['waktu'] ?? '-'}')),
                              DataCell(Text('${m['jenisMutasi'] ?? '-'}')),
                              DataCell(SizedBox(
                                  width: 220,
                                  child: Text('${m['keterangan'] ?? '-'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis))),
                              DataCell(Text(_fmtRp.format(_angka(m['masuk'])))),
                              DataCell(Text(_fmtRp.format(_angka(m['keluar'])))),
                              DataCell(Text(
                                  _fmtRp.format(_angka(m['saldoPerPenabung'])))),
                            ])
                        ],
                      ),
                    ),
                  ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daftar = _saldoPerAnggota;
    final totalSaldo =
        daftar.fold<double>(0, (s, r) => s + (r['saldoAkhir'] as double));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: _memuat ? null : _pilihRentang,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                  '${_fmtTglTampil.format(_dari)} - ${_fmtTglTampil.format(_sampai)}')),
          SizedBox(
            width: 240,
            child: TextField(
              decoration: const InputDecoration(
                  labelText: 'Cari anggota',
                  prefixIcon: Icon(Icons.search),
                  isDense: true),
              onChanged: (v) => setStateIfMounted(() => _cari = v),
            ),
          ),
          OutlinedButton.icon(
              onPressed:
                  _menyiapkanLaporan ? null : () => _aturAtauPreview(preview: true),
              icon: const Icon(Icons.preview_outlined, size: 18),
              label: const Text('Preview')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan
                  ? null
                  : () => _aturAtauPreview(preview: false),
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Atur Model')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('pdf'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('excel'),
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: const Text('Excel')),
          OutlinedButton.icon(
              onPressed: _menyiapkanLaporan ? null : () => _ekspor('word'),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Word')),
          IconButton(
              onPressed: _memuat ? null : _muat,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (!_memuat && _galat == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Text('${daftar.length} anggota',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('Total saldo akhir: ${_fmtRp.format(totalSaldo)}',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
          ]),
        ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
                    ]),
                  ))
                : daftar.isEmpty
                    ? const Center(
                        child: Text(
                            'Belum ada saldo voucher pada rentang tanggal ini.'))
                    : AppDataTable(
                        minWidth: 820,
                        emptyText: 'Tidak ada data pada rentang ini.',
                        columns: const [
                          AppTableColumn('Anggota', flex: 4),
                          AppTableColumn('Saldo Awal',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Masuk', flex: 2, align: TextAlign.right),
                          AppTableColumn('Keluar', flex: 2, align: TextAlign.right),
                          AppTableColumn('Saldo Akhir',
                              flex: 2, align: TextAlign.right),
                          AppTableColumn('Aksi', width: 70),
                        ],
                        rows: daftar
                            .map((r) => AppTableRowData(
                                  onTap: () => _bukaRiwayat(r),
                                  cells: [
                                    AppTableCell.text('${r['namaAnggota']}',
                                        flex: 4),
                                    AppTableCell.text(
                                        _fmtRp.format(r['saldoAwal'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['masuk'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['keluar'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right),
                                    AppTableCell.text(
                                        _fmtRp.format(r['saldoAkhir'] ?? 0),
                                        flex: 2,
                                        align: TextAlign.right,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    AppTableCell(
                                      width: 70,
                                      align: TextAlign.center,
                                      child: IconButton(
                                          tooltip: 'Lihat riwayat transaksi',
                                          icon: const Icon(
                                              Icons.receipt_long_outlined,
                                              size: 18),
                                          onPressed: () => _bukaRiwayat(r)),
                                    ),
                                  ],
                                ))
                            .toList(),
                      ),
      ),
    ]);
  }
}
