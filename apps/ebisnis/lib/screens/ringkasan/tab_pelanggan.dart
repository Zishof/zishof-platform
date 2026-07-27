import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';

const _periodeOpsi = ['harian', 'mingguan', 'bulanan', 'semester', 'tahunan'];

/// Tab 4/9 "Perilaku Pelanggan" -- aksi `dashboard_pelanggan` (param
/// `periode`). Jam sibuk (30 hari, di-bucket ulang jadi 24 jam penuh di sisi
/// klien -- server hanya kirim jam yg ada transaksinya) + 10 pembeli
/// terloyal (30 hari) + rekap pelanggan terloyal per periode terpilih.
class RingkasanTabPelanggan extends StatefulWidget {
  const RingkasanTabPelanggan({super.key});
  @override
  State<RingkasanTabPelanggan> createState() => _RingkasanTabPelangganState();
}

class _RingkasanTabPelangganState extends State<RingkasanTabPelanggan> {
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
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('dashboard_pelanggan', {'periode': _periode});
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
    final jamSibukMentah = ((d['jamSibuk'] as List?) ?? []).cast<Map<String, dynamic>>();
    final petaJam = {for (final e in jamSibukMentah) (e['jam'] as num).toInt(): (e['jumlah'] as num).toDouble()};
    final jamSibuk = List.generate(24, (jam) => (label: '$jam', nilai: petaJam[jam] ?? 0.0));
    final terloyal = titikDariList(d['pembeliTerloyal'] as List?, labelKey: 'nama', nilaiKey: 'total');
    final rekapTerloyal = ((d['rekapPelangganTerloyal'] as List?) ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          PanelChart(judul: 'Jam Sibuk (30 hari)', child: BarVertikal(data: jamSibuk, warna: const Color(0xFFB8860B))),
          const SizedBox(height: 12),
          PanelChart(judul: '10 Pembeli Terloyal (30 hari)', child: BarHorizontal(data: terloyal, formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Rekap Pelanggan Terloyal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      DropdownButton<String>(
                        value: _periode,
                        items: _periodeOpsi.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _periode = v);
                            _muat();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (rekapTerloyal.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Belum ada data.', style: TextStyle(color: Colors.black45)))
                  else
                    ...rekapTerloyal.take(30).map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('${r['nama']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              Text('${r['frekuensi']}x', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(formatRupiahDasbor.format(r['total'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
