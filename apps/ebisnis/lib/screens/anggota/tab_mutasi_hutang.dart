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

/// Tab "Mutasi Piutang" (nama backend legacy: mutasi_hutang) -- buku besar
/// piutang dari sudut pandang toko: DEBIT
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

  Future<void> _bukaDetailPiutang(Map<String, dynamic> baris) async {
    final transaksiId = (baris['transaksiId'] as num?)?.toInt();
    if (transaksiId == null) {
      await showDialog<void>(
        context: context,
        builder: (_) => _DialogDetailPelunasan(baris: baris),
      );
      return;
    }
    final slot = ((baris['slotPiutang'] as num?)?.toInt() ?? 1).clamp(1, 5);
    final detail = ApiClient.instance.aksi('mutasi_piutang_detail', {
      'transaksi_id': transaksiId,
      'slot': slot,
      if (baris['idAnggota'] != null) 'id_anggota': baris['idAnggota'],
    });
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogDetailPiutang(detail: detail),
    );
  }

  /// Hapus satu entri PEMBAYARAN hutang.
  ///
  /// Hanya baris pembayaran yang boleh dihapus. Daftar mutasi mencampur dua sumber,
  /// dan `barisId` membedakannya: awalan `C` = koperasi.pembayaran_hutang (id-nya
  /// mengikuti), awalan `H<slot>` = pembelian anggota yang menambah hutang. Menghapus
  /// baris `H` berarti membatalkan pembeliannya -- bukan urusan layar ini.
  ///
  /// Pembayaran hutang TIDAK menjurnal (tidak ada mesin posting yang merujuk
  /// PembayaranHutang), jadi menghapusnya tidak meninggalkan jurnal yatim.
  Future<void> _hapusPembayaran(Map<String, dynamic> baris) async {
    final kode = '${baris['barisId'] ?? ''}';
    final id = int.tryParse(kode.startsWith('C') ? kode.substring(1) : '');
    if (id == null) return;
    final ya = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pelunasan piutang?'),
        content: Text(
            'Pelunasan ${_formatRpMutasiHutang.format(baris['berkurang'] ?? 0)} '
            'atas nama ${baris['namaAnggota'] ?? '-'} akan dihapus. '
            'Sisa piutang pelanggan akan naik kembali sebesar itu.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'hutang_bayar_hapus',
        body: {'id': id},
        kunci: 'hutang_bayar:hapus:$id',
      );
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(terapkanGalat(e))));
      }
    }
  }

  Future<void> _unduhExcel() async {
    if (_data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada data untuk diunduh.')));
      return;
    }
    final bytes = buildSimpleXlsx(
      sheetName: 'Mutasi Piutang',
      headers: const [
        'NAMA_ANGGOTA',
        'TANGGAL',
        'JENIS_MUTASI',
        'KETERANGAN',
        'PIUTANG_BERTAMBAH',
        'PELUNASAN',
        'SALDO_PIUTANG_ANGGOTA',
        'SALDO_PIUTANG_TOTAL',
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
        'Mutasi_Piutang_${DateFormat('yyyyMMdd').format(_dari)}_${DateFormat('yyyyMMdd').format(_sampai)}.xlsx';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan Mutasi Piutang (Excel)',
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
              pw.Text('Mutasi Piutang Pelanggan',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  '${DateFormat('dd/MM/yyyy').format(_dari)} s/d ${DateFormat('dd/MM/yyyy').format(_sampai)}'),
              pw.SizedBox(height: 8),
            ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
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
        onLayout: (_) async => doc.save(), name: 'Mutasi_Piutang.pdf');
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
                label: Text(_namaAnggotaFilter ?? 'Semua Pelanggan'),
              ),
              if (_idAnggotaFilter != null)
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _hapusFilterAnggota),
              if (Sesi.instance.bolehEntryPelunasanPiutang)
                ElevatedButton.icon(
                  onPressed: _bukaFormBayarHutang,
                  icon: const Icon(Icons.money_off_csred_outlined, size: 18),
                  label: const Text('Entri Pelunasan Piutang'),
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
              if (Sesi.instance.bolehEntryPelunasanPiutang)
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
                    label: 'Piutang Bertambah',
                    nilai: _formatRpMutasiHutang.format(totalBertambah),
                    warna: AppColors.danger)),
            const SizedBox(width: 8),
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Total Pelunasan',
                    nilai: _formatRpMutasiHutang.format(totalBerkurang),
                    warna: AppColors.success)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Saldo Piutang Awal',
                    nilai: _formatRpMutasiHutang.format(totalSaldoAwal),
                    warna: AppColors.info)),
            const SizedBox(width: 8),
            Expanded(
                child: _KartuTotalHutang(
                    label: 'Saldo Piutang Akhir',
                    nilai: _formatRpMutasiHutang.format(totalSaldoAkhir),
                    warna: AppColors.danger)),
          ]),
          const SizedBox(height: 12),
          const Text('Rekap Piutang per Pelanggan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AppDataTable(
            minWidth: 760,
            emptyText: 'Tidak ada rekap piutang pada rentang ini.',
            columns: const [
              AppTableColumn('Pelanggan', flex: 2),
              AppTableColumn('Saldo Awal', flex: 1, align: TextAlign.right),
              AppTableColumn('Bertambah', flex: 1, align: TextAlign.right),
              AppTableColumn('Pelunasan', flex: 1, align: TextAlign.right),
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
          const Text('Rincian Mutasi & Sisa Piutang',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          AppDataTable(
            minWidth: 1120,
            emptyText: 'Tidak ada mutasi piutang pada rentang ini.',
            columns: const [
              AppTableColumn('Nama', flex: 2),
              AppTableColumn('Tanggal', flex: 2),
              AppTableColumn('Jenis', flex: 2),
              AppTableColumn('Bertambah', flex: 1, align: TextAlign.right),
              AppTableColumn('Pelunasan', flex: 1, align: TextAlign.right),
              AppTableColumn('Sisa Piutang', flex: 1, align: TextAlign.right),
              AppTableColumn('Aksi', flex: 2, align: TextAlign.center),
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
                AppTableCell(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => _bukaDetailPiutang(r),
                        icon: const Icon(Icons.visibility_outlined, size: 17),
                        label: const Text('Lihat Detail'),
                      ),
                      if ('${r['barisId'] ?? ''}'.startsWith('C') &&
                          Sesi.instance.bolehEntryPelunasanPiutang)
                        IconButton(
                          tooltip: 'Hapus pembayaran',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _hapusPembayaran(r),
                        ),
                    ],
                  ),
                ),
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
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: warna.withValues(alpha: 0.3)),
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
  final DateTime _waktu = DateTime.now();
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
            title: 'Entri Pelunasan Piutang',
            subtitle: 'Catat cicilan atau pelunasan piutang pelanggan.',
            icon: Icons.money_off_csred_outlined,
            errorText: _pesanError,
            errorDetail: detailUntuk(_pesanError),
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
            children: [
              AppFormSection(judul: 'Pelanggan', children: [
                OutlinedButton.icon(
                  onPressed: _pilihAnggota,
                  icon: const Icon(Icons.person_search, size: 18),
                  label: Text(_namaAnggota ?? 'Pilih Pelanggan...'),
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
          ),
        ),
      ),
    );
  }
}

class _DialogDetailPelunasan extends StatelessWidget {
  final Map<String, dynamic> baris;

  const _DialogDetailPelunasan({required this.baris});

  @override
  Widget build(BuildContext context) {
    final waktu = DateTime.tryParse('${baris['waktu'] ?? ''}');
    return AlertDialog(
      title: const Text('Detail Pelunasan Piutang'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailPiutangBaris(
                label: 'Pelanggan', nilai: '${baris['namaAnggota'] ?? '-'}'),
            _DetailPiutangBaris(
              label: 'Tanggal',
              nilai: waktu == null
                  ? '${baris['waktu'] ?? '-'}'
                  : _formatTglMutasiHutang.format(waktu),
            ),
            _DetailPiutangBaris(
              label: 'Nominal pelunasan',
              nilai: _formatRpMutasiHutang.format(baris['berkurang'] ?? 0),
            ),
            _DetailPiutangBaris(
                label: 'Keterangan', nilai: '${baris['keterangan'] ?? '-'}'),
            const SizedBox(height: 10),
            Text(
              'Pelunasan ini mengurangi saldo piutang pelanggan secara umum dan tidak dialokasikan ke satu nota tertentu.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondaryOf(context)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}

class _DialogDetailPiutang extends StatelessWidget {
  final Future<Map<String, dynamic>> detail;

  const _DialogDetailPiutang({required this.detail});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detail Piutang Pembelian'),
      content: SizedBox(
        width: 680,
        child: FutureBuilder<Map<String, dynamic>>(
          future: detail,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Text('${snapshot.error}', textAlign: TextAlign.center),
                ),
              );
            }
            final data = snapshot.data ?? const <String, dynamic>{};
            final item = ((data['item'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailPiutangBaris(
                        label: 'Nomor nota', nilai: '${data['nomor'] ?? '-'}'),
                    _DetailPiutangBaris(
                        label: 'Tanggal', nilai: '${data['waktu'] ?? '-'}'),
                    _DetailPiutangBaris(
                      label: 'Pelanggan',
                      nilai:
                          '${data['kodeAnggota'] ?? ''} - ${data['namaAnggota'] ?? '-'}',
                    ),
                    _DetailPiutangBaris(
                      label: 'Metode piutang',
                      nilai: '${data['metodePembayaran'] ?? '-'}',
                    ),
                    _DetailPiutangBaris(
                      label: 'Nilai piutang',
                      nilai: _formatRpMutasiHutang
                          .format(data['nominalPiutang'] ?? 0),
                    ),
                    _DetailPiutangBaris(
                      label: 'Total transaksi',
                      nilai: _formatRpMutasiHutang
                          .format(data['totalTransaksi'] ?? 0),
                    ),
                    const Divider(height: 24),
                    const Text('Barang yang dibeli',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    if (item.isEmpty)
                      const Text('Tidak ada rincian barang pada transaksi ini.')
                    else
                      ...item.map((produk) {
                        final qty = (produk['qty'] as num?)?.toDouble() ?? 0;
                        final harga =
                            (produk['harga'] as num?)?.toDouble() ?? 0;
                        final diskon =
                            (produk['diskon'] as num?)?.toDouble() ?? 0;
                        final subtotal =
                            (produk['subtotal'] as num?)?.toDouble() ??
                                ((qty * harga) - diskon);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text('${produk['nama'] ?? 'Produk'}'),
                          subtitle: Text(
                            '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} × ${_formatRpMutasiHutang.format(harga)}'
                            '${diskon > 0 ? ' · diskon ${_formatRpMutasiHutang.format(diskon)}' : ''}',
                          ),
                          trailing: Text(_formatRpMutasiHutang.format(subtotal),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        );
                      }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup')),
      ],
    );
  }
}

class _DetailPiutangBaris extends StatelessWidget {
  final String label;
  final String nilai;

  const _DetailPiutangBaris({required this.label, required this.nilai});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(color: AppColors.textSecondaryOf(context))),
          ),
          Expanded(child: Text(nilai)),
        ],
      ),
    );
  }
}
