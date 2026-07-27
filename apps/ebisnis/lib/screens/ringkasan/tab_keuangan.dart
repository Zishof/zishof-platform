import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';

/// Tab 2/9 "Keuangan & Kinerja" -- aksi `dashboard_keuangan` (tanpa filter,
/// window tetap 14 hari utk tren laba). Berisi 3 sub-bagian: laba (KPI+tren),
/// performa toko (harian/mingguan/bulanan), dan Resep/HPP/Margin ringkas
/// (KPI+tabel menu+tabel bahan baku).
class RingkasanTabKeuangan extends StatefulWidget {
  const RingkasanTabKeuangan({super.key});
  @override
  State<RingkasanTabKeuangan> createState() => _RingkasanTabKeuanganState();
}

class _RingkasanTabKeuanganState extends State<RingkasanTabKeuangan> {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('dashboard_keuangan');
      setState(() => _d = hasil);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null) return statusMuatDasbor(memuat: _memuat, error: _error, onCoba: _muat);
    final d = _d!;
    final laba = (d['laba'] as Map<String, dynamic>?) ?? {};
    final labaKpi = (laba['kpi'] as Map<String, dynamic>?) ?? {};
    final performa = (d['performaToko'] as Map<String, dynamic>?) ?? {};
    final resepHpp = (d['resepHpp'] as Map<String, dynamic>?) ?? {};
    final resepKpi = (resepHpp['kpi'] as Map<String, dynamic>?) ?? {};
    final rekapMenu = ((resepHpp['rekapMenu'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rekapBahan = ((resepHpp['rekapBahan'] as List?) ?? []).cast<Map<String, dynamic>>();
    final trenLaba = ((laba['tren'] as List?) ?? []).cast<Map<String, dynamic>>();

    Map<String, dynamic> p(String key) => (performa[key] as Map<String, dynamic>?) ?? {};

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          BarisKpi(kartu: [
            KartuKpi(label: 'Omzet (14 hari)', nilai: formatRupiahDasbor.format(labaKpi['omzet'] ?? 0), warna: const Color(0xFF1E3A5F)),
            KartuKpi(label: 'Modal (14 hari)', nilai: formatRupiahDasbor.format(labaKpi['modal'] ?? 0), warna: const Color(0xFFC0563D)),
            KartuKpi(label: 'Laba Kotor', nilai: formatRupiahDasbor.format(labaKpi['labaKotor'] ?? 0), warna: const Color(0xFF2E7D32)),
            KartuKpi(label: 'Margin', nilai: '${((labaKpi['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%', warna: const Color(0xFF0284C7)),
          ]),
          const SizedBox(height: 12),
          PanelChart(
            judul: 'Tren Laba Harian (14 hari)',
            child: BarVertikal(
              data: trenLaba.map((e) => (label: '${e['tanggal'] ?? ''}'.split('-').last, nilai: (e['laba'] as num?)?.toDouble() ?? 0)).toList(),
              formatNilai: formatRupiahDasbor.format,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Performa Toko', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {0: FlexColumnWidth(1.4), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1.4)},
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Periode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Pembeli', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      ]),
                      for (final e in [('Harian', p('harian')), ('Mingguan', p('mingguan')), ('Bulanan', p('bulanan'))])
                        TableRow(children: [
                          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(e.$1, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${e.$2['qty'] ?? 0}', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${e.$2['pembeli'] ?? 0}', style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(formatRupiahDasbor.format(e.$2['total'] ?? 0), style: const TextStyle(fontSize: 12))),
                        ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Resep, HPP & Margin', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          BarisKpi(kartu: [
            KartuKpi(label: 'Menu Ber-Resep', nilai: '${resepKpi['menuBerResep'] ?? 0}', warna: const Color(0xFF1E3A5F)),
            KartuKpi(label: 'Rata Margin', nilai: '${((resepKpi['rataMargin'] as num?) ?? 0).toStringAsFixed(1)}%', warna: const Color(0xFF2E7D32)),
            KartuKpi(label: 'Margin Tertipis', nilai: '${resepKpi['marginTertipisNama'] ?? '-'}', warna: Colors.red),
            KartuKpi(label: 'Bahan Terpakai (30h)', nilai: formatRupiahDasbor.format(resepKpi['nilaiBahanTerpakai'] ?? 0), warna: const Color(0xFFB8860B)),
          ]),
          const SizedBox(height: 12),
          if (rekapMenu.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Rekap Menu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...rekapMenu.take(20).map((m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${m['tenant']} · ${m['menu']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${((m['marginPersen'] as num?) ?? 0).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (rekapBahan.isNotEmpty)
            PanelChart(
              judul: 'Pemakaian Bahan Baku (30 hari)',
              child: BarHorizontal(
                data: rekapBahan.map((e) => (label: '${e['nama']}', nilai: (e['nilai'] as num?)?.toDouble() ?? 0)).toList(),
                formatNilai: formatRupiahDasbor.format,
              ),
            ),
        ],
      ),
    );
  }
}
