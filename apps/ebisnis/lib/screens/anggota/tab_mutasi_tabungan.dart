import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';

final _formatRpMutasiTabungan =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTglMutasiTabungan = DateFormat('dd MMM yyyy HH:mm', 'id_ID');

/// Tab "Mutasi Tabungan" (padanan `_mutasi_tabungan.jsp`) -- buku besar
/// UNION topup+belanja+cashback dgn saldo berjalan, dihitung server (aksi
/// `mutasi_tabungan_list`, versi Java dari query raw-SQL client-side JSP,
/// krn Flutter tidak punya jalur SQL langsung -- lihat JavaDoc
/// KantinHelper.mutasiTabunganList). Flat-list (server cap 3000 baris),
/// paginasi CLIENT spt JSP. Download (CSV)/Upload (bulk topup via
/// `topup_saldo`)/Cetak PDF (client-side, `pdf`+`printing`, TANPA aksi
/// server baru).
class AnggotaTabMutasiTabungan extends StatefulWidget {
  const AnggotaTabMutasiTabungan({super.key});

  @override
  State<AnggotaTabMutasiTabungan> createState() =>
      _AnggotaTabMutasiTabunganState();
}

class _AnggotaTabMutasiTabunganState extends State<AnggotaTabMutasiTabungan> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  static const _pageSize = 20;
  late DateTime _dari;
  late DateTime _sampai;
  int? _idAnggotaFilter;
  String? _namaAnggotaFilter;
  bool _mengunggah = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dari = DateTime(now.year, now.month, 1);
    _sampai = now;
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('mutasi_tabungan_list', {
        'dari': DateFormat('yyyy-MM-dd').format(_dari),
        'sampai': DateFormat('yyyy-MM-dd').format(_sampai),
        if (_idAnggotaFilter != null) 'id_anggota': _idAnggotaFilter,
      });
      final data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (mounted) {
        setStateIfMounted(() {
          _data = data;
          _halaman = 1;
        });
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihRentangTanggal() async {
    final hasil = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _dari, end: _sampai),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      _dari = hasil.start;
      _sampai = hasil.end;
    });
    _muat();
  }

  Future<void> _pilihAnggotaFilter() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PilihAnggotaSheet(),
    );
    if (dipilih == null) return;
    setStateIfMounted(() {
      _idAnggotaFilter = dipilih['id'] as int;
      _namaAnggotaFilter = '${dipilih['nama']}';
    });
    _muat();
  }

  void _hapusFilterAnggota() {
    setStateIfMounted(() {
      _idAnggotaFilter = null;
      _namaAnggotaFilter = null;
    });
    _muat();
  }

  int get _totalHalaman => (_data.length / _pageSize).ceil().clamp(1, 999999);
  List<Map<String, dynamic>> get _dataHalaman {
    final awal = (_halaman - 1) * _pageSize;
    final akhir = (awal + _pageSize).clamp(0, _data.length);
    return awal >= _data.length ? [] : _data.sublist(awal, akhir);
  }

  Future<void> _unduhCsv() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diunduh.')));
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln(
        'NAMA_ANGGOTA,TANGGAL,JENIS_MUTASI,KETERANGAN,MASUK_DEBIT,KELUAR_KREDIT,SALDO_PER_PENABUNG,SALDO_TOTAL');
    for (final r in _data) {
      buffer.writeln([
        _csv('${r['namaAnggota'] ?? ''}'),
        _csv('${r['waktu'] ?? ''}'),
        _csv('${r['jenisMutasi'] ?? ''}'),
        _csv('${r['keterangan'] ?? ''}'),
        r['masuk'] ?? 0,
        r['keluar'] ?? 0,
        r['saldoPerPenabung'] ?? 0,
        r['saldoTotal'] ?? 0,
      ].join(','));
    }
    final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
    final nama =
        'Mutasi_Tabungan_${DateFormat('yyyyMMdd').format(_dari)}_${DateFormat('yyyyMMdd').format(_sampai)}.csv';
    await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan Mutasi Tabungan',
      fileName: nama,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
  }

  String _csv(String v) => '"${v.replaceAll('"', '""')}"';

  Future<void> _cetakPdf() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk dicetak.')));
      return;
    }
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: const PdfPageFormat(842, 595.2, marginAll: 24),
        header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Mutasi Tabungan (Buku Besar)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              '${DateFormat('dd/MM/yyyy').format(_dari)} s/d ${DateFormat('dd/MM/yyyy').format(_sampai)}'),
          pw.SizedBox(height: 8),
        ]),
        build: (_) => [
          pw.Table.fromTextArray(
            headers: const [
              'Nama', 'Tanggal', 'Jenis', 'Keterangan', 'Masuk', 'Keluar', 'Saldo'
            ],
            data: _data.map((r) => [
              '${r['namaAnggota'] ?? ''}',
              '${r['waktu'] ?? ''}',
              '${r['jenisMutasi'] ?? ''}',
              '${r['keterangan'] ?? ''}',
              _formatRpMutasiTabungan.format(r['masuk'] ?? 0),
              _formatRpMutasiTabungan.format(r['keluar'] ?? 0),
              _formatRpMutasiTabungan.format(r['saldoPerPenabung'] ?? 0),
            ]).toList(),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save(), name: 'Mutasi_Tabungan.pdf');
  }

  Future<void> _unggahCsv() async {
    final hasil = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (hasil == null || hasil.files.isEmpty) return;
    final bytes = hasil.files.single.bytes;
    if (bytes == null) return;
    final baris = const LineSplitter().convert(utf8.decode(bytes));
    if (baris.length < 2) return;

    setStateIfMounted(() => _mengunggah = true);
    int berhasil = 0, gagal = 0;
    final pesanGagal = <String>[];
    for (var i = 1; i < baris.length; i++) {
      final kolom = baris[i].split(',').map((k) => k.replaceAll('"', '').trim()).toList();
      if (kolom.length < 2 || kolom[0].isEmpty) continue;
      final kodeAnggota = kolom[0];
      final nominal = double.tryParse(kolom[1]) ?? 0;
      if (nominal <= 0) {
        gagal++;
        continue;
      }
      try {
        final cari = await ApiClient.instance
            .aksi('anggota_list', {'keyword': kodeAnggota, 'page_size': 5});
        final list = ((cari['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final match = list.where((m) => '${m['kode']}' == kodeAnggota).toList();
        if (match.isEmpty) {
          gagal++;
          pesanGagal.add('Baris ${i + 1}: kode "$kodeAnggota" tidak ditemukan.');
          continue;
        }
        await ApiClient.instance.aksi('topup_saldo', {
          'id_member': match.first['id'],
          'nominal': nominal,
          'keterangan': kolom.length > 3 ? kolom[3] : '',
          if (kolom.length > 2 && kolom[2].isNotEmpty) 'waktu': kolom[2],
        });
        berhasil++;
      } catch (e) {
        gagal++;
        pesanGagal.add('Baris ${i + 1}: $e');
      }
    }
    setStateIfMounted(() => _mengunggah = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload selesai: $berhasil berhasil, $gagal gagal.'
              '${pesanGagal.isNotEmpty ? ' ${pesanGagal.take(3).join(' ')}' : ''}')));
    }
    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
          ]),
        ),
      );
    }
    final totalMasuk = _data.fold<double>(0, (s, r) => s + ((r['masuk'] as num?)?.toDouble() ?? 0));
    final totalKeluar = _data.fold<double>(0, (s, r) => s + ((r['keluar'] as num?)?.toDouble() ?? 0));

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pilihRentangTanggal,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                    '${DateFormat('dd/MM/yy').format(_dari)} - ${DateFormat('dd/MM/yy').format(_sampai)}'),
              ),
              OutlinedButton.icon(
                onPressed: _pilihAnggotaFilter,
                icon: const Icon(Icons.person_search, size: 18),
                label: Text(_namaAnggotaFilter ?? 'Semua Anggota'),
              ),
              if (_idAnggotaFilter != null)
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _hapusFilterAnggota),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _unduhCsv,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Download'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success, foregroundColor: Colors.white),
              ),
              if (Sesi.instance.bolehEntryTopup)
                ElevatedButton.icon(
                  onPressed: _mengunggah ? null : _unggahCsv,
                  icon: _mengunggah
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning, foregroundColor: Colors.white),
                ),
              ElevatedButton.icon(
                onPressed: _cetakPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Cetak PDF'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _KartuTotal(
                    label: 'Total Masuk',
                    nilai: _formatRpMutasiTabungan.format(totalMasuk),
                    warna: AppColors.success)),
            const SizedBox(width: 8),
            Expanded(
                child: _KartuTotal(
                    label: 'Total Keluar',
                    nilai: _formatRpMutasiTabungan.format(totalKeluar),
                    warna: AppColors.danger)),
          ]),
          const SizedBox(height: 12),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Tidak ada mutasi pada rentang ini.',
            columns: const [
              AppTableColumn('Nama', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Jenis', flex: 2),
              AppTableColumn('Masuk', flex: 1, align: TextAlign.right),
              AppTableColumn('Keluar', flex: 1, align: TextAlign.right),
              AppTableColumn('Saldo', flex: 1, align: TextAlign.right),
            ],
            rows: _dataHalaman.map((r) {
              final waktu = DateTime.tryParse('${r['waktu']}');
              return AppTableRowData(cells: [
                AppTableCell.text('${r['namaAnggota'] ?? '-'}', flex: 2),
                AppTableCell.text(
                    waktu == null ? '${r['waktu']}' : _formatTglMutasiTabungan.format(waktu),
                    flex: 2),
                AppTableCell.text('${r['jenisMutasi'] ?? ''}', flex: 2),
                AppTableCell.text(
                    ((r['masuk'] as num?) ?? 0) > 0
                        ? _formatRpMutasiTabungan.format(r['masuk'])
                        : '-',
                    flex: 1,
                    align: TextAlign.right),
                AppTableCell.text(
                    ((r['keluar'] as num?) ?? 0) > 0
                        ? _formatRpMutasiTabungan.format(r['keluar'])
                        : '-',
                    flex: 1,
                    align: TextAlign.right),
                AppTableCell.text(_formatRpMutasiTabungan.format(r['saldoPerPenabung'] ?? 0),
                    flex: 1, align: TextAlign.right),
              ]);
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _data.length,
              labelData: 'mutasi',
              onSebelumnya:
                  _halaman > 1 ? () => setStateIfMounted(() => _halaman--) : null,
              onBerikutnya: _halaman < _totalHalaman
                  ? () => setStateIfMounted(() => _halaman++)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _KartuTotal extends StatelessWidget {
  final String label;
  final String nilai;
  final Color warna;
  const _KartuTotal({required this.label, required this.nilai, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warna.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warna.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: warna, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(nilai, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: warna)),
      ]),
    );
  }
}

/// Sheet pencarian anggota (dipakai filter ledger DAN form Bayar Hutang) --
/// debounce 400ms, mirip pola `_cariAnggota` di `tab_topup.dart`.
class PilihAnggotaSheet extends StatefulWidget {
  const PilihAnggotaSheet();

  @override
  State<PilihAnggotaSheet> createState() => PilihAnggotaSheetState();
}

class PilihAnggotaSheetState extends State<PilihAnggotaSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _hasil = [];
  bool _mencari = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _cari(String kata) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (kata.trim().length < 2) {
        setStateIfMounted(() => _hasil = []);
        return;
      }
      setStateIfMounted(() => _mencari = true);
      try {
        final res = await ApiClient.instance
            .aksi('anggota_list', {'keyword': kata.trim(), 'page_size': 20});
        final data = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        if (mounted) setStateIfMounted(() => _hasil = data);
      } finally {
        if (mounted) setStateIfMounted(() => _mencari = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('Pilih Anggota', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              onChanged: _cari,
              decoration: const InputDecoration(
                hintText: 'Ketik kode/nama anggota...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_mencari) const LinearProgressIndicator(),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _hasil.length,
                itemBuilder: (context, i) {
                  final m = _hasil[i];
                  return ListTile(
                    title: Text('${m['nama'] ?? ''}'),
                    subtitle: Text('${m['kode'] ?? ''}'),
                    onTap: () => Navigator.of(context).pop(m),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
