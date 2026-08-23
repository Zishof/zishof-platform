import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';
import 'pengadaan_dasbor_tab.dart';

/// Proses Transitori — **jalan keluar** dari rekening transitori. Padanan layar ZK
/// `ais.action.master.akunting.ProsesTransitoriAction`.
///
/// Pada Proses Transfer, tiap baris DPC ditandai **Transfer** (langsung ke penerima) atau
/// **Transitori** (mampir dulu di rekening transitori). Baris yang ditandai Transitori
/// melahirkan satu *catatan transitori*; catatan itulah yang dikumpulkan di sini ke dalam
/// satu batch. Begitu batch-nya disetujui, dananya dianggap keluar dari rekening transitori
/// dan barisnya siap dijurnal.
///
/// **Satu penjaga yang tidak ada di layar ZK.** Catatan hanya boleh diproses bila proses
/// transfernya sudah **direalisasikan** — memindahkan dana keluar sebelum dananya masuk
/// tidak punya arti. Kandidat yang belum siap tetap **ditampilkan beserta alasannya**,
/// tidak disembunyikan, supaya penggunanya tahu apa yang harus diselesaikan lebih dulu.
class ProsesTransitoriScreen extends StatefulWidget {
  /// Dipasang di dalam layar Proses Transfer sebagai salah satu tab.
  ///
  /// Mode tersemat melepas [AppShell] dan deret tab miliknya sendiri; isinya --
  /// penyaring, tabel, dan seluruh aksinya -- tetap utuh.
  final bool tersemat;

  const ProsesTransitoriScreen({super.key, this.tersemat = false});

  @override
  State<ProsesTransitoriScreen> createState() => _ProsesTransitoriScreenState();
}

class _ProsesTransitoriScreenState extends State<ProsesTransitoriScreen> {
  static const _cacheKey = 'proses_transitori';
  final _fmt = DateFormat('yyyy-MM-dd');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<String> _daftarStatus = const [];
  String _catatanAlur = '';
  Map<String, bool> _hak = const {};
  double _totalNilai = 0;

  final TextEditingController _cari = TextEditingController();
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatSemua());
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final opsi = await ApiClient.instance.aksi('proses_transitori_opsi', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _daftarStatus = ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
        _catatanAlur = '${opsi['catatanAlur'] ?? ''}';
      });
      await _muatDaftar();
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'proses_transitori_daftar',
        {
          if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
          if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
        },
        _cacheKey,
        kolomKunci: 'id',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            _totalNilai = (hasil['totalNilai'] as num?)?.toDouble() ?? 0;
            final h = hasil['hak'];
            _hak = h is Map
                ? {
                    for (final k in ['create', 'update', 'delete', 'approve', 'reject'])
                      k: h[k] != false
                  }
                : const {};
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

  bool _boleh(String aksi) => _hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  Future<bool> _kirimLokalDulu(
    String aksi,
    Map<String, dynamic> body, {
    required String kunci,
    Map<String, dynamic>? rowLokal,
    int? idLokal,
    bool hapusLokal = false,
  }) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await prosesSimpanMaster(
        context,
        aksi: aksi,
        body: body,
        kunci: kunci,
        cacheKey: _cacheKey,
        rowLokal: rowLokal,
        hapusLokal: hapusLokal,
        idLokal: idLokal,
        entitas: 'proses_transitori',
      );
      if (hasil['offline'] == true) {
        _pesan('Tersimpan di perangkat. Akan dikirim otomatis saat jaringan pulih.');
      } else {
        _pesan('${hasil['message'] ?? 'Perubahan tersimpan.'}');
      }
      await _muatDaftar();
      return true;
    } catch (e) {
      _pesan('$e');
      return false;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<bool> _konfirmasi(String judul, String isi, String tombol) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tombol)),
        ],
      ),
    );
    return ya == true;
  }

  String _rupiah(Object? v) =>
      NumberFormat.decimalPattern('id').format((v as num?)?.toDouble() ?? 0);

  // ------------------------------------------------------------- formulir

  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    DateTime? tanggal = DateTime.tryParse('${baris?['tanggalPembuatan'] ?? ''}');
    final terpilih = <int, double>{};
    List<Map<String, dynamic>> kandidat = [];
    final cariKandidat = TextEditingController();
    bool hanyaSiap = false;
    int belumSiap = 0;
    bool memuatKandidat = false;
    bool sudahMuat = false;

    if (ubah) {
      try {
        final d = await ApiClient.instance
            .aksi('proses_transitori_detail', {'id': baris['id']});
        for (final e in ((d['item'] as List?) ?? []).cast<Map<String, dynamic>>()) {
          terpilih[(e['id'] as num).toInt()] = (e['nominal'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        _pesan('$e');
        return;
      }
    }

    if (!mounted) return;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> muatKandidat() async {
            setDialog(() => memuatKandidat = true);
            try {
              final res = await ApiClient.instance.aksi('proses_transitori_kandidat', {
                if (cariKandidat.text.trim().isNotEmpty) 'cari': cariKandidat.text.trim(),
                if (hanyaSiap) 'hanyaSiap': true,
              });
              kandidat = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
              belumSiap = (res['belumSiap'] as num?)?.toInt() ?? 0;
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memuatKandidat = false);
            }
          }

          if (!sudahMuat) {
            sudahMuat = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => muatKandidat());
          }

          final total = terpilih.values.fold<double>(0, (a, b) => a + b);
          return AlertDialog(
            title: Text(ubah ? 'Ubah Proses Transitori' : 'Proses Transitori Baru'),
            content: SizedBox(
              width: 820,
              height: 560,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: nama,
                      decoration: const InputDecoration(
                          labelText: 'Judul Proses *',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: OutlinedButton(
                      onPressed: () async {
                        final t = await showDatePicker(
                          context: c,
                          initialDate: tanggal ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (t != null) setDialog(() => tanggal = t);
                      },
                      child: Text(tanggal == null ? 'Tanggal' : _fmt.format(tanggal!)),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(
                      labelText: 'Keterangan', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Catatan transitori yang akan dikeluarkan',
                      style: Theme.of(c).textTheme.titleSmall),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: cariKandidat,
                      hintText: 'Cari kode / judul / kode transfer…',
                      onChanged: (_) => muatKandidat(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Menyembunyikan yang belum siap adalah PILIHAN pengguna, bukan bawaan:
                  // secara bawaan semuanya tampil beserta alasannya.
                  FilterChip(
                    label: const Text('Hanya yang siap'),
                    selected: hanyaSiap,
                    onSelected: (v) {
                      hanyaSiap = v;
                      muatKandidat();
                    },
                  ),
                ]),
                if (belumSiap > 0 && !hanyaSiap)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$belumSiap catatan belum dapat diproses karena proses transfernya '
                        'belum direalisasikan — dananya belum masuk rekening transitori.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: memuatKandidat
                      ? const Center(child: CircularProgressIndicator())
                      : kandidat.isEmpty
                          ? const Center(
                              child: Text('Tidak ada catatan transitori yang menunggu.'))
                          : ListView.builder(
                              itemCount: kandidat.length,
                              itemBuilder: (_, i) {
                                final b = kandidat[i];
                                final id = (b['id'] as num).toInt();
                                final siap = b['siap'] == true;
                                return CheckboxListTile(
                                  dense: true,
                                  value: terpilih.containsKey(id),
                                  title: Text('${b['kode'] ?? ''} — ${b['nama'] ?? ''}',
                                      style: const TextStyle(fontSize: 12.5)),
                                  subtitle: Text(
                                    siap
                                        ? '${b['prosesTransferKode'] ?? ''} · '
                                            '${b['satuanKerja'] ?? '-'} · '
                                            'Rp ${_rupiah(b['nominal'])}'
                                        : '${b['alasan'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: siap ? null : AppColors.danger),
                                  ),
                                  // Barisnya tetap TAMPIL walau tidak dapat dipilih; server
                                  // juga menolaknya, jadi ini hanya mencegah kejutan.
                                  onChanged: siap
                                      ? (v) => setDialog(() {
                                            if (v == true) {
                                              terpilih[id] =
                                                  (b['nominal'] as num?)?.toDouble() ?? 0;
                                            } else {
                                              terpilih.remove(id);
                                            }
                                          })
                                      : null,
                                );
                              },
                            ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${terpilih.length} catatan dipilih · Total Rp ${_rupiah(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Judul Proses Transitori wajib diisi.');
      return;
    }
    if (terpilih.isEmpty) {
      _pesan('Pilih minimal satu catatan transitori yang akan diproses.');
      return;
    }

    final idBaru = ubah ? null : MasterOffline.idSementaraBaru();
    await _kirimLokalDulu(
      'proses_transitori_simpan',
      {
        if (ubah) 'id': baris['id'],
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        if (tanggal != null) 'tanggalPembuatan': _fmt.format(tanggal!),
        'transitoriIds': terpilih.keys.toList(),
      },
      kunci: 'proses_transitori:${ubah ? baris['id'] : idBaru}',
      idLokal: ubah ? null : idBaru,
      rowLokal: {
        'id': ubah ? baris['id'] : idBaru,
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'nilai': terpilih.values.fold<double>(0, (a, b) => a + b),
        'jumlahItem': terpilih.length,
        'statusDokumen': 'Draft',
        if (tanggal != null) 'tanggalPembuatan': _fmt.format(tanggal!),
      },
    );
  }

  // ------------------------------------------------------------- detail

  Future<void> _detail(Map<String, dynamic> baris) async {
    Map<String, dynamic> header = {};
    List<Map<String, dynamic>> item = [];
    bool memuat = true;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> muat() async {
            try {
              final d = await ApiClient.instance
                  .aksi('proses_transitori_detail', {'id': baris['id']});
              header = ((d['header'] as Map?) ?? {}).cast<String, dynamic>();
              item = ((d['item'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memuat = false);
            }
          }

          if (memuat) {
            WidgetsBinding.instance.addPostFrameCallback((_) => muat());
          }

          final status = '${header['statusDokumen'] ?? ''}';
          return AlertDialog(
            title: Text('${baris['nama'] ?? ''}'),
            content: SizedBox(
              width: 760,
              height: 460,
              child: memuat
                  ? const Center(child: CircularProgressIndicator())
                  : Column(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$status · Rp ${_rupiah(header['nilai'])} · '
                          '${item.length} catatan',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: item.length,
                          itemBuilder: (_, i) {
                            final b = item[i];
                            final peringatan = '${b['peringatan'] ?? ''}';
                            return ListTile(
                              dense: true,
                              title: Text('${b['kode'] ?? ''} — ${b['nama'] ?? ''}',
                                  style: const TextStyle(fontSize: 12.5)),
                              subtitle: Text(
                                '${b['prosesTransferKode'] ?? ''} · '
                                '${b['caraPembayaran'] ?? ''} · '
                                'Akun transitori: ${b['akunTransitori']?.toString().isEmpty ?? true ? '—' : b['akunTransitori']}'
                                '${peringatan.isEmpty ? '' : '\n$peringatan'}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: peringatan.isEmpty ? null : AppColors.danger),
                              ),
                              isThreeLine: peringatan.isNotEmpty,
                              trailing: Text(
                                'Rp ${_rupiah(b['nominal'])}'
                                '${b['sudahDijurnal'] == true ? '\nsudah dijurnal' : ''}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            );
                          },
                        ),
                      ),
                    ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
    await _muatDaftar();
  }

  Future<void> _hapusBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Hapus proses transitori?',
        '${b['nama']}\n\nCatatan transitorinya dikembalikan ke daftar belum diproses; '
            'dananya masih ada di rekening transitori.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'proses_transitori_hapus',
      {'id': b['id']},
      kunci: 'proses_transitori:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    if (widget.tersemat) {
      return _isi();
    }
    return AppShell(
      menuAktif: MenuEBisnis.prosesTransitori,
      judul: 'Proses Transitori',
      subjudul: 'Mengeluarkan dana yang mampir di rekening transitori',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      ],
      aksiHeader: IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      body: _bungkusTab(_isi()),
    );
  }

  /// Isi layar tanpa kerangka -- dipakai bersama oleh mode berdiri sendiri
  /// (di dalam [_bungkusTab]) dan mode tersemat.
  Widget _isi() {
    if (_galat != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_galat!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _muatSemua, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    return Column(children: [
      _penyaring(),
      Expanded(
        child: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _tabel(),
      ),
    ]);
  }

  Widget _bungkusTab(Widget isiData) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Proses Transitori'),
          ]),
          Expanded(
            child: TabBarView(children: [
              const PengadaanDasborTab(
                  tahap: 'proses_transitori',
                  aksi: 'proses_transitori_dasbor',
                  namaParam: 'modul'),
              isiData,
            ]),
          ),
        ]),
      );

  Widget _penyaring() => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          if (_catatanAlur.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_catatanAlur, style: const TextStyle(fontSize: 12))),
              ]),
            ),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: AppSearchField(
                controller: _cari,
                hintText: 'Cari judul / keterangan',
                onChanged: (_) => _muatDaftar(),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _statusFilter.isEmpty ? null : _statusFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status', isDense: true),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('(semua status)')),
                  ..._daftarStatus.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))),
                ],
                onChanged: (v) {
                  _statusFilter = v ?? '';
                  _muatDaftar();
                },
              ),
            ),
            if (_boleh('create'))
              FilledButton.icon(
                onPressed: _sibuk ? null : () => _form(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Proses Transitori Baru'),
              ),
            Text('Total Rp ${_rupiah(_totalNilai)}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ]),
      );

  Widget _tabel() => AppDataTable(
        minWidth: 940,
        emptyText: 'Belum ada proses transitori.',
        columns: const [
          AppTableColumn('Judul', flex: 4),
          AppTableColumn('Tanggal', flex: 2),
          AppTableColumn('Catatan', flex: 1, align: TextAlign.center),
          AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
          AppTableColumn('Status', flex: 2, align: TextAlign.center),
          AppTableColumn('Aksi', width: 64, align: TextAlign.center),
        ],
        rows: _data.map((b) {
          final status = '${b['statusDokumen'] ?? ''}';
          final draft = status == 'Draft';
          final disetujui = status == 'Disetujui';
          final sudahJurnal = ((b['sudahDijurnal'] as num?)?.toInt() ?? 0) > 0;
          return AppTableRowData(cells: [
            AppTableCell.text('${b['nama'] ?? ''}', flex: 4),
            AppTableCell.text('${b['tanggalPembuatan'] ?? ''}', flex: 2),
            AppTableCell.text('${(b['jumlahItem'] as num?)?.toInt() ?? 0}',
                flex: 1, align: TextAlign.center),
            AppTableCell.text('Rp ${_rupiah(b['nilai'])}', flex: 2, align: TextAlign.right),
            AppTableCell(
              flex: 2,
              align: TextAlign.center,
              child: Center(
                child: Text(
                  sudahJurnal ? '$status · dijurnal' : status,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: disetujui ? AppColors.success : null),
                ),
              ),
            ),
            AppTableCell(
              width: 64,
              child: AksiBarisMenu(
                tooltip: 'Aksi dokumen',
                aksi: [
                  AksiBaris(
                      ikon: Icons.list_alt_outlined,
                      label: 'Lihat catatan transitorinya',
                      onTap: _sibuk ? null : () => _detail(b)),
                  AksiBaris(
                      ikon: Icons.edit_outlined,
                      label: 'Ubah',
                      onTap: draft && _boleh('update') && !_sibuk ? () => _form(b) : null),
                  AksiBaris(
                      ikon: Icons.check_circle_outline,
                      label: 'Setujui (dana keluar dari transitori)',
                      onTap: draft && _boleh('approve') && !_sibuk
                          ? () async {
                              if (await _konfirmasi(
                                  'Setujui proses transitori?',
                                  '${b['nama']}\n\n'
                                      'Setelah ini catatannya siap diposting dari Draft Jurnal.',
                                  'Setujui')) {
                                await _kirimLokalDulu(
                                    'proses_transitori_setujui', {'id': b['id']},
                                    kunci: 'proses_transitori:${b['id']}',
                                    rowLokal: {...b, 'statusDokumen': 'Disetujui'});
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.cancel_outlined,
                      label: 'Batalkan persetujuan',
                      onTap: disetujui && _boleh('reject') && !_sibuk
                          ? () async {
                              if (await _konfirmasi('Batalkan persetujuan?',
                                  '${b['nama']}', 'Batalkan')) {
                                await _kirimLokalDulu(
                                    'proses_transitori_batal_setuju', {'id': b['id']},
                                    kunci: 'proses_transitori:${b['id']}',
                                    rowLokal: {...b, 'statusDokumen': 'Draft'});
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.delete_outline,
                      label: 'Hapus',
                      merusak: true,
                      onTap: draft && _boleh('delete') && !_sibuk ? () => _hapusBaris(b) : null),
                ],
              ),
            ),
          ]);
        }).toList(),
      );
}
