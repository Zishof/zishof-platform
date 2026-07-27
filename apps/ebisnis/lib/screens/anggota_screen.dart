import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../models.dart';

/// Layar Customer/Anggota (padanan anggota.html/anggota-renderer.js Electron)
/// -- BEDA dari Produk: daftarnya paginasi SERVER-SIDE (aksi `anggota_list`
/// sudah menerima page/page_size sendiri, bukan client-side spt katalog).
///
/// Tombol "Sinkronkan" mengisi `anggota_cache` lokal (aksi `anggota_sync_list`,
/// cursor `sejak_id` diulang sampai `adaLagi=false`) -- inilah yang membuat
/// picker member offline di layar Kasir (lihat KeranjangScreen._DialogPilihMember)
/// akhirnya punya isi; sebelum tombol ini pernah ditekan, cache itu selalu kosong.
class AnggotaScreen extends StatefulWidget {
  const AnggotaScreen({super.key});

  @override
  State<AnggotaScreen> createState() => _AnggotaScreenState();
}

class _AnggotaScreenState extends State<AnggotaScreen> {
  bool _memuat = true;
  bool _sinkronBerjalan = false;
  String? _pesanError;
  List<Anggota> _daftar = [];
  List<Kategori> _jenisAnggota = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';
  Map<String, dynamic>? _statistik;

  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      await Future.wait([_muatDaftar(), _muatJenis(), _muatStatistik()]);
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  Future<void> _muatDaftar() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('anggota_list', {'keyword': _kataKunci.isEmpty ? null : _kataKunci, 'page': _halaman, 'page_size': _pageSize});
      final data = ((hasil['data'] as List?) ?? []).map((e) => Anggota.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) {
        setState(() {
          _daftar = data;
          _total = (hasil['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _pesanError = e.toString());
    }
  }

  Future<void> _muatJenis() async {
    try {
      final hasil = await ApiClient.instance.aksi('jenis_anggota_list');
      final data = ((hasil['data'] as List?) ?? []).map((e) => Kategori.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() => _jenisAnggota = data);
    } catch (_) {
      // Dropdown jenis gagal muat -- form tetap bisa dipakai tanpa memilih jenis.
    }
  }

  Future<void> _muatStatistik() async {
    try {
      final hasil = await ApiClient.instance.aksi('anggota_statistik');
      if (mounted) setState(() => _statistik = hasil);
    } catch (_) {
      // dasbor KPI gagal muat bukan blocker.
    }
  }

  Future<void> _cariUlang(String v) async {
    setState(() {
      _kataKunci = v;
      _halaman = 1;
    });
    await _muatDaftar();
  }

  Future<void> _pindahHalaman(int halamanBaru) async {
    setState(() => _halaman = halamanBaru);
    await _muatDaftar();
  }

  Future<void> _sinkronkanCacheOffline() async {
    if (_sinkronBerjalan) return;
    setState(() => _sinkronBerjalan = true);
    try {
      var sejakId = 0;
      var totalTersinkron = 0;
      while (true) {
        final hasil = await ApiClient.instance.aksi('anggota_sync_list', {'sejak_id': sejakId, 'page_size': 500});
        final data = (hasil['data'] as List?) ?? [];
        if (data.isNotEmpty) {
          await CoreDb.instance
              .upsertAnggotaCache(data.map((e) => Anggota.keCacheRow(e as Map<String, dynamic>)).toList());
          totalTersinkron += data.length;
        }
        sejakId = (hasil['maksId'] as num?)?.toInt() ?? sejakId;
        if (hasil['adaLagi'] != true) break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$totalTersinkron member tersinkron ke cache offline.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sinkronBerjalan = false);
    }
  }

  Future<void> _bukaFormAnggota({Anggota? anggota}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormAnggota(anggota: anggota, jenisAnggota: _jenisAnggota),
    );
    if (tersimpan == true) await _muatSemua();
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer / Anggota'),
        actions: [
          IconButton(
            icon: _sinkronBerjalan
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined),
            onPressed: _sinkronBerjalan ? null : _sinkronkanCacheOffline,
            tooltip: 'Sinkronkan ke cache offline (utk picker member Kasir)',
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatSemua, tooltip: 'Muat ulang'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaFormAnggota(),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Tambah Member'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _muatSemua, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muatSemua,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      if (_statistik != null) _KartuStatistikAnggota(statistik: _statistik!),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cari nama/kode/kode identitas...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: _cariUlang,
                      ),
                      const SizedBox(height: 12),
                      if (_daftar.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('Belum ada member.')),
                        )
                      else
                        ..._daftar.map((a) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  child: Text(a.nama.isNotEmpty ? a.nama[0].toUpperCase() : '?',
                                      style: const TextStyle(color: Colors.white)),
                                ),
                                title: Text(a.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${a.kode} · ${a.jenisNama.isEmpty ? "Tanpa Jenis" : a.jenisNama}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (!a.aktif) const Text('Nonaktif', style: TextStyle(fontSize: 11, color: Colors.red)),
                                    if (a.wajibPin) const Text('Wajib PIN', style: TextStyle(fontSize: 11, color: Colors.orange)),
                                  ],
                                ),
                                onTap: () => _bukaFormAnggota(anggota: a),
                              ),
                            )),
                      if (_total > _pageSize)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: _halaman > 1 ? () => _pindahHalaman(_halaman - 1) : null,
                              ),
                              Text('Halaman $_halaman / $_totalHalaman ($_total member)'),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: _halaman < _totalHalaman ? () => _pindahHalaman(_halaman + 1) : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _KartuStatistikAnggota extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistikAnggota({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final item = <(String, String, Color)>[
      ('Total', '${statistik['totalAnggota'] ?? 0}', const Color(0xFF1E3A5F)),
      ('Aktif', '${statistik['totalAktif'] ?? 0}', const Color(0xFF2E7D32)),
      ('Nonaktif', '${statistik['totalNonaktif'] ?? 0}', Colors.black54),
      ('Wajib PIN', '${statistik['totalWajibPin'] ?? 0}', Colors.orange),
    ];
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: item.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (label, nilai, warna) = item[i];
          return Container(
            width: 120,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: warna.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(nilai, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: warna)),
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FormAnggota extends StatefulWidget {
  final Anggota? anggota;
  final List<Kategori> jenisAnggota;
  const _FormAnggota({required this.anggota, required this.jenisAnggota});

  @override
  State<_FormAnggota> createState() => _FormAnggotaState();
}

class _FormAnggotaState extends State<_FormAnggota> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _kodeIdentitas;
  late final TextEditingController _hp;
  late final TextEditingController _telp;
  late final TextEditingController _email;
  late final TextEditingController _keterangan;
  int? _jenisId;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final a = widget.anggota;
    _nama = TextEditingController(text: a?.nama ?? '');
    _kodeIdentitas = TextEditingController(text: a?.kodeIdentitas ?? '');
    _hp = TextEditingController(text: a?.hp ?? '');
    _telp = TextEditingController(text: a?.telp ?? '');
    _email = TextEditingController(text: a?.email ?? '');
    _keterangan = TextEditingController(text: a?.keterangan ?? '');
    _jenisId = a?.jenisAnggotaKoperasiId;
    _aktif = a?.aktif ?? true;
  }

  @override
  void dispose() {
    _nama.dispose();
    _kodeIdentitas.dispose();
    _hp.dispose();
    _telp.dispose();
    _email.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      await ApiClient.instance.aksi('anggota_simpan', {
        if (widget.anggota != null) 'id': widget.anggota!.id,
        'nama': _nama.text.trim(),
        'kode_identitas': _kodeIdentitas.text.trim(),
        'hp': _hp.text.trim(),
        'telp': _telp.text.trim(),
        'email': _email.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'jenis_anggota_koperasi_id': _jenisId,
        'aktif': _aktif,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.anggota != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(ubah ? 'Ubah Member' : 'Tambah Member Baru', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (ubah) Text('Kode: ${widget.anggota!.kode}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              if (_pesanError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(_pesanError!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                ),
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _kodeIdentitas,
                decoration: const InputDecoration(labelText: 'Kode Identitas (NIS/NIM/dll)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _jenisId,
                decoration: const InputDecoration(labelText: 'Jenis Anggota', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('-- Tanpa Jenis --')),
                  ...widget.jenisAnggota.map((k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.nama))),
                ],
                onChanged: (v) => setState(() => _jenisId = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _hp,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telp,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telepon', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keterangan,
                decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _menyimpan ? null : _simpan,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _menyimpan
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simpan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
