import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../services/master_offline.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/pulihkan_terhapus.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Layar **Anggaran (RAB Bulanan)** — padanan Desktop/Android dari empat layar ZK:
///
/// * `workspace_bulanan.zul` — pemilih Tahun Anggaran, Satuan Kerja, Sumber Dana, dan Revisi;
/// * `workspace_revisi_bulanan.zul` — pohon item anggaran satu revisi dengan rincian dua belas
///   bulan, tambah/ubah/hapus item, dan agregat induk yang ikut terhitung ulang;
/// * `realisasi_bulanan.zul` — rekap pagu vs realisasi per bulan;
/// * `penggunaan_anggaran.zul` — transaksi pemakaian anggaran yang menjadi sumber angka realisasi.
///
/// Seluruh perhitungan (agregat induk, salin revisi, keaktifan penggunaan anggaran) dikerjakan
/// server lewat aksi `anggaran_*`; layar ini menyusun hierarki dari `parentId` dan menampilkan.
class AnggaranScreen extends StatefulWidget {
  /// 0 Rencana Bulanan, 1 Realisasi, 2 Penggunaan Anggaran.
  final int tabAwal;
  const AnggaranScreen({super.key, this.tabAwal = 0});

  @override
  State<AnggaranScreen> createState() => _AnggaranScreenState();
}

class _AnggaranScreenState extends State<AnggaranScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> namaBulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  late final TabController _tab;
  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  // --- konteks / penyaring
  List<int> _tahunOpsi = [];
  List<Map<String, dynamic>> _satkerOpsi = [];
  List<Map<String, dynamic>> _sumberDanaOpsi = [];
  List<Map<String, dynamic>> _revisiOpsi = [];
  int? _tahun;
  int? _satkerId;
  int? _sumberDanaId;
  int _revisi = 1;

  // --- data
  List<Map<String, dynamic>> _item = [];
  List<double> _ringkasanBulan = List<double>.filled(12, 0);
  double _totalPagu = 0;
  List<Map<String, dynamic>> _realisasi = [];
  List<double> _paguBulan = List<double>.filled(12, 0);
  List<double> _realisasiBulan = List<double>.filled(12, 0);
  double _totalRealisasi = 0;
  List<Map<String, dynamic>> _penggunaan = [];
  double _totalPenggunaanAktif = 0;
  List<Map<String, dynamic>> _akun = [];

  Map<String, bool> _hak = const {
    'create': true,
    'update': true,
    'delete': true
  };
  final _cari = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(
        length: 3,
        vsync: this,
        initialIndex:
            widget.tabAwal >= 0 && widget.tabAwal <= 2 ? widget.tabAwal : 0);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        setStateIfMounted(() {});
        _muatTabAktif();
      }
    });
    _muatKonteks();
  }

  @override
  void dispose() {
    _tab.dispose();
    _cari.dispose();
    super.dispose();
  }

  bool _boleh(String aksi) => _hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  Map<String, bool> _bacaHak(Map<String, dynamic> res) {
    final h = res['hak'];
    if (h is! Map)
      return const {'create': true, 'update': true, 'delete': true};
    return {
      'create': h['create'] != false,
      'update': h['update'] != false,
      'delete': h['delete'] != false,
    };
  }

  List<double> _bacaBulan(dynamic v) {
    final hasil = List<double>.filled(12, 0);
    if (v is List) {
      for (var i = 0; i < 12 && i < v.length; i++) {
        hasil[i] = (v[i] as num?)?.toDouble() ?? 0;
      }
    }
    return hasil;
  }

  Map<String, dynamic> get _filter => {
        'tahun': _tahun ?? 0,
        'satkerId': _satkerId ?? 0,
        'sumberDanaId': _sumberDanaId ?? 0,
        'revisi': _revisi,
        if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
      };

  Future<void> _muatKonteks() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final res = await ApiClient.instance.aksi('anggaran_konteks', {});
      final akun = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
      if (!mounted) return;
      final tahun = ((res['tahun'] as List?) ?? [])
          .map((e) => (e as num).toInt())
          .toList();
      setStateIfMounted(() {
        _tahunOpsi = tahun;
        _satkerOpsi =
            ((res['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _sumberDanaOpsi =
            ((res['sumberDana'] as List?) ?? []).cast<Map<String, dynamic>>();
        _akun = ((akun['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _hak = _bacaHak(res);
        _tahun ??= tahun.isEmpty ? null : tahun.first;
        _satkerId ??= _satkerOpsi.isEmpty
            ? null
            : (_satkerOpsi.first['id'] as num?)?.toInt();
      });
      await _muatRevisi();
    } catch (e) {
      setStateIfMounted(() => _galat = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _muatRevisi() async {
    if (_tahun == null) return;
    try {
      final res =
          await ApiClient.instance.aksi('anggaran_revisi_list', _filter);
      if (!mounted) return;
      final daftar =
          ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      setStateIfMounted(() {
        _revisiOpsi = daftar;
        if (daftar.isNotEmpty &&
            !daftar.any((r) => (r['revisi'] as num?)?.toInt() == _revisi)) {
          _revisi = (daftar.last['revisi'] as num?)?.toInt() ?? 1;
        }
      });
      await _muatTabAktif();
    } catch (e) {
      setStateIfMounted(() => _galat = '$e');
    }
  }

  Future<void> _muatTabAktif() async {
    if (_tahun == null) return;
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      if (_tab.index == 0) {
        // BACA LOKAL DULU: baris yang masih mengantre kirim tetap terlihat, dan
        // daftar tetap terbuka saat perangkat sedang offline.
        await MasterOffline.daftarCacheDulu(
          'anggaran_item_list',
          _filter,
          _cacheItem,
          onData: (res) {
            if (!mounted) return;
            setStateIfMounted(() {
              _item =
                  ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
              // Ringkasan & hak hanya ikut pada emisi SERVER; emisi lokal cuma
              // membawa barisnya, jadi nilai lama dipertahankan.
              if (res.containsKey('ringkasanBulan')) {
                _ringkasanBulan = _bacaBulan(res['ringkasanBulan']);
              }
              if (res.containsKey('totalPagu')) {
                _totalPagu = (res['totalPagu'] as num?)?.toDouble() ?? 0;
              }
              if (res.containsKey('hak')) _hak = _bacaHak(res);
            });
          },
        );
      } else if (_tab.index == 1) {
        final res =
            await ApiClient.instance.aksi('anggaran_realisasi_list', _filter);
        if (!mounted) return;
        setStateIfMounted(() {
          _realisasi =
              ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
          _paguBulan = _bacaBulan(res['paguBulan']);
          _realisasiBulan = _bacaBulan(res['realisasiBulan']);
          _totalPagu = (res['totalPagu'] as num?)?.toDouble() ?? 0;
          _totalRealisasi = (res['totalRealisasi'] as num?)?.toDouble() ?? 0;
          _hak = _bacaHak(res);
        });
      } else {
        await MasterOffline.daftarCacheDulu(
          'anggaran_penggunaan_list',
          _filter,
          _cachePenggunaan,
          onData: (res) {
            if (!mounted) return;
            setStateIfMounted(() {
              _penggunaan =
                  ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
              if (res.containsKey('totalAktif')) {
                _totalPenggunaanAktif =
                    (res['totalAktif'] as num?)?.toDouble() ?? 0;
              }
              if (res.containsKey('hak')) _hak = _bacaHak(res);
            });
          },
        );
      }
    } catch (e) {
      setStateIfMounted(() => _galat = '$e');
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  /// Kunci cache daftar item per penyaring -- pohon anggaran berbeda per tahun,
  /// satuan kerja, sumber dana, dan revisi, jadi cache-nya tidak boleh dicampur.
  String get _cacheItem =>
      'master:anggaran_item:${_tahun ?? 0}:${_satkerId ?? 0}:${_sumberDanaId ?? 0}:$_revisi';

  String get _cachePenggunaan =>
      'master:anggaran_penggunaan:${_tahun ?? 0}:${_satkerId ?? 0}:$_revisi';

  /// Mutasi ITEM anggaran: LOKAL DULU dengan id sementara.
  ///
  /// Item baru yang dibuat offline mendapat id negatif; baris Penggunaan Anggaran yang
  /// menunjuknya ikut ditukar saat sinkron, dan penggunaan itu DITAHAN sampai itemnya
  /// benar-benar terkirim -- jadi tidak pernah ada penggunaan yang menggantung.
  Future<bool> _kirimItem(String aksi, Map<String, dynamic> body) {
    final hapus = aksi.endsWith('_hapus');
    return _kirimMaster(
      aksi,
      body,
      kunci: body['id'] == null
          ? 'anggaran_item:baru:${DateTime.now().microsecondsSinceEpoch}'
          : 'anggaran_item:${body['id']}',
      cacheKey: _cacheItem,
      rowLokal: hapus ? {'id': body['id']} : {...body, 'hargaTotal': 0},
      hapusLokal: hapus,
      entitas: 'anggaran_item',
      baru: !hapus && body['id'] == null,
    );
  }

  /// Mutasi baris DAUN yang aman diantre (Penggunaan Anggaran): baris ini tidak
  /// dirujuk id-nya oleh alur lain, dan itemnya sendiri sudah ada di server.
  Future<bool> _kirimMaster(
    String aksi,
    Map<String, dynamic> body, {
    required String kunci,
    String? cacheKey,
    Map<String, dynamic>? rowLokal,
    bool hapusLokal = false,
    String entitas = 'anggaran',
    bool baru = false,
  }) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final idLokal = baru ? MasterOffline.idSementaraBaru() : null;
      final hasil = await prosesSimpanMaster(
        context,
        aksi: aksi,
        body: body,
        kunci: kunci,
        cacheKey: cacheKey,
        rowLokal:
            idLokal == null ? rowLokal : {...(rowLokal ?? body), 'id': idLokal},
        hapusLokal: hapusLokal,
        idLokal: idLokal,
        entitas: entitas,
      );
      if (hasil['offline'] != true) {
        _pesan('${hasil['message'] ?? 'Perubahan tersimpan.'}');
      }
      await _muatTabAktif();
      return true;
    } catch (e) {
      _pesan('$e');
      return false;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Aksi yang HARUS dihitung server (bukan mutasi baris master): hasilnya tidak punya
  /// bentuk lokal yang benar, jadi tidak diantrekan. Contohnya "Buat Revisi Baru" yang
  /// menyalin seluruh pohon revisi tertinggi -- mengantrekannya berisiko revisi ganda.
  Future<bool> _kirimServer(String aksi, Map<String, dynamic> body) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      _pesan('${hasil['message'] ?? 'Perubahan tersimpan.'}');
      await _muatTabAktif();
      return true;
    } catch (e) {
      _pesan('$e');
      return false;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<bool> _konfirmasi(String judul, String isi,
      {String tombol = 'Hapus'}) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(tombol)),
        ],
      ),
    );
    return ya == true;
  }

  /// Pohon item: baris anak diberi indentasi sesuai kedalaman induknya, sama seperti
  /// pohon pada layar ZK. Baris yang induknya tidak ikut terambil dianggap akar.
  List<Map<String, dynamic>> _pohon(List<Map<String, dynamic>> sumber) {
    final anakDari = <String, List<Map<String, dynamic>>>{};
    final akar = <Map<String, dynamic>>[];
    final semuaId = sumber.map((a) => '${a['id']}').toSet();
    for (final a in sumber) {
      final p = a['parentId'];
      if (p == null || !semuaId.contains('$p')) {
        akar.add(a);
      } else {
        anakDari.putIfAbsent('$p', () => []).add(a);
      }
    }
    final hasil = <Map<String, dynamic>>[];
    void telusuri(Map<String, dynamic> node, int level) {
      hasil.add({...node, '_level': level});
      for (final anak in (anakDari['${node['id']}'] ?? const [])) {
        telusuri(anak, level + 1);
      }
    }

    for (final a in akar) {
      telusuri(a, 0);
    }
    return hasil;
  }

  // ==================================================================== formulir

  /// Formulir item anggaran. [induk] terisi = tambah anak di bawah item itu.
  Future<void> _formItem(
      {Map<String, dynamic>? item, Map<String, dynamic>? induk}) async {
    final ubah = item != null;
    final kode = TextEditingController(text: '${item?['kode'] ?? ''}');
    final nama = TextEditingController(text: '${item?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${item?['keterangan'] ?? ''}');
    final qty = TextEditingController(
        text: ((item?['qty'] as num?)?.toDouble() ?? 1).toStringAsFixed(0));
    final satuanVolume =
        TextEditingController(text: '${item?['satuanVolume'] ?? ''}');
    final hargaSatuan = TextEditingController(
        text: ((item?['hargaSatuan'] as num?)?.toDouble() ?? 0)
            .toStringAsFixed(0));
    final bulan = List<TextEditingController>.generate(
      12,
      (i) => TextEditingController(
          text: (_bacaBulan(item?['bulan'])[i]).toStringAsFixed(0)),
    );
    int? akunId = (item?['akunId'] as num?)?.toInt();
    int parentId = ubah
        ? ((item['parentId'] as num?)?.toInt() ?? 0)
        : ((induk?['id'] as num?)?.toInt() ?? 0);
    bool aktif = item == null ? true : item['aktif'] != false;

    double totalDari(List<TextEditingController> c) {
      var t = 0.0;
      for (final e in c) {
        t += double.tryParse(e.text.trim()) ?? 0;
      }
      return t;
    }

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(ubah
              ? 'Ubah Item Anggaran'
              : (induk == null
                  ? 'Tambah Item Anggaran'
                  : 'Tambah Item di Bawah "${induk['nama']}"')),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: kode,
                    decoration: const InputDecoration(
                        labelText: 'Kode',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: nama,
                    decoration: const InputDecoration(
                        labelText: 'Nama Item *',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: parentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Induk',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: [
                    const DropdownMenuItem(
                        value: 0, child: Text('= Item Akar =')),
                    ..._item
                        .where((e) =>
                            (e['id'] as num?)?.toInt() !=
                            (item?['id'] as num?)?.toInt())
                        .map((e) => DropdownMenuItem(
                              value: (e['id'] as num?)?.toInt(),
                              child: Text(
                                  '${e['kode'] ?? ''} ${e['nama'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            )),
                  ],
                  onChanged: (v) => setDialog(() => parentId = v ?? 0),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: qty,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Volume',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: satuanVolume,
                        decoration: const InputDecoration(
                            labelText: 'Satuan',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: hargaSatuan,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Harga Satuan',
                            border: OutlineInputBorder(),
                            isDense: true)),
                  ),
                ]),
                const SizedBox(height: 12),
                PemilihAkunField(
                  label: 'Akun',
                  daftar: _akun,
                  nilai: akunId,
                  helperText:
                      'Akun buku besar yang dibebani item anggaran ini.',
                  onChanged: (v) => setDialog(() => akunId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: keterangan,
                    decoration: const InputDecoration(
                        labelText: 'Keterangan',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Rencana per Bulan',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  // Aturan ini milik server (padanan WorkspaceTreeModel): nilai induk selalu
                  // ditimpa jumlah anaknya, jadi angka bulanan hanya berarti pada item daun.
                  child: Text(
                    'Untuk item yang punya turunan, nilai bulanan dihitung ulang server dari jumlah anaknya.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 12; i++)
                      SizedBox(
                        width: 128,
                        child: TextField(
                          controller: bulan[i],
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setDialog(() {}),
                          decoration: InputDecoration(
                              labelText: namaBulan[i],
                              border: const OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Total setahun: ${_uang.format(totalDari(bulan))}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Nama item anggaran wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': item['id'],
      'tahun': _tahun ?? 0,
      'satkerId': _satkerId ?? 0,
      'sumberDanaId': _sumberDanaId ?? 0,
      'revisi': _revisi,
      'parentId': parentId,
      'kode': kode.text.trim(),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'qty': double.tryParse(qty.text.trim()) ?? 1,
      'satuanVolume': satuanVolume.text.trim(),
      'hargaSatuan': double.tryParse(hargaSatuan.text.trim()) ?? 0,
      'akunId': akunId ?? 0,
      'aktif': aktif,
      'bulan': [
        for (var i = 0; i < 12; i++) double.tryParse(bulan[i].text.trim()) ?? 0,
      ],
    };
    await _kirimItem('anggaran_item_simpan', payload);
  }

  Future<void> _formPenggunaan({Map<String, dynamic>? data}) async {
    final ubah = data != null;
    if (ubah && '${data['sumber'] ?? ''}' != 'Entri Manual') {
      _pesan(
          'Baris ini berasal dari dokumen ${data['sumber']}, ubah dari dokumen asalnya.');
      return;
    }
    final kode = TextEditingController(text: '${data?['kode'] ?? ''}');
    final nama = TextEditingController(text: '${data?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${data?['keterangan'] ?? ''}');
    final nilai = TextEditingController(
        text: ((data?['nilai'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    int? workspaceId = (data?['workspaceId'] as num?)?.toInt();
    DateTime waktu =
        DateTime.tryParse('${data?['waktu'] ?? ''}') ?? DateTime.now();

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(
              ubah ? 'Ubah Penggunaan Anggaran' : 'Catat Penggunaan Anggaran'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  value: workspaceId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Item Anggaran *',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: _item
                      .map((e) => DropdownMenuItem(
                            value: (e['id'] as num?)?.toInt(),
                            child: Text('${e['kode'] ?? ''} ${e['nama'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setDialog(() => workspaceId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: kode,
                    decoration: const InputDecoration(
                        labelText: 'Kode / No. Bukti',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: nama,
                    decoration: const InputDecoration(
                        labelText: 'Uraian *',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                TextField(
                    controller: nilai,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Nilai *',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showDatePicker(
                          context: c,
                          initialDate: waktu,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (t != null) setDialog(() => waktu = t);
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(
                        'Tanggal ${DateFormat('yyyy-MM-dd').format(waktu)}'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: keterangan,
                    decoration: const InputDecoration(
                        labelText: 'Keterangan',
                        border: OutlineInputBorder(),
                        isDense: true)),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true) return;
    // Id anggaran pada basis data warisan SELALU negatif (19 digit), jadi "belum
    // dipilih" berarti TEPAT nol. Memakai <= 0 di sini membuat setiap item yang sah
    // ditolak dan formulir tidak pernah bisa disimpan.
    if (nama.text.trim().isEmpty || (workspaceId ?? 0) == 0) {
      _pesan('Item anggaran dan uraian wajib diisi.');
      return;
    }
    final payload = <String, dynamic>{
      if (ubah) 'id': data['id'],
      'workspaceId': workspaceId,
      'kode': kode.text.trim(),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'nilai': double.tryParse(nilai.text.trim()) ?? 0,
      'waktu': DateFormat('yyyy-MM-dd HH:mm:ss').format(waktu),
    };
    await _kirimMaster(
      'anggaran_penggunaan_simpan',
      payload,
      kunci: ubah
          ? 'anggaran_penggunaan:${data['id']}'
          : 'anggaran_penggunaan:baru:${DateTime.now().microsecondsSinceEpoch}',
      cacheKey: _cachePenggunaan,
      rowLokal: {...payload, 'aktif': true, 'sumber': 'Entri Manual'},
      entitas: 'anggaran_penggunaan',
      baru: !ubah,
    );
  }

  Future<void> _buatRevisiBaru() async {
    if (!await _konfirmasi(
        'Buat revisi baru?',
        'Seluruh item revisi tertinggi akan disalin menjadi revisi berikutnya beserta hierarkinya. '
            'Nilai realisasi tidak ikut disalin.',
        tombol: 'Buat')) {
      return;
    }
    final berhasil = await _kirimServer('anggaran_revisi_baru', {
      'tahun': _tahun ?? 0,
      'satkerId': _satkerId ?? 0,
      'sumberDanaId': _sumberDanaId ?? 0,
    });
    if (berhasil) await _muatRevisi();
  }

  // ==================================================================== ekspor
  // Isi berkas SELALU mengikuti tab yang sedang aktif beserta penyaringnya, sehingga
  // yang tercetak sama persis dengan yang sedang dilihat pengguna.

  String get _judulTab => _tab.index == 0
      ? 'Rencana Bulanan'
      : (_tab.index == 1 ? 'Realisasi' : 'Penggunaan Anggaran');

  String get _konteksTeks {
    final satker = _satkerOpsi.firstWhere(
        (s) => (s['id'] as num?)?.toInt() == _satkerId,
        orElse: () => const <String, dynamic>{});
    final sd = _sumberDanaOpsi.firstWhere(
        (s) => (s['id'] as num?)?.toInt() == _sumberDanaId,
        orElse: () => const <String, dynamic>{});
    final bagian = <String>[
      'Tahun ${_tahun ?? '-'}',
      if (satker.isNotEmpty) 'Satker ${satker['nama'] ?? ''}',
      if (sd.isNotEmpty) 'Sumber Dana ${sd['nama'] ?? ''}',
      'Revisi $_revisi',
      if (_cari.text.trim().isNotEmpty) 'Cari "${_cari.text.trim()}"',
    ];
    return bagian.join(' · ');
  }

  String _teksItem(Map<String, dynamic> a) =>
      '${'    ' * ((a['_level'] as int?) ?? 0)}${a['kode'] ?? ''} ${a['nama'] ?? ''}'
          .trim();

  List<String> get _kolomEkspor {
    if (_tab.index == 0) {
      return ['Tingkat', 'Kode', 'Item', 'Total Setahun', ...namaBulan];
    }
    if (_tab.index == 1) {
      return [
        'Tingkat',
        'Kode',
        'Item',
        'Pagu',
        'Realisasi',
        'Sisa',
        'Persen',
        'Transaksi',
        ...namaBulan
      ];
    }
    return [
      'Waktu',
      'Kode',
      'Uraian',
      'Item Anggaran',
      'Sumber',
      'Nilai',
      'Aktif'
    ];
  }

  /// Baris ekspor. Angka dikirim sebagai angka (bukan teks) supaya bisa langsung
  /// dijumlah di Excel; kolom "Tingkat" menjaga hierarki tetap terbaca walau
  /// indentasi teks hilang saat berkas dibuka di aplikasi lain.
  List<List<Object?>> _barisEkspor() {
    if (_tab.index == 0) {
      return _pohon(_item).map((a) {
        final bulan = _bacaBulan(a['bulan']);
        return <Object?>[
          (a['_level'] as int?) ?? 0,
          '${a['kode'] ?? ''}',
          _teksItem(a),
          (a['hargaTotal'] as num?)?.toDouble() ?? 0,
          ...bulan,
        ];
      }).toList();
    }
    if (_tab.index == 1) {
      return _pohon(_realisasi).map((a) {
        final real = _bacaBulan(a['realisasiBulan']);
        return <Object?>[
          (a['_level'] as int?) ?? 0,
          '${a['kode'] ?? ''}',
          _teksItem(a),
          (a['hargaTotal'] as num?)?.toDouble() ?? 0,
          (a['realisasi'] as num?)?.toDouble() ?? 0,
          (a['sisa'] as num?)?.toDouble() ?? 0,
          (a['persen'] as num?)?.toDouble() ?? 0,
          (a['jumlahTransaksi'] as num?)?.toInt() ?? 0,
          ...real,
        ];
      }).toList();
    }
    return _penggunaan
        .map((p) => <Object?>[
              '${p['waktu'] ?? ''}',
              '${p['kode'] ?? ''}',
              '${p['nama'] ?? ''}',
              '${p['workspaceLabel'] ?? ''}',
              '${p['sumber'] ?? ''}',
              (p['nilai'] as num?)?.toDouble() ?? 0,
              p['aktif'] == true ? 'Ya' : 'Tidak',
            ])
        .toList();
  }

  String get _namaBerkas =>
      'Anggaran_${_judulTab.replaceAll(' ', '_')}_${_tahun ?? 0}_R$_revisi'
      '_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

  Future<void> _unduhExcel() async {
    final baris = _barisEkspor();
    if (baris.isEmpty) {
      _pesan('Tidak ada data untuk diunduh pada tab ini.');
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final bytes = buildSimpleXlsx(
        sheetName: _judulTab,
        headers: _kolomEkspor,
        rows: baris,
      );
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan $_judulTab',
          fileName: '$_namaBerkas.xlsx',
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: bytes);
      if (path != null) await File(path).writeAsBytes(bytes);
      _pesan('${baris.length} baris disiapkan ke Excel.');
    } catch (e) {
      _pesan('Gagal mengunduh: $e');
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _cetakPdf() async {
    final baris = _barisEkspor();
    if (baris.isEmpty) {
      _pesan('Tidak ada data untuk dicetak pada tab ini.');
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final kolom = _kolomEkspor;
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          // Mendatar: tabel rencana dan realisasi punya dua belas kolom bulan.
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(18),
          header: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Anggaran (RAB Bulanan) — $_judulTab',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(_konteksTeks, style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 6),
              ]),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8)),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: kolom,
              data: baris
                  .map((r) => r
                      .map((v) => v is num ? _uang.format(v) : '${v ?? ''}')
                      .toList())
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 6.5),
              headerStyle:
                  pw.TextStyle(fontSize: 6.5, fontWeight: pw.FontWeight.bold),
              cellAlignment: pw.Alignment.centerRight,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft
              },
              columnWidths:
                  _tab.index == 2 ? null : {2: const pw.FlexColumnWidth(3)},
            ),
            pw.SizedBox(height: 8),
            pw.Text(_ringkasCetak(), style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
      );
      await Printing.layoutPdf(
          onLayout: (_) async => doc.save(), name: '$_namaBerkas.pdf');
    } catch (e) {
      _pesan('Gagal menyiapkan PDF: $e');
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  String _ringkasCetak() {
    if (_tab.index == 0) {
      return 'Total pagu setahun: ${_uang.format(_totalPagu)}';
    }
    if (_tab.index == 1) {
      return 'Pagu: ${_uang.format(_totalPagu)}   Realisasi: ${_uang.format(_totalRealisasi)}'
          '   Sisa: ${_uang.format(_totalPagu - _totalRealisasi)}';
    }
    return 'Total penggunaan aktif: ${_uang.format(_totalPenggunaanAktif)}';
  }

  // ==================================================================== tampilan

  /// Penghapusan lokal bersifat LUNAK; baris yang belum terkirim masih tersimpan di
  /// perangkat dan dapat dikembalikan dari sini.
  Future<void> _bukaTerhapus() async {
    final tabPenggunaan = _tab.index == 2;
    final jumlah = await bukaPulihkanTerhapus(
      context,
      cacheKey: tabPenggunaan ? _cachePenggunaan : _cacheItem,
      judul: tabPenggunaan ? 'Penggunaan Terhapus' : 'Item Anggaran Terhapus',
      labelBaris: (b) => '${b['kode'] ?? ''} ${b['nama'] ?? ''}'.trim(),
      keteranganBaris: (b) => tabPenggunaan
          ? '${b['waktu'] ?? ''}  ${_uang.format((b['nilai'] as num?)?.toDouble() ?? 0)}'
          : '${b['keterangan'] ?? ''}',
    );
    if (jumlah > 0) await _muatTabAktif();
  }

  Widget _penyaring() {
    final sdTerpakai = _sumberDanaOpsi
        .where((s) =>
            _tahun == null ||
            s['tahun'] == null ||
            (s['tahun'] as num).toInt() == _tahun)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<int>(
                value: _tahun,
                decoration: const InputDecoration(
                    labelText: 'Tahun Anggaran',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: _tahunOpsi
                    .map((t) => DropdownMenuItem(value: t, child: Text('$t')))
                    .toList(),
                onChanged: (v) {
                  setStateIfMounted(() => _tahun = v);
                  _muatRevisi();
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                value: _satkerId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Satuan Kerja',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: _satkerOpsi
                    .map((s) => DropdownMenuItem(
                          value: (s['id'] as num?)?.toInt(),
                          child: Text('${s['kode'] ?? ''} ${s['nama'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  setStateIfMounted(() => _satkerId = v);
                  _muatRevisi();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                value: _sumberDanaId ?? 0,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Sumber Dana',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('= Semua =')),
                  ...sdTerpakai.map((s) => DropdownMenuItem(
                        value: (s['id'] as num?)?.toInt(),
                        child: Text('${s['nama'] ?? ''}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) {
                  setStateIfMounted(
                      () => _sumberDanaId = (v ?? 0) == 0 ? null : v);
                  _muatRevisi();
                },
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<int>(
                value: _revisiOpsi
                        .any((r) => (r['revisi'] as num?)?.toInt() == _revisi)
                    ? _revisi
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Revisi',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: _revisiOpsi
                    .map((r) => DropdownMenuItem(
                          value: (r['revisi'] as num?)?.toInt(),
                          child: Text(
                              'Revisi ${r['revisi']} · ${r['jumlahItem']} item',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  setStateIfMounted(() => _revisi = v ?? 1);
                  _muatTabAktif();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: AppSearchField(
                controller: _cari,
                hintText: 'Cari kode / nama',
                onChanged: (_) => _muatTabAktif(),
              ),
            ),
            FilledButton.icon(
                onPressed: _memuat ? null : _muatTabAktif,
                icon: const Icon(Icons.filter_alt_outlined, size: 18),
                label: const Text('Terapkan')),
            if (_tab.index != 1)
              OutlinedButton.icon(
                  onPressed: _sibuk || _memuat ? null : _bukaTerhapus,
                  icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
                  label: const Text('Data Terhapus')),
            OutlinedButton.icon(
                onPressed: _sibuk || _memuat ? null : _unduhExcel,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Download Excel')),
            OutlinedButton.icon(
                onPressed: _sibuk || _memuat ? null : _cetakPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Cetak PDF')),
            if (_tab.index == 0 && _boleh('create'))
              FilledButton.icon(
                  onPressed: _sibuk ? null : () => _formItem(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Item')),
            if (_tab.index == 0 && _boleh('create'))
              OutlinedButton.icon(
                  onPressed: _sibuk ? null : _buatRevisiBaru,
                  icon: const Icon(Icons.difference_outlined, size: 18),
                  label: const Text('Buat Revisi Baru')),
            if (_tab.index == 2 && _boleh('create'))
              FilledButton.icon(
                  onPressed: _sibuk ? null : () => _formPenggunaan(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Catat Penggunaan')),
            if (_sibuk)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
    );
  }

  Widget _kartuRingkas(String judul, double nilai, {Color? warna}) => Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (warna ?? AppColors.primary).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: (warna ?? AppColors.primary).withValues(alpha: .35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(judul, style: const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(_uang.format(nilai),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      );

  Widget _stripBulan(String judul, List<double> nilai) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            SizedBox(
                width: 92,
                child: Text(judul,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12))),
            for (var i = 0; i < 12; i++)
              SizedBox(
                width: 104,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(namaBulan[i],
                          style: const TextStyle(fontSize: 10.5)),
                      Text(_uang.format(nilai[i]),
                          style: const TextStyle(fontSize: 12)),
                    ]),
              ),
          ]),
        ),
      );

  AppTableCell _aksiItem(Map<String, dynamic> a) => AppTableCell(
      width: 64,
      child: AksiBarisMenu(aksi: [
        AksiBaris(
            ikon: Icons.playlist_add,
            label: 'Tambah item di bawahnya',
            onTap: _boleh('create')
                ? _sibuk
                    ? null
                    : () => _formItem(induk: a)
                : null),
        AksiBaris(
            ikon: Icons.edit_outlined,
            label: 'Ubah item',
            onTap: _boleh('update')
                ? _sibuk
                    ? null
                    : () => _formItem(item: a)
                : null),
        AksiBaris(
            ikon: Icons.delete_outline,
            label: 'Hapus item',
            onTap: _boleh('delete')
                ? _sibuk
                    ? null
                    : () async {
                        if (await _konfirmasi('Hapus item anggaran?',
                            '"${a['nama']}" akan dihapus. Item yang punya turunan atau sudah dipakai realisasi akan ditolak server.')) {
                          await _kirimItem(
                              'anggaran_item_hapus', {'id': a['id']});
                        }
                      }
                : null,
            merusak: true)
      ]));

  Widget _tabRencana() {
    final data = _pohon(_item);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          _kartuRingkas('Total Pagu Setahun', _totalPagu),
        ]),
      ),
      _stripBulan('Pagu/bulan', _ringkasanBulan),
      Expanded(
        child: AppDataTable(
          minWidth: 1900,
          emptyText: 'Belum ada item anggaran untuk penyaring ini.',
          columns: [
            const AppTableColumn('Item', flex: 5),
            const AppTableColumn('Total', flex: 2, align: TextAlign.right),
            for (final b in namaBulan)
              AppTableColumn(b, width: 104, align: TextAlign.right),
            const AppTableColumn('Aksi', width: 64, align: TextAlign.center),
          ],
          rows: data.map((a) {
            final bulan = _bacaBulan(a['bulan']);
            return AppTableRowData(cells: [
              AppTableCell.text(
                  '${'    ' * ((a['_level'] as int?) ?? 0)}${a['kode'] ?? ''} ${a['nama'] ?? ''}',
                  flex: 5),
              AppTableCell.text(
                  _uang.format((a['hargaTotal'] as num?)?.toDouble() ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              for (var i = 0; i < 12; i++)
                AppTableCell.text(_uang.format(bulan[i]),
                    width: 104, align: TextAlign.right),
              _aksiItem(a),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _tabRealisasi() {
    final data = _pohon(_realisasi);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(children: [
          _kartuRingkas('Pagu', _totalPagu),
          _kartuRingkas('Realisasi', _totalRealisasi, warna: AppColors.success),
          _kartuRingkas('Sisa', _totalPagu - _totalRealisasi,
              warna: AppColors.warning),
        ]),
      ),
      _stripBulan('Pagu', _paguBulan),
      _stripBulan('Realisasi', _realisasiBulan),
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Baris induk menampilkan jumlah seluruh turunannya, baik pagu maupun realisasi.',
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ),
      Expanded(
        child: AppDataTable(
          minWidth: 2400,
          emptyText: 'Belum ada data realisasi untuk penyaring ini.',
          columns: [
            const AppTableColumn('Item', flex: 5),
            const AppTableColumn('Pagu', flex: 2, align: TextAlign.right),
            const AppTableColumn('Realisasi', flex: 2, align: TextAlign.right),
            const AppTableColumn('Sisa', flex: 2, align: TextAlign.right),
            const AppTableColumn('%', flex: 1, align: TextAlign.right),
            const AppTableColumn('Trx', flex: 1, align: TextAlign.right),
            // Dua belas kolom realisasi per bulan -- inti layar realisasi_bulanan.zul.
            for (final b in namaBulan)
              AppTableColumn(b, width: 104, align: TextAlign.right),
          ],
          rows: data.map((a) {
            final persen = (a['persen'] as num?)?.toDouble() ?? 0;
            final realBulan = _bacaBulan(a['realisasiBulan']);
            return AppTableRowData(cells: [
              AppTableCell.text(
                  '${'    ' * ((a['_level'] as int?) ?? 0)}${a['kode'] ?? ''} ${a['nama'] ?? ''}',
                  flex: 5),
              AppTableCell.text(
                  _uang.format((a['hargaTotal'] as num?)?.toDouble() ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              AppTableCell.text(
                  _uang.format((a['realisasi'] as num?)?.toDouble() ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              AppTableCell.text(
                  _uang.format((a['sisa'] as num?)?.toDouble() ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              AppTableCell.text('${persen.toStringAsFixed(1)}%',
                  flex: 1, align: TextAlign.right),
              AppTableCell.text('${a['jumlahTransaksi'] ?? 0}',
                  flex: 1, align: TextAlign.right),
              for (var i = 0; i < 12; i++)
                AppTableCell.text(_uang.format(realBulan[i]),
                    width: 104, align: TextAlign.right),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _tabPenggunaan() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          _kartuRingkas('Total Penggunaan Aktif', _totalPenggunaanAktif,
              warna: AppColors.success),
        ]),
      ),
      Expanded(
        child: AppDataTable(
          minWidth: 1150,
          emptyText: 'Belum ada transaksi penggunaan anggaran.',
          columns: const [
            AppTableColumn('Waktu', flex: 2),
            AppTableColumn('Kode', flex: 2),
            AppTableColumn('Uraian', flex: 4),
            AppTableColumn('Item Anggaran', flex: 4),
            AppTableColumn('Sumber', flex: 2),
            AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
            AppTableColumn('Aktif', flex: 1),
            AppTableColumn('Aksi', width: 64, align: TextAlign.center),
          ],
          rows: _penggunaan.map((p) {
            final manual = '${p['sumber'] ?? ''}' == 'Entri Manual';
            return AppTableRowData(cells: [
              AppTableCell.text('${p['waktu'] ?? ''}', flex: 2),
              AppTableCell.text('${p['kode'] ?? ''}', flex: 2),
              AppTableCell.text('${p['nama'] ?? ''}', flex: 4),
              AppTableCell.text('${p['workspaceLabel'] ?? ''}', flex: 4),
              AppTableCell.text('${p['sumber'] ?? ''}', flex: 2),
              AppTableCell.text(
                  _uang.format((p['nilai'] as num?)?.toDouble() ?? 0),
                  flex: 2,
                  align: TextAlign.right),
              AppTableCell.text(p['aktif'] == true ? 'Ya' : 'Tidak', flex: 1),
              AppTableCell(
                width: 96,
                align: TextAlign.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (manual && _boleh('update'))
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Ubah',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: _sibuk ? null : () => _formPenggunaan(data: p),
                    ),
                  if (manual && _boleh('delete'))
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Hapus',
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      onPressed: _sibuk
                          ? null
                          : () async {
                              if (await _konfirmasi(
                                  'Hapus penggunaan anggaran?',
                                  '"${p['nama']}" akan dihapus permanen.')) {
                                await _kirimMaster(
                                  'anggaran_penggunaan_hapus',
                                  {'id': p['id']},
                                  kunci: 'anggaran_penggunaan:${p['id']}',
                                  cacheKey: _cachePenggunaan,
                                  rowLokal: {'id': p['id']},
                                  hapusLokal: true,
                                );
                              }
                            },
                    ),
                  // Baris dari dokumen lain sengaja tidak bisa disunting di sini supaya
                  // angka realisasi tetap sinkron dengan dokumen asalnya.
                  if (!manual)
                    const Tooltip(
                      message:
                          'Berasal dari dokumen lain — ubah dari dokumen asalnya',
                      child: Icon(Icons.lock_outline, size: 16),
                    ),
                ]),
              ),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _penyaring(),
      TabBar(
        controller: _tab,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Rencana Bulanan'),
          Tab(text: 'Realisasi'),
          Tab(text: 'Penggunaan Anggaran'),
        ],
      ),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_galat!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _muatKonteks,
                            child: const Text('Coba lagi')),
                      ]),
                    ),
                  )
                : TabBarView(
                    controller: _tab,
                    children: [
                      _tabRencana(),
                      _tabRealisasi(),
                      _tabPenggunaan()
                    ],
                  ),
      ),
    ]);
  }
}
