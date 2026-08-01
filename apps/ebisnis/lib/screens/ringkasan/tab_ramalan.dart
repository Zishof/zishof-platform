import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../widgets/dashboard_charts.dart';

/// Tab 7/9 "Ramalan Penjualan" -- aksi `ramalan_penjualan`. Prediksi dihitung
/// SERVER-SIDE (regresi linear sederhana atas 14 titik transaksi harian) --
/// klien murni menampilkan angka yg sudah jadi, tidak menghitung ulang.
class RingkasanTabRamalan extends StatefulWidget {
  const RingkasanTabRamalan({super.key});
  @override
  State<RingkasanTabRamalan> createState() => _RingkasanTabRamalanState();
}

class _RingkasanTabRamalanState extends State<RingkasanTabRamalan> {
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
      final hasil = await ApiClient.instance.aksi('ramalan_penjualan');
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
    final naik = d['naik'] == true;
    final trenTransaksi = titikDariList(d['trenTransaksi'] as List?);
    final trenOmzet = titikDariList(d['trenOmzet'] as List?);
    final proyeksi = titikDariList(d['proyeksi'] as List?);

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Angka di halaman ini adalah estimasi berdasarkan tren 14 hari terakhir, bukan jaminan.', style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900)),
                ),
              ],
            ),
          ),
          BarisKpi(kartu: [
            KartuKpi(label: 'Total Transaksi (14h)', nilai: '${(d['totalTransaksi'] as num?)?.toStringAsFixed(0) ?? 0}', warna: const Color(0xFF1E3A5F)),
            KartuKpi(label: 'Rata-rata/hari', nilai: '${(d['rataRata'] as num?)?.toStringAsFixed(1) ?? 0}', warna: const Color(0xFF0284C7)),
            KartuKpi(label: 'Prediksi Besok', nilai: '${(d['prediksiBerikutnya'] as num?)?.toStringAsFixed(0) ?? 0}', warna: const Color(0xFF2E7D32)),
            KartuKpi(
              label: 'Arah Tren',
              nilai: '${naik ? "Naik" : "Turun"} ${((d['persenTren'] as num?) ?? 0).toStringAsFixed(1)}%',
              warna: naik ? const Color(0xFF2E7D32) : Colors.red,
            ),
          ]),
          const SizedBox(height: 12),
          PanelChart(judul: 'Tren Jumlah Transaksi (14 hari)', child: BarVertikal(data: trenTransaksi)),
          const SizedBox(height: 12),
          PanelChart(judul: 'Tren Omzet (14 hari)', child: BarVertikal(data: trenOmzet, warna: const Color(0xFF2E7D32), formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          PanelChart(judul: 'Proyeksi 3 Hari ke Depan', child: BarHorizontal(data: proyeksi, warna: const Color(0xFFB8860B), tampilkanPeringkat: false)),
        ],
      ),
    );
  }
}
