import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/safe_state.dart';
import 'pos_help.dart';

final _rp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// <h3>Persediaan Apotik -- FASE B (formularium, batch/ED, PBF, opname, retur).</h3>
///
/// Lima tab di atas aksi server FASE B (`apotik_terima_barang`,
/// `apotik_opname_simpan`, `apotik_retur_simpan`, `apotik_batch_monitor`) +
/// formularium (`apotik_item_cari`/`apotik_item_profil_simpan`). Semua mutasi
/// stok terjadi di server lewat ledger SIRS bertanda -- layar ini tidak pernah
/// menghitung stok sendiri.
class PersediaanApotikScreen extends StatefulWidget {
  final int tabAwal;
  const PersediaanApotikScreen({super.key, this.tabAwal = 0});

  @override
  State<PersediaanApotikScreen> createState() => _PersediaanApotikScreenState();
}

class _PersediaanApotikScreenState extends State<PersediaanApotikScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 5, vsync: this, initialIndex: widget.tabAwal.clamp(0, 4));
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
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: const Text('Persediaan Apotik'),
        actions: [
          PosHelp.button(
              context,
              const [
                'apotik_formularium',
                'apotik_batch',
                'apotik_pengadaan',
                'apotik_stok_opname',
                'apotik_retur'
              ][_tab.index],
              compact: true)
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Formularium'),
            Tab(text: 'Batch & Kedaluwarsa'),
            Tab(text: 'Penerimaan PBF'),
            Tab(text: 'Stok Opname'),
            Tab(text: 'Retur Obat'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _TabFormularium(),
          _TabBatchMonitor(),
          _TabPenerimaanPbf(),
          _TabOpname(),
          _TabRetur(),
        ],
      ),
    );
  }
}

/// Picker item bersama -- cari via `apotik_item_cari`, kembalikan Map item.
Future<Map<String, dynamic>?> _pilihItem(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SheetCariItem(),
  );
}

class _SheetCariItem extends StatefulWidget {
  const _SheetCariItem();

  @override
  State<_SheetCariItem> createState() => _SheetCariItemState();
}

class _SheetCariItemState extends State<_SheetCariItem> {
  final _cari = TextEditingController();
  Timer? _debounce;
  bool _memuat = false;
  List<Map<String, dynamic>> _data = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _cari.dispose();
    super.dispose();
  }

  void _berubah(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().isEmpty) return;
      setStateIfMounted(() => _memuat = true);
      try {
        final hasil = await ApiClient.instance
            .aksi('apotik_item_cari', {'keyword': v.trim(), 'page_size': 20});
        setStateIfMounted(() => _data =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
      } catch (_) {
        // Biarkan daftar lama; kegagalan cari bukan blocker sheet.
      } finally {
        setStateIfMounted(() => _memuat = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      expand: false,
      builder: (context, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _cari,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Cari obat: kode / barcode / nama...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
            onChanged: _berubah,
          ),
        ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  controller: sc,
                  itemCount: _data.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _data[i];
                    return ListTile(
                      dense: true,
                      title: Text('${it['nama']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${it['kode']} • stok ${it['stok']} • ${it['golonganObat']}',
                          style: const TextStyle(fontSize: 11.5)),
                      onTap: () => Navigator.pop(context, it),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Tab 1 -- Formularium: daftar obat + set golongan/LASA
// =============================================================================

class _TabFormularium extends StatefulWidget {
  const _TabFormularium();

  @override
  State<_TabFormularium> createState() => _TabFormulariumState();
}

class _TabFormulariumState extends State<_TabFormularium> {
  final _cari = TextEditingController();
  bool _memuat = false;
  List<Map<String, dynamic>> _data = [];

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi('apotik_item_cari', {
        if (_cari.text.trim().isNotEmpty) 'keyword': _cari.text.trim(),
        'page_size': 30,
      });
      setStateIfMounted(() => _data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
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
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _ubahProfil(Map<String, dynamic> it) async {
    var golongan = '${it['golonganObat'] ?? 'BEBAS'}';
    var lasa = it['lasa'] == true;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${it['nama']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: golongan,
              decoration: const InputDecoration(
                  labelText: 'Golongan Obat', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'BEBAS', child: Text('Bebas')),
                DropdownMenuItem(
                    value: 'BEBAS_TERBATAS', child: Text('Bebas Terbatas')),
                DropdownMenuItem(value: 'KERAS', child: Text('Keras')),
                DropdownMenuItem(value: 'NARKOTIKA', child: Text('Narkotika')),
                DropdownMenuItem(
                    value: 'PSIKOTROPIKA', child: Text('Psikotropika')),
              ],
              onChanged: (v) => setD(() => golongan = v ?? 'BEBAS'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              title: const Text('LASA (Look-Alike Sound-Alike)'),
              subtitle: const Text('Tampil beda di kasir agar tidak tertukar',
                  style: TextStyle(fontSize: 11)),
              value: lasa,
              onChanged: (v) => setD(() => lasa = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true) return;
    try {
      await ApiClient.instance.aksi('apotik_item_profil_simpan', {
        'item_id': it['id'],
        'golongan_obat': golongan,
        'lasa': lasa,
      });
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal simpan: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        TextField(
          controller: _cari,
          decoration: const InputDecoration(
              hintText: 'Cari obat...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true),
          onSubmitted: (_) => _muat(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: _data.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final it = _data[i];
                    final terkendali = it['terkendali'] == true;
                    return ListTile(
                      dense: true,
                      title: Text('${it['nama']}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${it['kode']} • stok ${it['stok']} • ${_rp.format((it['hargaJual'] as num?) ?? 0)}',
                          style: const TextStyle(fontSize: 11.5)),
                      trailing: Wrap(spacing: 4, children: [
                        if (it['lasa'] == true)
                          const StatusPill(
                              label: 'LASA', warna: Color(0xFFB8860B)),
                        StatusPill(
                            label: '${it['golonganObat']}',
                            warna:
                                terkendali ? AppColors.danger : AppColors.teal),
                      ]),
                      onTap: () => _ubahProfil(it),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Tab 2 -- Batch & Kedaluwarsa (monitor lintas item)
// =============================================================================

class _TabBatchMonitor extends StatefulWidget {
  const _TabBatchMonitor();

  @override
  State<_TabBatchMonitor> createState() => _TabBatchMonitorState();
}

class _TabBatchMonitorState extends State<_TabBatchMonitor> {
  bool _memuat = true;
  int _hari = 90;
  List<Map<String, dynamic>> _data = [];

  Future<void> _muat() async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil = await ApiClient.instance.aksi(
          'apotik_batch_monitor', {'hari_ke_depan': _hari, 'page_size': 100});
      setStateIfMounted(() => _data =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
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
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
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
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
                  ? const Center(
                      child:
                          Text('Tidak ada batch mendekati kedaluwarsa. Bagus.'))
                  : ListView.separated(
                      itemCount: _data.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final b = _data[i];
                        final expired = b['kedaluwarsa'] == true;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              expired
                                  ? Icons.dangerous_outlined
                                  : Icons.schedule,
                              color: expired
                                  ? AppColors.danger
                                  : AppColors.warning),
                          title: Text('${b['nama']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${b['kode']} • sisa ${b['sisa']} • ED ${b['tanggalKadaluarsa']}',
                              style: const TextStyle(fontSize: 11.5)),
                          trailing: StatusPill(
                              label: expired ? 'KEDALUWARSA' : 'SEGERA',
                              warna: expired
                                  ? AppColors.danger
                                  : AppColors.warning),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// =============================================================================
// Baris input bersama utk tab Penerimaan/Opname/Retur
// =============================================================================

class _BarisInput {
  final Map<String, dynamic> item;
  final TextEditingController qty = TextEditingController(text: '1');
  final TextEditingController harga = TextEditingController(text: '0');
  final TextEditingController ed = TextEditingController();
  _BarisInput(this.item);

  void dispose() {
    qty.dispose();
    harga.dispose();
    ed.dispose();
  }
}

// =============================================================================
// Tab 3 -- Penerimaan PBF
// =============================================================================

class _TabPenerimaanPbf extends StatefulWidget {
  const _TabPenerimaanPbf();

  @override
  State<_TabPenerimaanPbf> createState() => _TabPenerimaanPbfState();
}

class _TabPenerimaanPbfState extends State<_TabPenerimaanPbf> {
  final _penyedia = TextEditingController();
  final _noFaktur = TextEditingController();
  final List<_BarisInput> _baris = [];
  bool _proses = false;

  @override
  void dispose() {
    _penyedia.dispose();
    _noFaktur.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) setStateIfMounted(() => _baris.add(_BarisInput(it)));
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance.aksi('apotik_terima_barang', {
        'penyedia': _penyedia.text.trim(),
        'no_faktur': _noFaktur.text.trim(),
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty': double.tryParse(b.qty.text) ?? 0,
                  'harga_beli':
                      double.tryParse(b.harga.text.replaceAll(',', '.')) ?? 0,
                  if (b.ed.text.trim().isNotEmpty)
                    'tanggal_kadaluarsa': b.ed.text.trim(),
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Penerimaan tercatat: ${hasil['jumlahBaris']} baris, ${hasil['jumlahBatch']} batch ED.')));
        setStateIfMounted(() {
          for (final b in _baris) {
            b.dispose();
          }
          _baris.clear();
          _penyedia.clear();
          _noFaktur.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(
            child: TextField(
                controller: _penyedia,
                decoration: const InputDecoration(
                    labelText: 'PBF / Pemasok',
                    border: OutlineInputBorder(),
                    isDense: true))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _noFaktur,
                decoration: const InputDecoration(
                    labelText: 'No. Faktur',
                    border: OutlineInputBorder(),
                    isDense: true))),
      ]),
      const SizedBox(height: 10),
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text('${b.item['nama']}',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    onPressed: () => setStateIfMounted(() {
                          _baris.removeAt(e.key).dispose();
                        })),
              ]),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: b.qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                            isDense: true))),
                const SizedBox(width: 6),
                Expanded(
                    child: TextField(
                        controller: b.harga,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Harga Beli',
                            border: OutlineInputBorder(),
                            isDense: true))),
                const SizedBox(width: 6),
                Expanded(
                    child: TextField(
                        controller: b.ed,
                        decoration: const InputDecoration(
                            labelText: 'ED (yyyy-mm-dd)',
                            border: OutlineInputBorder(),
                            isDense: true))),
              ]),
            ]),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.inventory_2_outlined),
        label: const Text('Catat Penerimaan'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
    ]);
  }
}

// =============================================================================
// Tab 4 -- Stok Opname
// =============================================================================

class _TabOpname extends StatefulWidget {
  const _TabOpname();

  @override
  State<_TabOpname> createState() => _TabOpnameState();
}

class _TabOpnameState extends State<_TabOpname> {
  final List<_BarisInput> _baris = [];
  bool _proses = false;
  List<Map<String, dynamic>> _hasilTerakhir = [];

  @override
  void dispose() {
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) {
      final b = _BarisInput(it);
      b.qty.text = '${it['stok'] ?? 0}';
      setStateIfMounted(() => _baris.add(b));
    }
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      final hasil = await ApiClient.instance.aksi('apotik_opname_simpan', {
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty_fisik': double.tryParse(b.qty.text) ?? 0,
                })
            .toList(),
      });
      setStateIfMounted(() {
        _hasilTerakhir =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        for (final b in _baris) {
          b.dispose();
        }
        _baris.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            title: Text('${b.item['nama']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Stok sistem: ${b.item['stok']}'),
            trailing: SizedBox(
              width: 110,
              child: TextField(
                  controller: b.qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Qty Fisik',
                      border: OutlineInputBorder(),
                      isDense: true)),
            ),
            onLongPress: () => setStateIfMounted(() {
              _baris.removeAt(e.key).dispose();
            }),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat Diopname')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.fact_check_outlined),
        label: const Text('Simpan Opname (koreksi selisih)'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
      if (_hasilTerakhir.isNotEmpty) ...[
        const SizedBox(height: 14),
        const Text('Hasil opname terakhir:',
            style: TextStyle(fontWeight: FontWeight.w800)),
        ..._hasilTerakhir.map((r) => ListTile(
              dense: true,
              title: Text('${r['nama']}'),
              subtitle:
                  Text('sistem ${r['stokSistem']} -> fisik ${r['qtyFisik']}'),
              trailing: Text('${(r['selisih'] as num?) ?? 0}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: ((r['selisih'] as num?) ?? 0) == 0
                          ? AppColors.success
                          : AppColors.warning)),
            )),
      ],
    ]);
  }
}

// =============================================================================
// Tab 5 -- Retur Obat
// =============================================================================

class _TabRetur extends StatefulWidget {
  const _TabRetur();

  @override
  State<_TabRetur> createState() => _TabReturState();
}

class _TabReturState extends State<_TabRetur> {
  String _jenis = 'penjualan';
  final _keterangan = TextEditingController();
  final List<_BarisInput> _baris = [];
  bool _proses = false;

  @override
  void dispose() {
    _keterangan.dispose();
    for (final b in _baris) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _tambah() async {
    final it = await _pilihItem(context);
    if (it != null) setStateIfMounted(() => _baris.add(_BarisInput(it)));
  }

  Future<void> _simpan() async {
    if (_baris.isEmpty) return;
    setStateIfMounted(() => _proses = true);
    try {
      await ApiClient.instance.aksi('apotik_retur_simpan', {
        'jenis': _jenis,
        'keterangan': _keterangan.text.trim(),
        'items': _baris
            .map((b) => {
                  'item_id': b.item['id'],
                  'qty': double.tryParse(b.qty.text) ?? 0,
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Retur tercatat.')));
        setStateIfMounted(() {
          for (final b in _baris) {
            b.dispose();
          }
          _baris.clear();
          _keterangan.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ditolak: $e')));
      }
    } finally {
      setStateIfMounted(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
              value: 'penjualan',
              label: Text('Dari Pembeli (masuk)'),
              icon: Icon(Icons.assignment_return_outlined)),
          ButtonSegment(
              value: 'pbf',
              label: Text('Ke PBF (keluar)'),
              icon: Icon(Icons.local_shipping_outlined)),
        ],
        selected: {_jenis},
        onSelectionChanged: (s) => setStateIfMounted(() => _jenis = s.first),
      ),
      const SizedBox(height: 10),
      TextField(
          controller: _keterangan,
          decoration: const InputDecoration(
              labelText: 'Keterangan / alasan retur',
              border: OutlineInputBorder(),
              isDense: true)),
      const SizedBox(height: 10),
      ..._baris.asMap().entries.map((e) {
        final b = e.value;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            title: Text('${b.item['nama']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Stok: ${b.item['stok']}'),
            trailing: SizedBox(
              width: 100,
              child: TextField(
                  controller: b.qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true)),
            ),
            onLongPress: () => setStateIfMounted(() {
              _baris.removeAt(e.key).dispose();
            }),
          ),
        );
      }),
      OutlinedButton.icon(
          onPressed: _tambah,
          icon: const Icon(Icons.add),
          label: const Text('Tambah Obat')),
      const SizedBox(height: 10),
      ElevatedButton.icon(
        onPressed: _baris.isEmpty || _proses ? null : _simpan,
        icon: _proses
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.assignment_return_outlined),
        label: const Text('Catat Retur'),
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
      ),
    ]);
  }
}
