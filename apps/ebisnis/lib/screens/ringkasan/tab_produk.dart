import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../api_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

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

class _RingkasanTabProdukState extends State<RingkasanTabProduk> with JejakGalat {
  static final _formatTanggalServer = DateFormat('yyyy-MM-dd');
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  String _periode = 'bulanan';
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

  /// Produk terpilih di dropdown "Jam Sibuk per Produk" -- null berarti
  /// belum dipilih manual, jatuh ke entri PERTAMA (`jamSibukPerProduk` sudah
  /// dibatasi top 5 terlaris server-side, lihat JavaDoc `prosesDashboardProduk`).
  int? _produkJamSibukTerpilih;

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
      final hasil = await ApiClient.instance.aksi('dashboard_produk', {
        'periode': _periode,
        'tanggalAcuan': _formatTanggalServer.format(_tanggalAcuan),
      });
      if (!mounted) return;
      setStateIfMounted(() => _d = hasil);
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _error = terapkanGalat(e));
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
    if (_memuat || _error != null)
      return statusMuatDasbor(
          memuat: _memuat,
          error: _error,
          detail: detailUntuk(_error),
          onCoba: _muat);
    final d = _d!;
    final stok = ((d['stok'] as List?) ?? []).cast<Map<String, dynamic>>();
    final bahanBaku = (d['bahanBaku'] as Map<String, dynamic>?) ?? {};
    final bahanKpi = (bahanBaku['kpi'] as Map<String, dynamic>?) ?? {};
    final bahanList =
        ((bahanBaku['list'] as List?) ?? []).cast<Map<String, dynamic>>();
    final rekon = (d['rekonsiliasiAset'] as Map<String, dynamic>?) ?? {};
    final rekonKpi = (rekon['kpi'] as Map<String, dynamic>?) ?? {};
    final rekonList =
        ((rekon['list'] as List?) ?? []).cast<Map<String, dynamic>>();
    final terlaris = titikDariList(d['produkTerlaris'] as List?,
        labelKey: 'nama', nilaiKey: 'qty');
    final metodeBayar = titikDariList(d['metodeBayar'] as List?,
        labelKey: 'nama', nilaiKey: 'total');
    final rekapTerlaris = ((d['rekapProdukTerlaris'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final kurangLaku = titikDariList(d['produkKurangLaku'] as List?,
        labelKey: 'nama', nilaiKey: 'terjual');
    final jamSibukPerProduk = ((d['jamSibukPerProduk'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
    final perputaranStok =
        ((d['perputaranStok'] as List?) ?? []).cast<Map<String, dynamic>>();
    final kepuasanPelanggan =
        (d['kepuasanPelanggan'] as Map<String, dynamic>?) ?? {};

    final entriJamSibuk = jamSibukPerProduk.isEmpty
        ? null
        : jamSibukPerProduk.firstWhere(
            (e) => (e['produkId'] as num?)?.toInt() == _produkJamSibukTerpilih,
            orElse: () => jamSibukPerProduk.first);
    final jamSibukProduk = entriJamSibuk == null
        ? <TitikChart>[]
        : List.generate(24, (jam) {
            final arr = (entriJamSibuk['jam'] as List?) ?? const [];
            final nilai = jam < arr.length ? (arr[jam] as num?) ?? 0 : 0;
            return (label: '$jam', nilai: nilai.toDouble());
          });

    return RefreshIndicator(
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
          if (stok.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Peringatan Stok',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ...stok.take(30).map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text('${s['namaProduk']}',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              Text('${s['sisaStok']}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: _warnaStatus('${s['status']}')
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text('${s['status']}',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: _warnaStatus('${s['status']}'))),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          BarisKpi(kartu: [
            KartuKpi(
              label: 'Kepuasan Pelanggan (30 hari)$_sufiksAcuan',
              nilai:
                  '★ ${((kepuasanPelanggan['rataRating'] as num?) ?? 0).toStringAsFixed(1)} · ${kepuasanPelanggan['jumlahResponden'] ?? 0} responden',
              warna: const Color(0xFFB8860B),
            ),
          ]),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Produk Terlaris (30 hari)$_sufiksAcuan',
              child: BarHorizontal(data: terlaris)),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Komposisi Metode Bayar (30 hari)$_sufiksAcuan',
              child: StackProporsional(data: metodeBayar)),
          const SizedBox(height: 12),
          if (jamSibukPerProduk.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Jam Sibuk per Produk (30 hari)$_sufiksAcuan',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        DropdownButton<int>(
                          value: (entriJamSibuk?['produkId'] as num?)?.toInt(),
                          items: jamSibukPerProduk
                              .map((e) => DropdownMenuItem(
                                    value: (e['produkId'] as num).toInt(),
                                    child: Text('${e['nama']}',
                                        style: const TextStyle(fontSize: 12)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setStateIfMounted(
                                  () => _produkJamSibukTerpilih = v);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    BarVertikal(
                        data: jamSibukProduk, warna: const Color(0xFF0284C7)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text('Bahan Baku & Estimasi Habis',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          BarisKpi(kartu: [
            KartuKpi(
                label: 'Dipantau',
                nilai: '${bahanKpi['dipantau'] ?? 0}',
                warna: const Color(0xFF1E3A5F)),
            KartuKpi(
                label: 'Segera Habis',
                nilai: '${bahanKpi['segeraHabis'] ?? 0}',
                warna: Colors.red),
            KartuKpi(
                label: 'Paling Mendesak',
                nilai: '${bahanKpi['palingMendesakNama'] ?? '-'}',
                warna: Colors.orange),
            KartuKpi(
                label: 'Nilai Stok',
                nilai: formatRupiahDasbor.format(bahanKpi['nilaiStok'] ?? 0),
                warna: const Color(0xFF2E7D32)),
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
                                Expanded(
                                    child: Text('${b['nama']}',
                                        style: const TextStyle(fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                                Text(
                                  b['estimasiHari'] != null
                                      ? '~${b['estimasiHari']} hari lagi'
                                      : '-',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          AppColors.textSecondaryOf(context)),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          if ((rekonKpi['tertaut'] ?? 0) != 0 || rekonList.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Rekonsiliasi Aset',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            BarisKpi(kartu: [
              KartuKpi(
                  label: 'Tertaut',
                  nilai: '${rekonKpi['tertaut'] ?? 0}',
                  warna: const Color(0xFF1E3A5F)),
              KartuKpi(
                  label: 'Stok Cocok',
                  nilai: '${rekonKpi['stokCocok'] ?? 0}',
                  warna: const Color(0xFF2E7D32)),
              KartuKpi(
                  label: 'Perlu Dicek',
                  nilai: '${rekonKpi['perluDicek'] ?? 0}',
                  warna: Colors.orange),
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
                        Text('Rekap Produk Terlaris$_sufiksAcuan',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        DropdownButton<String>(
                          value: _periode,
                          items: _periodeOpsi
                              .map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(p,
                                      style: const TextStyle(fontSize: 12))))
                              .toList(),
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
                              Expanded(
                                  child: Text('${r['nama']}',
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              Text('${r['qty']}x',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(formatRupiahDasbor.format(r['total'] ?? 0),
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
          if (perputaranStok.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Perputaran Stok (Turnover)$_sufiksAcuan',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: perputaranStok.take(20).map((t) {
                    final perputaran = (t['perputaran'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text('${t['nama']}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                                'Terjual ${formatAngkaDasbor.format(t['qtyTerjual'] ?? 0)}',
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.right),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                                'Stok ${formatAngkaDasbor.format(t['stokKini'] ?? 0)}',
                                style: const TextStyle(fontSize: 11),
                                textAlign: TextAlign.right),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text('${perputaran.toStringAsFixed(2)}x',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          PanelChart(
            judul: 'Produk Kurang Laku (≤5 terjual/30 hari)$_sufiksAcuan',
            child: BarHorizontal(
              data: kurangLaku,
              warna: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
