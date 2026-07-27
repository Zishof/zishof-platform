import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';

/// Tab 8/9 "Monitor Promo & Cashback" -- aksi `monitor_promo_cashback`.
class RingkasanTabPromo extends StatefulWidget {
  const RingkasanTabPromo({super.key});
  @override
  State<RingkasanTabPromo> createState() => _RingkasanTabPromoState();
}

class _RingkasanTabPromoState extends State<RingkasanTabPromo> {
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
      final hasil = await ApiClient.instance.aksi('monitor_promo_cashback');
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
    final topProduk = titikDariList(d['topProduk'] as List?);
    final topMember = titikDariList(d['topMember'] as List?);
    final aturan = ((d['aturanDiskon'] as List?) ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          BarisKpi(kartu: [
            KartuKpi(label: 'Diskon Diberikan (30h)', nilai: formatRupiahDasbor.format(d['diskonDiberikan'] ?? 0), warna: const Color(0xFFC0563D)),
            KartuKpi(label: 'Cashback Diberikan (30h)', nilai: formatRupiahDasbor.format(d['cashbackDiberikan'] ?? 0), warna: const Color(0xFF0284C7)),
            KartuKpi(label: 'Cashback Dicairkan (30h)', nilai: formatRupiahDasbor.format(d['cashbackDicairkan'] ?? 0), warna: const Color(0xFF2E7D32)),
            KartuKpi(label: 'Saldo Mengendap', nilai: formatRupiahDasbor.format(d['saldoMengendap'] ?? 0), warna: const Color(0xFFB8860B)),
          ]),
          const SizedBox(height: 12),
          PanelChart(judul: 'Top 5 Produk (Diskon+Cashback, 30 hari)', child: BarHorizontal(data: topProduk, formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          PanelChart(judul: 'Top 8 Member (Cashback, 30 hari)', child: BarHorizontal(data: topMember, warna: const Color(0xFF0284C7), formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          if (aturan.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dampak Aturan Diskon (30 hari)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...aturan.take(50).map((a) {
                      final potonganLangsung = a['potonganLangsung'] == true;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text('${a['namaAturan']}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: (potonganLangsung ? const Color(0xFFC0563D) : const Color(0xFF0284C7)).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(potonganLangsung ? 'Potong Struk' : 'Cashback',
                                  style: TextStyle(fontSize: 10, color: potonganLangsung ? const Color(0xFFC0563D) : const Color(0xFF0284C7))),
                            ),
                            Text('${a['dipakai']}x', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                            const SizedBox(width: 8),
                            Text(formatRupiahDasbor.format(a['totalBiaya'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
