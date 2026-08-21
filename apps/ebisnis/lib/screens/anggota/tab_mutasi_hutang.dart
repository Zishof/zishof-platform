import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../api_client.dart';
import '../../services/diff_daftar_lokal.dart';
import '../../services/master_offline.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../services/simple_xlsx.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/kilau_perubahan.dart';
import '../../widgets/safe_state.dart';
import 'tab_mutasi_tabungan.dart' show PilihAnggotaSheet;
import '../../widgets/jejak_galat.dart';

final _formatRpMutasiHutang =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatTglMutasiHutang = DateFormat('dd MMM yyyy HH:mm', 'id_ID');

/// Tab "Mutasi Hutang" (padanan `_mutasi_hutang.jsp`) -- buku besar DEBIT
/// (belanja pakai cara bayar bertanda `masukSebagaiHutang`, dihitung per
/// slot split-pembayaran) + KREDIT (`koperasi.pembayaran_hutang`, entri
/// manual lewat tombol "Bayar Hutang" di sini) dgn saldo berjalan, aksi
/// server `mutasi_hutang_list` (lihat JavaDoc KantinHelper.mutasiHutangList).
/// Download/Upload/Cetak PDF pola SAMA dgn `AnggotaTabMutasiTabungan` --
/// beda hanya Upload di sini memanggil `hutang_bayar_simpan` (bukan
/// `topup_saldo`).
class AnggotaTabMutasiHutang extends StatefulWidget {
  const AnggotaTabMutasiHutang({super.key});

  @override
  State<AnggotaTabMutasiHutang> createState() => _AnggotaTabMutasiHutangState();
}

class _AnggotaTabMutasiHutangState extends State<AnggotaTabMutasiHutang>
    with JejakGalat {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  static const _pageSize = 15;
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

  /// Diff emisi "lokal dulu" -- menggerakkan animasi kilau baris (termasuk
  /// mutasi yang baru dicatat kasir lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  /// Kunci satu baris utk [KilauBaris]. Daftar mutasi hutang TIDAK punya
  /// kolom 'id'; identitasnya `barisId` (mis. 'H1123' utk slot split-bayar
  /// belanja, 'C45' utk pembayaran hutang). MasterOffline menyusun kunci
  /// diff-nya sebagai `<kolomKunci>=<nilai>` (lihat MasterOffline._kunciDiff)
  /// sehingga format di sini WAJIB sama, kalau tidak kilau tidak pernah cocok.
  String _kunciKilau(Map<String, dynamic> r) => 'barisId=${r['barisId'] ?? ''}';

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Cache dipisah
      // per rentang tanggal DAN filter anggota, sebab kolom saldo berjalan
      // tiap baris hanya sahih untuk kombinasi filter itu.
      await MasterOffline.daftarCacheDulu(
          'mutasi_hutang_list',
          {
            'dari': DateFormat('yyyy-MM-dd').format(_dari),
            'sampai': DateFormat('yyyy-MM-dd').format(_sampai),
            if (_idAnggotaFilter != null) 'id_anggota': _idAnggotaFilter,
          },
          'master:mutasi_hutang:${DateFormat('yyyyMMdd').format(_dari)}-${DateFormat('yyyyMMdd').format(_sampai)}:${_idAnggotaFilter ?? 'semua'}',
          kolomKunci: 'barisId', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          _halaman = 1;
        });
      });
    } catch (e) {
      if (mounted) setStateIfMounted(() => _error = terapkanGalat(e));
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

  List<Map<String, dynamic>> get _rekapPerAnggota {
    final rekap = <String, Map<String, dynamic>>{};
    for (final r in _data) {
      final kunci = '${r['idAnggota'] ?? r['namaAnggota']}';
      final item = rekap.putIfAbsent(
          kunci,
          () => {
                'namaAnggota': r['namaAnggota'],
                'saldoAwal': (r['saldoAwal'] as num?)?.toDouble() ?? 0,
                'bertambah': 0.0,
                'berkurang': 0.0,
              });
      item['bertambah'] = (item['bertambah'] as double) +
          ((r['bertambah'] as num?)?.toDouble() ?? 0);
      item['berkurang'] = (item['berkurang'] as double) +
          ((r['berkurang'] as num?)?.toDouble() ?? 0);
    }
    return rekap.values.map((r) {
      r['saldoAkhir'] = (r['saldoAwal'] as double) +
          (r['bertambah'] as double) -
          (r['berkurang'] as double);
      return r;
    }).toList();
  }

  Future<void> _bukaFormBayarHutang() async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FormBayarHutang(),
    );
    if (tersimpan == true) await _muat();
  }

  Future<void> _unduhExcel() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diunduh.')));
      return;
    }
    final bytes = buildSimpleXlsx(
      sheetName: 'Mutasi Hutang',
      headers: const [
        'NAMA_ANGGOTA',
        'TANGGAL',
        'JENIS_MUTASI',
        'KETERANGAN',
        'HUTANG_BERTAMBAH',
        'PEMBAYARAN',
        'SALDO_HUTANG_ANGGOTA',
        'SALDO_HUTANG_TOTAL',
      ],
      rows: _data
          .map((r) => <Object?>[
                r['namaAnggota'] ?? '',
                r['waktu'] ?? '',
                r['jenisMutasi'] ?? '',
                r['keterangan'] ?? '',
                (r['bertambah'] as num?) ?? 0,
                (r['berkurang'] as num?) ?? 0,
                (r['saldoPerAnggota'] as num?) ?? 0,
                (r['saldoTotal'] as num?) ?? 0,
              ])
          .toList(),
    );
    final nama =
        'Mutasi_Hutang_${DateFormat('yyyyMMdd').format(_dari)}_${DateFormat('yyyyMMdd').format(_sampai)}.xlsx';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan Mutasi Hutang (Excel)',
      fileName: nama,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    if (path != null) await File(path).writeAsBytes(bytes);
  }

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
        header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Mutasi Hutang (Piutang Toko)',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  '${DateFormat('dd/MM/yyyy').format(_dari)} s/d ${DateFormat('dd/MM/yyyy').format(_sampai)}'),
              pw.SizedBox(height: 8),
            ]),
        build: (_) => [
          pw.Table.fromTextArray(
            headers: const [
              'Nama',
              'Tanggal',
              'Jenis',
              'Keterangan',
              'Bertambah',
              'Bayar',
              'Saldo'
            ],
            data: _data
                .map((r) => [
                      '${r['namaAnggota'] ?? ''}',
                      '${r['waktu'] ?? ''}',
                      '${r['jenisMutasi'] ?? ''}',
                      '${r['keterangan'] ?? ''}',
                      _formatRpMutasiHutang.format(r['bertambah'] ?? 0),
                      _formatRpMutasiHutang.format(r['berkurang'] ?? 0),
                      _formatRpMutasiHutang.format(r['saldoPerAnggota'] ?? 0),
                    ])
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle:
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
        onLayout: (_) async => doc.save(), name: 'Mutasi_Hutang.pdf');
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
    int berhasil = 0, gagal = 0, antre = 0;
    final pesanGagal = <String>[];
    for (var i = 1; i < baris.length; i++) {
      final kolom =
          baris[i].split(',').map((k) => k.replaceAll('"', '').trim()).toList();
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
        final list =
            ((cari['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final match = list.where((m) => '${m['kode']}' == kodeAnggota).toList();
        if (match.isEmpty) {
          gagal++;
          pesanGagal
              .add('Baris ${i + 1}: kode "$kodeAnggota" tidak ditemukan.');
          continue;
        }
        final r = await MasterOffline.simpanAtauAntre(
          'hutang_bayar_simpan',
          {
            'id_member': match.first['id'],
            'nominal': nominal,
            'keterangan': kolom.length > 3 ? kolom[3] : '',
            if (kolom.length > 2 && kolom[2].isNotEmpty) 'waktu': kolom[2],
          },
          kunci: 'hutang_bayar:${match.first['id']}:$i',
        );
        // Baris yang baru mengantre dihitung TERSENDIRI. Menghitungnya sebagai
        // berhasil membuat petugas mengira seluruh berkas sudah sampai server.
        if (r['offline'] == true) {
          antre++;
        } else {
          berhasil++;
        }
      } catch (e) {
        gagal++;
        pesanGagal.add('Baris ${i + 1}: $e');
      }
    }
    setStateIfMounted(() => _mengunggah = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload selesai: $berhasil berhasil, '
              '${antre > 0 ? '$antre mengantre, ' : ''}$gagal gagal.'
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
            AppDetailGalatOpsional(detail: detailUntuk(_error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _muat, child: const Text('Coba Lagi')),
          ]),
        ),
      );
    }
    final totalBertambah = _data.fold<double>(
        0, (s, r) => s + ((r['bertambah'] as num?)?.toDouble() ?? 0));
    final totalBerkurang = _data.fold<double>(
        0, (s, r) => s + ((r['berkurang'] as num?)?.toDouble() ?? 0));
    final totalSaldoAwal = _rekapPerAnggota.fold<double>(
        0, (s, r) => s + ((r['saldoAwal'] as num?)?.toDouble() ?? 0));
    final totalSaldoAkhir = _rekapPerAnggota.fold<double>(
        0, (s, r) => s + ((r['saldoAkhir'] as num?)?.toDouble() ?? 0));

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
              if (Sesi.instance.bolehEntryTopup)
                ElevatedButton.icon(
                  onPressed: _bukaFormBayarHutang,
                  icon: const Icon(Icons.money_off_csred_outlined, size: 18),
                  label: const Text('Bayar Hutang'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white),
                ),
              ElevatedButton.icon(
                onPressed: _unduhExcel,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Download Excel'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white),
              ),
              if (Sesi.instance.bolehEntryTopup)
                ElevatedButton.icon(
                  onPressed: _mengunggah ? null : _unggahCsv,
                  icon: _mengunggah
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Upload'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      foregroundColor: Colors.white),
                ),
              ElevatedButton.icon(
                onPressed: _cetakPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Cetak PDF'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textSecondary,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Hutang Bertambah',
                    nilai: _formatRpMutasiHutang.format(totalBertambah),
                    warna: AppColors.danger)),
            const SizedBox(width: 8),
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Total Dibayar',
                    nilai: _formatRpMutasiHutang.format(totalBerkurang),
                    warna: AppColors.success)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Saldo Hutang Awal',
                    nilai: _formatRpMutasiHutang.format(totalSaldoAwal),
                    warna: AppColors.info)),
            const SizedBox(width: 8),
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Saldo Hutang Akhir',
                    nilai: _formatRpMutasiHutang.format(totalSaldoAkhir),
                    warna: AppColors.danger)),
          ]),
          const SizedBox(height: 12),
          const Text('Rekap Hutang per Anggota',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AppDataTable(
            minWidth: 760,
            emptyText: 'Tidak ada rekap hutang pada rentang ini.',
            columns: const [
              AppTableColumn('Anggota', flex: 2),
              AppTableColumn('Saldo Awal', flex: 1, align: TextAlign.right),
              AppTableColumn('Bertambah', flex: 1, align: TextAlign.right),
              AppTableColumn('Dibayar', flex: 1, align: TextAlign.right),
              AppTableColumn('Saldo Akhir', flex: 1, align: TextAlign.right),
            ],
            rows: _rekapPerAnggota
                .map((r) => AppTableRowData(cells: [
                      AppTableCell.text('${r['namaAnggota'] ?? '-'}', flex: 2),
                      AppTableCell.text(
                          _formatRpMutasiHutang.format(r['saldoAwal']),
                          flex: 1,
                          align: TextAlign.right),
                      AppTableCell.text(
                          _formatRpMutasiHutang.format(r['bertambah']),
                          flex: 1,
                          align: TextAlign.right),
                      AppTableCell.text(
                          _formatRpMutasiHutang.format(r['berkurang']),
                          flex: 1,
                          align: TextAlign.right),
                      AppTableCell.text(
                          _formatRpMutasiHutang.format(r['saldoAkhir']),
                          flex: 1,
                          align: TextAlign.right),
                    ]))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text('Rincian Mutasi & Sisa Hutang',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AppDataTable(
            minWidth: 900,
            emptyText: 'Tidak ada mutasi hutang pada rentang ini.',
            columns: const [
              AppTableColumn('Nama', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Jenis', flex: 2),
              AppTableColumn('Bertambah', flex: 1, align: TextAlign.right),
              AppTableColumn('Bayar', flex: 1, align: TextAlign.right),
              AppTableColumn('Sisa Hutang', flex: 1, align: TextAlign.right),
            ],
            rows: _dataHalaman.map((r) {
              final waktu = DateTime.tryParse('${r['waktu']}');
              return AppTableRowData(cells: [
                AppTableCell(
                  flex: 2,
                  child: KilauBaris(
                    kunci: _kunciKilau(r),
                    idBaru: _diff.idBaru,
                    idBerubah: _diff.idBerubah,
                    child: Text('${r['namaAnggota'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                AppTableCell.text(
                    waktu == null
                        ? '${r['waktu']}'
                        : _formatTglMutasiHutang.format(waktu),
                    flex: 2),
                AppTableCell.text('${r['jenisMutasi'] ?? ''}', flex: 2),
                AppTableCell.text(
                    ((r['bertambah'] as num?) ?? 0) > 0
                        ? _formatRpMutasiHutang.format(r['bertambah'])
                        : '-',
                    flex: 1,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.danger)),
                AppTableCell.text(
                    ((r['berkurang'] as num?) ?? 0) > 0
                        ? _formatRpMutasiHutang.format(r['berkurang'])
                        : '-',
                    flex: 1,
                    align: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.success)),
                AppTableCell.text(
                    _formatRpMutasiHutang.format(r['saldoPerAnggota'] ?? 0),
                    flex: 1,
                    align: TextAlign.right),
              ]);
            }).toList(),
            pagination: AppTablePagination(
              halaman: _halaman,
              totalHalaman: _totalHalaman,
              totalData: _data.length,
              labelData: 'mutasi',
              onSebelumnya: _halaman > 1
                  ? () => setStateIfMounted(() => _halaman--)
                  : null,
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

class _KartuTotalHutang extends StatelessWidget {
  final String label;
  final String nilai;
  final Color warna;
  const _KartuTotalHutang(
      {required this.label, required this.nilai, required this.warna});

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
        Text(label,
            style: TextStyle(
                fontSize: 11, color: warna, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(nilai,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: warna)),
      ]),
    );
  }
}

class _FormBayarHutang extends StatefulWidget {
  const _FormBayarHutang();

  @override
  State<_FormBayarHutang> createState() => _FormBayarHutangState();
}

class _FormBayarHutangState extends State<_FormBayarHutang> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  final _nominal = TextEditingController();
  final _keterangan = TextEditingController();
  int? _idAnggota;
  String? _namaAnggota;
  DateTime _waktu = DateTime.now();
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void dispose() {
    _nominal.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _pilihAnggota() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PilihAnggotaSheet(),
    );
    if (dipilih == null) return;
    setStateIfMounted(() {
      _idAnggota = dipilih['id'] as int;
      _namaAnggota = '${dipilih['nama']}';
    });
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idAnggota == null) {
      setStateIfMounted(() => _pesanError = 'Anggota wajib dipilih.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      // LOKAL DULU: pembayaran ditulis ke antrean sebelum menyentuh jaringan, lalu
      // dikirim. Tanpa cacheKey: kunci cache daftar mutasi bergantung penyaring
      // tanggal milik layar INDUK, sehingga menebaknya dari lembar ini justru
      // berisiko menulis ke cache yang salah. Barisnya muncul setelah tersinkron.
      await prosesSimpanMaster(
        context,
        aksi: 'hutang_bayar_simpan',
        body: {
          'id_member': _idAnggota,
          'nominal': double.tryParse(_nominal.text.trim()) ?? 0,
          'keterangan': _keterangan.text.trim(),
          'waktu': DateFormat('yyyy-MM-dd HH:mm:ss').format(_waktu),
        },
        kunci: 'hutang_bayar:baru:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: 'Entri Pembayaran Hutang',
            subtitle: 'Catat pelunasan/cicilan hutang anggota.',
            icon: Icons.money_off_csred_outlined,
            errorText: _pesanError,
            errorDetail: detailUntuk(_pesanError),
            children: [
              AppFormSection(judul: 'Anggota', children: [
                OutlinedButton.icon(
                  onPressed: _pilihAnggota,
                  icon: const Icon(Icons.person_search, size: 18),
                  label: Text(_namaAnggota ?? 'Pilih Anggota...'),
                ),
              ]),
              AppFormSection(judul: 'Pembayaran', children: [
                AppFormTextField(
                  label: 'Nominal *',
                  controller: _nominal,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) => (v == null ||
                          double.tryParse(v.trim()) == null ||
                          double.parse(v.trim()) <= 0)
                      ? 'Nominal wajib diisi'
                      : null,
                ),
                AppFormTextField(
                    label: 'Keterangan', controller: _keterangan, maxLines: 2),
              ]),
            ],
            actions: [
              OutlinedButton.icon(
                onPressed:
                    _menyimpan ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
