import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';
import 'pengadaan_bayar_screen.dart';
import 'pengadaan_dasbor_tab.dart';
import 'pengadaan_transitori_tab.dart';
import 'proses_transitori_screen.dart';

/// Proses Transfer — **pencairan** baris DPC. Padanan layar ZK
/// `ais.action.master.akunting.ProsesTransferAction`.
///
/// **Mata rantai terakhir alur Keuangan.** Delapan modul sebelumnya (Uang Muka, LPJ,
/// Kas Besar, LPJ Kas Besar, Kas Kecil, Penggantian Kas Kecil, Dana Talangan, dan
/// Reimbursement Pegawai) semuanya bermuara di Daftar Pengajuan Transfer lalu berhenti.
/// Mesin posting menuntut barisnya sudah menempel pada satu Proses Transfer, jadi tanpa
/// layar ini dokumen yang lahir di POS tidak akan pernah dapat dijurnal.
///
/// Empat tahap, dan tiap tahap mengubah apa yang boleh disentuh:
///
/// | Status | Isinya | Tanda per baris |
/// |---|---|---|
/// | `Draft` | boleh disunting, baris boleh dilepas | belum boleh diisi |
/// | `Disetujui` | terkunci | **wajib** diisi Transfer / Transitori |
/// | `Terealisasi` | terkunci | terkunci |
///
/// Tanda **Transfer / Transitori** itu bukan hiasan: ia yang menentukan akun kredit
/// jurnalnya (`akun` vs `akunTransitori` pada cara pembayaran). Karena itu realisasi
/// ditahan server selama masih ada baris yang belum bertanda.
class ProsesTransferScreen extends StatefulWidget {
  const ProsesTransferScreen({super.key});

  @override
  State<ProsesTransferScreen> createState() => _ProsesTransferScreenState();
}

class _ProsesTransferScreenState extends State<ProsesTransferScreen> {
  static const _cacheKey = 'proses_transfer';
  final _fmt = DateFormat('yyyy-MM-dd');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _cara = const [];
  List<Map<String, dynamic>> _satker = const [];
  List<Map<String, dynamic>> _kategori = const [];
  List<String> _daftarStatus = const [];
  Map<String, bool> _hak = const {};
  double _totalNilai = 0;

  final TextEditingController _cari = TextEditingController();
  String _statusFilter = '';
  int? _caraFilter;

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
      final opsi = await ApiClient.instance.aksi('proses_transfer_opsi', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _cara = ((opsi['caraPembayaran'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _satker =
            ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _kategori =
            ((opsi['kategori'] as List?) ?? []).cast<Map<String, dynamic>>();
        _daftarStatus =
            ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
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
        'proses_transfer_daftar',
        {
          if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
          if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
          if (_caraFilter != null) 'caraPembayaranId': _caraFilter,
        },
        _cacheKey,
        kolomKunci: 'id',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data =
                ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            _totalNilai = (hasil['totalNilai'] as num?)?.toDouble() ?? 0;
            final h = hasil['hak'];
            _hak = h is Map
                ? {
                    for (final k in [
                      'create',
                      'update',
                      'delete',
                      'approve',
                      'reject'
                    ])
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
        entitas: 'proses_transfer',
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

  String _rupiah(Object? v) =>
      NumberFormat.decimalPattern('id').format((v as num?)?.toDouble() ?? 0);

  // ------------------------------------------------------------- formulir

  /// Formulir Draft: kepala dokumen + pemilih baris DPC yang belum diproses.
  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    int? caraId;
    DateTime? tanggal =
        DateTime.tryParse('${baris?['tanggalPembuatan'] ?? ''}');
    final terpilih = <int, double>{};
    List<Map<String, dynamic>> kandidat = [];
    final kategoriAktif = <String>{};
    final cariKandidat = TextEditingController();
    int? satkerId;
    bool memuatKandidat = false;
    bool sudahMuat = false;

    if (ubah) {
      try {
        final d = await ApiClient.instance
            .aksi('proses_transfer_detail', {'id': baris['id']});
        caraId = ((d['header'] as Map?)?['caraPembayaranId'] as num?)?.toInt();
        for (final e
            in ((d['item'] as List?) ?? []).cast<Map<String, dynamic>>()) {
          terpilih[(e['id'] as num).toInt()] =
              (e['nominal'] as num?)?.toDouble() ?? 0;
        }
      } catch (e) {
        _pesan('$e');
        return;
      }
    } else {
      for (final c in _cara) {
        if (c['bawaan'] == true) caraId = (c['id'] as num?)?.toInt();
      }
    }

    // Detail dokumen dimuat lebih dulu (await di atas), jadi context-nya harus
    // diperiksa ulang sebelum dialog dibuka -- layar bisa saja sudah ditutup.
    if (!mounted) return;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> muatKandidat() async {
            setDialog(() => memuatKandidat = true);
            try {
              final res =
                  await ApiClient.instance.aksi('proses_transfer_kandidat', {
                if (cariKandidat.text.trim().isNotEmpty)
                  'cari': cariKandidat.text.trim(),
                if (satkerId != null) 'satuanKerjaId': satkerId,
                if (kategoriAktif.isNotEmpty)
                  'kategori': kategoriAktif.toList(),
              });
              kandidat =
                  ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
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
            title: Text(ubah ? 'Ubah Proses Transfer' : 'Proses Transfer Baru'),
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
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int?>(
                      value: caraId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Cara Pembayaran',
                          helperText: 'Menentukan akun kredit jurnalnya.',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('(belum dipilih)')),
                        ..._cara.map((e) => DropdownMenuItem<int?>(
                              value: (e['id'] as num?)?.toInt(),
                              child: Text('${e['nama'] ?? ''}'
                                  '${e['akunLengkap'] == false ? '  ⚠ akun belum lengkap' : ''}'),
                            )),
                      ],
                      onChanged: (v) => setDialog(() => caraId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () async {
                        final t = await showDatePicker(
                          context: c,
                          initialDate: tanggal ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (t != null) setDialog(() => tanggal = t);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tanggal',
                          helperText: 'Tanggal proses transfer.',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon:
                              Icon(Icons.calendar_today_outlined, size: 18),
                        ),
                        child: Text(tanggal == null
                            ? 'Pilih tanggal'
                            : _fmt.format(tanggal!)),
                      ),
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Baris DPC yang akan ditransfer',
                      style: Theme.of(c).textTheme.titleSmall),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(
                    // Kotak cari standar aplikasi: ikon cari, tombol bersihkan,
                    // dan jeda 220 ms. Sebelumnya TextField biasa yang baru
                    // mencari ketika Enter ditekan, sehingga kotaknya terlihat
                    // tidak bereaksi saat diketik.
                    child: AppSearchField(
                      controller: cariKandidat,
                      hintText: 'Cari kode / judul DPC…',
                      onChanged: (_) => muatKandidat(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<int?>(
                      value: satkerId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Satuan Kerja',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('(semua)')),
                        ..._satker.map((s) => DropdownMenuItem<int?>(
                            value: (s['id'] as num?)?.toInt(),
                            child: Text('${s['nama'] ?? ''}'))),
                      ],
                      onChanged: (v) {
                        satkerId = v;
                        muatKandidat();
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                // Penyaring kategori bersifat MENAMBAH, bukan menyembunyikan: tanpa
                // satu pun dipilih, semua baris tampil. Kategori "Lainnya" menampung
                // baris yang sumbernya belum dikenali, jadi tidak ada yang bisa hilang.
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final k in _kategori)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            label: Text('${k['label']}',
                                style: const TextStyle(fontSize: 11.5)),
                            selected: kategoriAktif.contains('${k['kunci']}'),
                            onSelected: (v) {
                              if (v) {
                                kategoriAktif.add('${k['kunci']}');
                              } else {
                                kategoriAktif.remove('${k['kunci']}');
                              }
                              muatKandidat();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: memuatKandidat
                      ? const Center(child: CircularProgressIndicator())
                      : (kandidat.isEmpty && terpilih.isEmpty)
                          ? const Center(
                              child: Text(
                                  'Tidak ada baris DPC yang menunggu diproses.'))
                          : ListView.builder(
                              itemCount: kandidat.length,
                              itemBuilder: (_, i) {
                                final b = kandidat[i];
                                final id = (b['id'] as num).toInt();
                                return CheckboxListTile(
                                  dense: true,
                                  value: terpilih.containsKey(id),
                                  title: Text(
                                      '${b['kode'] ?? ''} — ${b['nama'] ?? ''}',
                                      style: const TextStyle(fontSize: 12.5)),
                                  subtitle: Text(
                                      '${b['sumber'] ?? ''} · ${b['satuanKerja'] ?? '-'} · '
                                      'Rp ${_rupiah(b['nominal'])}',
                                      style: const TextStyle(fontSize: 11.5)),
                                  onChanged: (v) => setDialog(() {
                                    if (v == true) {
                                      terpilih[id] =
                                          (b['nominal'] as num?)?.toDouble() ??
                                              0;
                                    } else {
                                      terpilih.remove(id);
                                    }
                                  }),
                                );
                              },
                            ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(
                        '${terpilih.length} baris dipilih · Total Rp ${_rupiah(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (simpan != true) return;
    if (nama.text.trim().isEmpty) {
      _pesan('Judul Proses Transfer wajib diisi.');
      return;
    }
    if (terpilih.isEmpty) {
      _pesan('Pilih minimal satu baris DPC yang akan ditransfer.');
      return;
    }

    final idBaru = ubah ? null : MasterOffline.idSementaraBaru();
    await _kirimLokalDulu(
      'proses_transfer_simpan',
      {
        if (ubah) 'id': baris['id'],
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        if (caraId != null) 'caraPembayaranId': caraId,
        if (tanggal != null) 'tanggalPembuatan': _fmt.format(tanggal!),
        'dptIds': terpilih.keys.toList(),
      },
      kunci: 'proses_transfer:${ubah ? baris['id'] : idBaru}',
      idLokal: ubah ? null : idBaru,
      rowLokal: {
        'id': ubah ? baris['id'] : idBaru,
        'kode': baris?['kode'] ?? '(menunggu nomor)',
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

  /// Panel detail: baris DPC berikut tanda Transfer/Transitori-nya.
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
                  .aksi('proses_transfer_detail', {'id': baris['id']});
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
          final bolehTandai = status == 'Disetujui' && _boleh('update');
          return AlertDialog(
            title: Text('${baris['kode'] ?? ''} — ${baris['nama'] ?? ''}'),
            content: SizedBox(
              width: 760,
              height: 480,
              child: memuat
                  ? const Center(child: CircularProgressIndicator())
                  : Column(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$status · Rp ${_rupiah(header['nilai'])} · '
                          '${header['caraPembayaran'] ?? 'cara pembayaran belum dipilih'}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (status == 'Disetujui')
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Tandai tiap baris Transfer atau Transitori. Tanda itu yang '
                            'menentukan akun kredit jurnalnya, dan realisasi ditahan '
                            'selama masih ada baris yang belum bertanda.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: item.length,
                          itemBuilder: (_, i) {
                            final b = item[i];
                            final mode = b['transitori'] == true
                                ? 'transitori'
                                : (b['transfer'] == true
                                    ? 'transfer'
                                    : 'kosong');
                            return ListTile(
                              dense: true,
                              title: Text(
                                  '${b['kode'] ?? ''} — ${b['nama'] ?? ''}',
                                  style: const TextStyle(fontSize: 12.5)),
                              subtitle: Text(
                                  '${b['sumber'] ?? ''} · ${b['satuanKerja'] ?? '-'} · '
                                  'Rp ${_rupiah(b['nominal'])}',
                                  style: const TextStyle(fontSize: 11.5)),
                              trailing: bolehTandai
                                  ? SegmentedButton<String>(
                                      showSelectedIcon: false,
                                      style: const ButtonStyle(
                                          visualDensity: VisualDensity.compact),
                                      segments: const [
                                        ButtonSegment(
                                            value: 'transfer',
                                            label: Text('Transfer')),
                                        ButtonSegment(
                                            value: 'transitori',
                                            label: Text('Transitori')),
                                      ],
                                      selected: mode == 'kosong'
                                          ? <String>{}
                                          : {mode},
                                      emptySelectionAllowed: true,
                                      onSelectionChanged: (s) async {
                                        final pilih =
                                            s.isEmpty ? 'kosong' : s.first;
                                        await _kirimLokalDulu(
                                          'proses_transfer_tandai',
                                          {'dptId': b['id'], 'mode': pilih},
                                          kunci:
                                              'proses_transfer_item:${b['id']}',
                                        );
                                        setDialog(() => memuat = true);
                                      },
                                    )
                                  : Text(
                                      mode == 'kosong'
                                          ? 'belum bertanda'
                                          : mode,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: mode == 'kosong'
                                              ? AppColors.danger
                                              : null),
                                    ),
                            );
                          },
                        ),
                      ),
                    ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Tutup')),
            ],
          );
        },
      ),
    );
    await _muatDaftar();
  }

  // ------------------------------------------------------------- aksi baris

  Future<void> _hapusBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Hapus proses transfer?',
        '${b['kode']} — ${b['nama']}\n\n'
            'Baris DPC-nya dikembalikan ke daftar belum diproses, dokumen sumbernya tetap utuh.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'proses_transfer_hapus',
      {'id': b['id']},
      kunci: 'proses_transfer:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.prosesTransfer,
      judul: 'Proses Transfer',
      subjudul: 'Pencairan baris DPC — mata rantai terakhir sebelum jurnal',
      scrollable: false,
      actionsAppBar: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      ],
      aksiHeader:
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatDaftar),
      body: _bungkusTab(
        _galat != null
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
            : Column(children: [
                _penyaring(),
                Expanded(
                  child: _memuat
                      ? const Center(child: CircularProgressIndicator())
                      : _tabel(),
                ),
              ]),
      ),
    );
  }

  /// SATU menu untuk seluruh rangkaian pencairan.
  ///
  /// Proses Transfer, Pembayaran Vendor, dan Proses Transitori dulunya tiga menu
  /// terpisah di grup Keuangan padahal ketiganya satu rangkaian atas dokumen yang
  /// sama: baris DPC dicairkan (transfer), tagihan penyedianya dibayar, dan yang
  /// singgah di rekening perantara direalisasikan. Berdiri sendiri-sendiri,
  /// pengguna harus menebak menu mana yang memuat pekerjaan yang dicarinya.
  ///
  /// <b>Hak akses tidak ikut digabung.</b> Tiap tab tetap bergantung pada kunci
  /// menunya sendiri (`pengadaan_dpc`, `proses_transitori`). Menyatukan menu tidak
  /// boleh diam-diam membuka isi modul yang memang tidak boleh dilihat peran ini.
  Widget _bungkusTab(Widget isiData) {
    final bolehBayarVendor = Sesi.instance.bolehMenu('pengadaan_dpc');
    final bolehTransitori = Sesi.instance.bolehMenu('proses_transitori');

    final tabs = <Tab>[
      const Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
      const Tab(
          icon: Icon(Icons.list_alt_outlined, size: 18),
          text: 'Proses Transfer'),
      if (bolehBayarVendor)
        const Tab(
            icon: Icon(Icons.payments_outlined, size: 18),
            text: 'Pembayaran Vendor'),
      if (bolehBayarVendor)
        const Tab(
            icon: Icon(Icons.pause_circle_outline, size: 18),
            text: 'Transitori Menunggu'),
      if (bolehTransitori)
        const Tab(
            icon: Icon(Icons.swap_horiz_outlined, size: 18),
            text: 'Proses Transitori'),
    ];
    final halaman = <Widget>[
      _DasborPencairan(
          bolehBayarVendor: bolehBayarVendor, bolehTransitori: bolehTransitori),
      isiData,
      if (bolehBayarVendor) const PengadaanBayarScreen(tersemat: true),
      if (bolehBayarVendor) const PengadaanTransitoriTab(),
      if (bolehTransitori) const ProsesTransitoriScreen(tersemat: true),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        // Dapat digulir: lima tab tidak muat pada jendela kasir yang sempit.
        TabBar(isScrollable: true, tabs: tabs),
        Expanded(child: TabBarView(children: halaman)),
      ]),
    );
  }

  Widget _penyaring() => Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: AppSearchField(
                  controller: _cari,
                  hintText: 'Cari kode / judul',
                  onChanged: (_) => _muatDaftar(),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter.isEmpty ? null : _statusFilter,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Status', isDense: true),
                  items: [
                    const DropdownMenuItem<String>(
                        value: null, child: Text('(semua status)')),
                    ..._daftarStatus.map((s) =>
                        DropdownMenuItem<String>(value: s, child: Text(s))),
                  ],
                  onChanged: (v) {
                    _statusFilter = v ?? '';
                    _muatDaftar();
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  value: _caraFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Cara Pembayaran', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text('(semua)')),
                    ..._cara.map((e) => DropdownMenuItem<int?>(
                        value: (e['id'] as num?)?.toInt(),
                        child: Text('${e['nama'] ?? ''}'))),
                  ],
                  onChanged: (v) {
                    _caraFilter = v;
                    _muatDaftar();
                  },
                ),
              ),
              if (_boleh('create'))
                FilledButton.icon(
                  onPressed: _sibuk ? null : () => _form(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Proses Transfer Baru'),
                ),
              Text('Total Rp ${_rupiah(_totalNilai)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
      );

  Widget _tabel() => AppDataTable(
        minWidth: 1040,
        emptyText: 'Belum ada proses transfer.',
        columns: const [
          AppTableColumn('Kode', flex: 2),
          AppTableColumn('Judul', flex: 3),
          AppTableColumn('Cara Bayar', flex: 2),
          AppTableColumn('Baris', flex: 1, align: TextAlign.center),
          AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
          AppTableColumn('Status', flex: 2, align: TextAlign.center),
          AppTableColumn('Aksi', width: 64, align: TextAlign.center),
        ],
        rows: _data.map((b) {
          final status = '${b['statusDokumen'] ?? ''}'.trim();
          final statusNormal = status.toLowerCase();
          final draft = status == 'Draft';
          final disetujui = status == 'Disetujui';
          final cair = status == 'Terealisasi';
          final sudahCair = cair ||
              statusNormal == 'realisasi' ||
              '${b['realisasikanOleh'] ?? ''}'.trim().isNotEmpty;
          return AppTableRowData(cells: [
            AppTableCell.text('${b['kode'] ?? ''}', flex: 2),
            AppTableCell.text('${b['nama'] ?? ''}', flex: 3),
            AppTableCell.text('${b['caraPembayaran'] ?? ''}', flex: 2),
            AppTableCell.text('${(b['jumlahItem'] as num?)?.toInt() ?? 0}',
                flex: 1, align: TextAlign.center),
            AppTableCell.text('Rp ${_rupiah(b['nilai'])}',
                flex: 2, align: TextAlign.right),
            AppTableCell(
              flex: 2,
              align: TextAlign.center,
              child: Center(
                child: Text(status,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sudahCair
                            ? AppColors.success
                            : (disetujui ? AppColors.primary : null))),
              ),
            ),
            AppTableCell(
              width: 64,
              child: AksiBarisMenu(
                tooltip: 'Aksi dokumen',
                aksi: [
                  AksiBaris(
                      ikon: Icons.list_alt_outlined,
                      label: 'Lihat baris DPC-nya',
                      onTap: _sibuk ? null : () => _detail(b)),
                  AksiBaris(
                      ikon: Icons.edit_outlined,
                      label: 'Ubah',
                      onTap: draft && _boleh('update') && !_sibuk
                          ? () => _form(b)
                          : null),
                  AksiBaris(
                      ikon: Icons.check_circle_outline,
                      label: 'Setujui',
                      onTap: draft && _boleh('approve') && !_sibuk
                          ? () async {
                              if (await _konfirmasi('Setujui proses transfer?',
                                  '${b['kode']} — ${b['nama']}', 'Setujui')) {
                                await _kirimLokalDulu(
                                    'proses_transfer_setujui', {'id': b['id']},
                                    kunci: 'proses_transfer:${b['id']}',
                                    rowLokal: {
                                      ...b,
                                      'statusDokumen': 'Disetujui'
                                    });
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.payments_outlined,
                      label: 'Realisasikan (dana cair)',
                      onTap: disetujui &&
                              !sudahCair &&
                              _boleh('approve') &&
                              !_sibuk
                          ? () async {
                              if (await _konfirmasi(
                                  'Tandai dana sudah cair?',
                                  '${b['kode']} — ${b['nama']}\n\n'
                                      'Setelah ini jurnal umum dibuat otomatis.',
                                  'Realisasikan')) {
                                await _kirimLokalDulu(
                                    'proses_transfer_realisasikan',
                                    {'id': b['id']},
                                    kunci: 'proses_transfer:${b['id']}',
                                    rowLokal: {
                                      ...b,
                                      'statusDokumen': 'Terealisasi'
                                    });
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.undo,
                      label: 'Batalkan realisasi',
                      onTap: cair && _boleh('reject') && !_sibuk
                          ? () async {
                              if (await _konfirmasi('Batalkan realisasi?',
                                  '${b['kode']} — ${b['nama']}', 'Batalkan')) {
                                await _kirimLokalDulu(
                                    'proses_transfer_batal_realisasi',
                                    {'id': b['id']},
                                    kunci: 'proses_transfer:${b['id']}',
                                    rowLokal: {
                                      ...b,
                                      'statusDokumen': 'Disetujui'
                                    });
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.cancel_outlined,
                      label: 'Batalkan persetujuan',
                      onTap: disetujui && _boleh('reject') && !_sibuk
                          ? () async {
                              if (await _konfirmasi(
                                  'Batalkan persetujuan?',
                                  '${b['kode']} — ${b['nama']}\n\n'
                                      'Baris DPC-nya dilepas kembali agar tidak nyangkut '
                                      'di status sudah diajukan.',
                                  'Batalkan')) {
                                await _kirimLokalDulu(
                                    'proses_transfer_batal_setuju',
                                    {'id': b['id']},
                                    kunci: 'proses_transfer:${b['id']}',
                                    rowLokal: {...b, 'statusDokumen': 'Draft'});
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.delete_outline,
                      label: 'Hapus',
                      merusak: true,
                      onTap: draft && _boleh('delete') && !_sibuk
                          ? () => _hapusBaris(b)
                          : null),
                ],
              ),
            ),
          ]);
        }).toList(),
      );
}

/// Tab "Dasbor" layar Proses Transfer -- satu tab, tiga modul.
///
/// Sebelum penggabungan, masing-masing menu membawa dasbornya sendiri. Menyatukan
/// menunya tidak boleh membuang dua dasbor itu, jadi ketiganya tetap ada dan
/// dipilih lewat satu pemilih di atas. Yang ditawarkan hanya modul yang memang
/// boleh dilihat peran ini.
class _DasborPencairan extends StatefulWidget {
  final bool bolehBayarVendor;
  final bool bolehTransitori;

  const _DasborPencairan(
      {required this.bolehBayarVendor, required this.bolehTransitori});

  @override
  State<_DasborPencairan> createState() => _DasborPencairanState();
}

class _DasborPencairanState extends State<_DasborPencairan> {
  /// (label, tahap, aksi, namaParam)
  late final List<List<String>> _modul = [
    ['Proses Transfer', 'proses_transfer', 'proses_transfer_dasbor', 'modul'],
    if (widget.bolehBayarVendor)
      ['Pembayaran Vendor', 'dpc', 'pengadaan_dasbor', 'tahap'],
    if (widget.bolehTransitori)
      [
        'Proses Transitori',
        'proses_transitori',
        'proses_transitori_dasbor',
        'modul'
      ],
  ];

  int _terpilih = 0;

  @override
  Widget build(BuildContext context) {
    final m = _modul[_terpilih.clamp(0, _modul.length - 1)];
    return Column(children: [
      if (_modul.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(children: [
            const Text('Dasbor modul: '),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _terpilih,
              items: [
                for (var i = 0; i < _modul.length; i++)
                  DropdownMenuItem<int>(value: i, child: Text(_modul[i][0])),
              ],
              onChanged: (v) => setStateIfMounted(() => _terpilih = v ?? 0),
            ),
          ]),
        ),
      Expanded(
        child: PengadaanDasborTab(
            key: ValueKey('dasbor-pencairan-${m[1]}'),
            tahap: m[1],
            aksi: m[2],
            namaParam: m[3]),
      ),
    ]);
  }
}
