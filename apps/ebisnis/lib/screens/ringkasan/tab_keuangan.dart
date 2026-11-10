import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';
import '../../widgets/penanda_data_tersimpan.dart';
import '../../widgets/rincian_intip_dialog.dart';
import 'muat_dashboard.dart';

/// Tab 2/9 "Keuangan & Kinerja" -- aksi `dashboard_keuangan` (semua jendela
/// dihitung SAMPAI tanggal acuan; default hari ini). Berisi 3 sub-bagian:
/// laba (KPI+tren), performa toko (harian/mingguan/bulanan), dan
/// Resep/HPP/Margin ringkas (KPI+tabel menu+tabel bahan baku).
class RingkasanTabKeuangan extends StatefulWidget {
  const RingkasanTabKeuangan({super.key});
  @override
  State<RingkasanTabKeuangan> createState() => _RingkasanTabKeuanganState();
}

class _RingkasanTabKeuanganState extends State<RingkasanTabKeuangan> with JejakGalat {
  static final _formatTanggalServer = DateFormat('yyyy-MM-dd');
  bool _memuat = true;
  String? _error;

  /// Benar selama yang tampil masih salinan lokal (server belum menjawab,
  /// atau jawabannya tidak dapat diproses) -- menyalakan PenandaDataTersimpan.
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;
  Map<String, dynamic>? _d;
  DateTime _tanggalAcuan =
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool get _acuanBukanHariIni {
    final n = DateTime.now();
    return _tanggalAcuan.year != n.year ||
        _tanggalAcuan.month != n.month ||
        _tanggalAcuan.day != n.day;
  }

  String get _sufiksAcuan => _acuanBukanHariIni
      ? ' • s.d. ${DateFormat('dd-MM-yyyy').format(_tanggalAcuan)}'
      : '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _pilihTanggalAcuan() async {
    final v = await showDatePicker(
      context: context,
      initialDate: _tanggalAcuan,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Pilih tanggal acuan dashboard',
    );
    if (v == null || !mounted) return;
    setStateIfMounted(() => _tanggalAcuan = DateTime(v.year, v.month, v.day));
    await _muat();
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
      aksi: 'dashboard_keuangan',
      payload: {'tanggalAcuan': _formatTanggalServer.format(_tanggalAcuan)},
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
    if (_memuat || _error != null) return statusMuatDasbor(
          memuat: _memuat,
          error: _error,
          detail: detailUntuk(_error),
          onCoba: _muat);
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
          Row(
            children: [
              const Expanded(
                child: Text('Tanggal Acuan',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                onPressed: _memuat ? null : _pilihTanggalAcuan,
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(_formatTanggalServer.format(_tanggalAcuan)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BarisKpi(kartu: [
            KartuKpi(
              label: 'Omzet (14 hari)$_sufiksAcuan',
              nilai: formatRupiahDasbor.format(labaKpi['omzet'] ?? 0),
              warna: const Color(0xFF1E3A5F),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Tren Omzet & Laba Harian (14 Hari)',
                subjudul:
                    'Total Omzet: ${formatRupiahDasbor.format(labaKpi['omzet'] ?? 0)} | Laba Kotor: ${formatRupiahDasbor.format(labaKpi['labaKotor'] ?? 0)}',
                kolom: const ['No', 'Tanggal', 'Omzet', 'Modal / HPP', 'Laba Kotor'],
                baris: trenLaba
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tanggal'] ?? '-',
                          formatRupiahDasbor.format(e.value['omzet'] ?? 0),
                          formatRupiahDasbor.format(e.value['modal'] ?? 0),
                          formatRupiahDasbor.format(e.value['laba'] ?? 0),
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'Modal / HPP (14 hari)$_sufiksAcuan',
              nilai: formatRupiahDasbor.format(labaKpi['modal'] ?? 0),
              warna: const Color(0xFFC0563D),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Modal / HPP (14 Hari)',
                subjudul: 'Total Modal: ${formatRupiahDasbor.format(labaKpi['modal'] ?? 0)}',
                kolom: const ['No', 'Tanggal', 'Omzet', 'Modal / HPP', 'Laba Kotor'],
                baris: trenLaba
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tanggal'] ?? '-',
                          formatRupiahDasbor.format(e.value['omzet'] ?? 0),
                          formatRupiahDasbor.format(e.value['modal'] ?? 0),
                          formatRupiahDasbor.format(e.value['laba'] ?? 0),
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'Laba Kotor (GM Rp)$_sufiksAcuan',
              nilai: formatRupiahDasbor.format(labaKpi['labaKotor'] ?? 0),
              warna: const Color(0xFF2E7D32),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Laba Kotor / Gross Margin (Rp)',
                subjudul:
                    'Laba Kotor: ${formatRupiahDasbor.format(labaKpi['labaKotor'] ?? 0)} (GM%: ${((labaKpi['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%)',
                kolom: const ['No', 'Tanggal', 'Omzet', 'Modal / HPP', 'Laba Kotor'],
                baris: trenLaba
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tanggal'] ?? '-',
                          formatRupiahDasbor.format(e.value['omzet'] ?? 0),
                          formatRupiahDasbor.format(e.value['modal'] ?? 0),
                          formatRupiahDasbor.format(e.value['laba'] ?? 0),
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'GM (%) Margin$_sufiksAcuan',
              nilai: '${((labaKpi['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
              warna: const Color(0xFF0284C7),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Gross Margin (%) per Menu / Produk',
                subjudul:
                    'Rata-rata Margin: ${((labaKpi['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
                kolom: const ['No', 'Tenant / Toko', 'Produk / Menu', 'Margin (%)'],
                baris: rekapMenu
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tenant'] ?? '-',
                          e.value['menu'] ?? '-',
                          '${((e.value['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
                        ])
                    .toList(),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          PanelChart(
            judul: 'Tren Laba Harian (14 hari)$_sufiksAcuan',
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
                  Text('Performa Toko$_sufiksAcuan', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
            KartuKpi(
              label: 'Menu Ber-Resep',
              nilai: '${resepKpi['menuBerResep'] ?? 0}',
              warna: const Color(0xFF1E3A5F),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Rekap Menu & Margin HPP',
                subjudul: 'Total Menu Ber-Resep: ${resepKpi['menuBerResep'] ?? 0}',
                kolom: const ['No', 'Tenant', 'Nama Menu', 'Margin (%)'],
                baris: rekapMenu
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tenant'] ?? '-',
                          e.value['menu'] ?? '-',
                          '${((e.value['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'Rata Margin',
              nilai: '${((resepKpi['rataMargin'] as num?) ?? 0).toStringAsFixed(1)}%',
              warna: const Color(0xFF2E7D32),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Margin Menu',
                subjudul:
                    'Rata-rata Margin: ${((resepKpi['rataMargin'] as num?) ?? 0).toStringAsFixed(1)}%',
                kolom: const ['No', 'Tenant', 'Nama Menu', 'Margin (%)'],
                baris: rekapMenu
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tenant'] ?? '-',
                          e.value['menu'] ?? '-',
                          '${((e.value['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'Margin Tertipis',
              nilai: '${resepKpi['marginTertipisNama'] ?? '-'}',
              warna: Colors.red,
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Menu Berdasarkan Margin',
                subjudul: 'Margin Tertipis: ${resepKpi['marginTertipisNama'] ?? '-'}',
                kolom: const ['No', 'Tenant', 'Nama Menu', 'Margin (%)'],
                baris: rekapMenu
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['tenant'] ?? '-',
                          e.value['menu'] ?? '-',
                          '${((e.value['marginPersen'] as num?) ?? 0).toStringAsFixed(1)}%',
                        ])
                    .toList(),
              ),
            ),
            KartuKpi(
              label: 'Bahan Terpakai (30h)$_sufiksAcuan',
              nilai: formatRupiahDasbor.format(resepKpi['nilaiBahanTerpakai'] ?? 0),
              warna: const Color(0xFFB8860B),
              onTap: () => tampilkanRincianKlikDialog(
                context,
                judul: 'Rincian Pemakaian Bahan Baku (30 Hari)',
                subjudul:
                    'Total Nilai Pemakaian: ${formatRupiahDasbor.format(resepKpi['nilaiBahanTerpakai'] ?? 0)}',
                kolom: const ['No', 'Nama Bahan Baku', 'Nilai Pemakaian'],
                baris: rekapBahan
                    .asMap()
                    .entries
                    .map((e) => <Object?>[
                          e.key + 1,
                          e.value['nama'] ?? '-',
                          formatRupiahDasbor.format(e.value['nilai'] ?? 0),
                        ])
                    .toList(),
              ),
            ),
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
              judul: 'Pemakaian Bahan Baku (30 hari)$_sufiksAcuan',
              child: BarHorizontal(
                data: rekapBahan.map((e) => (label: '${e['nama']}', nilai: (e['nilai'] as num?)?.toDouble() ?? 0)).toList(),
                formatNilai: formatRupiahDasbor.format,
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
