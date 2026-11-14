import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  ('SEMUA', '- Semua Jenis Diskon -'),
  ('DISKON_GRUP', 'Diskon Grup (Promo Produk)'),
  ('ATURAN_DISKON', 'Aturan Diskon (Member/Umum)'),
  ('POTONG_STRUK', 'Potong Langsung di Struk'),
  ('CASHBACK', 'Cashback Saldo'),
];

/// Tab "Monitor Diskon" (padanan `monitor_diskon_kantin.jsp` / ZK
/// `MonitorDiskonKantinAction`) -- KPI + tren + top-list + dampak aturan &
/// grup promo, dgn filter Toko, Jenis/Tipe Anggota, Periode, Jenis Diskon
/// (termasuk Diskon Grup & Aturan Diskon Biasa), serta Aturan / Grup Promo.
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
  List<Kategori> _tipeAnggota = [];
  List<Map<String, dynamic>> _daftarAturanMaster = [];
  List<Map<String, dynamic>> _daftarGrupMaster = [];
  final Map<int, Set<int>> _produkPerGrup = {};
  final Map<int, Set<String>> _namaProdukPerGrup = {};
  int? _jenisAnggotaId;
  int? _tipeAnggotaId;
  int? _tokoId;
  String _periode = 'month';
  String _jenisDiskon = 'SEMUA';
  int? _aturanDiskonId;

  @override
  void initState() {
    super.initState();
    _inisialisasi();
  }

  Future<void> _inisialisasi() async {
    await _muatDropdown();
    await _muat();
  }

  Future<void> _muatDropdown() async {
    try {
      final hasilJenis = await MasterOffline.daftarDenganCache(
          'jenis_anggota_list', {}, 'master:jenis_anggota_pilihan');
      final hasilTipe = await MasterOffline.daftarDenganCache(
          'tipe_anggota_list', {}, 'master:tipe_anggota_pilihan');
      final hasilAturan = await MasterOffline.daftarDenganCache(
          'diskon_list', {'page': 1, 'page_size': 200}, 'master:diskon');
      final hasilGrup = await MasterOffline.daftarDenganCache('diskon_grup_list',
          {'page': 1, 'page_size': 200}, 'master:diskon_grup');
      final grupList = ((hasilGrup['data'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      for (final g in grupList) {
        final gid = (g['id'] as num?)?.toInt();
        if (gid == null || gid <= 0) continue;
        try {
          final det = await ApiClient.instance
              .aksi('diskon_grup_detail', {'id': gid});
          final rows = ((det['data'] as List?) ?? []).whereType<Map>();
          final setPid = <int>{};
          final setNama = <String>{};
          for (final r in rows) {
            final pid = (r['produkId'] ?? r['id'] ?? r['produk_id']);
            final pidInt = pid is num ? pid.toInt() : int.tryParse('$pid');
            if (pidInt != null && pidInt > 0) setPid.add(pidInt);
            final nm = '${r['produkNama'] ?? r['nama'] ?? ''}'
                .trim()
                .toLowerCase();
            if (nm.isNotEmpty) setNama.add(nm);
          }
          _produkPerGrup[gid] = setPid;
          _namaProdukPerGrup[gid] = setNama;
        } catch (_) {}
      }

      if (!mounted) return;
      setStateIfMounted(() {
        _jenisAnggota = ((hasilJenis['data'] as List?) ?? [])
            .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
            .toList();
        _tipeAnggota = ((hasilTipe['data'] as List?) ?? [])
            .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
            .toList();
        _daftarAturanMaster = ((hasilAturan['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _daftarGrupMaster = grupList;
      });
    } catch (_) {
      // Dropdown gagal muat bukan blocker.
    }
  }

  (String, String) _rentangTanggalPeriode(String periode) {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');
    DateTime mulai;
    switch (periode) {
      case 'today':
        mulai = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        mulai = now.subtract(const Duration(days: 7));
        break;
      case 'semester':
        mulai = DateTime(now.year, now.month - 6, now.day);
        break;
      case 'year':
        mulai = DateTime(now.year, 1, 1);
        break;
      case '3years':
        mulai = DateTime(now.year - 3, now.month, now.day);
        break;
      case 'month':
      default:
        mulai = DateTime(now.year, now.month, 1);
        break;
    }
    return (fmt.format(mulai), fmt.format(now));
  }

  int? _cariGrupUntukItem(int? produkId, String namaProduk, double harga,
      double qty, double diskon) {
    final nmBersih = namaProduk.trim().toLowerCase();
    final kandidat = <Map<String, dynamic>>[];
    for (final g in _daftarGrupMaster) {
      if (g['aktif'] == false) continue;
      final gid = (g['id'] as num?)?.toInt();
      if (gid == null || gid <= 0) continue;
      final semuaProduk =
          (g['berlakuSemuaProduk'] ?? g['berlaku_semua_produk']) == true;
      final setPid = _produkPerGrup[gid] ?? const <int>{};
      final setNama = _namaProdukPerGrup[gid] ?? const <String>{};
      final cocokProduk = semuaProduk ||
          (produkId != null && setPid.contains(produkId)) ||
          (nmBersih.isNotEmpty && setNama.contains(nmBersih));
      if (cocokProduk) {
        kandidat.add(g);
      }
    }
    if (kandidat.isEmpty) return null;
    if (kandidat.length == 1) return (kandidat.first['id'] as num?)?.toInt();

    final subtotal = harga * (qty <= 0 ? 1 : qty);
    final persenAktual = subtotal > 0 ? (diskon / subtotal) * 100.0 : 0.0;
    Map<String, dynamic>? terbaik;
    double selisihTerbaik = double.infinity;
    for (final g in kandidat) {
      final persenGrup = ((g['persentase'] as num?) ?? 0).toDouble();
      final selisih = (persenGrup - persenAktual).abs();
      if (selisih < selisihTerbaik) {
        selisihTerbaik = selisih;
        terbaik = g;
      }
    }
    return ((terbaik ?? kandidat.first)['id'] as num?)?.toInt();
  }

  Future<Map<String, dynamic>> _perkayaDariRincianProduk(
      Map<String, dynamic> hasilAwal) async {
    final sudahAdaGrupServer = hasilAwal['daftarGrupFilter'] is List;
    if (sudahAdaGrupServer) return hasilAwal;

    final hasil = Map<String, dynamic>.from(hasilAwal);
    try {
      final (tglMulai, tglSampai) = _rentangTanggalPeriode(_periode);
      final semuaItem = <Map<String, dynamic>>[];
      for (var hal = 1; hal <= 5; hal++) {
        final rincian = await ApiClient.instance.aksi('laporan_rincian_produk', {
          'tglMulai': tglMulai,
          'tglSampai': tglSampai,
          if (Sesi.instance.isAdmin && _tokoId != null) 'toko_id': _tokoId,
          'page': hal,
          'pageSize': 100,
        });
        final baris = ((rincian['data'] as List?) ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        semuaItem.addAll(baris);
        final totalOrder = (rincian['total'] as num?)?.toInt() ?? 0;
        if (baris.isEmpty || hal * 100 >= totalOrder) break;
      }

      final pakaiPerGrup = <int, int>{};
      final biayaPerGrup = <int, double>{};
      final pakaiPerAturan = <int, int>{};
      final biayaPerAturan = <int, double>{};

      final aturanDefault = _daftarAturanMaster
          .where((a) =>
              a['aktif'] == true &&
              a['aktivasiManual'] != true &&
              ((a['produkNama'] as String?)?.trim().isEmpty ?? true))
          .toList();
      final int? idAturanUmum = aturanDefault.isNotEmpty
          ? (aturanDefault.first['id'] as num?)?.toInt()
          : null;

      final filterHanyaGrup = _jenisDiskon == 'DISKON_GRUP' ||
          (_aturanDiskonId != null && _aturanDiskonId! < 0);
      final filterHanyaAturan = _jenisDiskon == 'ATURAN_DISKON' ||
          (_aturanDiskonId != null && _aturanDiskonId! > 0);
      final filterKhusus = filterHanyaGrup ||
          filterHanyaAturan ||
          _tipeAnggotaId != null;

      double diskonTerfilter = 0;
      final trenMap = <String, double>{};
      final topProdukMap = <String, double>{};
      final bulanan = _periode == 'year' ||
          _periode == 'semester' ||
          _periode == '3years';

      for (final item in semuaItem) {
        final diskon = ((item['diskon'] as num?) ?? 0).toDouble();
        if (diskon <= 0) continue;
        final pidRaw = item['produkId'];
        final pid = pidRaw is num ? pidRaw.toInt() : int.tryParse('$pidRaw');
        final namaProduk =
            '${item['produkNamaRekap'] ?? item['produkNama'] ?? '-'}'.trim();
        final harga = ((item['hargaSatuan'] as num?) ?? 0).toDouble();
        final qty = ((item['qty'] as num?) ?? 1).toDouble();

        final gid = _cariGrupUntukItem(pid, namaProduk, harga, qty, diskon);
        int? aid;
        if (gid != null) {
          pakaiPerGrup[gid] = (pakaiPerGrup[gid] ?? 0) + 1;
          biayaPerGrup[gid] = (biayaPerGrup[gid] ?? 0) + diskon;
        } else if (idAturanUmum != null) {
          aid = idAturanUmum;
          pakaiPerAturan[aid] = (pakaiPerAturan[aid] ?? 0) + 1;
          biayaPerAturan[aid] = (biayaPerAturan[aid] ?? 0) + diskon;
        }

        var cocokFilter = true;
        if (_jenisDiskon == 'DISKON_GRUP' && gid == null) cocokFilter = false;
        if (_jenisDiskon == 'ATURAN_DISKON' && gid != null) cocokFilter = false;
        if (_aturanDiskonId != null) {
          if (_aturanDiskonId! < 0 && gid != -_aturanDiskonId!) {
            cocokFilter = false;
          } else if (_aturanDiskonId! > 0 && aid != _aturanDiskonId!) {
            cocokFilter = false;
          }
        }
        if (!cocokFilter) continue;

        diskonTerfilter += diskon;
        topProdukMap[namaProduk] = (topProdukMap[namaProduk] ?? 0) + diskon;
        final waktuStr = '${item['waktu'] ?? ''}'.trim();
        if (waktuStr.length >= 10) {
          final bucket =
              bulanan ? waktuStr.substring(0, 7) : waktuStr.substring(0, 10);
          trenMap[bucket] = (trenMap[bucket] ?? 0) + diskon;
        }
      }

      final gabunganAturan = <Map<String, dynamic>>[];
      final sudahAdaId = <int>{};
      for (final a
          in ((hasil['aturanDiskon'] as List?) ?? []).whereType<Map>()) {
        final m = Map<String, dynamic>.from(a);
        final id = (m['id'] as num?)?.toInt() ?? 0;
        if (id != 0) sudahAdaId.add(id);
        m['sumber'] = m['sumber'] ?? (id < 0 ? 'GRUP' : 'ATURAN');
        gabunganAturan.add(m);
      }

      for (final g in _daftarGrupMaster) {
        final gid = (g['id'] as num?)?.toInt() ?? 0;
        if (gid <= 0 || sudahAdaId.contains(-gid)) continue;
        final dipakai = pakaiPerGrup[gid] ?? 0;
        final totalBiaya = biayaPerGrup[gid] ?? 0.0;
        final persen = ((g['persentase'] as num?) ?? 0).toDouble();
        final jmlProduk = ((g['jumlahProduk'] as num?) ?? 0).toInt();
        gabunganAturan.add({
          'id': -gid,
          'grupId': gid,
          'namaAturan': '${g['namaGrup'] ?? g['nama_grup'] ?? 'Grup #$gid'}',
          'potonganLangsung':
              (g['potonganLangsung'] ?? g['potongan_langsung']) ?? true,
          'sumber': 'GRUP',
          'persentase': persen,
          'jumlahProduk': jmlProduk,
          'dipakai': dipakai,
          'totalBiaya': totalBiaya,
        });
      }

      for (final a in _daftarAturanMaster) {
        final aid = (a['id'] as num?)?.toInt() ?? 0;
        if (aid <= 0 || sudahAdaId.contains(aid)) continue;
        final dipakai = pakaiPerAturan[aid] ?? 0;
        final totalBiaya = biayaPerAturan[aid] ?? 0.0;
        final persen = ((a['persentase'] as num?) ?? 0).toDouble();
        gabunganAturan.add({
          'id': aid,
          'namaAturan': '${a['namaAturan'] ?? a['nama_aturan'] ?? 'Aturan #$aid'}',
          'potonganLangsung':
              (a['potonganLangsung'] ?? a['potongan_langsung']) ?? true,
          'sumber': 'ATURAN',
          'persentase': persen,
          'dipakai': dipakai,
          'totalBiaya': totalBiaya,
        });
      }

      gabunganAturan.sort((a, b) {
        final va = ((a['totalBiaya'] as num?) ?? 0).toDouble();
        final vb = ((b['totalBiaya'] as num?) ?? 0).toDouble();
        if (va != vb) return vb.compareTo(va);
        return '${a['namaAturan']}'.compareTo('${b['namaAturan']}');
      });
      hasil['aturanDiskon'] = gabunganAturan;

      if (filterKhusus) {
        hasil['diskonDiberikan'] =
            _jenisDiskon == 'CASHBACK' ? 0.0 : diskonTerfilter;
        final sortedBuckets = trenMap.keys.toList()..sort();
        hasil['tren'] = [
          for (final k in sortedBuckets)
            {
              'periode': k,
              'diskon': _jenisDiskon == 'CASHBACK' ? 0.0 : (trenMap[k] ?? 0.0),
              'cashback': 0.0,
            }
        ];
        final sortedProduk = topProdukMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        hasil['topProduk'] = [
          for (final e in sortedProduk.take(5))
            {'label': e.key, 'nilai': e.value}
        ];
      }
    } catch (_) {}
    return hasil;
  }

  Future<void> _muat() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasilMentah =
          await ApiClient.instance.aksi('monitor_promo_cashback', {
        'periode': _periode,
        if (_jenisAnggotaId != null) 'jenis_anggota_id': _jenisAnggotaId,
        if (_tipeAnggotaId != null) 'tipe_anggota_id': _tipeAnggotaId,
        if (Sesi.instance.isAdmin && _tokoId != null) 'toko_id': _tokoId,
        if (_jenisDiskon != 'SEMUA') 'jenis_diskon': _jenisDiskon,
        if (_aturanDiskonId != null) 'aturan_diskon_id': _aturanDiskonId,
        if (_aturanDiskonId != null && _aturanDiskonId! < 0)
          'grup_diskon_id': -_aturanDiskonId!,
      });
      final hasil = await _perkayaDariRincianProduk(hasilMentah);
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
    final opsiAturan = _opsiAturanDropdown();
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
                  width: 175,
                  child: DropdownButtonFormField<int?>(
                    value: _tokoId,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Toko',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('- Semua Toko -')),
                      ...Sesi.instance.daftarToko
                          .map((t) => DropdownMenuItem<int?>(
                                value: t['id'] as int?,
                                child: Text('${t['nama']}',
                                    overflow: TextOverflow.ellipsis),
                              )),
                    ],
                    onChanged: (v) {
                      _tokoId = v;
                      _muat();
                    },
                  ),
                ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<int?>(
                  value: _jenisAnggotaId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis Anggota',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('- Semua Jenis -')),
                    ..._jenisAnggota.map((k) => DropdownMenuItem<int?>(
                        value: k.id,
                        child: Text(k.nama, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    _jenisAnggotaId = v;
                    _muat();
                  },
                ),
              ),
              if (_tipeAnggota.isNotEmpty)
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<int?>(
                    value: _tipeAnggotaId,
                    isDense: true,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipe Member',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('- Semua Tipe -',
                              overflow: TextOverflow.ellipsis)),
                      ..._tipeAnggota.map((k) => DropdownMenuItem<int?>(
                          value: k.id,
                          child:
                              Text(k.nama, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) {
                      _tipeAnggotaId = v;
                      _muat();
                    },
                  ),
                ),
              SizedBox(
                width: 165,
                child: DropdownButtonFormField<String>(
                  value: _periode,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Periode',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: _opsiPeriode
                      .map((p) => DropdownMenuItem<String>(
                          value: p.$1, child: Text(p.$2)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    _periode = v;
                    _muat();
                  },
                ),
              ),
              SizedBox(
                width: 225,
                child: DropdownButtonFormField<String>(
                  value: _jenisDiskon,
                  isDense: true,
                  isExpanded: true,
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
                    if (_aturanDiskonId != null &&
                        !_opsiAturanDropdown()
                            .any((a) => a['id'] == _aturanDiskonId)) {
                      _aturanDiskonId = null;
                    }
                    _muat();
                  },
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<int?>(
                  value: opsiAturan.any((a) => a['id'] == _aturanDiskonId)
                      ? _aturanDiskonId
                      : null,
                  isDense: true,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aturan / Grup Promo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('- Semua Aturan & Grup Promo -',
                          overflow: TextOverflow.ellipsis),
                    ),
                    ...opsiAturan.map((a) {
                      final isGrup = a['sumber'] == 'GRUP';
                      final prefix = isGrup ? '[Grup] ' : '[Aturan] ';
                      final infoTipe = a['potonganLangsung'] == true
                          ? 'Potong Struk'
                          : 'Cashback';
                      return DropdownMenuItem<int?>(
                        value: a['id'] as int,
                        child: Text(
                          '$prefix${a['nama']} ($infoTipe)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) {
                    _aturanDiskonId = v;
                    _muat();
                  },
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Muat Ulang',
                  onPressed: _muat),
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
    final peta = <int, Map<String, dynamic>>{};

    for (final g in _daftarGrupMaster) {
      if (g['aktif'] == false) continue;
      final gid = (g['id'] as num?)?.toInt() ?? 0;
      final nama = '${g['namaGrup'] ?? g['nama_grup'] ?? ''}'.trim();
      if (gid <= 0 || nama.isEmpty) continue;
      peta[-gid] = {
        'id': -gid,
        'nama': nama,
        'sumber': 'GRUP',
        'potonganLangsung':
            (g['potonganLangsung'] ?? g['potongan_langsung']) ?? true,
      };
    }

    for (final a in _daftarAturanMaster) {
      if (a['aktif'] == false) continue;
      final aid = (a['id'] as num?)?.toInt() ?? 0;
      final nama = '${a['namaAturan'] ?? a['nama_aturan'] ?? ''}'.trim();
      if (aid <= 0 || nama.isEmpty) continue;
      peta[aid] = {
        'id': aid,
        'nama': nama,
        'sumber': 'ATURAN',
        'potonganLangsung':
            (a['potonganLangsung'] ?? a['potongan_langsung']) ?? true,
      };
    }

    for (final e
        in ((_d?['daftarAturanFilter'] as List?) ?? []).whereType<Map>()) {
      final id = (e['id'] as num?)?.toInt() ?? 0;
      final nama = '${e['namaAturan'] ?? e['nama_grup'] ?? ''}'.trim();
      if (id == 0 || nama.isEmpty) continue;
      final sumber = '${e['sumber'] ?? (id < 0 ? 'GRUP' : 'ATURAN')}';
      peta[id] = {
        'id': id,
        'nama': nama,
        'sumber': sumber,
        'potonganLangsung': e['potonganLangsung'] == true,
      };
    }

    final daftar = peta.values.toList();
    return daftar.where((a) {
      if (_jenisDiskon == 'DISKON_GRUP') return a['sumber'] == 'GRUP';
      if (_jenisDiskon == 'ATURAN_DISKON') return a['sumber'] == 'ATURAN';
      if (_jenisDiskon == 'POTONG_STRUK') return a['potonganLangsung'] == true;
      if (_jenisDiskon == 'CASHBACK') return a['potonganLangsung'] != true;
      return true;
    }).toList();
  }

  Widget _isiDasbor(BuildContext context) {
    final d = _d!;
    final hanyaPotongStruk = _jenisDiskon == 'POTONG_STRUK';
    final hanyaCashback = _jenisDiskon == 'CASHBACK';
    final hanyaDiskonGrup = _jenisDiskon == 'DISKON_GRUP';
    final hanyaAturanBiasa = _jenisDiskon == 'ATURAN_DISKON';
    final tren = ((d['tren'] as List?) ?? []).cast<Map<String, dynamic>>();
    final labelTren = tren.map((t) => '${t['periode']}').toList();
    final seriDiskon = tren
        .map((t) =>
            hanyaCashback ? 0.0 : ((t['diskon'] as num?)?.toDouble() ?? 0.0))
        .toList();
    final seriCashback = tren
        .map((t) => hanyaPotongStruk
            ? 0.0
            : ((t['cashback'] as num?)?.toDouble() ?? 0.0))
        .toList();
    final topProduk = titikDariList(d['topProduk'] as List?);
    final topMember = hanyaPotongStruk
        ? <TitikChart>[]
        : titikDariList(d['topMember'] as List?);
    final aturan = ((d['aturanDiskon'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .where((a) {
          final id = (a['id'] as num?)?.toInt() ?? 0;
          final sumber = '${a['sumber'] ?? (id < 0 ? 'GRUP' : 'ATURAN')}';
          if (hanyaDiskonGrup && sumber != 'GRUP') return false;
          if (hanyaAturanBiasa && sumber != 'ATURAN') return false;
          if (hanyaPotongStruk && a['potonganLangsung'] != true) return false;
          if (hanyaCashback && a['potonganLangsung'] == true) return false;
          if (_aturanDiskonId != null && id != _aturanDiskonId) {
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
                nilai: formatRupiahDasbor
                    .format(hanyaCashback ? 0 : (d['diskonDiberikan'] ?? 0)),
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
                nilai: formatRupiahDasbor
                    .format(hanyaPotongStruk ? 0 : (d['saldoMengendap'] ?? 0)),
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
              child: BarHorizontal(
                  data: topProduk, formatNilai: formatRupiahDasbor.format)),
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
                    const Text('Dampak Aturan & Grup Promo',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                        'Seberapa sering tiap aturan diskon maupun diskon grup dipakai beserta total potongannya.',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 10),
                    ...aturan.take(50).map((a) {
                      final potonganLangsung = a['potonganLangsung'] == true;
                      final id = (a['id'] as num?)?.toInt() ?? 0;
                      final isGrup =
                          '${a['sumber'] ?? (id < 0 ? 'GRUP' : 'ATURAN')}' ==
                              'GRUP';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: (isGrup
                                        ? const Color(0xFF4F46E5)
                                        : const Color(0xFF0D9488))
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  isGrup ? 'Diskon Grup' : 'Aturan Diskon',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isGrup
                                          ? const Color(0xFF4F46E5)
                                          : const Color(0xFF0D9488))),
                            ),
                            Expanded(
                                child: Text('${a['namaAturan']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: (potonganLangsung
                                        ? const Color(0xFFC0563D)
                                        : const Color(0xFF0284C7))
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                  potonganLangsung
                                      ? 'Potong Struk'
                                      : 'Cashback',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: potonganLangsung
                                          ? const Color(0xFFC0563D)
                                          : const Color(0xFF0284C7))),
                            ),
                            Text('${a['dipakai'] ?? 0}x',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondaryOf(context))),
                            const SizedBox(width: 8),
                            Text(
                                formatRupiahDasbor
                                    .format(a['totalBiaya'] ?? 0),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
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
