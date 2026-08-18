import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import '../widgets/safe_state.dart';

/// Kelola Toko/Outlet (admin-only) -- padanan layar ZK TokoAction & JSP toko.jsp.
///
/// CRUD toko lewat aksi `toko_kelola_*` + pemilihan multi Unit Usaha per toko
/// (katalog `unit_usaha_katalog`, 60 jenis dari UMKM sampai menengah). Toko demo
/// dapat men-generate produk contoh SESUAI unit usahanya lewat aksi
/// `pos_demo_seed_products_unit_usaha` (250 s.d. 100.000 produk per unit); bila
/// toko belum memilih unit usaha, server membalas `perlu_pilih_unit_usaha` dan
/// layar ini menampilkan popup checkbox -- kontrak yang sama dipakai JSP/ZK.
class TokoKelolaScreen extends StatefulWidget {
  const TokoKelolaScreen({super.key});

  @override
  State<TokoKelolaScreen> createState() => _TokoKelolaScreenState();
}

class _TokoKelolaScreenState extends State<TokoKelolaScreen> {
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];
  List<Map<String, dynamic>> _katalogUnit = [];
  final _cari = TextEditingController();
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _pastikanKatalog() async {
    if (_katalogUnit.isNotEmpty) return _katalogUnit;
    final res = await MasterOffline.daftarDenganCache(
        'unit_usaha_katalog', {}, 'master:unit_usaha_katalog');
    if (res['status'] != '00' && res['status'] != 'success') {
      throw Exception(res['description'] ?? 'Gagal memuat katalog unit usaha.');
    }
    _katalogUnit = (res['data'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return _katalogUnit;
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu('toko_kelola_list',
          {'cari': _cari.text.trim()}, 'master:toko_kelola',
          // Tanpa kata kunci respons = SELURUH toko (boleh deteksi hapus);
          // saat mencari respons parsial -> merge saja, lokal dipertahankan.
          responsLengkap: _cari.text.trim().isEmpty, onData: (res) {
        if (!mounted) return;
        final sukses = res['status'] == '00' || res['status'] == 'success';
        if (!sukses) {
          setStateIfMounted(() {
            _galat = '${res['description'] ?? 'Gagal memuat daftar toko.'}';
            _memuat = false;
          });
          return;
        }
        final data = (res['data'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final dariServer = res['dariServer'] == true;
        setStateIfMounted(() {
          _daftar = data;
          _idBaru = dariServer
              ? Set<String>.from(res['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(res['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus = dariServer ? (res['jumlahHapus'] as int? ?? 0) : 0;
          if (dariServer &&
              (_idBaru.isNotEmpty ||
                  _idBerubah.isNotEmpty ||
                  _jumlahHapus > 0)) {
            _versiPerubahan++;
          }
          _memuat = false;
        });
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  void _snack(String pesan, {bool galat = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pesan),
        backgroundColor: galat ? Theme.of(context).colorScheme.error : null));
  }

  Future<void> _simpan(Map<String, dynamic>? awal) async {
    final List<Map<String, dynamic>> katalog;
    try {
      katalog = await _pastikanKatalog();
    } catch (e) {
      _snack('$e', galat: true);
      return;
    }
    if (!mounted) return;
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormTokoDialog(awal: awal, katalogUnit: katalog),
    );
    if (hasil == null || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'toko_kelola_simpan',
        body: hasil,
        kunci: hasil['id'] != null
            ? 'toko:${hasil['id']}'
            : 'toko:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:toko_kelola',
        rowLokal: hasil,
      );
      await _muat();
    } catch (e) {
      _snack('Gagal menyimpan: $e', galat: true);
    }
  }

  Future<void> _hapus(Map<String, dynamic> t) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Toko'),
        content: Text('Hapus toko "${t['nama']}"? Toko yang masih memiliki '
            'produk atau akun pedagang akan ditolak server.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster).
      await prosesSimpanMaster(
        context,
        aksi: 'toko_kelola_hapus',
        body: {'id': t['id']},
        kunci: 'toko:${t['id']}',
        cacheKey: 'master:toko_kelola',
        rowLokal: {'id': t['id']},
        hapusLokal: true,
      );
      await _muat();
    } catch (e) {
      _snack('Gagal menghapus: $e', galat: true);
    }
  }

  /// Generate produk contoh per unit usaha. Selalu menampilkan popup pilihan
  /// (pre-checked dari unit usaha toko) supaya admin sadar apa yang di-seed;
  /// popup yang sama menjadi jawaban `perlu_pilih_unit_usaha` dari server.
  Future<void> _generateProduk(Map<String, dynamic> t) async {
    final List<Map<String, dynamic>> katalog;
    try {
      katalog = await _pastikanKatalog();
    } catch (e) {
      _snack('$e', galat: true);
      return;
    }
    final terpilihAwal = ((t['unit_usaha'] as List?) ?? [])
        .map((e) => (e as Map)['kode'].toString())
        .toSet();
    if (!mounted) return;
    final pilihan = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PilihUnitUsahaDialog(
          namaToko: '${t['nama']}',
          katalog: katalog,
          terpilihAwal: terpilihAwal),
    );
    if (pilihan == null) return;
    try {
      final res =
          await ApiClient.instance.aksi('pos_demo_seed_products_unit_usaha', {
        'toko_id': t['id'],
        'unit_usaha': pilihan['unit_usaha'],
        'jumlah_per_unit': pilihan['jumlah_per_unit'],
        'konfirmasi': 'SEED-DEMO-PRODUK-UNIT-USAHA',
      });
      if (res['perlu_pilih_unit_usaha'] == true) {
        _snack('Pilih minimal satu unit usaha dahulu.', galat: true);
        return;
      }
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!sukses) {
        _snack('Gagal: ${res['description'] ?? res['status']}', galat: true);
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProgressGenerateDialog(tokoId: t['id']),
      );
    } catch (e) {
      _snack('Gagal generate: $e', galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Toko / Outlet'),
        actions: [
          const IndikatorSinkronMaster(),
          IconButton(
              onPressed: _muat,
              tooltip: 'Muat ulang',
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _simpan(null),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Tambah Toko'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _cari,
              decoration: InputDecoration(
                labelText: 'Cari nama/kode toko',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _cari.clear();
                      _muat();
                    }),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _muat(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: BannerPerubahanServer(
              key: ValueKey('perubahan:$_versiPerubahan'),
              baru: _idBaru.length,
              berubah: _idBerubah.length,
              dihapus: _jumlahHapus,
            ),
          ),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _galat != null
                    ? Center(
                        child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_galat!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: _muat,
                                child: const Text('Coba lagi')),
                          ],
                        ),
                      ))
                    : _daftar.isEmpty
                        ? const Center(child: Text('Belum ada toko.'))
                        : RefreshIndicator(
                            onRefresh: _muat,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _daftar.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (c, i) => _kartuToko(_daftar[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _kartuToko(Map<String, dynamic> t) {
    final aktif = t['aktif'] == true;
    final demo = t['toko_demo'] == true;
    final unit = ((t['unit_usaha'] as List?) ?? [])
        .map((e) => (e as Map)['label'].toString())
        .toList();
    return Card(
      child: ListTile(
        title: KilauBaris(
          kunci: '${t['id'] ?? t['_kunci'] ?? ''}',
          idBaru: _idBaru,
          idBerubah: _idBerubah,
          child: Row(children: [
            IndikatorBarisSinkron(kunci: kunciBarisMaster('toko', t)),
            Expanded(
              child: Text(
                  '${(t['kode'] ?? '').toString().isEmpty ? '' : '${t['kode']} - '}${t['nama']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(unit.isEmpty
                ? 'Unit usaha: belum dipilih'
                : 'Unit usaha: ${unit.join(', ')}'),
            if (!aktif || demo)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 6, children: [
                  if (!aktif) const Chip(label: Text('NONAKTIF')),
                  if (demo) const Chip(label: Text('TOKO DEMO')),
                ]),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t['id'] != null)
              IconButton(
                  tooltip: 'Riwayat data ini (AuditTrails)',
                  onPressed: () => tampilkanRiwayatData(context,
                      entitas: 'toko', id: t['id'], judul: '${t['nama'] ?? ''}'),
                  icon: const Icon(Icons.history)),
            if (demo)
              IconButton(
                  tooltip: 'Generate produk contoh sesuai unit usaha',
                  onPressed: () => _generateProduk(t),
                  icon: const Icon(Icons.auto_awesome_outlined)),
            IconButton(
                tooltip: 'Ubah',
                onPressed: () => _simpan(t),
                icon: const Icon(Icons.edit_outlined)),
            IconButton(
                tooltip: 'Hapus',
                onPressed: () => _hapus(t),
                icon: const Icon(Icons.delete_outline)),
          ],
        ),
      ),
    );
  }
}

/// Checkbox unit usaha ber-grup (Retail, Kuliner, Otomotif, Jasa, Agri, ...).
class _PilihanUnitUsaha extends StatelessWidget {
  final List<Map<String, dynamic>> katalog;
  final Set<String> terpilih;
  final ValueChanged<String> onToggle;
  const _PilihanUnitUsaha(
      {required this.katalog, required this.terpilih, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final anak = <Widget>[];
    String? grupAktif;
    for (final e in katalog) {
      final grup = '${e['grup']}';
      if (grup != grupAktif) {
        grupAktif = grup;
        anak.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(grup,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ));
      }
      final kode = '${e['kode']}';
      anak.add(CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('${e['label']}'),
        value: terpilih.contains(kode),
        onChanged: (_) => onToggle(kode),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: anak);
  }
}

class _FormTokoDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  final List<Map<String, dynamic>> katalogUnit;
  const _FormTokoDialog({this.awal, required this.katalogUnit});

  @override
  State<_FormTokoDialog> createState() => _FormTokoDialogState();
}

class _FormTokoDialogState extends State<_FormTokoDialog> {
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late bool _aktif;
  late bool _bolehLihatTokoLain;
  late bool _bolehStokHabis;
  late bool _tokoDemo;
  late final Set<String> _unit;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _kode = TextEditingController(text: (a?['kode'] ?? '').toString());
    _nama = TextEditingController(text: (a?['nama'] ?? '').toString());
    _keterangan =
        TextEditingController(text: (a?['keterangan'] ?? '').toString());
    _aktif = a == null || a['aktif'] == true;
    _bolehLihatTokoLain = a?['boleh_melihat_toko_lain'] == true;
    _bolehStokHabis = a?['boleh_transaksi_stok_habis'] == true;
    _tokoDemo = a?['toko_demo'] == true;
    _unit = ((a?['unit_usaha'] as List?) ?? [])
        .map((e) => (e as Map)['kode'].toString())
        .toSet();
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baru = widget.awal == null;
    return AlertDialog(
      title: Text(baru ? 'Tambah Toko' : 'Ubah Toko'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                  controller: _nama,
                  decoration: const InputDecoration(
                      labelText: 'Nama Toko *',
                      hintText: 'Mis. Outlet Cabang Bandung')),
              const SizedBox(height: 8),
              TextField(
                  controller: _kode,
                  decoration: const InputDecoration(
                      labelText: 'Kode', hintText: 'Opsional')),
              const SizedBox(height: 8),
              TextField(
                  controller: _keterangan,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Keterangan')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: _aktif,
                  onChanged: (v) => setState(() => _aktif = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Boleh melihat toko lain'),
                  value: _bolehLihatTokoLain,
                  onChanged: (v) => setState(() => _bolehLihatTokoLain = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Paksa semua produk boleh stok minus'),
                  value: _bolehStokHabis,
                  onChanged: (v) => setState(() => _bolehStokHabis = v)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Toko demo (target data contoh)'),
                  value: _tokoDemo,
                  onChanged: (v) => setState(() => _tokoDemo = v)),
              const Divider(),
              const Text('Unit Usaha (boleh pilih lebih dari satu)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Text(
                  'Menjadi dasar generate produk contoh untuk toko demo.',
                  style: TextStyle(fontSize: 12)),
              _PilihanUnitUsaha(
                  katalog: widget.katalogUnit,
                  terpilih: _unit,
                  onToggle: (kode) => setState(() {
                        if (!_unit.add(kode)) _unit.remove(kode);
                      })),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_nama.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Nama toko wajib diisi.')));
              return;
            }
            Navigator.pop(context, <String, dynamic>{
              if (!baru) 'id': widget.awal!['id'],
              'nama': _nama.text.trim(),
              'kode': _kode.text.trim(),
              'keterangan': _keterangan.text.trim(),
              'aktif': _aktif,
              'boleh_melihat_toko_lain': _bolehLihatTokoLain,
              'boleh_transaksi_stok_habis': _bolehStokHabis,
              'toko_demo': _tokoDemo,
              'unit_usaha': _unit.toList(),
            });
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

/// Popup pemilihan unit usaha + jumlah produk per unit sebelum generate.
class _PilihUnitUsahaDialog extends StatefulWidget {
  final String namaToko;
  final List<Map<String, dynamic>> katalog;
  final Set<String> terpilihAwal;
  const _PilihUnitUsahaDialog(
      {required this.namaToko,
      required this.katalog,
      required this.terpilihAwal});

  @override
  State<_PilihUnitUsahaDialog> createState() => _PilihUnitUsahaDialogState();
}

class _PilihUnitUsahaDialogState extends State<_PilihUnitUsahaDialog> {
  late final Set<String> _unit = {...widget.terpilihAwal};
  final _jumlah = TextEditingController(text: '250');

  @override
  void dispose() {
    _jumlah.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Generate Produk Contoh — ${widget.namaToko}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  widget.terpilihAwal.isEmpty
                      ? 'Toko ini belum memiliki unit usaha. Centang jenis '
                          'usaha yang produk contohnya akan diimpor.'
                      : 'Produk contoh dibuat sesuai unit usaha terpilih.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                  controller: _jumlah,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Jumlah produk per unit usaha',
                      helperText: 'Minimal 250, maksimal 100.000 per unit')),
              _PilihanUnitUsaha(
                  katalog: widget.katalog,
                  terpilih: _unit,
                  onToggle: (kode) => setState(() {
                        if (!_unit.add(kode)) _unit.remove(kode);
                      })),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (_unit.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Pilih minimal satu unit usaha.')));
              return;
            }
            final jumlah = int.tryParse(_jumlah.text.trim()) ?? 250;
            Navigator.pop(context, <String, dynamic>{
              'unit_usaha': _unit.toList(),
              // Server tetap meng-clamp 250..100000; clamp di sini hanya
              // supaya angka yang dikirim = angka yang dijalankan.
              'jumlah_per_unit': jumlah.clamp(250, 100000),
            });
          },
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

/// Dialog progres: poll `pos_demo_status` sampai job latar server selesai.
class _ProgressGenerateDialog extends StatefulWidget {
  final dynamic tokoId;
  const _ProgressGenerateDialog({required this.tokoId});

  @override
  State<_ProgressGenerateDialog> createState() =>
      _ProgressGenerateDialogState();
}

class _ProgressGenerateDialogState extends State<_ProgressGenerateDialog> {
  String _tahap = 'Memulai...';
  int _selesai = 0;
  int _target = 0;
  bool _tuntas = false;
  String? _ringkasan;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  Future<void> _poll() async {
    while (mounted && !_tuntas) {
      try {
        final res = await ApiClient.instance
            .aksi('pos_demo_status', {'toko_id': widget.tokoId});
        if (!mounted) return;
        setState(() {
          _tahap = (res['tahap'] ?? '').toString();
          _selesai = (res['selesai'] as num? ?? 0).toInt();
          _target = (res['target'] as num? ?? 0).toInt();
          if (res['berjalan'] == false) {
            _tuntas = true;
            _ringkasan = (res['ringkasan'] ?? '').toString();
          }
        });
      } catch (_) {
        // Sekali gagal poll bukan kegagalan job (job jalan di server);
        // coba lagi pada iterasi berikutnya.
      }
      if (!_tuntas) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rasio = _target == 0 ? null : (_selesai / _target).clamp(0.0, 1.0);
    return AlertDialog(
      title: const Text('Generate Produk Contoh'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_tuntas ? (_ringkasan ?? 'Selesai.') : _tahap),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _tuntas ? 1.0 : rasio),
          const SizedBox(height: 8),
          Text('$_selesai / ${_target == 0 ? '...' : _target}'),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _tuntas ? () => Navigator.pop(context) : null,
          child: Text(_tuntas ? 'Tutup' : 'Berjalan...'),
        ),
      ],
    );
  }
}
