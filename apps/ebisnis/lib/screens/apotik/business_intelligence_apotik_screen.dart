import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api_client.dart';
import '../../widgets/app_shell.dart';

class BusinessIntelligenceApotikScreen extends StatefulWidget {
  const BusinessIntelligenceApotikScreen({super.key});

  @override
  State<BusinessIntelligenceApotikScreen> createState() =>
      _BusinessIntelligenceApotikScreenState();
}

class _BusinessIntelligenceApotikScreenState
    extends State<BusinessIntelligenceApotikScreen> {
  final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _angka = NumberFormat.decimalPattern('id_ID');
  List<Map<String, dynamic>> _produk = const [];
  List<Map<String, dynamic>> _golongan = const [];
  Map<String, dynamic> _laporan = const {};
  Map<String, dynamic> _metrik = const {};
  bool _memuat = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  bool _sukses(Map<String, dynamic> hasil) =>
      hasil['status'] == '00' || hasil['status'] == 'success';

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await Future.wait([
        ApiClient.instance
            .aksi('apotik_laporan_penjualan', const {'page_size': 100}),
        ApiClient.instance.aksi('apotik_metrik_operasional', const {}),
      ]);
      if (!_sukses(hasil[0]) || !_sukses(hasil[1])) {
        throw Exception('Data analitik belum dapat dimuat.');
      }
      if (!mounted) return;
      setState(() {
        _laporan = hasil[0];
        _metrik = hasil[1];
        _produk = ((hasil[0]['perItem'] as List?) ??
                (hasil[0]['data'] as List?) ??
                const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _golongan = ((hasil[0]['perGolongan'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _memuat = false;
      });
    }
  }

  num _nilai(Map<String, dynamic> data, String key) => (data[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Business Intelligence Apotik',
      subjudul: 'Penjualan, layanan resep, risiko stok, dan performa farmasi',
      scrollable: false,
      actionsAppBar: [
        IconButton(
          tooltip: 'Segarkan analitik',
          onPressed: _memuat ? null : _muat,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: _isi(),
    );
  }

  Widget _isi() {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.query_stats_outlined, size: 48),
          const SizedBox(height: 12),
          Text(_error!),
          TextButton.icon(
            onPressed: _muat,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final lebar = constraints.maxWidth;
      return CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          sliver: SliverToBoxAdapter(child: _hero()),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          sliver: SliverGrid.count(
            crossAxisCount: lebar >= 1250
                ? 4
                : lebar >= 700
                    ? 2
                    : 1,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: lebar >= 1250 ? 2.15 : 2.6,
            children: [
              _kpi(
                  'Nilai penjualan',
                  _rupiah.format(_nilai(_laporan, 'totalNilai')),
                  Icons.payments_outlined,
                  const Color(0xFF047857)),
              _kpi('Unit terjual', _angka.format(_nilai(_laporan, 'totalQty')),
                  Icons.inventory_2_outlined, const Color(0xFF0369A1)),
              _kpi(
                  'Baris transaksi',
                  _angka.format(_nilai(_laporan, 'jumlahBaris')),
                  Icons.receipt_long_outlined,
                  const Color(0xFF7C3AED)),
              _kpi(
                  'Produk aktif terjual',
                  _angka.format(_nilai(_laporan, 'jumlahItem')),
                  Icons.medication_outlined,
                  const Color(0xFFC2410C)),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          sliver: SliverToBoxAdapter(
            child: lebar >= 1000
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _bauran()),
                    const SizedBox(width: 12),
                    Expanded(child: _operasional()),
                  ])
                : Column(children: [
                    _bauran(),
                    const SizedBox(height: 12),
                    _operasional(),
                  ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          sliver: SliverToBoxAdapter(child: _produkTerlaris()),
        ),
      ]);
    });
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF312E81), Color(0xFF4338CA), Color(0xFF0369A1)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        const Icon(Icons.insights_outlined, color: Colors.white, size: 42),
        const SizedBox(width: 16),
        const Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Executive Pharmacy Cockpit',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text('Satu pandangan untuk keputusan penjualan, layanan, dan stok.',
                style: TextStyle(color: Color(0xFFE0E7FF))),
          ]),
        ),
        Text('${_produk.length} data dianalisis',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _kpi(String label, String nilai, IconData ikon, Color warna) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: warna.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(ikon, color: warna),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(nilai,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w900)),
                  Text(label,
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _bauran() {
    final total = _golongan.fold<num>(0, (sum, e) => sum + _nilai(e, 'nilai'));
    return _panel(
      'Bauran Penjualan per Golongan',
      Icons.donut_large_outlined,
      Column(children: [
        for (final g in _golongan) ...[
          Row(children: [
            SizedBox(
              width: 110,
              child: Text('${g['golongan']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : _nilai(g, 'nilai') / total,
                  minHeight: 11,
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 116,
              child: Text(_rupiah.format(_nilai(g, 'nilai')),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 14),
        ],
      ]),
    );
  }

  Widget _operasional() {
    return _panel(
      'Indikator Operasional',
      Icons.monitor_heart_outlined,
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _indikator('Resep menunggu', _nilai(_metrik, 'resepMenunggu'),
              const Color(0xFFC2410C)),
          _indikator('Total resep', _nilai(_metrik, 'resepTotal'),
              const Color(0xFF0369A1)),
          _indikator('Batch segera ED', _nilai(_metrik, 'batchSegera'),
              const Color(0xFFB45309)),
          _indikator('Batch ditahan', _nilai(_metrik, 'batchDitahan'),
              const Color(0xFFB91C1C)),
          _indikator('Batch kedaluwarsa', _nilai(_metrik, 'batchKedaluwarsa'),
              const Color(0xFF7C2D12)),
          _indikator('Item habis', _nilai(_metrik, 'itemHabis'),
              const Color(0xFF475569)),
        ],
      ),
    );
  }

  Widget _indikator(String label, num nilai, Color warna) => Container(
        width: 155,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: warna.withValues(alpha: .18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_angka.format(nilai),
              style: TextStyle(
                  color: warna, fontSize: 19, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(fontSize: 11.5)),
        ]),
      );

  Widget _produkTerlaris() {
    final top = _produk.take(20).toList();
    final maksimum = top.isEmpty
        ? 1
        : top.map((e) => _nilai(e, 'nilai')).reduce((a, b) => a > b ? a : b);
    return _panel(
      '20 Produk dengan Kontribusi Terbesar',
      Icons.leaderboard_outlined,
      Column(children: [
        for (var i = 0; i < top.length; i++) ...[
          Row(children: [
            SizedBox(
              width: 30,
              child: Text('${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              flex: 3,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${top[i]['nama']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${top[i]['kode']}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: LinearProgressIndicator(
                  value: _nilai(top[i], 'nilai') / maksimum,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text('${_angka.format(_nilai(top[i], 'qty'))} unit',
                  textAlign: TextAlign.end),
            ),
            SizedBox(
              width: 145,
              child: Text(_rupiah.format(_nilai(top[i], 'nilai')),
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
          if (i != top.length - 1) const Divider(height: 20),
        ],
      ]),
    );
  }

  Widget _panel(String judul, IconData ikon, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ikon, size: 21),
              const SizedBox(width: 8),
              Text(judul,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 18),
            child,
          ]),
        ),
      );
}
