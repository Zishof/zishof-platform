import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';
import 'proses_stok_opname_dialog.dart';

/// Tab **Riwayat Entry SO Grand** — Pemantauan Progres Kertas Kerja Stok Opname (KKSO) per Rak.
///
/// Menjawab kebutuhan operasional toko agar pengawas & tim gudang dapat memantau secara utuh:
/// 1. Rak mana saja yang **Belum Entry** (`0%`).
/// 2. Rak mana yang **Sedang Entry** (sebagian produk pada rak sudah diinput fisik).
/// 3. Rak mana yang **Sudah Semua Di-entry** (`100%` produk pada rak telah terisi fisik).
/// 4. Rak mana yang sedang dalam tahap **Proses SO** (perbandingan selisih & cetak daftar selisih).
/// 5. Rak mana yang sudah **Finish / Disetujui** (Adjustment stok selesai & terkunci permanen).
///
/// Dari tab ini pengguna dapat langsung menekan **"Entry Rak"** untuk melompat ke tab `SO Grand`
/// pada Rak terkait, atau menekan **"Proses & Adjustment"** untuk membuka [ProsesStokOpnameDialog].
class TabRiwayatSoGrand extends StatefulWidget {
  final void Function(int? rakId, String rakNama)? onPilihRakUntukEntry;

  const TabRiwayatSoGrand({
    super.key,
    this.onPilihRakUntukEntry,
  });

  @override
  State<TabRiwayatSoGrand> createState() => _TabRiwayatSoGrandState();
}

class _TabRiwayatSoGrandState extends State<TabRiwayatSoGrand> {
  final _formatAngka = NumberFormat('#,##0.##', 'id_ID');
  final TextEditingController _cariCtrl = TextEditingController();

  DateTime _tanggalOpname = DateTime.now();
  bool _memuat = true;
  String? _pesanError;
  String _filterStatus = 'SEMUA';

  Map<String, dynamic> _ringkasan = {};
  List<Map<String, dynamic>> _daftarRak = [];

  String get _tanggalTeks => DateFormat('yyyy-MM-dd').format(_tanggalOpname);

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final pilihan = await showDatePicker(
      context: context,
      initialDate: _tanggalOpname,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Pilih Tanggal Pemantauan KKSO per Rak',
    );
    if (pilihan == null || !mounted) return;
    setStateIfMounted(() => _tanggalOpname = pilihan);
    await _muatData();
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final res = await ApiClient.instance.aksi('so_grand_riwayat_rak', {
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        'tanggal_opname': _tanggalTeks,
      });
      final ringkasan = res['ringkasan'] is Map
          ? Map<String, dynamic>.from(res['ringkasan'] as Map)
          : <String, dynamic>{};
      final list = ((res['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setStateIfMounted(() {
        _ringkasan = ringkasan;
        _daftarRak = list;
      });
    } catch (e) {
      if (mounted) {
        setStateIfMounted(() => _pesanError = 'Gagal memuat riwayat KKSO per Rak: $e');
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Color _warnaStatusRak(String status) {
    switch (status.toUpperCase()) {
      case 'FINISH_DISETUJUI':
        return AppColors.success;
      case 'PROSES_SO':
        return AppColors.info;
      case 'SUDAH_SEMUA_ENTRY':
        return const Color(0xFF0D9488);
      case 'SEDANG_ENTRY':
        return AppColors.warning;
      default:
        return Colors.grey.shade600;
    }
  }

  List<Map<String, dynamic>> get _filteredRak {
    final kw = _cariCtrl.text.trim().toLowerCase();
    return _daftarRak.where((r) {
      final st = '${r['statusRak'] ?? 'BELUM_ENTRY'}'.toUpperCase();
      if (_filterStatus != 'SEMUA' && st != _filterStatus) {
        return false;
      }
      if (kw.isEmpty) return true;
      final nama = '${r['rakNama'] ?? ''}'.toLowerCase();
      final kode = '${r['rakKode'] ?? ''}'.toLowerCase();
      final dok = '${r['kodeDokumen'] ?? ''}'.toLowerCase();
      final petugas = '${r['petugas'] ?? ''}'.toLowerCase();
      return nama.contains(kw) ||
          kode.contains(kw) ||
          dok.contains(kw) ||
          petugas.contains(kw);
    }).toList();
  }

  Widget _kartuKpi(
      String label, int nilai, Color warna, IconData ikon, String filterKey) {
    final aktif = _filterStatus == filterKey;
    return SizedBox(
      width: 176,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setStateIfMounted(() {
          _filterStatus = _filterStatus == filterKey ? 'SEMUA' : filterKey;
        }),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: warna.withValues(alpha: aktif ? 0.18 : 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: aktif ? warna : warna.withValues(alpha: 0.3),
              width: aktif ? 1.8 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(ikon, size: 17, color: warna),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$nilai Rak',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: warna),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tampil = _filteredRak;
    final totalRak = (_ringkasan['totalRak'] as num?)?.toInt() ?? _daftarRak.length;
    final belumEntry = (_ringkasan['belumEntry'] as num?)?.toInt() ?? 0;
    final sedangEntry = (_ringkasan['sedangEntry'] as num?)?.toInt() ?? 0;
    final sudahSemua = (_ringkasan['sudahSemuaEntry'] as num?)?.toInt() ?? 0;
    final prosesSo = (_ringkasan['prosesSo'] as num?)?.toInt() ?? 0;
    final finish = (_ringkasan['finishDisetujui'] as num?)?.toInt() ?? 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // BARIS ATAS: TANGGAL OPNAME, PENCARIAN, DAFTAR DOKUMEN & MUAT ULANG
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _pilihTanggal,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(
                  'Tanggal KKSO: ${DateFormat('dd MMM yyyy', 'id_ID').format(_tanggalOpname)}'),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _cariCtrl,
                decoration: InputDecoration(
                  hintText: 'Cari nama rak / kode dokumen / petugas...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => setStateIfMounted(() {}),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final berubah = await DaftarDokumenOpnameSheet.buka(
                  context,
                  filterJenisSo: 'SO_GRAND',
                );
                if (berubah) await _muatData();
              },
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: const Text('Semua Dokumen & Berita Acara SO Grand'),
            ),
            IconButton(
              tooltip: 'Muat Ulang Status Rak',
              onPressed: _memuat ? null : _muatData,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // BANNER PENJELASAN MONITORING PER RAK
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.latarLembut(AppColors.info),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Pemantauan Riwayat Entry SO Grand menampilkan progres pengisian fisik tiap Rak KKSO secara menyeluruh: '
            'mulai dari Rak yang Belum Entry, Sedang Entry, Sudah Semua Di-entry, Proses SO (bandingkan selisih & cetak daftar selisih), '
            'hingga Finish / Disetujui (Adjustment stok selesai & terkunci permanen). Klik kartu status di bawah untuk menyaring daftar Rak.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),

        // KARTU KPI FILTERABLE PER STATUS RAK
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _kartuKpi('Total Rak KKSO', totalRak, AppColors.primary,
                Icons.shelves, 'SEMUA'),
            _kartuKpi('Belum Entry', belumEntry, Colors.grey.shade700,
                Icons.hourglass_empty, 'BELUM_ENTRY'),
            _kartuKpi('Sedang Entry', sedangEntry, AppColors.warning,
                Icons.edit_note, 'SEDANG_ENTRY'),
            _kartuKpi('Sudah Semua Di-entry', sudahSemua,
                const Color(0xFF0D9488), Icons.playlist_add_check, 'SUDAH_SEMUA_ENTRY'),
            _kartuKpi('Proses SO (Selisih)', prosesSo, AppColors.info,
                Icons.compare_arrows, 'PROSES_SO'),
            _kartuKpi('Finish / Disetujui', finish, AppColors.success,
                Icons.verified, 'FINISH_DISETUJUI'),
          ],
        ),
        const SizedBox(height: 14),

        if (_pesanError != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.danger),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_pesanError!,
                style: const TextStyle(color: AppColors.danger)),
          ),

        if (_memuat)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!_memuat && tampil.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
                child: Text('Tidak ada Rak yang sesuai dengan filter saat ini.')),
          ),

        if (!_memuat && tampil.isNotEmpty)
          AppDataTable(
            minWidth: 1180,
            emptyText: 'Belum ada data Rak.',
            columns: const [
              AppTableColumn('Rak KKSO', flex: 3),
              AppTableColumn('Progres Entry Barang', flex: 3),
              AppTableColumn('Status Tahapan Rak', flex: 2),
              AppTableColumn('Dokumen / Berita Acara', flex: 2),
              AppTableColumn('Petugas & Waktu Update', flex: 2),
              AppTableColumn('Aksi Cepat', flex: 3),
            ],
            rows: tampil.map((r) {
              final rakIdRaw = (r['rakId'] as num?)?.toInt() ?? 0;
              final rakNama = '${r['rakNama'] ?? 'Rak Belum Ditentukan'}';
              final totalProduk = (r['totalProduk'] as num?)?.toInt() ?? 0;
              final sudahEntry = (r['jumlahSudahEntry'] as num?)?.toInt() ?? 0;
              final belum = (r['jumlahBelumEntry'] as num?)?.toInt() ?? 0;
              final persen = (r['persenProgres'] as num?)?.toDouble() ?? 0.0;
              final statusRak = '${r['statusRak'] ?? 'BELUM_ENTRY'}';
              final labelStatus = '${r['labelStatusRak'] ?? statusRak}';
              final warna = _warnaStatusRak(statusRak);
              final dokId = (r['dokumenId'] as num?)?.toInt();
              final kodeDok = '${r['kodeDokumen'] ?? ''}';
              final nomorBa = '${r['nomorBeritaAcara'] ?? ''}';
              final cetakSel = r['sudahCetakSelisih'] == true;
              final cetakBa = r['sudahCetakBeritaAcara'] == true;
              final terkunci = statusRak.toUpperCase() == 'FINISH_DISETUJUI';

              return AppTableRowData(cells: [
                AppTableCell(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        rakNama,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if ('${r['lokasi'] ?? ''}'.trim().isNotEmpty)
                        Text(
                          'Lokasi: ${r['lokasi']}',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                    ],
                  ),
                ),
                AppTableCell(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${_formatAngka.format(sudahEntry)} / ${_formatAngka.format(totalProduk)} produk (${persen.toStringAsFixed(1)}%) · Sisa ${_formatAngka.format(belum)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (persen / 100.0).clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: Colors.grey.shade200,
                          color: warna,
                        ),
                      ),
                    ],
                  ),
                ),
                AppTableCell(
                  flex: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      labelStatus,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: warna,
                      ),
                    ),
                  ),
                ),
                AppTableCell.text(
                  kodeDok.isEmpty
                      ? '-'
                      : '$kodeDok${nomorBa.isEmpty ? '' : '\nBA: $nomorBa'}'
                          '${cetakSel ? '\n✓ Selisih' : ''}${cetakBa ? ' · ✓ BA' : ''}',
                  flex: 2,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 11.5),
                ),
                AppTableCell.text(
                  '${('${r['petugas'] ?? ''}').isEmpty ? '-' : r['petugas']}'
                  '${('${r['waktuUpdateTerakhir'] ?? ''}').isEmpty ? '' : '\n${r['waktuUpdateTerakhir']}'}',
                  flex: 2,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11.5),
                ),
                AppTableCell(
                  flex: 3,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (!terkunci)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            final targetRak = rakIdRaw <= 0 ? -1 : rakIdRaw;
                            widget.onPilihRakUntukEntry
                                ?.call(targetRak, rakNama);
                          },
                          icon: const Icon(Icons.edit_note, size: 16),
                          label: Text(
                              sudahEntry > 0 ? 'Lanjut Entry' : 'Mulai Entry'),
                        ),
                      if (dokId != null && dokId > 0)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                terkunci ? AppColors.info : AppColors.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final berubah = await ProsesStokOpnameDialog.buka(
                              context,
                              dokumenId: dokId,
                            );
                            if (berubah) await _muatData();
                          },
                          icon: Icon(
                            terkunci
                                ? Icons.description_outlined
                                : Icons.fact_check_outlined,
                            size: 15,
                          ),
                          label: Text(terkunci ? 'Berita Acara' : 'Proses SO'),
                        ),
                    ],
                  ),
                ),
              ]);
            }).toList(),
          ),
      ],
    );
  }
}
