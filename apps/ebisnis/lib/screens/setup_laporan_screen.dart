import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Setup Laporan untuk POS Desktop dan Android.
///
/// Ini adalah padanan native layar ZK
/// `pages/master/akunting/kelompok_laporan_dan_detail.zul`: pengguna melihat
/// Jenis Laporan -> Grup Laporan -> Sub Laporan -> akun yang dijumlahkan.
/// Daftar dibaca dari cache lebih dahulu. Semua mutasi sengaja ONLINE-ONLY
/// karena memindahkan akun dapat langsung mengubah Neraca/Laba Rugi; perubahan
/// seperti ini tidak aman dimasukkan outbox dan tidak boleh diberi sukses lokal
/// palsu.
class SetupLaporanScreen extends StatefulWidget {
  const SetupLaporanScreen({super.key});

  @override
  State<SetupLaporanScreen> createState() => _SetupLaporanScreenState();
}

class _SetupLaporanScreenState extends State<SetupLaporanScreen> {
  static const _cacheKey = 'master:pemetaan_akun_setup_laporan';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;
  String _cari = '';
  String _jenisDipilih = '';
  String _grupDipilih = '';
  String _statusDipilih = 'semua';

  List<Map<String, dynamic>> _kelompok = [];
  List<Map<String, dynamic>> _jenis = [];
  List<Map<String, dynamic>> _masterGrup = [];
  List<Map<String, dynamic>> _akun = [];
  Map<String, bool> _hak = const {};
  int _jumlahTerpetakan = 0;
  int _jumlahBelum = 0;
  int _jumlahRelasi = 0;
  bool _dariServer = false;
  bool _dataDipotong = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  static List<Map<String, dynamic>> _daftar(dynamic nilai) =>
      ((nilai as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  static Map<String, bool> _bacaHak(dynamic nilai) {
    final hasil = <String, bool>{};
    if (nilai is Map) {
      for (final e in nilai.entries) {
        hasil['${e.key}'] = e.value == true;
      }
    }
    return hasil;
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'pemetaan_akun_setup_daftar',
        const {'batasAkun': 10000},
        _cacheKey,
        responsLengkap: true,
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _kelompok = _daftar(hasil['data']);
            _dariServer = hasil['dariServer'] == true;
            if (hasil.containsKey('jenisLaporan')) {
              _jenis = _daftar(hasil['jenisLaporan']);
            }
            if (hasil.containsKey('masterGrupLaporan')) {
              _masterGrup = _daftar(hasil['masterGrupLaporan']);
            }
            if (hasil.containsKey('akunTersedia')) {
              _akun = _daftar(hasil['akunTersedia']);
            }
            if (hasil.containsKey('hak')) _hak = _bacaHak(hasil['hak']);
            _jumlahTerpetakan =
                (hasil['jumlahAkunTerpetakan'] as num?)?.toInt() ??
                    _akunTerpetakanLokal;
            _jumlahBelum =
                (hasil['jumlahAkunBelumTerpetakan'] as num?)?.toInt() ?? 0;
            _jumlahRelasi = (hasil['jumlahRelasi'] as num?)?.toInt() ??
                _kelompok.fold<int>(
                    0, (n, k) => n + ((k['qtyAkun'] as num?)?.toInt() ?? 0));
            _dataDipotong = hasil['dataDipotong'] == true;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  int get _akunTerpetakanLokal {
    final ids = <String>{};
    for (final k in _kelompok) {
      for (final a in _daftar(k['akun'])) {
        ids.add('${a['akunId']}');
      }
    }
    return ids.length;
  }

  bool _boleh(String aksi) => _hak[aksi] ?? false;

  List<Map<String, dynamic>> get _hasilFilter {
    final q = _cari.trim().toLowerCase();
    return _kelompok.where((k) {
      if (_jenisDipilih.isNotEmpty && '${k['jenisId']}' != _jenisDipilih) {
        return false;
      }
      if (_grupDipilih.isNotEmpty && '${k['masterGrupId']}' != _grupDipilih) {
        return false;
      }
      if (_statusDipilih == 'aktif' && k['aktif'] != true) return false;
      if (_statusDipilih == 'nonaktif' && k['aktif'] == true) return false;
      if (q.isEmpty) return true;
      final teks = [
        k['jenisNama'],
        k['jenisKeterangan'],
        k['masterGrupNama'],
        k['masterGrupKeterangan'],
        k['keterangan'],
        k['keterangan1'],
        ..._daftar(k['akun']).expand((a) => [a['kode'], a['nama']]),
      ].join(' ').toLowerCase();
      return teks.contains(q);
    }).toList()
      ..sort((a, b) {
        final jenis = '${a['jenisNama']}'.compareTo('${b['jenisNama']}');
        if (jenis != 0) return jenis;
        final grup =
            '${a['masterGrupNama']}'.compareTo('${b['masterGrupNama']}');
        if (grup != 0) return grup;
        return ((a['urut'] as num?)?.toDouble() ?? 0)
            .compareTo((b['urut'] as num?)?.toDouble() ?? 0);
      });
  }

  Future<Map<String, dynamic>?> _aksiOnline(
      String aksi, Map<String, dynamic> body) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      // Online-only: pemetaan memengaruhi angka laporan dan harus divalidasi
      // server dalam transaksi yang sama. Jangan dialihkan ke MasterOffline.
      final hasil = await ApiClient.instance.aksi(aksi, body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Berhasil.'}')),
        );
      }
      await _muat();
      return hasil;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Perubahan belum disimpan: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
      return null;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _petakanOtomatis() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final usulan = await ApiClient.instance
          .aksi('pemetaan_akun_usulan', const {'batasContoh': 30});
      if (!mounted) return;
      final jumlah = (usulan['jumlahBelumDipetakan'] as num?)?.toInt() ?? 0;
      if (jumlah == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Semua akun sudah memiliki kelompok laporan.')),
        );
        return;
      }
      final setuju = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Petakan akun otomatis?'),
          content: Text('$jumlah akun belum terpetakan. Sistem akan memakai '
              'hierarki bagan akun untuk memilih Jenis dan Kelompok Laporan. '
              'Pemetaan yang sudah ada tidak dihapus atau ditimpa.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Terapkan')),
          ],
        ),
      );
      if (setuju == true) {
        await _aksiOnline('pemetaan_akun_terapkan', const {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Pemetaan otomatis belum dapat dijalankan: $e')),
        );
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _formKelompok([Map<String, dynamic>? data]) async {
    final jenisAwal = data == null ? null : '${data['jenisId']}';
    String? jenisId = _jenis.any((e) => '${e['id']}' == jenisAwal)
        ? jenisAwal
        : (_jenis.isEmpty ? null : '${_jenis.first['id']}');
    final grupAwal = data == null ? '' : '${data['masterGrupId'] ?? ''}';
    String grupId =
        _masterGrup.any((e) => '${e['id']}' == grupAwal) ? grupAwal : '';
    final sub = TextEditingController(text: '${data?['keterangan'] ?? ''}');
    final ket = TextEditingController(text: '${data?['keterangan1'] ?? ''}');
    final urut = TextEditingController(text: '${data?['urut'] ?? 0}');
    bool aktif = data?['aktif'] != false;
    bool rinci = data?['rinci'] != false;
    String? pesan;
    final simpan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) {
        return AppDetailDialogShell(
          title: data == null
              ? 'Tambah Kelompok Laporan'
              : 'Ubah Kelompok Laporan',
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (jenisId == null || sub.text.trim().isEmpty) {
                  setLocal(() =>
                      pesan = 'Jenis Laporan dan Sub Laporan wajib diisi.');
                  return;
                }
                Navigator.pop(c, {
                  if (data != null) 'id': data['id'],
                  'jenisId': int.parse(jenisId!),
                  'masterGrupId': int.tryParse(grupId) ?? 0,
                  'keterangan': sub.text.trim(),
                  'keterangan1': ket.text.trim(),
                  'urut': double.tryParse(urut.text.trim()) ?? 0,
                  'rinci': rinci,
                  'aktif': aktif,
                });
              },
              child: const Text('Simpan'),
            ),
          ],
          children: [
            DropdownButtonFormField<String>(
              value: jenisId,
              decoration: const InputDecoration(
                  labelText: 'Jenis Laporan *', border: OutlineInputBorder()),
              items: _jenis
                  .map((e) => DropdownMenuItem(
                      value: '${e['id']}', child: Text('${e['nama']}')))
                  .toList(),
              onChanged: (v) => setLocal(() => jenisId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: grupId,
              decoration: const InputDecoration(
                  labelText: 'Grup Laporan', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: '', child: Text('Tanpa grup / Lainnya')),
                ..._masterGrup.map((e) => DropdownMenuItem(
                    value: '${e['id']}',
                    child: Text('${e['nama']} — ${e['keterangan']}'))),
              ],
              onChanged: (v) => setLocal(() => grupId = v ?? ''),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: sub,
                decoration: const InputDecoration(
                    labelText: 'Sub Laporan *', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: ket,
                decoration: const InputDecoration(
                    labelText: 'Keterangan tambahan',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: urut,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Nomor urut', border: OutlineInputBorder())),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: rinci,
                title: const Text('Tampilkan akun rinci'),
                onChanged: (v) => setLocal(() => rinci = v ?? true)),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: aktif,
                title: const Text('Aktif'),
                onChanged: (v) => setLocal(() => aktif = v ?? true)),
            if (pesan != null)
              Text(pesan!, style: const TextStyle(color: AppColors.danger)),
          ],
        );
      }),
    );
    sub.dispose();
    ket.dispose();
    urut.dispose();
    if (simpan != null) {
      await _aksiOnline('pemetaan_akun_setup_kelompok_simpan', simpan);
    }
  }

  Future<void> _tambahAkun(Map<String, dynamic> kelompok) async {
    if (_akun.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Daftar akun harus dimuat dari server sebelum pemetaan dapat diubah.'),
      ));
      return;
    }
    final sudah =
        _daftar(kelompok['akun']).map((e) => '${e['akunId']}').toSet();
    final dipilih = <String>{};
    String cari = '';
    bool pindahkan = false;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setLocal) {
        final q = cari.toLowerCase();
        final opsi = _akun.where((a) {
          if (sudah.contains('${a['id']}')) return false;
          return q.isEmpty ||
              '${a['kode']} ${a['nama']}'.toLowerCase().contains(q);
        }).toList();
        return AlertDialog(
          title: Text('Tambah Akun — ${kelompok['keterangan']}'),
          content: SizedBox(
            width: 760,
            height: 540,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Cari kode atau nama akun',
                    border: OutlineInputBorder()),
                onChanged: (v) => setLocal(() => cari = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: pindahkan,
                title: const Text(
                    'Pindahkan bila akun sudah berada di kelompok lain pada jenis laporan yang sama'),
                subtitle: const Text(
                    'Tanpa pilihan ini, akun bentrok dilewati agar nilai laporan tidak terhitung ganda.'),
                onChanged: (v) => setLocal(() => pindahkan = v ?? false),
              ),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      '${dipilih.length} akun dipilih • ${opsi.length} hasil')),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.builder(
                  itemCount: opsi.length,
                  itemBuilder: (_, i) {
                    final a = opsi[i];
                    final id = '${a['id']}';
                    return CheckboxListTile(
                      dense: true,
                      value: dipilih.contains(id),
                      title: Text('${a['kode']}  ${a['nama']}'),
                      subtitle: '${a['keterangan'] ?? ''}'.trim().isEmpty
                          ? null
                          : Text('${a['keterangan']}'),
                      onChanged: (v) => setLocal(() =>
                          v == true ? dipilih.add(id) : dipilih.remove(id)),
                    );
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            FilledButton.icon(
              onPressed: dipilih.isEmpty
                  ? null
                  : () => Navigator.pop(c, {
                        'kelompokId': kelompok['id'],
                        'akunIds': dipilih.map(int.parse).toList(),
                        'pindahkan': pindahkan,
                      }),
              icon: const Icon(Icons.add),
              label: const Text('Tambahkan'),
            ),
          ],
        );
      }),
    );
    if (body != null) {
      await _aksiOnline('pemetaan_akun_setup_akun_tambah', body);
    }
  }

  Future<void> _ubahUrutan(Map<String, dynamic> akun) async {
    final controller = TextEditingController(text: '${akun['nomorUrut'] ?? 0}');
    final nilai = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nomor urut ${akun['kode']}'),
        content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Nomor urut', border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(c, int.tryParse(controller.text.trim()) ?? 0),
              child: const Text('Simpan')),
        ],
      ),
    );
    controller.dispose();
    if (nilai != null) {
      await _aksiOnline('pemetaan_akun_setup_akun_urut',
          {'mappingId': akun['mappingId'], 'nomorUrut': nilai});
    }
  }

  Future<void> _hapusAkun(Map<String, dynamic> akun) async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Lepas akun dari laporan?'),
        content: Text(
            '${akun['kode']} ${akun['nama']} akan dilepas dari kelompok ini. Akun, jurnal, dan saldo tidak dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lepas')),
        ],
      ),
    );
    if (setuju == true) {
      await _aksiOnline(
          'pemetaan_akun_setup_akun_hapus', {'mappingId': akun['mappingId']});
    }
  }

  Future<void> _bersihkan(Map<String, dynamic> kelompok) async {
    final jumlah = (kelompok['qtyAkun'] as num?)?.toInt() ?? 0;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bersihkan daftar akun?'),
        content: Text(
            '$jumlah pemetaan pada ${kelompok['keterangan']} akan dilepas. Tindakan ini tidak menghapus akun atau jurnal, tetapi dapat mengubah angka laporan sampai akun dipetakan kembali.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Bersihkan')),
        ],
      ),
    );
    if (setuju == true) {
      await _aksiOnline('pemetaan_akun_setup_bersihkan',
          {'kelompokId': kelompok['id'], 'konfirmasi': 'BERSIHKAN'});
    }
  }

  Widget _filter() {
    return AppSectionCard(
      child: LayoutBuilder(builder: (context, box) {
        final lebar = box.maxWidth < 760 ? box.maxWidth : 260.0;
        return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                  width: lebar,
                  child: AppSearchField(
                      hintText: 'Kode akun, nama, atau kelompok...',
                      labelText: 'Pencarian',
                      onChanged: (v) => setStateIfMounted(() => _cari = v))),
              SizedBox(
                  width: lebar,
                  child: DropdownButtonFormField<String>(
                    value: _jenisDipilih,
                    decoration: const InputDecoration(
                        labelText: 'Jenis Laporan',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Semua jenis')),
                      ..._jenis.map((e) => DropdownMenuItem(
                          value: '${e['id']}', child: Text('${e['nama']}')))
                    ],
                    onChanged: (v) =>
                        setStateIfMounted(() => _jenisDipilih = v ?? ''),
                  )),
              SizedBox(
                  width: lebar,
                  child: DropdownButtonFormField<String>(
                    value: _grupDipilih,
                    decoration: const InputDecoration(
                        labelText: 'Grup Laporan',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('Semua grup')),
                      ..._masterGrup.map((e) => DropdownMenuItem(
                          value: '${e['id']}', child: Text('${e['nama']}')))
                    ],
                    onChanged: (v) =>
                        setStateIfMounted(() => _grupDipilih = v ?? ''),
                  )),
              SizedBox(
                  width: lebar,
                  child: DropdownButtonFormField<String>(
                    value: _statusDipilih,
                    decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: 'semua', child: Text('Semua status')),
                      DropdownMenuItem(value: 'aktif', child: Text('Aktif')),
                      DropdownMenuItem(
                          value: 'nonaktif', child: Text('Nonaktif'))
                    ],
                    onChanged: (v) =>
                        setStateIfMounted(() => _statusDipilih = v ?? 'semua'),
                  )),
              OutlinedButton.icon(
                  onPressed: _sibuk ? null : _muat,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Muat ulang')),
              if (_boleh('create'))
                FilledButton.icon(
                    onPressed: _sibuk ? null : () => _formKelompok(),
                    icon: const Icon(Icons.add),
                    label: const Text('Tambah Kelompok')),
              if (_boleh('create'))
                OutlinedButton.icon(
                    onPressed: _sibuk ? null : _petakanOtomatis,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Petakan Otomatis')),
              if (_sibuk)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]);
      }),
    );
  }

  Widget _ringkasan() {
    final kartu = [
      (
        Icons.account_tree_outlined,
        AppColors.primary,
        '${_kelompok.length}',
        'Kelompok laporan'
      ),
      (Icons.link, AppColors.success, '$_jumlahRelasi', 'Relasi akun'),
      (
        Icons.check_circle_outline,
        AppColors.info,
        '$_jumlahTerpetakan',
        'Akun terpetakan'
      ),
      (
        Icons.warning_amber,
        _jumlahBelum == 0 ? AppColors.success : AppColors.warning,
        '$_jumlahBelum',
        'Belum terpetakan'
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final n = box.maxWidth < 700 ? 2 : 4;
      final w = (box.maxWidth - (n - 1) * 10) / n;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final k in kartu)
          SizedBox(
              width: w,
              child:
                  AppKpiCard(icon: k.$1, warna: k.$2, nilai: k.$3, label: k.$4))
      ]);
    });
  }

  Widget _akunTable(Map<String, dynamic> kelompok) {
    final akun = _daftar(kelompok['akun']);
    if (akun.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
            'Belum ada akun pada kelompok ini. Gunakan Tambah Akun atau Petakan Otomatis.',
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 38,
        dataRowMaxHeight: 52,
        columns: const [
          DataColumn(label: Text('Kode Akun')),
          DataColumn(label: Text('Nama Akun')),
          DataColumn(label: Text('Keterangan')),
          DataColumn(label: Text('Nomor Urut'), numeric: true),
          DataColumn(label: Text('Aksi')),
        ],
        rows: [
          for (final a in akun.take(100))
            DataRow(cells: [
              DataCell(SizedBox(width: 110, child: Text('${a['kode']}'))),
              DataCell(SizedBox(
                  width: 250,
                  child:
                      Text('${a['nama']}', overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(
                  width: 320,
                  child: Text('${a['keterangan'] ?? ''}',
                      overflow: TextOverflow.ellipsis))),
              DataCell(Text('${a['nomorUrut'] ?? 0}')),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                if (_boleh('update'))
                  IconButton(
                      tooltip: 'Ubah nomor urut',
                      onPressed: _sibuk ? null : () => _ubahUrutan(a),
                      icon: const Icon(Icons.edit_outlined, size: 18)),
                if (_boleh('delete'))
                  IconButton(
                      tooltip: 'Lepas dari kelompok',
                      onPressed: _sibuk ? null : () => _hapusAkun(a),
                      icon: const Icon(Icons.link_off,
                          size: 18, color: AppColors.danger)),
              ])),
            ]),
        ],
      ),
    );
  }

  Widget _kelompokCard(Map<String, dynamic> k) {
    final jumlah = (k['qtyAkun'] as num?)?.toInt() ?? _daftar(k['akun']).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
            k['aktif'] == true
                ? Icons.folder_open_outlined
                : Icons.folder_off_outlined,
            color: k['aktif'] == true
                ? AppColors.primary
                : AppColors.textSecondaryOf(context)),
        title: Text(
            '${k['jenisNama']} • ${k['masterGrupNama']}'
                .replaceAll(RegExp(r' • $'), ''),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${k['keterangan']}${'${k['keterangan1'] ?? ''}'.trim().isEmpty ? '' : ' — ${k['keterangan1']}'}'),
        trailing: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusPill(
                  label: '$jumlah akun',
                  warna: jumlah > 0 ? AppColors.success : AppColors.warning),
              StatusPill(
                  label: k['rinci'] == true ? 'Rinci' : 'Ringkas',
                  warna: AppColors.info),
              if (_boleh('update'))
                IconButton(
                    tooltip: 'Ubah kelompok',
                    onPressed: _sibuk ? null : () => _formKelompok(k),
                    icon: const Icon(Icons.edit_outlined)),
            ]),
        children: [
          Container(
            width: double.infinity,
            color: AppColors.pageBgOf(context),
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (_boleh('create'))
                  FilledButton.icon(
                      onPressed: _sibuk ? null : () => _tambahAkun(k),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Tambah Akun')),
                if (_boleh('delete') && jumlah > 0)
                  OutlinedButton.icon(
                      onPressed: _sibuk ? null : () => _bersihkan(k),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Bersihkan')),
                if (jumlah > 100)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                          'Menampilkan 100 dari $jumlah akun; gunakan pencarian untuk mempersempit.')),
              ]),
              const SizedBox(height: 8),
              _akunTable(k),
            ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_galat != null && _kelompok.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 42),
          const SizedBox(height: 12),
          Text('Setup Laporan belum dapat dimuat.\n$_galat',
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _muat, child: const Text('Coba lagi')),
        ]),
      ));
    }
    final data = _hasilFilter;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.info),
              border: Border.all(color: AppColors.info.withValues(alpha: .35)),
              borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: AppColors.info),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    'Kelompok di halaman ini menentukan akun mana yang dijumlahkan pada Neraca, Laba Rugi, dan laporan berbasis jurnal. Grup Akun hanya merapikan bagan akun dan tidak menggantikan pemetaan ini. Daftar ${_dariServer ? 'sudah diperbarui dari server' : 'sedang dibaca dari cache lokal'}; setiap perubahan memerlukan koneksi dan validasi server.')),
          ]),
        ),
        if (_dataDipotong)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Data mencapai batas aman 10.000 akun. Gunakan pencarian atau periksa data duplikat.',
                  style: const TextStyle(
                      color: AppColors.warning, fontWeight: FontWeight.w600))),
        const SizedBox(height: 10),
        _ringkasan(),
        const SizedBox(height: 10),
        _filter(),
        const SizedBox(height: 10),
        Expanded(
          child: data.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.account_tree_outlined, size: 46),
                  const SizedBox(height: 10),
                  Text(_kelompok.isEmpty
                      ? 'Belum ada kelompok laporan.'
                      : 'Tidak ada kelompok yang cocok dengan filter.'),
                  const SizedBox(height: 10),
                  if (_kelompok.isEmpty && _boleh('create'))
                    FilledButton.icon(
                        onPressed: _petakanOtomatis,
                        icon: const Icon(Icons.auto_fix_high),
                        label: const Text('Petakan akun otomatis')),
                ]))
              : ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (_, i) => _kelompokCard(data[i])),
        ),
      ]),
    );
  }
}
