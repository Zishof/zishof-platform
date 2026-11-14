import 'package:flutter/material.dart';
import '../../api_client.dart';
import '../../models.dart';
import '../../services/master_offline.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard_charts.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/jejak_galat.dart';

/// Periode filter -- SAMA PERSIS 6 pilihan `MonitorDiskonKantinAction`
/// (ZK) / `KantinHelper.monitorDiskonTimeCond` (server): today/week/month/
/// semester/year/3years. Default "month" (paritas default combobox ZK),
/// BUKAN sentinel "last30" yg dipakai server hanya saat parameter ini
/// SAMA SEKALI tak dikirim (dipertahankan utk RingkasanTabPromo lama).
const _opsiPeriode = [
  ('today', 'Hari Ini'),
  ('week', '7 Hari Terakhir'),
  ('month', 'Bulan Ini'),
  ('semester', '6 Bulan Terakhir'),
  ('year', 'Tahun Ini'),
  ('3years', '3 Tahun Terakhir'),
];

const _opsiJenisDiskon = [
  ('SEMUA', '- Semua Jenis -'),
  ('POTONG_STRUK', 'Potong Langsung di Struk'),
  ('CASHBACK', 'Cashback Saldo'),
];

/// Tab 3/3 "Monitor Diskon" (padanan `monitor_diskon_kantin.jsp` / ZK
/// `MonitorDiskonKantinAction`) -- KPI + tren + top-list, dgn filter
/// Jenis Anggota/Toko/Periode. Aksi `monitor_promo_cashback` (SAMA dgn
/// RingkasanTabPromo, tapi di sini SELALU mengirim `periode` eksplisit
/// supaya dapat semantik filter ZK -- lihat JavaDoc server).
class TabMonitorDiskon extends StatefulWidget {
  const TabMonitorDiskon({super.key});
  @override
  State<TabMonitorDiskon> createState() => _TabMonitorDiskonState();
}

class _TabMonitorDiskonState extends State<TabMonitorDiskon> with JejakGalat {
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _d;
  List<Kategori> _jenisAnggota = [];
  List<Map<String, dynamic>> _daftarAturanMaster = [];
  int? _jenisAnggotaId;
  int? _tokoId;
  String _periode = 'month';
  String _jenisDiskon = 'SEMUA';
  int? _aturanDiskonId;

  @override
  void initState() {
    super.initState();
    _muatDropdown();
    _muat();
  }

  Future<void> _muatDropdown() async {
    try {
      // Filter referensi boleh memakai snapshot terakhir; data monitor tetap
      // online karena periodenya dinamis dan tidak boleh disamarkan sebagai
      // statistik terkini ketika jaringan putus.
      final hasil = await MasterOffline.daftarDenganCache(
          'jenis_anggota_list', {}, 'master:jenis_anggota_pilihan');
      final hasilAturan = await MasterOffline.daftarDenganCache(
          'diskon_list', {'page': 1, 'page_size': 200}, 'master:diskon');
      if (!mounted) return;
      setStateIfMounted(() {
        _jenisAnggota = ((hasil['data'] as List?) ?? [])
            .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
            .toList();
        _daftarAturanMaster = ((hasilAturan['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // Dropdown gagal muat bukan blocker -- filter Jenis Anggota cukup hilang.
    }
  }

  Future<void> _muat() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('monitor_promo_cashback', {
        'periode': _periode,
        if (_jenisAnggotaId != null) 'jenis_anggota_id': _jenisAnggotaId,
        if (Sesi.instance.isAdmin && _tokoId != null) 'toko_id': _tokoId,
        if (_jenisDiskon != 'SEMUA') 'jenis_diskon': _jenisDiskon,
        if (_aturanDiskonId != null) 'aturan_diskon_id': _aturanDiskonId,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (Sesi.instance.isAdmin && Sesi.instance.daftarToko.isNotEmpty)
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<int?>(
                    value: _tokoId,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Toko',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('- Semua Toko -')),
                      ...Sesi.instance.daftarToko.map((t) => DropdownMenuItem<int?>(
                            value: t['id'] as int?,
                            child: Text('${t['nama']}', overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) {
                      _tokoId = v;
                      _muat();
                    },
                  ),
                ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int?>(
                  value: _jenisAnggotaId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Anggota',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('- Semua -')),
                    ..._jenisAnggota.map((k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.nama))),
                  ],
                  onChanged: (v) {
                    _jenisAnggotaId = v;
                    _muat();
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _periode,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Periode',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _opsiPeriode
                      .map((p) => DropdownMenuItem<String>(value: p.$1, child: Text(p.$2)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    _periode = v;
                    _muat();
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  value: _jenisDiskon,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Diskon',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _opsiJenisDiskon
                      .map((p) => DropdownMenuItem<String>(
                            value: p.$1,
                            child: Text(p.$2, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    _jenisDiskon = v;
                    _muat();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  value: _opsiAturanDropdown().any((a) => a['id'] == _aturanDiskonId)
                      ? _aturanDiskonId
                      : null,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aturan Promo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('- Semua Aturan Promo -', overflow: TextOverflow.ellipsis),
                    ),
                    ..._opsiAturanDropdown().map((a) => DropdownMenuItem<int?>(
                          value: a['id'] as int,
                          child: Text(
                            '${a['nama']} (${a['potonganLangsung'] == true ? 'Potong Struk' : 'Cashback'})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) {
                    _aturanDiskonId = v;
                    _muat();
                  },
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Muat Ulang', onPressed: _muat),
            ],
          ),
        ),
        Expanded(
          child: _memuat || _error != null
              ? statusMuatDasbor(
          memuat: _memuat,
          error: _error,
          detail: detailUntuk(_error),
          onCoba: _muat)
              : _isiDasbor(context),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _opsiAturanDropdown() {
    final dariServer = ((_d?['daftarAturanFilter'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => <String, dynamic>{
              'id': (e['id'] as num?)?.toInt() ?? 0,
              'nama': '${e['namaAturan'] ?? ''}'.trim(),
              'potonganLangsung': e['potonganLangsung'] == true,
            })
        .where((e) => (e['id'] as int) > 0 && (e['nama'] as String).isNotEmpty)
        .toList();
    final sumber = dariServer.isNotEmpty
        ? dariServer
        : _daftarAturanMaster
            .map((e) => <String, dynamic>{
                  'id': (e['id'] as num?)?.toInt() ?? 0,
                  'nama': '${e['namaAturan'] ?? ''}'.trim(),
                  'potonganLangsung': e['potonganLangsung'] == true,
                })
            .where((e) => (e['id'] as int) > 0 && (e['nama'] as String).isNotEmpty)
            .toList();
    return sumber.where((a) {
      if (_jenisDiskon == 'POTONG_STRUK') return a['potonganLangsung'] == true;
      if (_jenisDiskon == 'CASHBACK') return a['potonganLangsung'] != true;
      return true;
    }).toList();
  }

  Widget _isiDasbor(BuildContext context) {
    final d = _d!;
    final hanyaPotongStruk = _jenisDiskon == 'POTONG_STRUK';
    final hanyaCashback = _jenisDiskon == 'CASHBACK';
    final tren = ((d['tren'] as List?) ?? []).cast<Map<String, dynamic>>();
    final labelTren = tren.map((t) => '${t['periode']}').toList();
    final seriDiskon = tren
        .map((t) => hanyaCashback ? 0.0 : ((t['diskon'] as num?)?.toDouble() ?? 0.0))
        .toList();
    final seriCashback = tren
        .map((t) => hanyaPotongStruk ? 0.0 : ((t['cashback'] as num?)?.toDouble() ?? 0.0))
        .toList();
    final topProduk = titikDariList(d['topProduk'] as List?);
    final topMember = hanyaPotongStruk
        ? <TitikChart>[]
        : titikDariList(d['topMember'] as List?);
    final aturan = ((d['aturanDiskon'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((a) {
          if (hanyaPotongStruk && a['potonganLangsung'] != true) return false;
          if (hanyaCashback && a['potonganLangsung'] == true) return false;
          if (_aturanDiskonId != null && (a['id'] as num?)?.toInt() != _aturanDiskonId) {
            return false;
          }
          return true;
        })
        .toList();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          BarisKpi(kartu: [
            KartuKpi(
                label: 'Diskon Diberikan',
                nilai: formatRupiahDasbor.format(
                    hanyaCashback ? 0 : (d['diskonDiberikan'] ?? 0)),
                warna: const Color(0xFFC0563D)),
            KartuKpi(
                label: 'Cashback Diberikan',
                nilai: formatRupiahDasbor.format(
                    hanyaPotongStruk ? 0 : (d['cashbackDiberikan'] ?? 0)),
                warna: const Color(0xFF0284C7)),
            KartuKpi(
                label: 'Cashback Dicairkan',
                nilai: formatRupiahDasbor.format(
                    hanyaPotongStruk ? 0 : (d['cashbackDicairkan'] ?? 0)),
                warna: const Color(0xFF2E7D32)),
            KartuKpi(
                label: 'Total Saldo Mengendap',
                nilai: formatRupiahDasbor.format(
                    hanyaPotongStruk ? 0 : (d['saldoMengendap'] ?? 0)),
                warna: const Color(0xFFB8860B)),
          ]),
          const SizedBox(height: 12),
          PanelChart(
            judul: 'Tren Pemberian Promo & Diskon',
            child: GroupedBarVertikal(
              labels: labelTren,
              seri1: seriDiskon,
              seri2: seriCashback,
              labelSeri1: 'Diskon',
              labelSeri2: 'Cashback',
              formatNilai: formatRupiahDasbor.format,
            ),
          ),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Top 5 Produk Promo Terbesar',
              child: BarHorizontal(data: topProduk, formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          PanelChart(
              judul: 'Member Penerima Cashback Terbesar',
              child: BarHorizontal(
                  data: topMember,
                  warna: const Color(0xFF0284C7),
                  formatNilai: formatRupiahDasbor.format)),
          const SizedBox(height: 12),
          if (aturan.isNotEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dampak Aturan Promo',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('Seberapa sering tiap aturan promo dipakai dan total biayanya.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 10),
                    ...aturan.take(50).map((a) {
                      final potonganLangsung = a['potonganLangsung'] == true;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text('${a['namaAturan']}',
                                    style: const TextStyle(fontSize: 12),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: (potonganLangsung ? const Color(0xFFC0563D) : const Color(0xFF0284C7))
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(potonganLangsung ? 'Potong Struk' : 'Cashback',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: potonganLangsung ? const Color(0xFFC0563D) : const Color(0xFF0284C7))),
                            ),
                            Text('${a['dipakai']}x',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context))),
                            const SizedBox(width: 8),
                            Text(formatRupiahDasbor.format(a['totalBiaya'] ?? 0),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
