import 'package:flutter/material.dart';

import '../services/master_offline.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';

/// Layar "Kelompok Aset" — pengganti natif `pages/master/asset/kelompok_asset.zul`,
/// yang sebelumnya dibuka lewat browser sistem dari "Sesuaikan Akun Posting".
///
/// Yang disunting di sini HANYA pemetaan akun, bukan CRUD kelompok aset: itulah
/// yang dibutuhkan saat memperbaiki akun posting, dan mempersempitnya membuat
/// layar ini tidak menduplikasi master aset di web.
///
/// Satu bidang akun berisi DAFTAR pasangan (Akun, Satuan Kerja), bukan satu akun
/// tunggal — satu kelompok boleh memakai akun berbeda untuk satuan kerja yang
/// berbeda. Baris tanpa satuan kerja berlaku umum.
///
/// Catatan: Master Aset sengaja TIDAK disediakan di sini. Getter akunnya
/// mengambil nilai kelompok bila kelompoknya terisi, sehingga menyuntingnya
/// diam-diam tidak berpengaruh pada keadaan yang normal — lihat
/// `docs/pos/103-akun-master-aset-ditimpa-kelompok.md`.
class BidangAkunKelompokAset {
  const BidangAkunKelompokAset(this.kode, this.judul, this.keterangan);

  /// Harus sama persis dengan daftar putih `BIDANG` di `KelompokAsetApiHelper`.
  final String kode;
  final String judul;
  final String keterangan;
}

const daftarBidangAkunKelompokAset = <BidangAkunKelompokAset>[
  BidangAkunKelompokAset('pembelian', 'Akun Pembelian / Persediaan',
      'Dipakai sebagai akun persediaan saat pembelian dan sebagai lawan jurnal HPP penjualan.'),
  BidangAkunKelompokAset('penyusutan', 'Akun Akumulasi Penyusutan',
      'Akun kontra-aset untuk aset tetap.'),
  BidangAkunKelompokAset('biaya', 'Akun Biaya / Biaya Penyusutan',
      'Beban periodik: biaya penyusutan untuk aset tetap, akun biaya untuk non-aset.'),
  BidangAkunKelompokAset('hpp', 'Akun Beban Pokok Penjualan (HPP)',
      'Akun DEBIT saat posting HPP penjualan.'),
];

class KelompokAsetScreen extends StatefulWidget {
  const KelompokAsetScreen({super.key});

  @override
  State<KelompokAsetScreen> createState() => _KelompokAsetScreenState();
}

class _KelompokAsetScreenState extends State<KelompokAsetScreen>
    with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  String _kataKunci = '';
  List<Map<String, dynamic>> _daftar = const [];
  List<Map<String, dynamic>> _akun = const [];
  List<Map<String, dynamic>> _satuanKerja = const [];

  @override
  void initState() {
    super.initState();
    _muat();
    _muatRujukan();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // BACA CACHE DULU: daftar kelompok aset jarang berubah, dan layar ini
      // dibuka justru ketika posting bermasalah — sering di luar jam kantor.
      await MasterOffline.daftarCacheDulu(
        'kelompok_aset_list',
        {'keyword': _kataKunci, 'limit': 200},
        'master:kelompok_aset:$_kataKunci',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _daftar = ((hasil['data'] as List?) ?? const [])
                .cast<Map<String, dynamic>>();
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() {
        _pesanError = terapkanGalat(e);
        _memuat = false;
      });
    }
  }

  Future<void> _muatRujukan() async {
    try {
      final akun = await MasterOffline.daftarDenganCache(
          'akun_list', {'limit': 5000}, 'master:akun');
      final sk = await MasterOffline.daftarDenganCache('satuan_kerja_list',
          {'cari': '', 'tampilkan_nonaktif': false}, 'master:satuan_kerja:_false');
      if (!mounted) return;
      setStateIfMounted(() {
        _akun = ((akun['data'] as List?) ?? const [])
            .cast<Map<String, dynamic>>();
        _satuanKerja =
            ((sk['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      // Rujukan gagal dimuat tidak boleh mengosongkan daftar kelompok aset;
      // pemilih akun akan kosong dan itu sudah cukup memberi tahu.
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    }
  }

  int _jumlahBaris(Map<String, dynamic> k, String bidang) =>
      ((k[bidang] as List?) ?? const []).length;

  Future<void> _buka(Map<String, dynamic> kelompok) async {
    final berubah = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditorAkunKelompokAset(
        kelompok: kelompok,
        akun: _akun,
        satuanKerja: _satuanKerja,
      ),
    );
    if (berubah == true) await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kelompok Aset — Akun Posting')),
      body: Column(
        children: [
          const IndikatorSinkronMaster(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Cari kelompok aset',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                _kataKunci = v.trim();
                _muat();
              },
            ),
          ),
          if (_pesanError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_pesanError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _daftar.isEmpty
                    ? const Center(child: Text('Belum ada kelompok aset.'))
                    : RefreshIndicator(
                        onRefresh: _muat,
                        child: ListView.separated(
                          itemCount: _daftar.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final k = _daftar[i];
                            final ringkas = daftarBidangAkunKelompokAset
                                .map((b) =>
                                    '${b.judul.split(' ').first} ${_jumlahBaris(k, b.kode)}')
                                .join(' · ');
                            return ListTile(
                              title: Text('${k['nama'] ?? ''}'),
                              subtitle: Text(ringkas),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _buka(k),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// Penyunting keempat bidang akun milik SATU kelompok aset.
///
/// Tiap bidang disimpan sendiri-sendiri: server menerima seluruh daftar satu
/// bidang sekaligus, jadi menyimpan per bidang membuat kiriman ulang antrean
/// menghasilkan keadaan yang sama, dan kegagalan satu bidang tidak menyeret
/// bidang lain.
class EditorAkunKelompokAset extends StatefulWidget {
  const EditorAkunKelompokAset({
    super.key,
    required this.kelompok,
    required this.akun,
    required this.satuanKerja,
  });

  final Map<String, dynamic> kelompok;
  final List<Map<String, dynamic>> akun;
  final List<Map<String, dynamic>> satuanKerja;

  @override
  State<EditorAkunKelompokAset> createState() => _EditorAkunKelompokAsetState();
}

class _EditorAkunKelompokAsetState extends State<EditorAkunKelompokAset>
    with JejakGalat {
  late final Map<String, List<Map<String, dynamic>>> _baris;
  final Set<String> _tersimpan = <String>{};
  String? _pesanError;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _baris = <String, List<Map<String, dynamic>>>{};
    for (final b in daftarBidangAkunKelompokAset) {
      _baris[b.kode] = ((widget.kelompok[b.kode] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((e) => <String, dynamic>{
                'akun': (e['akun'] as num?)?.toInt(),
                'satuanKerja': (e['satuanKerja'] as num?)?.toInt(),
                'akunDaun': e['akunDaun'] != false,
              })
          .toList();
    }
  }

  Future<void> _simpan(BidangAkunKelompokAset bidang) async {
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final id = (widget.kelompok['id'] as num?)?.toInt();
      final body = <String, dynamic>{
        'id': id,
        'bidang': bidang.kode,
        'baris': _baris[bidang.kode]!
            .where((r) => r['akun'] != null || r['satuanKerja'] != null)
            .map((r) => {'akun': r['akun'], 'satuanKerja': r['satuanKerja']})
            .toList(),
      };
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'kelompok_aset_akun_simpan',
        body: body,
        kunci: 'kelompok_aset:$id:${bidang.kode}',
        cacheKey: 'master:kelompok_aset',
        rowLokal: body,
      );
      final peringatan = (hasil['peringatan'] as List?) ?? const [];
      if (mounted && peringatan.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(peringatan.join('\n'))));
      }
      setStateIfMounted(() => _tersimpan.add(bidang.kode));
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  Widget _barisEditor(BidangAkunKelompokAset bidang, int i) {
    final r = _baris[bidang.kode]![i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: PemilihAkunField(
              label: 'Akun',
              daftar: widget.akun,
              nilai: r['akun'] as int?,
              onChanged: (v) => setStateIfMounted(() => r['akun'] = v),
              helperText: r['akunDaun'] == false
                  ? 'Bukan akun daun — akun induk tidak menampung transaksi.'
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int?>(
              isExpanded: true,
              value: r['satuanKerja'] as int?,
              decoration: const InputDecoration(
                labelText: 'Satuan Kerja',
                helperText: 'Kosong = berlaku umum',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                    value: null, child: Text('(semua)')),
                ...widget.satuanKerja.map((s) => DropdownMenuItem<int?>(
                      value: (s['id'] as num?)?.toInt(),
                      child: Text('${s['nama'] ?? ''}',
                          overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setStateIfMounted(() => r['satuanKerja'] = v),
            ),
          ),
          IconButton(
            tooltip: 'Hapus baris',
            icon: const Icon(Icons.delete_outline),
            onPressed: () =>
                setStateIfMounted(() => _baris[bidang.kode]!.removeAt(i)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          controller: scrollController,
          children: [
            Text('${widget.kelompok['nama'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
                'Tiap bidang berisi daftar pasangan Akun & Satuan Kerja. '
                'Simpan dilakukan per bidang.',
                style: Theme.of(context).textTheme.bodySmall),
            if (_pesanError != null) ...[
              const SizedBox(height: 8),
              Text(_pesanError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 12),
            for (final bidang in daftarBidangAkunKelompokAset)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(bidang.judul,
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                          ),
                          if (_tersimpan.contains(bidang.kode))
                            const Icon(Icons.check_circle_outline, size: 18),
                        ],
                      ),
                      Text(bidang.keterangan,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      if (_baris[bidang.kode]!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Belum ada akun untuk bidang ini.'),
                        ),
                      for (var i = 0; i < _baris[bidang.kode]!.length; i++)
                        _barisEditor(bidang, i),
                      Row(
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah baris'),
                            onPressed: () => setStateIfMounted(() =>
                                _baris[bidang.kode]!.add(<String, dynamic>{
                                  'akun': null,
                                  'satuanKerja': null,
                                  'akunDaun': true,
                                })),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed:
                                _menyimpan ? null : () => _simpan(bidang),
                            child: const Text('Simpan bidang ini'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_tersimpan.isNotEmpty),
              child: const Text('Tutup'),
            ),
          ],
        ),
      ),
    );
  }
}
