import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/app_shell.dart';
import 'pos_help.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _fmtTgl = DateFormat('yyyy-MM-dd');

/// <h3>Laporan Apotik -- FASE C (penjualan, obat terkendali, kedaluwarsa).</h3>
///
/// Tiga tab di atas aksi server read-only: `apotik_laporan_penjualan`,
/// `apotik_laporan_terkendali`, `apotik_laporan_kedaluwarsa`. Sumber datanya
/// jejak yang sudah ditulis kasir/persediaan (ledger AJ, register narkotika,
/// batch) -- tidak ada tabel laporan baru.
class LaporanApotikScreen extends StatefulWidget {
  final int tabAwal;
  const LaporanApotikScreen({super.key, this.tabAwal = 0});

  @override
  State<LaporanApotikScreen> createState() => _LaporanApotikScreenState();
}

class _LaporanApotikScreenState extends State<LaporanApotikScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 3, vsync: this, initialIndex: widget.tabAwal.clamp(0, 2));
    _tab.addListener(_ubahTab);
  }

  void _ubahTab() {
    if (!_tab.indexIsChanging && mounted) setState(() {});
  }

  @override
  void dispose() {
    _tab.removeListener(_ubahTab);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bantuan = const [
      'apotik_laporan',
      'apotik_narkotika',
      'apotik_laporan'
    ][_tab.index];
    return AppShell(
      menuAktif: MenuEBisnis.laporanApotik,
      judul: 'Laporan Apotik',
      subjudul: 'Penjualan, register obat terkendali, dan risiko kedaluwarsa',
      scrollable: false,
      actionsAppBar: [PosHelp.button(context, bantuan, compact: true)],
      aksiHeader: PosHelp.button(context, bantuan),
      body: Column(
        children: [
          Material(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(10),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Penjualan'),
                Tab(text: 'Obat Terkendali'),
                Tab(text: 'Kedaluwarsa'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                _TabPenjualan(),
                _TabTerkendali(),
                _TabKedaluwarsa(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris filter periode bersama (dari/sampai) -- default 30 hari terakhir.
class _FilterPeriode extends StatelessWidget {
  final DateTime dari;
  final DateTime sampai;
  final ValueChanged<DateTime> onDari;
  final ValueChanged<DateTime> onSampai;
  final VoidCallback onMuat;
  const _FilterPeriode(
      {required this.dari,
      required this.sampai,
      required this.onDari,
      required this.onSampai,
      required this.onMuat});

  Future<void> _pilih(
      BuildContext context, DateTime awal, ValueChanged<DateTime> cb) async {
    final t = await showDatePicker(
        context: context,
        initialDate: awal,
        firstDate: DateTime(2015),
        lastDate: DateTime(2100));
    if (t != null) cb(t);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pilih(context, dari, onDari),
            icon: const Icon(Icons.event, size: 16),
            label: Text('Dari: ${_fmtTgl.format(dari)}',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pilih(context, sampai, onSampai),
            icon: const Icon(Icons.event, size: 16),
            label: Text('Sampai: ${_fmtTgl.format(sampai)}',
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onMuat, child: const Text('Muat')),
      ]),
    );
  }
}

// =============================================================================
// Tab 1 -- Penjualan
// =============================================================================

class _TabPenjualan extends StatefulWidget {
  const _TabPenjualan();

  @override
  State<_TabPenjualan> createState() => _TabPenjualanState();
}

class _TabPenjualanState extends State<_TabPenjualan> {
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  bool _memuat = false;
  Map<String, dynamic>? _data;

  /// Benar selama yang tampil masih salinan lokal (server belum menjawab, atau
  /// gagal karena offline) -- menyalakan PenandaDataTersimpan.
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    // BACA LOKAL DULU (pola MasterOffline.daftarCacheDulu, dihitung MANUAL di
    // sini): `apotik_laporan_penjualan` mengembalikan satu AMPLOP
    // (totalNilai/totalQty + perGolongan + perItem) yang hanya bermakna
    // bersama-sama -- daftarCacheDulu menyimpan SATU daftar saja sehingga emisi
    // lokalnya menyisakan tabel per-item dengan KPI nol yang menyesatkan.
    // Kunci cache memuat SELURUH parameter yang mengubah isi laporan (periode).
    // TANPA kilau baris: baris perItem/perGolongan murni rekap agregat periode,
    // bukan dokumen ber-identitas -- cukup cache-nya saja.
    final kunci = 'laporan:apotik_penjualan:'
        '${_fmtTgl.format(_dari)}_${_fmtTgl.format(_sampai)}';
    var adaCacheLokal = false;
    final tersimpan = await CoreDb.instance.ambilCacheReferensi(kunci);
    if (tersimpan != null) {
      try {
        final lokal = jsonDecode(tersimpan) as Map<String, dynamic>;
        adaCacheLokal = true;
        final stempel = DateTime.tryParse('${lokal['_disimpanPada'] ?? ''}');
        setStateIfMounted(() {
          _data = lokal;
          _dariCache = true;
          _cacheDisimpanPada = stempel;
          _memuat = false;
        });
      } catch (_) {
        adaCacheLokal = false; // cache rusak -- lanjut jalur server biasa.
      }
    }
    try {
      final r = await ApiClient.instance.aksi('apotik_laporan_penjualan',
          {'dari': _fmtTgl.format(_dari), 'sampai': _fmtTgl.format(_sampai)});
      setStateIfMounted(() {
        _data = r;
        // Angka server sudah terpasang -> penanda salinan tersimpan padam.
        _dariCache = false;
        _cacheDisimpanPada = null;
      });
      // Stempel waktu ikut disimpan DI DALAM amplop supaya pemuatan berikutnya
      // bisa memberi tahu KAPAN salinan ini dibuat. Kunci berawalan garis bawah
      // tidak pernah dibaca perender di bawah (semua baca kunci spesifik).
      await CoreDb.instance.simpanCacheReferensi(
          kunci,
          jsonEncode({
            ...r,
            '_disimpanPada': DateTime.now().toIso8601String(),
          }));
    } catch (e) {
      // Offline dgn snapshot sudah tampil -> cukup diam (indikator offline
      // global sudah menceritakan kondisinya).
      if (e is ApiException && e.offline && adaCacheLokal) return;
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final perItem =
        ((d?['perItem'] as List?) ?? []).cast<Map<String, dynamic>>();
    final perGol =
        ((d?['perGolongan'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Column(children: [
      _FilterPeriode(
          dari: _dari,
          sampai: _sampai,
          onDari: (v) => setStateIfMounted(() => _dari = v),
          onSampai: (v) => setStateIfMounted(() => _sampai = v),
          onMuat: _muat),
      // Penanda salinan tersimpan -- di kolom utama tab, DI ATAS kartu KPI dan
      // tabel, supaya angka rupiah tidak terbaca sebagai data terkini.
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: PenandaDataTersimpan(
            tampil: _dariCache, diperbaruiPada: _cacheDisimpanPada),
      ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : d == null
                ? const Center(child: Text('Tekan Muat.'))
                : ListView(padding: const EdgeInsets.all(12), children: [
                    Row(children: [
                      Expanded(
                          child: AppKpiCard(
                              icon: Icons.payments_outlined,
                              warna: AppColors.primary,
                              nilai: _rp.format(d['totalNilai'] ?? 0),
                              label: 'Total Penjualan')),
                      const SizedBox(width: 8),
                      Expanded(
                          child: AppKpiCard(
                              icon: Icons.medication_outlined,
                              warna: AppColors.teal,
                              nilai: '${d['totalQty'] ?? 0}',
                              label: 'Total Qty')),
                    ]),
                    const SizedBox(height: 12),
                    if (perGol.isNotEmpty)
                      AppSectionCard(
                        judul: 'Per Golongan Obat',
                        child: Column(
                          children: perGol
                              .map((g) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(children: [
                                      Expanded(
                                          child: Text('${g['golongan']}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600))),
                                      Text('${g['qty']} • ',
                                          style: const TextStyle(fontSize: 12)),
                                      Text(_rp.format(g['nilai'] ?? 0),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ]),
                                  ))
                              .toList(),
                        ),
                      ),
                    const SizedBox(height: 12),
                    AppDataTable(
                      minWidth: 520,
                      emptyText: 'Tidak ada penjualan pada periode ini.',
                      columns: const [
                        AppTableColumn('Obat', flex: 4),
                        AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                        AppTableColumn('Nilai',
                            flex: 2, align: TextAlign.right),
                      ],
                      rows: perItem
                          .map((it) => AppTableRowData(cells: [
                                AppTableCell.text(
                                    '${it['nama']} (${it['kode']})',
                                    flex: 4,
                                    maxLines: 2),
                                AppTableCell.text('${it['qty']}',
                                    flex: 1, align: TextAlign.right),
                                AppTableCell.text(_rp.format(it['nilai'] ?? 0),
                                    flex: 2,
                                    align: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5)),
                              ]))
                          .toList(),
                    ),
                  ]),
      ),
    ]);
  }
}

// =============================================================================
// Tab 2 -- Obat Terkendali (register narkotika/psikotropika)
// =============================================================================

class _TabTerkendali extends StatefulWidget {
  const _TabTerkendali();

  @override
  State<_TabTerkendali> createState() => _TabTerkendaliState();
}

class _TabTerkendaliState extends State<_TabTerkendali> {
  DateTime _dari = DateTime.now().subtract(const Duration(days: 30));
  DateTime _sampai = DateTime.now();
  bool _memuat = false;
  List<Map<String, dynamic>> _data = [];

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final r = await ApiClient.instance.aksi('apotik_laporan_terkendali',
          {'dari': _fmtTgl.format(_dari), 'sampai': _fmtTgl.format(_sampai)});
      setStateIfMounted(() =>
          _data = ((r['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _FilterPeriode(
          dari: _dari,
          sampai: _sampai,
          onDari: (v) => setStateIfMounted(() => _dari = v),
          onSampai: (v) => setStateIfMounted(() => _sampai = v),
          onMuat: _muat),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _data.isEmpty
                ? const Center(
                    child: Text(
                        'Tidak ada penjualan obat terkendali pada periode ini.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _data.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _data[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.gpp_maybe_outlined,
                            color: AppColors.danger),
                        title: Text('${r['nama']} — ${r['qty']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${r['golongan']} • ${r['waktu']}\n'
                            'Pembeli: ${r['namaPembeli']}${(r['alamatPembeli'] as String?)?.isNotEmpty == true ? ' (${r['alamatPembeli']})' : ''}\n'
                            'Dokter: ${r['namaDokter']?.toString().isNotEmpty == true ? r['namaDokter'] : '-'} • Oleh: ${r['oleh']}',
                            style: const TextStyle(fontSize: 11.5)),
                        isThreeLine: true,
                        trailing: StatusPill(
                            label: '${r['golongan']}', warna: AppColors.danger),
                      );
                    },
                  ),
      ),
    ]);
  }
}

// =============================================================================
// Tab 3 -- Kedaluwarsa
// =============================================================================

class _TabKedaluwarsa extends StatefulWidget {
  const _TabKedaluwarsa();

  @override
  State<_TabKedaluwarsa> createState() => _TabKedaluwarsaState();
}

class _TabKedaluwarsaState extends State<_TabKedaluwarsa> {
  int _hari = 90;
  bool _memuat = false;
  Map<String, dynamic>? _data;

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final r = await ApiClient.instance
          .aksi('apotik_laporan_kedaluwarsa', {'hari_ke_depan': _hari});
      setStateIfMounted(() => _data = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final rows = ((d?['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          const Text('Kedaluwarsa dalam:'),
          const SizedBox(width: 8),
          DropdownButton<int>(
            value: _hari,
            items: const [
              DropdownMenuItem(value: 30, child: Text('30 hari')),
              DropdownMenuItem(value: 90, child: Text('90 hari')),
              DropdownMenuItem(value: 180, child: Text('180 hari')),
              DropdownMenuItem(value: 365, child: Text('1 tahun')),
            ],
            onChanged: (v) {
              _hari = v ?? 90;
              _muat();
            },
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muat),
        ]),
      ),
      if (d != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Expanded(
                child: AppKpiCard(
                    icon: Icons.dangerous_outlined,
                    warna: AppColors.danger,
                    nilai: '${d['jumlahKedaluwarsa'] ?? 0}',
                    label: 'Sudah Kedaluwarsa')),
            const SizedBox(width: 8),
            Expanded(
                child: AppKpiCard(
                    icon: Icons.schedule,
                    warna: AppColors.warning,
                    nilai: '${d['jumlahSegera'] ?? 0}',
                    label: 'Segera Kedaluwarsa')),
            const SizedBox(width: 8),
            Expanded(
                child: AppKpiCard(
                    icon: Icons.attach_money,
                    warna: AppColors.teal,
                    nilai: _rp.format(d['totalNilai'] ?? 0),
                    label: 'Nilai Terancam')),
          ]),
        ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : rows.isEmpty
                ? const Center(
                    child: Text('Tidak ada batch mendekati kedaluwarsa.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = rows[i];
                      final exp = b['kedaluwarsa'] == true;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                            exp ? Icons.dangerous_outlined : Icons.schedule,
                            color: exp ? AppColors.danger : AppColors.warning),
                        title: Text('${b['nama']} (${b['kode']})',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'ED ${b['tanggalKadaluarsa']} • sisa ${b['sisa']} • ${_rp.format(b['nilai'] ?? 0)}',
                            style: const TextStyle(fontSize: 11.5)),
                        trailing: StatusPill(
                            label: exp ? 'KEDALUWARSA' : 'SEGERA',
                            warna: exp ? AppColors.danger : AppColors.warning),
                      );
                    },
                  ),
      ),
    ]);
  }
}
