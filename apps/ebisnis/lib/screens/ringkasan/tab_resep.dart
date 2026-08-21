import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import 'muat_dashboard.dart';

/// Tab 6/9 "Resep, HPP & Margin" -- aksi `resep_hpp_margin`.
///
/// CATATAN: server mengirim `byBahanBaku` sbg `{label, jumlah}`, BUKAN
/// `{label, nilai}` -- referensi Electron (ringkasan-renderer.js) memanggil
/// `buatBarHorizontal` langsung tanpa remap, jadi bar chart bahan-baku di
/// Electron kemungkinan render 0/NaN (field `nilai` yg dibaca chart-nya tidak
/// pernah ada). Di sini di-remap eksplisit ke `nilai: jumlah` supaya benar.
class RingkasanTabResep extends StatefulWidget {
  const RingkasanTabResep({super.key});
  @override
  State<RingkasanTabResep> createState() => _RingkasanTabResepState();
}

class _RingkasanTabResepState extends State<RingkasanTabResep> with JejakGalat {
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
      aksi: 'resep_hpp_margin',
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
    final byBahanBaku = titikDariList(d['byBahanBaku'] as List?,
        labelKey: 'label', nilaiKey: 'jumlah');
    final topMargin =
        ((d['topMargin'] as List?) ?? []).cast<Map<String, dynamic>>();
    final daftarMenu =
        ((d['daftarMenu'] as List?) ?? []).cast<Map<String, dynamic>>();

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
          BarisKpi(kartu: [
            KartuKpi(
                label: 'Total Menu',
                nilai: '${d['totalMenu'] ?? 0}',
                warna: const Color(0xFF1E3A5F)),
            KartuKpi(
                label: 'Rata Margin',
                nilai:
                    '${((d['rataMargin'] as num?) ?? 0).toStringAsFixed(1)}%',
                warna: const Color(0xFF2E7D32)),
            KartuKpi(
                label: 'Margin Terendah',
                nilai: '${d['namaMarginTerendah'] ?? '-'}',
                warna: Colors.red),
            KartuKpi(
                label: 'Bahan Terpakai (30h)',
                nilai: formatRupiahDasbor.format(d['nilaiBahanTerpakai'] ?? 0),
                warna: const Color(0xFFB8860B)),
          ]),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Top 12 Margin Menu',
              child: BarHorizontal(
                  data: topMargin
                      .map((m) => (
                            label: '${m['nama']}',
                            nilai: (m['margin'] as num?)?.toDouble() ?? 0
                          ))
                      .toList(),
                  formatNilai: (v) => '${v.toStringAsFixed(0)}%')),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Bahan Baku Paling Banyak Terpakai (30 hari)',
              child: BarHorizontal(
                  data: byBahanBaku, warna: const Color(0xFFB8860B))),
          const SizedBox(height: 12),
          if (daftarMenu.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Semua Menu',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...daftarMenu.map((m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('${m['nama']} · ${m['kategori']}',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Expanded(
                                child: Text(
                                  'HPP ${formatRupiahDasbor.format(m['hpp'] ?? 0)}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          AppColors.textSecondaryOf(context)),
                                ),
                              ),
                              Text(
                                  '${((m['margin'] as num?) ?? 0).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
        ),
      ],
    );
  }
}
