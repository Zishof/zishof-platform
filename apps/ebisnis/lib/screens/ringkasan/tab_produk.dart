import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';

const _periodeOpsi = ['harian', 'mingguan', 'bulanan', 'semester', 'tahunan'];

/// Tab 3/9 "Produk & Inventaris" -- aksi `dashboard_produk` (param `periode`).
/// Peringatan stok, bahan baku & estimasi habis, rekonsiliasi aset (opsional,
/// kosong kalau modul tidak dipakai), produk terlaris, metode bayar, rekap
/// per-periode, dan produk kurang laku.
class RingkasanTabProduk extends StatefulWidget {
  const RingkasanTabProduk({super.key});
  @override
  State<RingkasanTabProduk> createState() => _RingkasanTabProdukState();
}

class _RingkasanTabProdukState extends State<RingkasanTabProduk> {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  String _periode = 'bulanan';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('dashboard_produk', {'periode': _periode});
      if (!mounted) return;
      setStateIfMounted(() => _d = hasil);
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Color _warnaStatus(String s) {
    switch (s) {
      case 'HABIS':
        return Colors.red;
      case 'KRITIS':
        return Colors.orange;
      default:
        return const Color(0xFFB8860B);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null) return statusMuatDasbor(memuat: _memuat, error: _error, onCoba: _muat);
    final d = _d!;
    final stok = ((d['stok'] as List?) ?? []).cast<Map<String, dynamic>>();
    final bahanBaku = (d['bahanBaku'] as Map<String, dynamic>?) ?? {};
    final bahanKpi = (bahanBaku['kpi'] as Map<String, dynamic>?) ?? {};
    final bahanList = ((bahanBaku['list'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rekon = (d['rekonsiliasiAset'] as Map<String, dynamic>?) ?? {};
    final rekonKpi = (rekon['kpi'] as Map<String, dynamic>?) ?? {};
    final rekonList = ((rekon['list'] as List?) ?? []).cast<Map<String, dynamic>>();
    final terlaris = titikDariList(d['produkTerlaris'] as List?, labelKey: 'nama', nilaiKey: 'qty');
    final metodeBayar = titikDariList(d['metodeBayar'] as List?, labelKey: 'nama', nilaiKey: 'total');
    final rekapTerlaris = ((d['rekapProdukTerlaris'] as List?) ?? []).cast<Map<String, dynamic>>();
    final kurangLaku = titikDariList(d['produkKurangLaku'] as List?, labelKey: 'nama', nilaiKey: 'terjual');

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          if (stok.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Peringatan Stok', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...stok.take(30).map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${s['namaProduk']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${s['sisaStok']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: _warnaStatus('${s['status']}').withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                child: Text('${s['status']}', style: TextStyle(fontSize: 10, color: _warnaStatus('${s['status']}'))),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          PanelChart(judul: 'Produk Terlaris (30 hari)', child: BarHorizontal(data: terlaris)),
          const SizedBox(height: 12),
          PanelChart(judul: 'Komposisi Metode Bayar (30 hari)', child: StackProporsional(data: metodeBayar)),
          const SizedBox(height: 12),
          Text('Bahan Baku & Estimasi Habis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          BarisKpi(kartu: [
            KartuKpi(label: 'Dipantau', nilai: '${bahanKpi['dipantau'] ?? 0}', warna: const Color(0xFF1E3A5F)),
            KartuKpi(label: 'Segera Habis', nilai: '${bahanKpi['segeraHabis'] ?? 0}', warna: Colors.red),
            KartuKpi(label: 'Paling Mendesak', nilai: '${bahanKpi['palingMendesakNama'] ?? '-'}', warna: Colors.orange),
            KartuKpi(label: 'Nilai Stok', nilai: formatRupiahDasbor.format(bahanKpi['nilaiStok'] ?? 0), warna: const Color(0xFF2E7D32)),
          ]),
          const SizedBox(height: 12),
          if (bahanList.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: bahanList
                      .take(20)
                      .map((b) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text('${b['nama']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                Text(b['estimasiHari'] != null ? '~${b['estimasiHari']} hari lagi' : '-', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          if ((rekonKpi['tertaut'] ?? 0) != 0 || rekonList.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Rekonsiliasi Aset', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            BarisKpi(kartu: [
              KartuKpi(label: 'Tertaut', nilai: '${rekonKpi['tertaut'] ?? 0}', warna: const Color(0xFF1E3A5F)),
              KartuKpi(label: 'Stok Cocok', nilai: '${rekonKpi['stokCocok'] ?? 0}', warna: const Color(0xFF2E7D32)),
              KartuKpi(label: 'Perlu Dicek', nilai: '${rekonKpi['perluDicek'] ?? 0}', warna: Colors.orange),
            ]),
          ],
          const SizedBox(height: 12),
          if (rekapTerlaris.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Rekap Produk Terlaris', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        DropdownButton<String>(
                          value: _periode,
                          items: _periodeOpsi.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setStateIfMounted(() => _periode = v);
                              _muat();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...rekapTerlaris.take(20).map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${r['nama']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${r['qty']}x', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(formatRupiahDasbor.format(r['total'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          PanelChart(judul: 'Produk Kurang Laku (≤5 terjual/30 hari)', child: BarHorizontal(data: kurangLaku, warna: Colors.grey)),
        ],
      ),
    );
  }
}
