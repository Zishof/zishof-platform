import 'package:flutter/material.dart';

import '../../../services/master_offline.dart';
import '../../../widgets/safe_state.dart';
import '../core/apotik_lokal_dulu.dart';
import '../shared/widgets/apotik_state_views.dart';
import '../shared/widgets/apotik_status_pill.dart';

/// Pusat operasional persediaan lanjutan berbasis data batch dan formularium
/// SIRS. Semua angka berasal dari API aktual; tidak ada angka contoh buatan UI.
class ApotikInventoryIntelligencePage extends StatefulWidget {
  final int tabAwal;
  final MuatDaftarApotik? muatDaftar;
  final VoidCallback? bukaMonitorBatch;
  final VoidCallback? bukaTransfer;
  final VoidCallback? bukaPengadaan;

  const ApotikInventoryIntelligencePage({
    super.key,
    this.tabAwal = 0,
    this.muatDaftar,
    this.bukaMonitorBatch,
    this.bukaTransfer,
    this.bukaPengadaan,
  });

  @override
  State<ApotikInventoryIntelligencePage> createState() =>
      _ApotikInventoryIntelligencePageState();
}

class _ApotikInventoryIntelligencePageState
    extends State<ApotikInventoryIntelligencePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
      length: 4, vsync: this, initialIndex: widget.tabAwal.clamp(0, 3));
  late final MuatDaftarApotik _muatDaftar =
      widget.muatDaftar ?? MasterOffline.daftarCacheDulu;

  List<Map<String, dynamic>> _batch = [];
  List<Map<String, dynamic>> _item = [];
  bool _memuatBatch = true;
  bool _memuatItem = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _baris(Map<String, dynamic> hasil) =>
      ((hasil['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuatBatch = true;
      _memuatItem = true;
      _galat = null;
    });
    await Future.wait([
      _muatDaftar(
        'apotik_batch_monitor',
        const {'hari_ke_depan': 3650, 'page_size': 100},
        kunciCacheBatchApotik,
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _batch = _baris(hasil);
            _memuatBatch = false;
          });
        },
      ).catchError((Object e) {
        if (!mounted) return;
        setStateIfMounted(() {
          _memuatBatch = false;
          if (_batch.isEmpty) _galat = '$e';
        });
      }),
      _muatDaftar(
        'apotik_item_cari',
        const {'page_size': 100},
        kunciCacheItemApotik,
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _item = _baris(hasil);
            _memuatItem = false;
          });
        },
      ).catchError((Object e) {
        if (!mounted) return;
        setStateIfMounted(() {
          _memuatItem = false;
          if (_item.isEmpty) _galat = '$e';
        });
      }),
    ]);
  }

  bool get _memuat => _memuatBatch || _memuatItem;
  List<Map<String, dynamic>> get _ditahan => _batch
      .where((e) => e['lotLayak'] == false || '${e['statusLot']}' != 'ELIGIBLE')
      .toList();
  List<Map<String, dynamic>> get _coldChain =>
      _batch.where((e) => e['coldChain'] == true).toList();

  @override
  Widget build(BuildContext context) {
    if (_memuat && _batch.isEmpty && _item.isEmpty) {
      return const ApotikLoadingState(pesan: 'Memuat kendali persediaan…');
    }
    if (_galat != null && _batch.isEmpty && _item.isEmpty) {
      return ApotikErrorState(pesan: _galat!, onCobaLagi: _muat);
    }
    return Column(children: [
      _ringkasan(),
      TabBar(
        controller: _tab,
        isScrollable: true,
        tabs: const [
          Tab(
              icon: Icon(Icons.report_gmailerrorred_outlined),
              text: 'Recall & Karantina'),
          Tab(icon: Icon(Icons.thermostat_outlined), text: 'Cold Chain'),
          Tab(
              icon: Icon(Icons.multiple_stop_outlined),
              text: 'Lokasi & Transfer'),
          Tab(icon: Icon(Icons.auto_graph_outlined), text: 'Perencanaan Stok'),
        ],
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _recall(),
          _coldChainView(),
          _lokasi(),
          _perencanaan(),
        ]),
      ),
    ]);
  }

  Widget _ringkasan() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        _angka('Batch dipantau', _batch.length, Icons.inventory_2_outlined),
        _angka('Ditahan / recall', _ditahan.length, Icons.block_outlined,
            bahaya: _ditahan.isNotEmpty),
        _angka('Cold-chain', _coldChain.length, Icons.ac_unit_outlined),
        _angka('Item dianalisis', _item.length, Icons.analytics_outlined),
        IconButton(
            onPressed: _memuat ? null : _muat,
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh)),
      ]),
    );
  }

  Widget _angka(String label, int nilai, IconData ikon, {bool bahaya = false}) {
    final warna =
        bahaya ? Theme.of(context).colorScheme.error : const Color(0xFF0F766E);
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: .08),
        border: Border.all(color: warna.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(ikon, size: 20, color: warna),
        const SizedBox(width: 9),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$nilai',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, color: warna)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ])),
      ]),
    );
  }

  Widget _recall() {
    final data = _ditahan;
    if (data.isEmpty) {
      return ApotikEmptyState(
        ikon: Icons.verified_user_outlined,
        judul: 'Tidak ada lot yang sedang ditahan',
        petunjuk: 'Seluruh ${_batch.length} batch terpantau berstatus layak.',
        aksi: FilledButton.icon(
            onPressed: widget.bukaMonitorBatch,
            icon: const Icon(Icons.manage_search),
            label: const Text('Kelola Status Batch')),
      );
    }
    return _daftarBatch(data, tampilkanSuhu: false);
  }

  Widget _coldChainView() {
    if (_coldChain.isEmpty) {
      return ApotikEmptyState(
        ikon: Icons.thermostat_outlined,
        judul: 'Belum ada batch cold-chain pada hasil ini',
        petunjuk:
            'Tandai profil obat sebagai cold-chain untuk memantau lot dan suhu penerimaannya.',
        aksi: OutlinedButton.icon(
            onPressed: widget.bukaMonitorBatch,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Buka Batch & Kedaluwarsa')),
      );
    }
    return _daftarBatch(_coldChain, tampilkanSuhu: true);
  }

  Widget _daftarBatch(List<Map<String, dynamic>> data,
      {required bool tampilkanSuhu}) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: data.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final b = data[i];
        final status = '${b['statusLot'] ?? 'ELIGIBLE'}';
        return Card(
          child: ListTile(
            leading: CircleAvatar(
                child: Icon(tampilkanSuhu
                    ? Icons.ac_unit
                    : Icons.warning_amber_rounded)),
            title: Text('${b['nama'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${b['kode'] ?? ''} • ED ${b['tanggalKadaluarsa'] ?? '-'} • ${b['lokasiNama']?.toString().trim().isEmpty == false ? b['lokasiNama'] : 'Lokasi utama'}\nSisa ${b['sisa'] ?? 0}${tampilkanSuhu ? ' • Kendali 2–8 °C' : ''}'),
            isThreeLine: true,
            trailing: status == 'ELIGIBLE'
                ? ApotikStatusPill.layak()
                : ApotikStatusPill.lotDitahan('${b['alasanLot'] ?? status}'),
          ),
        );
      },
    );
  }

  Widget _lokasi() {
    final grup = <String, List<Map<String, dynamic>>>{};
    for (final b in _batch) {
      final nama = '${b['lokasiNama'] ?? ''}'.trim();
      grup.putIfAbsent(nama.isEmpty ? 'Lokasi utama' : nama, () => []).add(b);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final e in grup.entries)
          Card(
              child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
            title: Text(e.key,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${e.value.length} batch • ${e.value.fold<num>(0, (a, b) => a + ((b['sisa'] as num?) ?? 0))} unit tersedia'),
            trailing: const Icon(Icons.chevron_right),
          )),
        const SizedBox(height: 8),
        FilledButton.icon(
            onPressed: widget.bukaTransfer,
            icon: const Icon(Icons.multiple_stop),
            label: const Text('Buat Transfer Antar Lokasi')),
      ],
    );
  }

  Widget _perencanaan() {
    final data = [..._item]..sort((a, b) =>
        (((a['stok'] as num?) ?? 0).compareTo((b['stok'] as num?) ?? 0)));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: data.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Expanded(
                  child: Text(
                      'Prioritas diurutkan dari stok terendah. Keputusan pemesanan tetap melalui persetujuan petugas.')),
              FilledButton.icon(
                  onPressed: widget.bukaPengadaan,
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Buat Pengadaan')),
            ]),
          );
        }
        final item = data[i - 1];
        final stok = (item['stok'] as num?) ?? 0;
        return Card(
            child: ListTile(
          leading: CircleAvatar(child: Text(i.toString().padLeft(2, '0'))),
          title: Text('${item['nama'] ?? '-'}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${item['kode'] ?? ''} • ${item['satuan'] ?? 'unit'}'),
          trailing: Text('Stok $stok',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color:
                      stok <= 10 ? Theme.of(context).colorScheme.error : null)),
        ));
      },
    );
  }
}
