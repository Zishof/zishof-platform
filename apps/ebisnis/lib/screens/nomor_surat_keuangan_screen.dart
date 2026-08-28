import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';

/// Penomoran Dokumen Keuangan — padanan layar ZK
/// `ais.action.master.akunting.NomorSuratAlurKeuanganAction`.
///
/// **Kenapa layar ini penting.** Setiap modul Keuangan membuat kode dokumennya dari templat
/// yang dipasang di sini. Alur yang belum dipasangi templat jatuh ke
/// `Common.getGeneratedBarCode()` — dokumennya terbit berkode seperti `1041B55F9FAF`
/// alih-alih nomor yang dapat dibaca, dan tidak ada satu pun pesan yang memberitahukannya.
///
/// Dua tab: **Alur Dokumen** (memasangkan templat ke tiap jenis dokumen) dan **Templat
/// Nomor** (menyusun formatnya). Pratinjau di sini **tidak menghabiskan nomor** — yang
/// menaikkan urutan hanyalah penerbitan dokumen yang sebenarnya.
class NomorSuratKeuanganScreen extends StatefulWidget {
  const NomorSuratKeuanganScreen({super.key});

  @override
  State<NomorSuratKeuanganScreen> createState() =>
      _NomorSuratKeuanganScreenState();
}

class _NomorSuratKeuanganScreenState extends State<NomorSuratKeuanganScreen> {
  static const _cacheAlur = 'nomor_surat_keuangan:alur';
  static const _cacheTemplat = 'nomor_surat_keuangan:templat';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _alur = [];
  List<Map<String, dynamic>> _templat = [];
  List<Map<String, dynamic>> _jenisSegmen = const [];
  int _belumDipasang = 0;
  String _catatanAlur = '';
  Map<String, bool> _hak = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatSemua());
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final opsi = await MasterOffline.objekDenganCache(
          'nomor_surat_keuangan_opsi', const {}, 'nomor_surat_keuangan_opsi');
      if (!mounted) return;
      setStateIfMounted(() {
        _jenisSegmen =
            ((opsi['jenisSegmen'] as List?) ?? []).cast<Map<String, dynamic>>();
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
        'nomor_surat_keuangan_daftar',
        {},
        _cacheAlur,
        kolomKunci: 'id',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _alur =
                ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            _belumDipasang = (hasil['belumDipasang'] as num?)?.toInt() ?? 0;
            final h = hasil['hak'];
            _hak = h is Map
                ? {
                    for (final k in ['create', 'update', 'delete'])
                      k: h[k] != false
                  }
                : const {};
          });
        },
      );
      await MasterOffline.daftarCacheDulu(
        'nomor_surat_keuangan_templat_daftar',
        {},
        _cacheTemplat,
        kolomKunci: 'id',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _templat =
                ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
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
    required String cacheKey,
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
        cacheKey: cacheKey,
        rowLokal: rowLokal,
        hapusLokal: hapusLokal,
        idLokal: idLokal,
        entitas: 'nomor_surat_keuangan',
      );
      if (hasil['offline'] == true) {
        _pesan(
            'Tersimpan di perangkat. Akan dikirim otomatis saat jaringan pulih.');
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

  // ------------------------------------------------------- pasang templat

  Future<void> _pasang(Map<String, dynamic> alur) async {
    int? pilih = (alur['nomorSuratId'] as num?)?.toInt();
    Future<bool> simpanData() => _kirimLokalDulu(
          'nomor_surat_keuangan_pasang',
          {'alurId': alur['id'], 'nomorSuratId': pilih ?? 0},
          kunci: 'nomor_surat_keuangan_alur:${alur['id']}',
          cacheKey: _cacheAlur,
          rowLokal: {
            ...alur,
            'nomorSuratId': pilih,
            'pakaiBarcode': pilih == null,
          },
        );

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text('Penomoran ${alur['nama'] ?? ''}'),
          content: SizedBox(
            width: 520,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int?>(
                value: pilih,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Templat Nomor',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('(tanpa templat — kode barcode)')),
                  ..._templat.map((t) => DropdownMenuItem<int?>(
                        value: (t['id'] as num?)?.toInt(),
                        child: Text(
                            '${t['nama'] ?? ''}  ·  ${t['contohFormat'] ?? ''}'),
                      )),
                ],
                onChanged: (v) => setDialog(() => pilih = v),
              ),
              const SizedBox(height: 12),
              // Konsekuensi "tanpa templat" ditulis apa adanya: inilah keadaan yang
              // membuat sembilan dari sepuluh alur terbit berkode barcode tanpa
              // seorang pun menyadarinya.
              if (pilih == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tanpa templat, dokumen jenis ini terbit dengan kode barcode '
                    '(mis. 1041B55F9FAF), bukan nomor dokumen yang dapat dibaca.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ]),
          ),
          actions: [AppCrudDialogActions(onSubmit: simpanData)],
        ),
      ),
    );
  }

  // ------------------------------------------------------- formulir templat

  Future<void> _formTemplat([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    int jumlahNol = (baris?['jumlahNolDepan'] as num?)?.toInt() ?? 3;
    bool aktif = baris == null ? true : baris['aktif'] == true;
    bool resetTahun = baris?['resetTiapTahun'] == true;
    bool resetBulan = baris?['resetTiapBulan'] == true;
    bool gunakanIndexUrut = baris?['gunakanIndexUrut'] == true;
    int nomorIndex = (baris?['nomorIndex'] as num?)?.toInt() ?? 1;
    var segmen = List<Map<String, dynamic>>.generate(
        10, (_) => {'jenis': 'Kosong', 'tanda': ''});
    String contoh = '';

    if (ubah) {
      try {
        final d = await ApiClient.instance
            .aksi('nomor_surat_keuangan_templat_detail', {'id': baris['id']});
        final s = ((d['segmen'] as List?) ?? []).cast<Map<String, dynamic>>();
        for (var i = 0; i < segmen.length && i < s.length; i++) {
          segmen[i] = {
            'jenis': '${s[i]['jenis']}',
            'tanda': '${s[i]['tanda'] ?? ''}'
          };
        }
        contoh = '${d['contoh'] ?? ''}';
      } catch (e) {
        _pesan('$e');
        return;
      }
    }

    if (!mounted) return;
    Future<bool> simpanData() async {
      if (nama.text.trim().isEmpty) {
        throw const FormatException('Nama templat wajib diisi.');
      }
      if (!segmen.any((s) => s['jenis'] == 'Nomor Urut')) {
        throw const FormatException(
            'Templat wajib memuat satu segmen "Nomor Urut"; tanpa itu semua dokumen akan menerima nomor yang sama persis.');
      }

      final idBaru = ubah ? null : MasterOffline.idSementaraBaru();
      return _kirimLokalDulu(
        'nomor_surat_keuangan_templat_simpan',
        {
          if (ubah) 'id': baris['id'],
          'nama': nama.text.trim(),
          'keterangan': keterangan.text.trim(),
          'aktif': aktif,
          'jumlahNolDepan': jumlahNol,
          'resetTiapTahun': resetTahun,
          'resetTiapBulan': resetBulan,
          'gunakanIndexUrut': gunakanIndexUrut,
          'nomorIndex': nomorIndex,
          'segmen': segmen,
        },
        kunci: 'nomor_surat_keuangan_templat:${ubah ? baris['id'] : idBaru}',
        cacheKey: _cacheTemplat,
        idLokal: ubah ? null : idBaru,
        rowLokal: {
          'id': ubah ? baris['id'] : idBaru,
          'nama': nama.text.trim(),
          'keterangan': keterangan.text.trim(),
          'aktif': aktif,
          'contohFormat': contoh,
          'dipakaiAlur': baris?['dipakaiAlur'] ?? 0,
        },
      );
    }

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> hitungContoh() async {
            try {
              final res = await ApiClient.instance
                  .aksi('nomor_surat_keuangan_pratinjau', {
                'segmen': segmen,
                'jumlahNolDepan': jumlahNol,
                'gunakanIndexUrut': gunakanIndexUrut,
                'nomorIndex': nomorIndex,
              });
              setDialog(() => contoh = '${res['contoh'] ?? ''}');
            } catch (_) {
              // Pratinjau gagal tidak menghalangi penyimpanan; server menghitungnya ulang.
            }
          }

          return AlertDialog(
            title: Text(ubah ? 'Ubah Templat Nomor' : 'Templat Nomor Baru'),
            content: SizedBox(
              width: 720,
              height: 540,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: nama,
                      decoration: const InputDecoration(
                          labelText: 'Nama Templat *',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      initialValue: '$jumlahNol',
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Angka nol depan',
                          border: OutlineInputBorder(),
                          isDense: true),
                      onChanged: (v) {
                        jumlahNol = int.tryParse(v) ?? 3;
                        hitungContoh();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(
                      labelText: 'Keterangan',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 12, children: [
                  FilterChip(
                    label: const Text('Reset tiap tahun'),
                    selected: resetTahun,
                    onSelected: (v) => setDialog(() => resetTahun = v),
                  ),
                  FilterChip(
                    label: const Text('Reset tiap bulan'),
                    selected: resetBulan,
                    onSelected: (v) => setDialog(() => resetBulan = v),
                  ),
                  FilterChip(
                    label: const Text('Pakai index tersimpan'),
                    selected: gunakanIndexUrut,
                    onSelected: (v) {
                      setDialog(() => gunakanIndexUrut = v);
                      hitungContoh();
                    },
                  ),
                  FilterChip(
                    label: const Text('Aktif'),
                    selected: aktif,
                    onSelected: (v) => setDialog(() => aktif = v),
                  ),
                ]),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Susunan nomor (10 segmen)',
                      style: Theme.of(c).textTheme.titleSmall),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: segmen.length,
                    itemBuilder: (_, i) {
                      final jenis = '${segmen[i]['jenis']}';
                      final kataStatis = jenis == 'Kata Statis';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          SizedBox(width: 28, child: Text('${i + 1}.')),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: jenis,
                              isExpanded: true,
                              decoration: const InputDecoration(isDense: true),
                              items: _jenisSegmen
                                  .map((j) => DropdownMenuItem<String>(
                                      value: '${j['nilai']}',
                                      child: Text('${j['label']}')))
                                  .toList(),
                              onChanged: (v) {
                                setDialog(() => segmen[i] = {
                                      'jenis': v ?? 'Kosong',
                                      'tanda': segmen[i]['tanda']
                                    });
                                hitungContoh();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              initialValue: '${segmen[i]['tanda'] ?? ''}',
                              decoration: InputDecoration(
                                isDense: true,
                                // Pada "Kata Statis", kolom ini BUKAN pemisah melainkan
                                // isinya sendiri -- perbedaan yang mudah salah tangkap.
                                labelText: kataStatis
                                    ? 'Isi teksnya'
                                    : 'Pemisah sesudahnya',
                              ),
                              onChanged: (v) {
                                segmen[i] = {'jenis': jenis, 'tanda': v};
                                hitungContoh();
                              },
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Text('Contoh hasil: ',
                        style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Text(
                          contoh.isEmpty ? '(belum dapat dihitung)' : contoh,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace')),
                    ),
                    const Text('pratinjau tidak memakai nomor',
                        style: TextStyle(fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            actions: [AppCrudDialogActions(onSubmit: simpanData)],
          );
        },
      ),
    );
  }

  Future<void> _hapusTemplat(Map<String, dynamic> b) async {
    final dipakai = (b['dipakaiAlur'] as num?)?.toInt() ?? 0;
    if (dipakai > 0) {
      _pesan(
          'Templat ini masih dipasang pada $dipakai alur dokumen. Lepaskan dulu, '
          'atau ganti dengan templat lain — bila dihapus begitu saja, dokumennya akan '
          'terbit berkode barcode.');
      return;
    }
    if (!await _konfirmasi('Hapus templat nomor?', '${b['nama']}', 'Hapus'))
      return;
    await _kirimLokalDulu(
      'nomor_surat_keuangan_templat_hapus',
      {'id': b['id']},
      kunci: 'nomor_surat_keuangan_templat:${b['id']}',
      cacheKey: _cacheTemplat,
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.nomorSuratKeuangan,
      judul: 'Penomoran Dokumen Keuangan',
      subjudul: 'Templat nomor untuk tiap jenis dokumen',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      ],
      aksiHeader:
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      body: _galat != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_galat!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: _muatSemua, child: const Text('Coba lagi')),
                ]),
              ),
            )
          : DefaultTabController(
              length: 2,
              child: Column(children: [
                const TabBar(tabs: [
                  Tab(
                      icon: Icon(Icons.article_outlined, size: 18),
                      text: 'Alur Dokumen'),
                  Tab(
                      icon: Icon(Icons.tune_outlined, size: 18),
                      text: 'Templat Nomor'),
                ]),
                Expanded(
                  child: _memuat
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [_tabAlur(), _tabTemplat()]),
                ),
              ]),
            ),
    );
  }

  Widget _tabAlur() => Column(children: [
        if (_catatanAlur.isNotEmpty || _belumDipasang > 0)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              if (_catatanAlur.isNotEmpty)
                Row(children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_catatanAlur,
                          style: const TextStyle(fontSize: 12))),
                ]),
              if (_belumDipasang > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.warning_amber_outlined,
                          color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_belumDipasang jenis dokumen belum punya templat nomor. '
                          'Dokumennya terbit berkode barcode, bukan nomor yang dapat dibaca.',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: AppDataTable(
            minWidth: 900,
            emptyText: 'Belum ada alur dokumen terdaftar.',
            columns: const [
              AppTableColumn('Kode', flex: 1),
              AppTableColumn('Jenis Dokumen', flex: 3),
              AppTableColumn('Templat Nomor', flex: 3),
              AppTableColumn('Contoh', flex: 3),
              AppTableColumn('Aksi', width: 64, align: TextAlign.center),
            ],
            rows: _alur.map((b) {
              final barcode = b['pakaiBarcode'] == true;
              return AppTableRowData(cells: [
                AppTableCell.text('${b['kode'] ?? ''}', flex: 1),
                AppTableCell.text('${b['nama'] ?? ''}', flex: 3),
                AppTableCell(
                  flex: 3,
                  child: Row(children: [
                    if (barcode)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.warning_amber_outlined,
                            size: 16, color: Colors.orange),
                      ),
                    Expanded(
                      child: Text(
                        barcode
                            ? 'belum dipasang — kode barcode'
                            : '${b['nomorSuratNama']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: barcode ? AppColors.danger : null),
                      ),
                    ),
                  ]),
                ),
                AppTableCell.text('${b['contohFormat'] ?? ''}', flex: 3),
                AppTableCell(
                  width: 64,
                  child: AksiBarisMenu(
                    tooltip: 'Aksi',
                    aksi: [
                      AksiBaris(
                          ikon: Icons.link,
                          label: 'Pasang / ganti templat',
                          onTap: _boleh('update') && !_sibuk
                              ? () => _pasang(b)
                              : null),
                    ],
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ]);

  Widget _tabTemplat() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Expanded(
              child: Text(
                'Susunan nomor dibentuk dari sepuluh segmen berurutan. Pratinjaunya tidak '
                'menghabiskan nomor.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_boleh('create'))
              FilledButton.icon(
                onPressed: _sibuk ? null : () => _formTemplat(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Templat Baru'),
              ),
          ]),
        ),
        Expanded(
          child: AppDataTable(
            minWidth: 900,
            emptyText: 'Belum ada templat nomor.',
            columns: const [
              AppTableColumn('Nama', flex: 3),
              AppTableColumn('Contoh', flex: 3),
              AppTableColumn('Dipakai', flex: 1, align: TextAlign.center),
              AppTableColumn('Aktif', flex: 1, align: TextAlign.center),
              AppTableColumn('Aksi', width: 64, align: TextAlign.center),
            ],
            rows: _templat.map((b) {
              return AppTableRowData(cells: [
                AppTableCell.text('${b['nama'] ?? ''}', flex: 3),
                AppTableCell.text('${b['contohFormat'] ?? ''}', flex: 3),
                AppTableCell.text('${(b['dipakaiAlur'] as num?)?.toInt() ?? 0}',
                    flex: 1, align: TextAlign.center),
                AppTableCell.text(b['aktif'] == true ? 'Ya' : 'Tidak',
                    flex: 1, align: TextAlign.center),
                AppTableCell(
                  width: 64,
                  child: AksiBarisMenu(
                    tooltip: 'Aksi templat',
                    aksi: [
                      AksiBaris(
                          ikon: Icons.edit_outlined,
                          label: 'Ubah',
                          onTap: _boleh('update') && !_sibuk
                              ? () => _formTemplat(b)
                              : null),
                      AksiBaris(
                          ikon: Icons.delete_outline,
                          label: 'Hapus',
                          merusak: true,
                          onTap: _boleh('delete') && !_sibuk
                              ? () => _hapusTemplat(b)
                              : null),
                    ],
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
      ]);
}
