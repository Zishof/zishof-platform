import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../sesi.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_components.dart';
import '../../widgets/proses_simpan_master.dart';
import '../../widgets/safe_state.dart';
import '../../widgets/aksi_baris_menu.dart';

/// Tab "Satuan Kerja" -- kelola satuan kerja lalu pilih member mana saja yang
/// tergolong di dalamnya.
///
/// Logika daftarnya ditentukan SERVER mengikuti layar ZKoss
/// (`rab.SatuanKerjaAction`): hanya yang aktif (`default_item = true`), dibatasi
/// per yayasan, dan disaring lagi per pendaftar bila akun punya tenant. Klien
/// sengaja TIDAK menyaring ulang supaya kedua kanal tidak pernah menampilkan
/// daftar yang berbeda.
class AnggotaTabSatuanKerja extends StatefulWidget {
  const AnggotaTabSatuanKerja({super.key});

  @override
  State<AnggotaTabSatuanKerja> createState() => _AnggotaTabSatuanKerjaState();
}

class _AnggotaTabSatuanKerjaState extends State<AnggotaTabSatuanKerja> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _daftar = [];
  String _cari = '';
  bool _tampilkanNonaktif = false;

  @override
  void initState() {
    super.initState();
    _muatDaftar();
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('satuan_kerja_list', {
        'cari': _cari,
        'tampilkan_nonaktif': _tampilkanNonaktif,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        _daftar =
            ((hasil['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _pesanError = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _bukaForm({Map<String, dynamic>? satuanKerja}) async {
    final ubah = satuanKerja != null;
    final kode = TextEditingController(text: '${satuanKerja?['kode'] ?? ''}');
    final nama = TextEditingController(text: '${satuanKerja?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${satuanKerja?['keterangan'] ?? ''}');
    final alamat =
        TextEditingController(text: '${satuanKerja?['alamat'] ?? ''}');
    var aktif = satuanKerja == null ? true : satuanKerja['aktif'] == true;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setDialog) => AlertDialog(
          title: Text(ubah ? 'Ubah Satuan Kerja' : 'Tambah Satuan Kerja'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppFormTextField(label: 'Kode', controller: kode),
                AppFormTextField(label: 'Nama *', controller: nama),
                AppFormTextField(label: 'Keterangan', controller: keterangan),
                AppFormTextField(label: 'Alamat', controller: alamat),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  subtitle: const Text(
                      'Satuan kerja nonaktif disembunyikan dari daftar, '
                      'tetapi member yang sudah ditugaskan tidak diubah.'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama satuan kerja wajib diisi.')));
      return;
    }
    try {
      final body = <String, dynamic>{
        if (ubah) 'id': '${satuanKerja['id']}',
        'kode': kode.text.trim(),
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'alamat': alamat.text.trim(),
        'aktif': aktif,
      };
      // Lokal dulu, baru dikirim: antre -> indikator kirim -> tutup. Offline
      // pun tidak menahan pengguna; pengiriman ulang berjalan di latar.
      await prosesSimpanMaster(
        context,
        aksi: 'satuan_kerja_simpan',
        body: body,
        kunci: ubah
            ? 'satuan_kerja:${satuanKerja['id']}'
            : 'satuan_kerja:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:satuan_kerja',
        rowLokal: body,
      );
      await _muatDaftar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Satuan kerja tersimpan.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  Future<void> _nonaktifkan(Map<String, dynamic> sk) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Nonaktifkan Satuan Kerja'),
        content: Text('"${sk['nama']}" akan disembunyikan dari daftar.\n\n'
            'Barisnya tidak dihapus karena dapat dirujuk member, pegawai, dan '
            'dokumen lain. Member yang sudah ditugaskan tidak diubah.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Nonaktifkan')),
        ],
      ),
    );
    if (ya != true) return;
    try {
      await prosesSimpanMaster(
        context,
        aksi: 'satuan_kerja_hapus',
        body: {'id': '${sk['id']}'},
        kunci: 'satuan_kerja:${sk['id']}',
        cacheKey: 'master:satuan_kerja',
        rowLokal: {'id': sk['id']},
        hapusLokal: true,
      );
      await _muatDaftar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menonaktifkan: $e')));
    }
  }

  Future<void> _aturMember(Map<String, dynamic> sk) async {
    final tersimpan = await showDialog<bool>(
      context: context,
      builder: (_) => _DialogAturMember(satuanKerja: sk),
    );
    if (tersimpan == true) await _muatDaftar();
  }

  @override
  Widget build(BuildContext context) {
    if (_memuat) return const Center(child: CircularProgressIndicator());
    if (_pesanError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Gagal memuat satuan kerja: $_pesanError',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _muatDaftar, child: const Text('Coba Lagi')),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _muatDaftar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: AppSearchField(
                  hintText: 'Cari kode/nama satuan kerja...',
                  debounce: const Duration(milliseconds: 450),
                  onChanged: (v) {
                    _cari = v;
                    _muatDaftar();
                  },
                ),
              ),
              if (Sesi.instance.bolehKelola) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _bukaForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Satuan Kerja'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _tampilkanNonaktif,
              title: const Text('Tampilkan yang nonaktif juga'),
              onChanged: (v) {
                _tampilkanNonaktif = v == true;
                _muatDaftar();
              },
            ),
          ),
          const SizedBox(height: 8),
          AppDataTable(
            minWidth: 760,
            emptyText: 'Belum ada satuan kerja.',
            columns: [
              const AppTableColumn('Kode', flex: 2),
              const AppTableColumn('Nama', flex: 4),
              const AppTableColumn('Keterangan', flex: 4),
              const AppTableColumn('Jumlah Member',
                  flex: 2, align: TextAlign.right),
              const AppTableColumn('Status', flex: 2, align: TextAlign.center),
              AppTableColumn('Aksi',
                  width: Sesi.instance.bolehKelola ? 150 : 96,
                  align: TextAlign.center),
            ],
            rows: _daftar.map((sk) {
              final aktif = sk['aktif'] == true;
              return AppTableRowData(
                onTap: Sesi.instance.bolehKelola
                    ? () => _bukaForm(satuanKerja: sk)
                    : null,
                cells: [
                  AppTableCell.text('${sk['kode'] ?? ''}', flex: 2),
                  AppTableCell.text('${sk['nama'] ?? ''}', flex: 4),
                  AppTableCell.text('${sk['keterangan'] ?? ''}', flex: 4),
                  AppTableCell.text('${sk['jumlahMember'] ?? 0}',
                      flex: 2, align: TextAlign.right),
                  AppTableCell(
                    flex: 2,
                    align: TextAlign.center,
                    child: StatusPill(
                      label: aktif ? 'Aktif' : 'Nonaktif',
                      warna:
                          aktif ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
                  AppTableCell(
                      width: 64,
                      child: AksiBarisMenu(aksi: [
                        AksiBaris(
                            ikon: Icons.group_outlined,
                            label: 'Atur member',
                            onTap: () => _aturMember(sk)),
                        AksiBaris(
                            ikon: Icons.edit_outlined,
                            label: 'Ubah',
                            onTap: Sesi.instance.bolehKelola
                                ? () => _bukaForm(satuanKerja: sk)
                                : null),
                        AksiBaris(
                            ikon: Icons.block,
                            label: 'Nonaktifkan',
                            onTap: (Sesi.instance.bolehKelola) && (aktif)
                                ? () => _nonaktifkan(sk)
                                : null)
                      ])),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// Pemilih member untuk satu satuan kerja.
///
/// Member yang TIDAK punya akun login tetap dapat dipilih -- penugasannya
/// disimpan pada member itu sendiri, sementara akun (bila ada) ikut disamakan
/// di server. Tanpa itu, member tanpa akun tidak akan pernah bisa dikelompokkan.
class _DialogAturMember extends StatefulWidget {
  final Map<String, dynamic> satuanKerja;

  const _DialogAturMember({required this.satuanKerja});

  @override
  State<_DialogAturMember> createState() => _DialogAturMemberState();
}

class _DialogAturMemberState extends State<_DialogAturMember> {
  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _member = [];
  final Set<String> _terpilih = <String>{};
  String _cari = '';
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('satuan_kerja_anggota_list', {
        'satuan_kerja_id': '${widget.satuanKerja['id']}',
        'cari': _cari,
      });
      if (!mounted) return;
      final data =
          ((hasil['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setStateIfMounted(() {
        _member = data;
        // Centang awal HANYA saat pemuatan pertama; pencarian ulang tidak boleh
        // menghapus pilihan yang belum disimpan.
        if (_terpilih.isEmpty) {
          for (final m in data) {
            if (m['terpilih'] == true) _terpilih.add('${m['id']}');
          }
        }
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _pesanError = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _simpan() async {
    setStateIfMounted(() => _menyimpan = true);
    try {
      // Penugasan member juga lokal dulu. Kuncinya per satuan kerja supaya
      // pengiriman ulang tidak menumpuk bila daftar diubah berkali-kali.
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'satuan_kerja_anggota_simpan',
        body: {
          'satuan_kerja_id': '${widget.satuanKerja['id']}',
          'anggota_id': _terpilih.toList(),
        },
        kunci: 'satuan_kerja_anggota:${widget.satuanKerja['id']}',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['description'] ?? 'Tersimpan.'}')));
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _menyimpan = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Member — ${widget.satuanKerja['nama']}'),
      content: SizedBox(
        width: 620,
        height: 460,
        child: Column(children: [
          AppSearchField(
            hintText: 'Cari kode/nama member...',
            debounce: const Duration(milliseconds: 450),
            onChanged: (v) {
              _cari = v;
              _muat();
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${_terpilih.length} member dipilih',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _memuat
                ? const Center(child: CircularProgressIndicator())
                : _pesanError != null
                    ? Center(child: Text('Gagal memuat: $_pesanError'))
                    : _member.isEmpty
                        ? const Center(
                            child: Text('Tidak ada member yang cocok.'))
                        : ListView.builder(
                            itemCount: _member.length,
                            itemBuilder: (_, i) {
                              final m = _member[i];
                              final id = '${m['id']}';
                              final skLain = m['satuanKerjaNama'];
                              final punyaAkun = m['punyaAkun'] == true;
                              return CheckboxListTile(
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _terpilih.contains(id),
                                title: Text('${m['nama'] ?? ''}'),
                                subtitle: Text(
                                  [
                                    if ('${m['kode'] ?? ''}'.isNotEmpty)
                                      '${m['kode']}',
                                    if (!punyaAkun) 'tanpa akun login',
                                    if (skLain != null &&
                                        '$skLain'.isNotEmpty &&
                                        '$skLain' !=
                                            '${widget.satuanKerja['nama']}')
                                      'kini di: $skLain',
                                  ].join('  ·  '),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onChanged: (v) => setStateIfMounted(() {
                                  if (v == true) {
                                    _terpilih.add(id);
                                  } else {
                                    _terpilih.remove(id);
                                  }
                                }),
                              );
                            },
                          ),
          ),
          const Text(
            'Member yang dicentang menjadi anggota satuan kerja ini; yang '
            'dilepas centangnya dikeluarkan.',
            style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _menyimpan ? null : () => Navigator.pop(context, false),
            child: const Text('Batal')),
        FilledButton(
            onPressed: _menyimpan ? null : _simpan,
            child: Text(_menyimpan ? 'Menyimpan...' : 'Simpan')),
      ],
    );
  }
}
