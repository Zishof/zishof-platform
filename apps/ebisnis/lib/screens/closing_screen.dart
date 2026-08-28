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

/// Closing — penutupan periode akuntansi. Padanan layar ZK
/// `ais.action.master.akunting.ClosingAction`.
///
/// **Closing-lah yang mengunci buku.** Setiap mesin pembatalan posting menolak baris yang
/// sudah masuk closing, dan dasbor Draft Jurnal menampilkan kolomnya. Jadi pengguna POS
/// sudah melihat angkanya dan sudah terkena akibatnya — sampai sekarang menutup periode
/// justru hanya bisa dari layar ZK.
///
/// Satu closing adalah **tanggal batas** berikut namanya: seluruh jurnal bertanggal
/// transaksi pada atau sebelum tanggal itu ditautkan padanya. Bila ada beberapa closing,
/// tiap jurnal berakhir pada closing **paling awal** yang mencakupnya.
class ClosingScreen extends StatefulWidget {
  const ClosingScreen({super.key});

  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  static const _cacheKey = 'closing';
  final _fmt = DateFormat('yyyy-MM-dd');
  final _tampil = DateFormat('dd MMM yyyy', 'id');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  String _catatanAlur = '';
  Map<String, bool> _hak = const {};
  final TextEditingController _cari = TextEditingController();

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
    try {
      final opsi = await MasterOffline.objekDenganCache(
          'closing_opsi', const {}, 'closing_opsi');
      if (!mounted) return;
      setStateIfMounted(() => _catatanAlur = '${opsi['catatanAlur'] ?? ''}');
    } catch (_) {
      // Catatan alur hanya penjelasan; kegagalannya tidak menghalangi daftar.
    }
    await _muatDaftar();
  }

  Future<void> _muatDaftar() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      await MasterOffline.daftarCacheDulu(
        'closing_daftar',
        {if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim()},
        _cacheKey,
        kolomKunci: 'id',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data =
                ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
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
        entitas: 'closing',
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

  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan =
        TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    DateTime? tanggal = DateTime.tryParse('${baris?['tanggal'] ?? ''}');
    Map<String, dynamic> periksa = {};
    bool memeriksa = false;

    if (!mounted) return;
    Future<bool> simpanData() async {
      if (nama.text.trim().isEmpty) {
        throw Exception('Nama Periode wajib diisi.');
      }
      if (tanggal == null) {
        throw Exception('Tanggal batas wajib dipilih.');
      }
      if (periksa['adaTidakBalance'] == true ||
          periksa['tanggalTerpakai'] == true) {
        throw Exception([
          if (periksa['tanggalTerpakai'] == true)
            '${periksa['peringatanTanggal']}',
          if (periksa['adaTidakBalance'] == true) '${periksa['peringatan']}',
        ].join('\n\n'));
      }

      final idBaru = ubah ? null : MasterOffline.idSementaraBaru();
      return _kirimLokalDulu(
        'closing_simpan',
        {
          if (ubah) 'id': baris['id'],
          'nama': nama.text.trim(),
          'keterangan': keterangan.text.trim(),
          'tanggal': _fmt.format(tanggal!),
        },
        kunci: 'closing:${ubah ? baris['id'] : idBaru}',
        idLokal: ubah ? null : idBaru,
        rowLokal: {
          'id': ubah ? baris['id'] : idBaru,
          'nama': nama.text.trim(),
          'keterangan': keterangan.text.trim(),
          'tanggal': _fmt.format(tanggal!),
          'terkunci': false,
          'jumlahJurnal': baris?['jumlahJurnal'] ?? 0,
        },
      );
    }

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> jalankanPeriksa() async {
            if (tanggal == null) return;
            setDialog(() => memeriksa = true);
            try {
              final res = await ApiClient.instance.aksi('closing_periksa', {
                'tanggal': _fmt.format(tanggal!),
                if (ubah) 'id': baris['id'],
              });
              periksa = res.cast<String, dynamic>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memeriksa = false);
            }
          }

          final timpang = periksa['adaTidakBalance'] == true;
          final bentrok = periksa['tanggalTerpakai'] == true;
          return AlertDialog(
            title: Text(ubah ? 'Ubah Closing' : 'Closing Baru'),
            content: SizedBox(
              width: 560,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nama,
                  decoration: const InputDecoration(
                      labelText: 'Nama Periode *',
                      helperText: 'Mis. "Tutup Januari 2026"',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final t = await showDatePicker(
                      context: c,
                      initialDate: tanggal ?? DateTime.now(),
                      firstDate: DateTime(2015),
                      lastDate: DateTime(2100),
                    );
                    if (t == null) return;
                    setDialog(() => tanggal = t);
                    await jalankanPeriksa();
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(tanggal == null
                      ? 'Pilih Tanggal Batas *'
                      : 'Tanggal batas: ${_tampil.format(tanggal!)}'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(
                      labelText: 'Keterangan',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 12),
                if (memeriksa)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (tanggal != null && periksa.isNotEmpty) ...[
                  // Kesiapan diperiksa SEBELUM Simpan ditekan. Penolakan yang baru
                  // muncul sesudahnya membuat orang mengira dirinya salah tekan,
                  // bukan salah tanggal.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${periksa['jumlahJurnal'] ?? 0} jurnal akan ditautkan ke closing ini.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (timpang || bentrok)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          [
                            if (bentrok) '${periksa['peringatanTanggal']}',
                            if (timpang) '${periksa['peringatan']}',
                          ].join('\n\n'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ]),
            ),
            actions: [
              AppCrudDialogActions(
                onSubmit: simpanData,
                enabled: !(timpang || bentrok),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- rincian

  Future<void> _jurnal(Map<String, dynamic> b) async {
    List<Map<String, dynamic>> item = [];
    bool memuat = true;
    bool seimbang = true;
    double debet = 0;
    double kredit = 0;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          if (memuat) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final d = await ApiClient.instance
                    .aksi('closing_jurnal', {'id': b['id']});
                item =
                    ((d['data'] as List?) ?? []).cast<Map<String, dynamic>>();
                seimbang = d['seimbang'] == true;
                debet = (d['totalDebet'] as num?)?.toDouble() ?? 0;
                kredit = (d['totalKredit'] as num?)?.toDouble() ?? 0;
              } catch (e) {
                _pesan('$e');
              } finally {
                setDialog(() => memuat = false);
              }
            });
          }
          return AlertDialog(
            title: Text('Jurnal dalam ${b['nama'] ?? ''}'),
            content: SizedBox(
              width: 720,
              height: 440,
              child: memuat
                  ? const Center(child: CircularProgressIndicator())
                  : Column(children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${item.length} jurnal · Debet Rp ${_rupiah(debet)} · '
                          'Kredit Rp ${_rupiah(kredit)}'
                          '${seimbang ? '' : '  ⚠ TIDAK SEIMBANG'}',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: seimbang ? null : AppColors.danger),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: item.isEmpty
                            ? const Center(
                                child:
                                    Text('Belum ada jurnal dalam periode ini.'))
                            : ListView.builder(
                                itemCount: item.length,
                                itemBuilder: (_, i) {
                                  final j = item[i];
                                  final ok = j['seimbang'] == true;
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                        '${j['kode'] ?? ''} — ${j['keterangan'] ?? ''}',
                                        style: const TextStyle(fontSize: 12.5)),
                                    subtitle: Text('${j['tanggal'] ?? ''}',
                                        style: const TextStyle(fontSize: 11.5)),
                                    trailing: Text(
                                      'D ${_rupiah(j['debet'])}\nK ${_rupiah(j['kredit'])}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: ok ? null : AppColors.danger),
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
  }

  Future<void> _hapusBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Hapus closing?',
        '${b['nama']}\n\n'
            '${(b['jumlahJurnal'] as num?)?.toInt() ?? 0} jurnal akan DILEPAS dari closing ini. '
            'Artinya periode itu terbuka kembali dan postingnya dapat dibatalkan lagi.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'closing_hapus',
      {'id': b['id']},
      kunci: 'closing:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  // ------------------------------------------------------------- tampilan

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.closing,
      judul: 'Closing',
      subjudul: 'Penutupan periode akuntansi',
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
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  if (_catatanAlur.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_catatanAlur,
                                style: const TextStyle(fontSize: 12))),
                      ]),
                    ),
                  Row(children: [
                    Expanded(
                      child: AppSearchField(
                        controller: _cari,
                        hintText: 'Cari nama / keterangan periode',
                        onChanged: (_) => _muatDaftar(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_boleh('create'))
                      FilledButton.icon(
                        onPressed: _sibuk ? null : () => _form(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Tutup Periode'),
                      ),
                  ]),
                ]),
              ),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _tabel(),
              ),
            ]),
    );
  }

  Widget _tabel() => AppDataTable(
        minWidth: 900,
        emptyText: 'Belum ada periode yang ditutup.',
        columns: const [
          AppTableColumn('Tanggal Batas', flex: 2),
          AppTableColumn('Nama Periode', flex: 3),
          AppTableColumn('Keterangan', flex: 3),
          AppTableColumn('Jurnal', flex: 1, align: TextAlign.center),
          AppTableColumn('Status', flex: 2, align: TextAlign.center),
          AppTableColumn('Aksi', width: 64, align: TextAlign.center),
        ],
        rows: _data.map((b) {
          final terkunci = b['terkunci'] == true;
          return AppTableRowData(cells: [
            AppTableCell.text('${b['tanggal'] ?? ''}', flex: 2),
            AppTableCell.text('${b['nama'] ?? ''}', flex: 3),
            AppTableCell.text('${b['keterangan'] ?? ''}', flex: 3),
            AppTableCell.text('${(b['jumlahJurnal'] as num?)?.toInt() ?? 0}',
                flex: 1, align: TextAlign.center),
            AppTableCell(
              flex: 2,
              align: TextAlign.center,
              child: Center(
                child: Text(
                  terkunci ? 'terkunci · ${b['dikunciOleh']}' : 'terbuka',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: terkunci ? AppColors.success : null),
                ),
              ),
            ),
            AppTableCell(
              width: 64,
              child: AksiBarisMenu(
                tooltip: 'Aksi periode',
                aksi: [
                  AksiBaris(
                      ikon: Icons.list_alt_outlined,
                      label: 'Lihat jurnalnya',
                      onTap: _sibuk ? null : () => _jurnal(b)),
                  AksiBaris(
                      ikon: Icons.edit_outlined,
                      label: 'Ubah',
                      onTap: !terkunci && _boleh('update') && !_sibuk
                          ? () => _form(b)
                          : null),
                  AksiBaris(
                      ikon: Icons.lock_outline,
                      label: 'Kunci periode',
                      onTap: !terkunci && _boleh('approve') && !_sibuk
                          ? () async {
                              if (await _konfirmasi(
                                  'Kunci periode ini?',
                                  '${b['nama']}\n\n'
                                      'Setelah dikunci, closing ini tidak dapat diubah '
                                      'maupun dihapus sampai kuncinya dibuka.',
                                  'Kunci')) {
                                await _kirimLokalDulu(
                                    'closing_kunci', {'id': b['id']},
                                    kunci: 'closing:${b['id']}',
                                    rowLokal: {...b, 'terkunci': true});
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.lock_open_outlined,
                      label: 'Buka kunci',
                      onTap: terkunci && _boleh('reject') && !_sibuk
                          ? () async {
                              if (await _konfirmasi('Buka kunci periode?',
                                  '${b['nama']}', 'Buka')) {
                                await _kirimLokalDulu(
                                    'closing_buka', {'id': b['id']},
                                    kunci: 'closing:${b['id']}',
                                    rowLokal: {...b, 'terkunci': false});
                              }
                            }
                          : null),
                  AksiBaris(
                      ikon: Icons.delete_outline,
                      label: 'Hapus',
                      merusak: true,
                      onTap: !terkunci && _boleh('delete') && !_sibuk
                          ? () => _hapusBaris(b)
                          : null),
                ],
              ),
            ),
          ]);
        }).toList(),
      );
}
