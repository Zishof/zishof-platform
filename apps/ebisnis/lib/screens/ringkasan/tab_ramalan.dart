import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import 'muat_dashboard.dart';

/// Tab 7/9 "Ramalan Penjualan" -- aksi `ramalan_penjualan`. Prediksi dihitung
/// SERVER-SIDE (regresi linear sederhana atas 14 titik transaksi harian) --
/// klien murni menampilkan angka yg sudah jadi, tidak menghitung ulang.
class RingkasanTabRamalan extends StatefulWidget {
  const RingkasanTabRamalan({super.key});
  @override
  State<RingkasanTabRamalan> createState() => _RingkasanTabRamalanState();
}

class _RingkasanTabRamalanState extends State<RingkasanTabRamalan> with JejakGalat {
  bool _memuat = true;
  String? _error;

  /// Benar selama yang tampil masih salinan lokal (server belum menjawab,
  /// atau jawabannya tidak dapat diproses) -- menyalakan PenandaDataTersimpan.
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;
  Map<String, dynamic>? _d;

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
    // Salinan lokal ditampilkan lebih dahulu bila ada, lalu ditimpa angka
    // server. Galat hanya muncul bila memang tidak ada yang bisa ditampilkan.
    await muatTabDashboard(
      aksi: 'ramalan_penjualan',
      payload: const <String, dynamic>{},
      masihAktif: () => mounted,
      onData: (data, dariCache, disimpanPada) => setStateIfMounted(() {
        _d = data;
        _dariCache = dariCache;
        _cacheDisimpanPada = disimpanPada;
      }),
      onError: (e) => setStateIfMounted(() => _error = terapkanGalat(e)),
    );
    if (mounted) setStateIfMounted(() => _memuat = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat || _error != null)
      return statusMuatDasbor(
          memuat: _memuat,
          error: _error,
          detail: detailUntuk(_error),
          onCoba: _muat);
    final d = _d!;
    final naik = d['naik'] == true;
    final trenTransaksi = titikDariList(d['trenTransaksi'] as List?);
    final trenOmzet = titikDariList(d['trenOmzet'] as List?);
    final proyeksi = titikDariList(d['proyeksi'] as List?);

    // Penanda salinan tersimpan duduk DI ATAS isi, sehingga angka di
    // bawahnya tidak pernah terbaca sebagai data terkini. Saat tidak
    // tampil ia menjadi SizedBox.shrink -- tata letaknya sama seperti
    // semula.
    return Column(
      children: [
        PenandaDataTersimpan(
            tampil: _dariCache, diperbaruiPada: _cacheDisimpanPada),
        Expanded(
          child: RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.warning),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Angka di halaman ini adalah estimasi berdasarkan tren 14 hari terakhir, bukan jaminan.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textPrimaryOf(context)),
                  ),
                ),
              ],
            ),
          ),
          BarisKpi(kartu: [
            KartuKpi(
                label: 'Total Transaksi (14h)',
                nilai:
                    '${(d['totalTransaksi'] as num?)?.toStringAsFixed(0) ?? 0}',
                warna: const Color(0xFF1E3A5F)),
            KartuKpi(
                label: 'Rata-rata/hari',
                nilai: '${(d['rataRata'] as num?)?.toStringAsFixed(1) ?? 0}',
                warna: const Color(0xFF0284C7)),
            KartuKpi(
                label: 'Prediksi Besok',
                nilai:
                    '${(d['prediksiBerikutnya'] as num?)?.toStringAsFixed(0) ?? 0}',
                warna: const Color(0xFF2E7D32)),
            KartuKpi(
              label: 'Arah Tren',
              nilai:
                  '${naik ? "Naik" : "Turun"} ${((d['persenTren'] as num?) ?? 0).toStringAsFixed(1)}%',
              warna: naik ? const Color(0xFF2E7D32) : Colors.red,
            ),
          ]),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Tren Jumlah Transaksi (14 hari)',
              child: BarVertikal(data: trenTransaksi)),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Tren Omzet (14 hari)',
              child: BarVertikal(
                  data: trenOmzet,
                  warna: const Color(0xFF2E7D32),
                  formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Proyeksi 3 Hari ke Depan',
              child: BarHorizontal(
                  data: proyeksi,
                  warna: const Color(0xFFB8860B),
                  tampilkanPeringkat: false)),
        ],
      ),
    ),
        ),
      ],
    );
  }
}
