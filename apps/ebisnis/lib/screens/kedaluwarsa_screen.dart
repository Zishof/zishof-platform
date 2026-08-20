import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../parse_util.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';

final _formatAngkaKedaluwarsa = NumberFormat.decimalPattern('id_ID');
final _formatTanggalKedaluwarsa = DateFormat('dd/MM/yyyy');

class KedaluwarsaScreen extends StatefulWidget {
  const KedaluwarsaScreen({super.key});

  @override
  State<KedaluwarsaScreen> createState() => _KedaluwarsaScreenState();
}

class _KedaluwarsaScreenState extends State<KedaluwarsaScreen> with JejakGalat {
  static const _pageSize = 15;
  final _cari = TextEditingController();
  bool _memuat = true;
  String? _error;
  String _filter = '90_HARI';
  int _halaman = 1;
  int _total = 0;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _summary = {};

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  final DiffDaftarLokal _diff = DiffDaftarLokal();

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      // Baca LOKAL DULU (lihat MasterOffline.daftarCacheDulu): snapshot
      // cache tampil seketika, hasil server menyusul + diff utk kilau baris.
      await MasterOffline.daftarCacheDulu('kedaluwarsa_list', {
        'filter': _filter,
        'keyword': _cari.text.trim(),
        'page': _halaman,
        'page_size': _pageSize,
      }, 'master:kedaluwarsa:$_filter', onData: (hasil) {
        if (!mounted) return;
        setStateIfMounted(() {
          _data = _diff.terapkan(hasil);
          if (_diff.dariServer) {
            _summary = ((hasil['summary'] as Map?) ?? {}).cast<String, dynamic>();
          }
          _total = _diff.total ?? _data.length;
        });
      });
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  DateTime? _parseTanggal(dynamic nilai) =>
      nilai == null ? null : DateTime.tryParse('$nilai');

  Future<void> _kelolaBatch(Map<String, dynamic>? row) async {
    List<Map<String, dynamic>> daftarProduk = [];
    if (row == null) {
      try {
        final hasil =
            await ApiClient.instance.aksi('produk_batch_produk_list', {
          if (Sesi.instance.tokoId != null) 'toko_id': Sesi.instance.tokoId,
        });
        daftarProduk =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      } catch (e) {
        if (mounted) {
          snackbarGalat(context, e);
        }
        return;
      }
    }
    int? produkId = (row?['produkId'] as num?)?.toInt();
    final batch = TextEditingController(text: '${row?['nomorBatch'] ?? ''}');
    final stok = TextEditingController(text: '${row?['stok'] ?? ''}');
    final catatan = TextEditingController(text: '${row?['keterangan'] ?? ''}');
    DateTime? produksi = _parseTanggal(row?['tanggalProduksi']);
    DateTime? expired = _parseTanggal(row?['tanggalExpired']);
    String status = '${row?['status'] ?? 'AKTIF'}';
    bool menyimpan = false;
    if (!mounted) return;

    Future<DateTime?> pilihTanggal(
            BuildContext dialogContext, DateTime? awal) =>
        showDatePicker(
          context: dialogContext,
          initialDate: awal ?? DateTime.now().add(const Duration(days: 365)),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );

    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (dialogContext) =>
          StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(
              row == null ? 'Tambah Batch' : 'Kelola Batch · ${row['nama']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (row == null) ...[
                  DropdownButtonFormField<int>(
                    value: produkId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Produk *'),
                    items: daftarProduk
                        .map((p) => DropdownMenuItem<int>(
                              value: (p['id'] as num).toInt(),
                              child: Text('${p['kode']} · ${p['nama']}',
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => produkId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                    controller: batch,
                    decoration: const InputDecoration(
                        labelText: 'Nomor Batch / Lot *')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: InkWell(
                    onTap: () async {
                      final t = await pilihTanggal(dialogContext, produksi);
                      if (t != null) setDialogState(() => produksi = t);
                    },
                    child: InputDecorator(
                      decoration:
                          const InputDecoration(labelText: 'Tanggal Produksi'),
                      child: Text(produksi == null
                          ? 'Opsional'
                          : _formatTanggalKedaluwarsa.format(produksi!)),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: InkWell(
                    onTap: () async {
                      final t = await pilihTanggal(dialogContext, expired);
                      if (t != null) setDialogState(() => expired = t);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Tanggal Kedaluwarsa *'),
                      child: Text(expired == null
                          ? 'Pilih tanggal'
                          : _formatTanggalKedaluwarsa.format(expired!)),
                    ),
                  )),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: stok,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration:
                        const InputDecoration(labelText: 'Stok fisik batch *'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: DropdownButtonFormField<String>(
                    value: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                          value: 'AKTIF', child: Text('Aktif / boleh dijual')),
                      DropdownMenuItem(
                          value: 'KARANTINA', child: Text('Karantina')),
                      DropdownMenuItem(
                          value: 'DIMUSNAHKAN', child: Text('Dimusnahkan')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => status = v ?? status),
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: catatan,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Catatan')),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: menyimpan
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Batal')),
            FilledButton.icon(
              onPressed: menyimpan
                  ? null
                  : () async {
                      final jumlah = parseDesimal(stok.text);
                      if (produkId == null ||
                          batch.text.trim().isEmpty ||
                          expired == null ||
                          jumlah == null ||
                          jumlah < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                'Nomor batch, tanggal kedaluwarsa, dan stok fisik wajib valid.')));
                        return;
                      }
                      setDialogState(() => menyimpan = true);
                      try {
                        // Alur "lokal dulu" ber-indikator animasi
                        // (prosesSimpanMaster): antre -> coba kirim -> tutup
                        // dialog (offline pun langsung lanjut).
                        await prosesSimpanMaster(dialogContext,
                            aksi: 'produk_batch_simpan',
                            body: {
                              if (Sesi.instance.tokoId != null)
                                'toko_id': Sesi.instance.tokoId,
                              if (row?['batchId'] != null)
                                'batch_id': row!['batchId'],
                              'produk_id': produkId,
                              'nomor_batch': batch.text.trim(),
                              if (produksi != null)
                                'tanggal_produksi':
                                    DateFormat('yyyy-MM-dd').format(produksi!),
                              'tanggal_expired':
                                  DateFormat('yyyy-MM-dd').format(expired!),
                              'stok_fisik': jumlah,
                              'status': status,
                              'keterangan': catatan.text.trim(),
                            },
                            kunci: row?['batchId'] != null
                                ? 'produk_batch:${row!['batchId']}'
                                : 'produk_batch:baru:${DateTime.now().microsecondsSinceEpoch}');
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          snackbarGalat(context, e);
                        }
                        setDialogState(() => menyimpan = false);
                      }
                    },
              icon: menyimpan
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Simpan'),
            ),
          ],
        );
      }),
    );
    batch.dispose();
    stok.dispose();
    catatan.dispose();
    if (tersimpan == true) await _muat();
  }

  Color _warnaSisa(int? hari) {
    if (hari == null) return AppColors.textSecondaryOf(context);
    if (hari < 0) return AppColors.danger;
    if (hari <= 7) return Colors.deepOrange;
    if (hari <= 30) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 999999);
    return AppShell(
      menuAktif: MenuEBisnis.kedaluwarsa,
      judul: 'Kedaluwarsa',
      subjudul:
          'Kontrol batch, FEFO, karantina, dan barang mendekati kedaluwarsa',
      scrollable: false,
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (Sesi.instance.bolehKelola) ...[
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _kelolaBatch(null),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Batch'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
              height: 96,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                SizedBox(
                    width: 180,
                    child: AppKpiCard(
                        icon: Icons.error_outline,
                        warna: AppColors.danger,
                        nilai: '${_summary['kedaluwarsa'] ?? 0}',
                        label: 'Sudah kedaluwarsa')),
                const SizedBox(width: 8),
                SizedBox(
                    width: 180,
                    child: AppKpiCard(
                        icon: Icons.timer_outlined,
                        warna: AppColors.warning,
                        nilai: '${_summary['dalam30Hari'] ?? 0}',
                        label: '≤ 30 hari')),
                const SizedBox(width: 8),
                SizedBox(
                    width: 180,
                    child: AppKpiCard(
                        icon: Icons.event_outlined,
                        warna: AppColors.primary,
                        nilai: '${_summary['dalam90Hari'] ?? 0}',
                        label: '≤ 90 hari')),
                const SizedBox(width: 8),
                SizedBox(
                    width: 180,
                    child: AppKpiCard(
                        icon: Icons.help_outline,
                        warna: Colors.blueGrey,
                        nilai: '${_summary['tanpaTanggal'] ?? 0}',
                        label: 'Belum didata')),
                const SizedBox(width: 8),
                SizedBox(
                    width: 180,
                    child: AppKpiCard(
                        icon: Icons.block_outlined,
                        warna: Colors.deepOrange,
                        nilai: _formatAngkaKedaluwarsa
                            .format(_summary['stokKarantina'] ?? 0),
                        label: 'Stok karantina')),
              ])),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final sempit = constraints.maxWidth < 650;
            final cari = TextField(
              controller: _cari,
              decoration: AppFormStyle.fieldDecoration(context,
                  labelText: 'Cari produk / kode / batch',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true),
              onSubmitted: (_) {
                _halaman = 1;
                _muat();
              },
            );
            final filter = DropdownButtonFormField<String>(
              value: _filter,
              decoration: AppFormStyle.fieldDecoration(context,
                  labelText: 'Filter', isDense: true),
              items: const [
                DropdownMenuItem(
                    value: 'KADALUWARSA', child: Text('Sudah kedaluwarsa')),
                DropdownMenuItem(value: '7_HARI', child: Text('≤ 7 hari')),
                DropdownMenuItem(value: '30_HARI', child: Text('≤ 30 hari')),
                DropdownMenuItem(value: '90_HARI', child: Text('≤ 90 hari')),
                DropdownMenuItem(value: 'KARANTINA', child: Text('Karantina')),
                DropdownMenuItem(
                    value: 'TANPA_TANGGAL', child: Text('Belum didata')),
                DropdownMenuItem(value: 'SEMUA', child: Text('Semua batch')),
              ],
              onChanged: (v) {
                _filter = v ?? '90_HARI';
                _halaman = 1;
                _muat();
              },
            );
            final refresh = IconButton.filled(
                onPressed: _muat,
                icon: const Icon(Icons.refresh),
                tooltip: 'Muat ulang');
            if (sempit) {
              return Column(children: [
                cari,
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: filter),
                  const SizedBox(width: 8),
                  refresh
                ]),
              ]);
            }
            return Row(children: [
              Expanded(child: cari),
              const SizedBox(width: 10),
              SizedBox(width: 210, child: filter),
              const SizedBox(width: 8),
              refresh,
            ]);
          }),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                      AppDetailGalatOpsional(detail: detailUntuk(_error)),
                    ])))
          else
            AppDataTable(
              minWidth: 980,
              emptyText: 'Tidak ada batch pada filter ini.',
              columns: const [
                AppTableColumn('Produk', flex: 3),
                AppTableColumn('Batch / Lot', flex: 2),
                AppTableColumn('Kedaluwarsa', flex: 2),
                AppTableColumn('Sisa Hari', flex: 1, align: TextAlign.right),
                AppTableColumn('Stok Batch', flex: 1, align: TextAlign.right),
                AppTableColumn('Status', flex: 2),
              ],
              rows: _data.map((r) {
                final exp = _parseTanggal(r['tanggalExpired']);
                final sisa = (r['sisaHari'] as num?)?.toInt();
                final status = r['legacy'] == true
                    ? 'Belum per batch'
                    : '${r['status'] ?? ''}';
                return AppTableRowData(onTap: () => _kelolaBatch(r), cells: [
                  AppTableCell(
                    flex: 3,
                    child: Row(children: [
                      Expanded(
                        child: Text('${r['nama']}\n${r['kode'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                      if (r['batchId'] != null)
                        IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Riwayat batch ini (AuditTrails)',
                            icon: const Icon(Icons.history, size: 16),
                            onPressed: () => tampilkanRiwayatData(context,
                                entitas: 'produk_batch',
                                id: r['batchId'],
                                judul: '${r['nama']}')),
                    ]),
                  ),
                  AppTableCell.text('${r['nomorBatch'] ?? '-'}', flex: 2),
                  AppTableCell.text(
                      exp == null ? '-' : _formatTanggalKedaluwarsa.format(exp),
                      flex: 2),
                  AppTableCell.text(
                      sisa == null
                          ? '-'
                          : (sisa < 0 ? 'Lewat ${-sisa} hari' : '$sisa hari'),
                      flex: 1,
                      align: TextAlign.right,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _warnaSisa(sisa),
                          fontSize: 12)),
                  AppTableCell.text(
                      _formatAngkaKedaluwarsa.format(r['stok'] ?? 0),
                      flex: 1,
                      align: TextAlign.right),
                  AppTableCell.text(status,
                      flex: 2,
                      style: TextStyle(
                          color: status == 'AKTIF'
                              ? AppColors.success
                              : Colors.deepOrange,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ]);
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: totalHalaman,
                totalData: _total,
                labelData: 'batch',
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
          const SizedBox(height: 8),
          Text(
              'Klik baris untuk melengkapi batch, memperbarui stok fisik, atau mengarantina barang.',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondaryOf(context))),
        ]),
      ),
    );
  }
}
