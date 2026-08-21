import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import 'muat_dashboard.dart';

/// Tab 5/9 "Peringkat Mitra" -- aksi `peringkat_mitra`. Lintas-toko utk akun
/// admin (`semuaToko: true`), terbatas ke toko sendiri utk akun pedagang/kasir.
class RingkasanTabPeringkat extends StatefulWidget {
  const RingkasanTabPeringkat({super.key});
  @override
  State<RingkasanTabPeringkat> createState() => _RingkasanTabPeringkatState();
}

class _RingkasanTabPeringkatState extends State<RingkasanTabPeringkat> with JejakGalat {
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
      aksi: 'peringkat_mitra',
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

  Color _warnaStatus(BuildContext context, String s) {
    switch (s) {
      case 'Tumbuh Pesat':
        return const Color(0xFF2E7D32);
      case 'Bertumbuh':
        return const Color(0xFF0284C7);
      case 'Menurun':
        return Colors.red;
      case 'Baru':
        return const Color(0xFFB8860B);
      default:
        return AppColors.textSecondaryOf(context);
    }
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
    final daftar = ((d['daftar'] as List?) ?? []).cast<Map<String, dynamic>>();
    final top10 = titikDariList(daftar.take(10).toList(),
        labelKey: 'nama', nilaiKey: 'omzet');

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
          if (d['semuaToko'] != true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Akun ini terbatas ke satu toko -- peringkat hanya menampilkan diri sendiri.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondaryOf(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          BarisKpi(kartu: [
            KartuKpi(
                label: 'Total Toko',
                nilai: '${d['totalToko'] ?? 0}',
                warna: const Color(0xFF1E3A5F)),
            KartuKpi(
                label: 'Omzet Tertinggi',
                nilai: '${d['namaOmzetTertinggi'] ?? '-'}',
                warna: const Color(0xFF2E7D32)),
            if (d['pertumbuhanTertinggi'] != null)
              KartuKpi(
                  label: 'Pertumbuhan Tertinggi',
                  nilai: '${d['namaPertumbuhanTertinggi'] ?? '-'}',
                  warna: const Color(0xFF0284C7)),
            if (d['pertumbuhanTerendah'] != null)
              KartuKpi(
                  label: 'Perlu Perhatian',
                  nilai: '${d['namaPertumbuhanTerendah'] ?? '-'}',
                  warna: Colors.red),
          ]),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Top 10 Toko by Omzet',
              child: BarHorizontal(
                  data: top10, formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Semua Toko',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (daftar.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Belum ada data.',
                        style: TextStyle(
                            color: AppColors.textSecondaryOf(context)),
                      ),
                    )
                  else
                    ...daftar.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text('${t['nama']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Expanded(
                                  child: Text(
                                      formatRupiahDasbor
                                          .format(t['omzet'] ?? 0),
                                      style: const TextStyle(fontSize: 11))),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color:
                                        _warnaStatus(context, '${t['status']}')
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('${t['status']}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: _warnaStatus(
                                            context, '${t['status']}'))),
                              ),
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
