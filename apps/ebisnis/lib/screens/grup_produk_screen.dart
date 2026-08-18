import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/master_offline.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/safe_state.dart';

/// Grup Produk (harga terpusat lintas toko) -- padanan layar ZK GrupProdukAction.
///
/// Menyimpan grup MENYALIN HPP/harga jual ke seluruh produk anggota di semua
/// toko/outlet (aksi `grup_produk_simpan`, per-baris di server agar ter-audit
/// Envers). Menu ini fail-closed: hanya tampil bila kunci `grup_produk`
/// dinyalakan pada role (lihat aksesMenu di konfigurasi server).
class GrupProdukScreen extends StatefulWidget {
  const GrupProdukScreen({super.key});

  @override
  State<GrupProdukScreen> createState() => _GrupProdukScreenState();
}

class _GrupProdukScreenState extends State<GrupProdukScreen> {
  final _formatRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _memuat = true;
  String? _galat;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Nama aksi mengikuti kontrak server r77580 (GrupProdukApiHelper):
      // grup_produk_daftar dengan parameter hanya_aktif (default true).
      // Offline-first: snapshot daftar tersimpan lokal (MasterOffline).
      final res = await MasterOffline.daftarDenganCache(
          'grup_produk_daftar', {'hanya_aktif': false}, 'master:grup_produk');
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!sukses) {
        throw Exception(res['description'] ?? 'Gagal memuat Grup Produk.');
      }
      final data = (res['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setStateIfMounted(() {
        _daftar = data;
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _simpan(Map<String, dynamic>? awal) async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _FormGrupDialog(awal: awal),
    );
    if (hasil == null) return;
    try {
      final res = await MasterOffline.simpanAtauAntre(
        'grup_produk_simpan',
        hasil,
        kunci: hasil['id'] != null
            ? 'grup_produk:${hasil['id']}'
            : 'grup_produk:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:grup_produk',
        rowLokal: hasil,
      );
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['offline'] == true
            ? 'Tersimpan lokal — akan dikirim otomatis saat online.'
            : sukses
                ? (res['description'] ?? 'Grup tersimpan.').toString()
                : 'Gagal: ${res['description'] ?? res['status']}'),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error,
      ));
      if (sukses) _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  Future<void> _hapus(Map<String, dynamic> g) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Grup Produk'),
        content: Text('Hapus grup "${g['nama']}"? Grup yang masih dipakai '
            'produk akan ditolak server.'),
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
    if (yakin != true) return;
    try {
      final res = await MasterOffline.simpanAtauAntre(
        'grup_produk_hapus',
        {'id': g['id']},
        kunci: 'grup_produk:${g['id']}',
        cacheKey: 'master:grup_produk',
        rowLokal: {'id': g['id']},
        hapusLokal: true,
      );
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['offline'] == true
            ? 'Dihapus lokal — akan dikirim otomatis saat online.'
            : sukses
                ? 'Grup dihapus.'
                : 'Gagal: ${res['description'] ?? res['status']}'),
        backgroundColor: sukses ? null : Theme.of(context).colorScheme.error,
      ));
      if (sukses) _muat();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal menghapus: $e'),
          backgroundColor: Theme.of(context).colorScheme.error));
    }
  }

  String _harga(dynamic v) =>
      v == null ? '-' : _formatRupiah.format((v as num).toDouble());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Produk (Harga Terpusat)'),
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
        icon: const Icon(Icons.add),
        label: const Text('Tambah Grup'),
      ),
      body: _memuat
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
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ],
                  ),
                ))
              : _daftar.isEmpty
                  ? const Center(
                      child: Text(
                          'Belum ada grup. Buat grup untuk produk yang bahannya '
                          'sama di banyak outlet,\nlalu pilih grup itu pada form '
                          'Produk di tiap outlet.',
                          textAlign: TextAlign.center))
                  : RefreshIndicator(
                      onRefresh: _muat,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _daftar.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (c, i) {
                          final g = _daftar[i];
                          final aktif = g['aktif'] == true;
                          return Card(
                            child: ListTile(
                              title: Row(children: [
                                IndikatorBarisSinkron(
                                    kunci:
                                        kunciBarisMaster('grup_produk', g)),
                                Expanded(
                                  child: Text(
                                      '${(g['kode'] ?? '').toString().isEmpty ? '' : '${g['kode']} - '}${g['nama']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              subtitle: Text(
                                  'HPP ${_harga(g['harga_beli'])}  ·  Jual ${_harga(g['harga_jual'])}\n'
                                  '${g['jumlah_anggota']} produk anggota'
                                  '${aktif ? '' : '  ·  NONAKTIF'}'),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                      tooltip: 'Ubah & terapkan harga',
                                      onPressed: () => _simpan(g),
                                      icon: const Icon(Icons.edit_outlined)),
                                  IconButton(
                                      tooltip: 'Hapus',
                                      onPressed: () => _hapus(g),
                                      icon: const Icon(Icons.delete_outline)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _FormGrupDialog extends StatefulWidget {
  final Map<String, dynamic>? awal;
  const _FormGrupDialog({this.awal});

  @override
  State<_FormGrupDialog> createState() => _FormGrupDialogState();
}

class _FormGrupDialogState extends State<_FormGrupDialog> {
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  late final TextEditingController _hargaBeli;
  late final TextEditingController _hargaJual;
  late bool _aktif;

  @override
  void initState() {
    super.initState();
    final a = widget.awal;
    _kode = TextEditingController(text: (a?['kode'] ?? '').toString());
    _nama = TextEditingController(text: (a?['nama'] ?? '').toString());
    _keterangan =
        TextEditingController(text: (a?['keterangan'] ?? '').toString());
    _hargaBeli = TextEditingController(
        text: a?['harga_beli'] == null ? '' : '${a!['harga_beli']}');
    _hargaJual = TextEditingController(
        text: a?['harga_jual'] == null ? '' : '${a!['harga_jual']}');
    _aktif = a == null || a['aktif'] == true;
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _keterangan.dispose();
    _hargaBeli.dispose();
    _hargaJual.dispose();
    super.dispose();
  }

  double? _angka(String t) =>
      t.trim().isEmpty ? null : double.tryParse(t.replaceAll(',', '.'));

  @override
  Widget build(BuildContext context) {
    final baru = widget.awal == null;
    return AlertDialog(
      title: Text(baru ? 'Tambah Grup Produk' : 'Ubah Grup Produk'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _kode,
                  decoration: const InputDecoration(
                      labelText: 'Kode Grup',
                      hintText: 'Mis. AYAM-MRN (opsional)')),
              const SizedBox(height: 8),
              TextField(
                  controller: _nama,
                  decoration: const InputDecoration(
                      labelText: 'Nama Grup *',
                      hintText: 'Mis. Ayam Marinasi')),
              const SizedBox(height: 8),
              TextField(
                  controller: _keterangan,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Keterangan')),
              const SizedBox(height: 8),
              TextField(
                  controller: _hargaBeli,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'HPP / Harga Beli',
                      helperText:
                          'Kosongkan bila HPP tidak dikendalikan grup')),
              const SizedBox(height: 8),
              TextField(
                  controller: _hargaJual,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Harga Jual',
                      helperText:
                          'Kosongkan bila harga jual tidak dikendalikan grup')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: _aktif,
                  onChanged: (v) => setState(() => _aktif = v)),
              const Text(
                  'Menyimpan akan MENYALIN harga terisi ke seluruh produk '
                  'anggota grup ini di semua toko/outlet.',
                  style: TextStyle(fontSize: 12)),
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
                  const SnackBar(content: Text('Nama grup wajib diisi.')));
              return;
            }
            Navigator.pop(context, <String, dynamic>{
              if (!baru) 'id': widget.awal!['id'],
              'kode': _kode.text.trim(),
              'nama': _nama.text.trim(),
              'keterangan': _keterangan.text.trim(),
              'harga_beli': _angka(_hargaBeli.text),
              'harga_jual': _angka(_hargaJual.text),
              'aktif': _aktif,
            });
          },
          child: const Text('Simpan & Terapkan'),
        ),
      ],
    );
  }
}
