import 'package:flutter/material.dart';

import '../services/master_offline.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';

/// Master satuan produk POS. Matriks konversi antar-UOM merupakan fitur
/// terpisah karena tabel `koperasi.satuan_produk` hanya menyimpan nama/status.
class UomScreen extends StatefulWidget {
  const UomScreen({super.key});

  @override
  State<UomScreen> createState() => _UomScreenState();
}

class _UomScreenState extends State<UomScreen> {
  static const int _pageSize = 25;
  final TextEditingController _cari = TextEditingController();
  List<Map<String, dynamic>> _data = <Map<String, dynamic>>[];
  bool _memuat = true;
  String? _error;
  int _halaman = 1;
  int _total = 0;

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

  Future<void> _muat() async {
    if (mounted) {
      setState(() {
        _memuat = true;
        _error = null;
      });
    }
    try {
      await MasterOffline.daftarCacheDulu(
        'uom_list',
        <String, dynamic>{
          'keyword': _cari.text.trim(),
          'page': _halaman,
          'page_size': _pageSize,
          'termasuk_nonaktif': true,
        },
        'master:uom',
        onData: (Map<String, dynamic> hasil) {
          if (!mounted) return;
          final List<dynamic> mentah = hasil['data'] is List
              ? hasil['data'] as List<dynamic>
              : <dynamic>[];
          final List<Map<String, dynamic>> rows = <Map<String, dynamic>>[];
          for (final dynamic item in mentah) {
            if (item is Map) {
              rows.add(Map<String, dynamic>.from(item));
            }
          }
          setState(() {
            _data = rows;
            _total = (hasil['total'] as num?)?.toInt() ?? rows.length;
            _memuat = false;
          });
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _memuat = false;
        });
      }
    }
  }

  Future<void> _form([Map<String, dynamic>? row]) async {
    final TextEditingController nama =
        TextEditingController(text: row?['nama']?.toString() ?? '');
    bool aktif = row?['aktif'] != false;
    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter ubah) => AlertDialog(
          title:
              Text(row == null ? 'Tambah Satuan / UOM' : 'Ubah Satuan / UOM'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nama,
                  autofocus: true,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Nama satuan *',
                    hintText: 'Contoh: Pcs, Kg, Liter, Dus',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (bool value) => ubah(() => aktif = value),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (nama.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) {
      nama.dispose();
      return;
    }
    final int idLokal = row?['id'] is num
        ? (row!['id'] as num).toInt()
        : -DateTime.now().millisecondsSinceEpoch;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'uom_simpan',
        body: <String, dynamic>{
          if (row?['id'] != null) 'id': row!['id'],
          'nama': nama.text.trim(),
          'aktif': aktif,
        },
        kunci: 'uom:$idLokal',
        cacheKey: 'master:uom',
        idLokal: idLokal,
        rowLokal: <String, dynamic>{
          'id': idLokal,
          'nama': nama.text.trim(),
          'aktif': aktif,
        },
      );
      await _muat();
    } finally {
      nama.dispose();
    }
  }

  Future<void> _hapus(Map<String, dynamic> row) async {
    final bool? ya = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Hapus satuan?'),
        content: Text(
          'Satuan "${row['nama']}" hanya dapat dihapus bila belum dipakai produk.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    await prosesSimpanMaster(
      context,
      aksi: 'uom_hapus',
      body: <String, dynamic>{'id': row['id']},
      kunci: 'uom:${row['id']}',
      cacheKey: 'master:uom',
      rowLokal: <String, dynamic>{'id': row['id']},
      hapusLokal: true,
    );
    await _muat();
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999).toInt();

  String _inisial(dynamic nama) {
    final String teks = nama?.toString().trim() ?? '';
    return teks.isEmpty ? '?' : teks.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.uom,
      judul: 'Satuan / UOM',
      subjudul: 'Kelola satuan katalog produk POS',
      scrollable: false,
      aksiHeader: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(onPressed: _muat, icon: const Icon(Icons.refresh)),
          if (Sesi.instance.bolehKelola)
            FilledButton.icon(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Satuan'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _cari,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari satuan...',
              ),
              onSubmitted: (_) {
                _halaman = 1;
                _muat();
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!, textAlign: TextAlign.center))
                      : _data.isEmpty
                          ? const Center(
                              child: Text('Belum ada satuan produk.'))
                          : ListView.separated(
                              itemCount: _data.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final Map<String, dynamic> row = _data[index];
                                final bool aktif = row['aktif'] != false;
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(_inisial(row['nama'])),
                                  ),
                                  title: Text(row['nama']?.toString() ?? '-'),
                                  subtitle: Text(aktif ? 'Aktif' : 'Nonaktif'),
                                  trailing: Sesi.instance.bolehKelola
                                      ? Wrap(
                                          children: <Widget>[
                                            IconButton(
                                              onPressed: () => _form(row),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _hapus(row),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: AppColors.danger,
                                              ),
                                            ),
                                          ],
                                        )
                                      : null,
                                  onTap: Sesi.instance.bolehKelola
                                      ? () => _form(row)
                                      : null,
                                );
                              },
                            ),
            ),
            if (_totalHalaman > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    onPressed: _halaman > 1
                        ? () {
                            _halaman--;
                            _muat();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Halaman $_halaman / $_totalHalaman'),
                  IconButton(
                    onPressed: _halaman < _totalHalaman
                        ? () {
                            _halaman++;
                            _muat();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
