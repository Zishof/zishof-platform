import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import 'keuangan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/safe_state.dart';

/// Layar **Uang Muka (Cash Advance)** -- padanan layar ZK
/// `ais.action.master.akunting.UangMukaAction`.
///
/// Seluruh aturan (urutan validasi, kode dokumen, pemeriksaan sisa saldo anggaran,
/// arti tiap status) dipegang server lewat `UangMukaApiHelper`, sehingga dokumen
/// yang dibuat dari sini identik dengan yang dibuat dari layar ZK. Layar ini hanya
/// menyajikan dan mengirim; tombol disembunyikan mengikuti hak akses yang dikirim
/// server, tetapi gerbang sebenarnya tetap di server.
class UangMukaScreen extends StatefulWidget {
  const UangMukaScreen({super.key});

  @override
  State<UangMukaScreen> createState() => _UangMukaScreenState();
}

class _UangMukaScreenState extends State<UangMukaScreen> {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  /// Kunci salinan lokal daftar ini -- dipakai baca cache-dulu dan
  /// penerapan optimistis hasil tulis.
  static const String _cacheKey = 'master:uang_muka';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _jenis = [];
  List<Map<String, dynamic>> _satker = [];
  List<String> _daftarStatus = const ['Pengajuan', 'Disetujui', 'Ditolak'];
  Map<String, bool> _hak = const {};
  bool _saldoHarusCukup = false;
  double _totalNilai = 0;

  // --- penyaring
  final _cari = TextEditingController();
  String _statusFilter = '';
  int? _satkerFilter;
  DateTime? _dari;
  DateTime? _sampai;
  bool _belumLpj = false;

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
      final opsi = await ApiClient.instance.aksi('uang_muka_opsi', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _jenis = ((opsi['jenisUangMuka'] as List?) ?? []).cast<Map<String, dynamic>>();
        _satker = ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _daftarStatus =
            ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
        _saldoHarusCukup = opsi['saldoHarusCukup'] == true;
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
      // Baca SALINAN LOKAL dulu: daftar tetap terbuka saat jaringan mati,
      // lalu diperbarui begitu balasan server tiba.
      await MasterOffline.daftarCacheDulu(
        'uang_muka_daftar',
        {
        if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
        if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
        if (_satkerFilter != null) 'satuanKerjaId': _satkerFilter,
        if (_dari != null) 'dari': _fmt.format(_dari!),
        if (_sampai != null) 'sampai': _fmt.format(_sampai!),
        if (_belumLpj) 'belumLpj': true,
        },
        _cacheKey,
        kolomKunci: 'id',
        onData: (hasil) {
          () async {
            final t = await MasterOffline.daftarTerhapusLokal(_cacheKey);
            if (mounted) setStateIfMounted(() => _terhapus = t);
          }();
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


  /// Baris yang dihapus di perangkat ini: TIDAK dibuang dari salinan lokal,
  /// hanya ditandai, supaya datanya masih bisa dilihat dan dipulihkan. Di sisi
  /// server penghapusannya sungguhan -- riwayatnya ada pada audit trail server.
  bool _tampilkanTerhapus = false;

  /// Diisi dari [MasterOffline.daftarTerhapusLokal]. Tidak bisa diambil dari
  /// [_data] karena `daftarCacheDulu` memang MENYARING baris bertanda `_dihapus`
  /// supaya tidak muncul di layar mana pun.
  List<Map<String, dynamic>> _terhapus = const [];

  List<Map<String, dynamic>> get _terlihat =>
      _tampilkanTerhapus ? _terhapus : _data;

  int get _jumlahTerhapus => _terhapus.length;

  bool _boleh(String aksi) => _hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }


  /// Tulis LOKAL DULU lalu kirim (prosesSimpanMaster): baris langsung tampak di
  /// daftar walau jaringan sedang mati, dan antreannya dikirim ulang otomatis.
  /// [rowLokal] adalah rupa baris setelah perubahan -- dipakai menerapkan hasilnya
  /// ke salinan lokal tanpa menunggu server.
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
        entitas: 'uang_muka',
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

  // ------------------------------------------------------------- pemilih anggaran

  /// Pemilih anggaran: hanya baris DAUN yang boleh dipilih, sesuai layar ZK.
  Future<Map<String, dynamic>?> _pilihAnggaran() async {
    final cari = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    bool memuat = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> jalankan() async {
            setDialog(() => memuat = true);
            try {
              final res = await ApiClient.instance
                  .aksi('uang_muka_cari_anggaran', {'cari': cari.text.trim()});
              hasil = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memuat = false);
            }
          }

          return AlertDialog(
            title: const Text('Pilih Anggaran'),
            content: SizedBox(
              width: 620,
              height: 420,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: cari,
                      hintText: 'Cari kode / nama anggaran',
                      autofocus: true,
                      onChanged: (_) => jalankan(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: jalankan, child: const Text('Cari')),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: memuat
                      ? const Center(child: CircularProgressIndicator())
                      : hasil.isEmpty
                          ? const Center(child: Text('Ketik kata kunci lalu tekan Cari.'))
                          : ListView.builder(
                              itemCount: hasil.length,
                              itemBuilder: (_, i) {
                                final w = hasil[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${w['kode'] ?? ''} ${w['nama'] ?? ''}'.trim()),
                                  subtitle: Text(
                                      'Pagu ${_uang.format((w['pagu'] as num?) ?? 0)}'
                                      ' • ${w['satuanKerja'] ?? '-'} • ${w['tahun'] ?? '-'}'),
                                  onTap: () => Navigator.pop(c, w),
                                );
                              },
                            ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            ],
          );
        },
      ),
    );
  }


  /// Pemilih baris **Permintaan Pengadaan (PR)** untuk uang muka berbasis PR.
  ///
  /// Menyalin aturan layar ZK (`AmbilDataPermintaanPengadaanMasterAssetBanyak`):
  /// hanya PR yang aktif, belum ditutup, dan sudah disetujui yang tampil; baris yang
  /// barangnya sudah diterima penuh tidak dapat dicentang. Baris yang sudah tertaut ke
  /// uang muka lain tetap bisa dipilih -- sama seperti ZK -- tetapi diberi peringatan
  /// karena memilihnya berarti memindahkan tautannya.
  Future<List<Map<String, dynamic>>?> _pilihBarisPr({
    required int? satkerId,
    required int? idDokumen,
    required List<Map<String, dynamic>> terpilihAwal,
  }) async {
    final cari = TextEditingController();
    final terpilih = <int, Map<String, dynamic>>{
      for (final b in terpilihAwal) (b['id'] as num).toInt(): b,
    };
    List<Map<String, dynamic>> daftarPr = [];
    bool memuat = false;
    String galat = '';
    bool sudahMuat = false;

    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Future<void> jalankan() async {
            setD(() {
              memuat = true;
              galat = '';
            });
            try {
              final res = await ApiClient.instance.aksi('uang_muka_cari_pr', {
                'cari': cari.text.trim(),
                if (satkerId != null) 'satuanKerjaId': satkerId,
                if (idDokumen != null) 'id': idDokumen,
              });
              daftarPr = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              galat = '$e';
            } finally {
              setD(() => memuat = false);
            }
          }

          if (!sudahMuat) {
            sudahMuat = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => jalankan());
          }

          double totalTerpilih = 0;
          for (final b in terpilih.values) {
            totalTerpilih += (b['total'] as num?)?.toDouble() ?? 0;
          }

          return AlertDialog(
            title: const Text('Pilih Baris Permintaan Pengadaan'),
            content: SizedBox(
              width: 720,
              height: 480,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: cari,
                      hintText: 'Cari kode / keterangan PR',
                      onChanged: (_) => jalankan(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: jalankan, child: const Text('Cari')),
                ]),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Hanya PR yang sudah disetujui dan belum ditutup yang tampil.',
                      style: TextStyle(fontSize: 12)),
                ),
                if (galat.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(galat,
                        style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: memuat
                      ? const Center(child: CircularProgressIndicator())
                      : daftarPr.isEmpty
                          ? const Center(
                              child: Text('Tidak ada permintaan pengadaan yang cocok.'))
                          : ListView.builder(
                              itemCount: daftarPr.length,
                              itemBuilder: (_, i) {
                                final pr = daftarPr[i];
                                final baris = ((pr['baris'] as List?) ?? [])
                                    .cast<Map<String, dynamic>>();
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        dense: true,
                                        title: Text('${pr['kode'] ?? ''} — ${pr['keterangan'] ?? ''}'),
                                        subtitle: Text(
                                            '${pr['satuanKerja'] ?? '-'}'
                                            '${(pr['anggaran'] ?? '').toString().isEmpty ? '' : ' • anggaran ${pr['anggaran']}'}'),
                                      ),
                                      ...baris.map((b) {
                                        final id = (b['id'] as num).toInt();
                                        final boleh = b['bolehPilih'] == true;
                                        final umLain =
                                            '${b['uangMukaKode'] ?? ''}'.isNotEmpty &&
                                                b['milikDokumenIni'] != true;
                                        return CheckboxListTile(
                                          dense: true,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          value: terpilih.containsKey(id),
                                          onChanged: boleh
                                              ? (v) => setD(() {
                                                    if (v == true) {
                                                      terpilih[id] = {
                                                        ...b,
                                                        'prKode': pr['kode'],
                                                      };
                                                    } else {
                                                      terpilih.remove(id);
                                                    }
                                                  })
                                              : null,
                                          title: Text(
                                              '${b['kodeAsset'] ?? ''} ${b['namaAsset'] ?? ''}'.trim()),
                                          subtitle: Text(
                                            '${_uang.format((b['jumlah'] as num?) ?? 0)}'
                                            ' x ${_uang.format((b['hargaBeli'] as num?) ?? 0)}'
                                            ' = ${_uang.format((b['total'] as num?) ?? 0)}'
                                            '${boleh ? '' : ' • ${b['alasanTerkunci']}'}'
                                            '${umLain ? ' • sudah tertaut ke ${b['uangMukaKode']}, memilihnya akan memindahkan tautan' : ''}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: !boleh || umLain
                                                    ? AppColors.danger
                                                    : null),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                      '${terpilih.length} baris dipilih • total ${_uang.format(totalTerpilih)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
              FilledButton(
                onPressed: () => Navigator.pop(c, terpilih.values.toList()),
                child: const Text('Pakai'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- formulir

  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    final nilai = TextEditingController(
        text: ((baris?['nilai'] as num?)?.toDouble() ?? 0) == 0
            ? ''
            : '${((baris?['nilai'] as num?) ?? 0).toInt()}');
    bool tanpaAnggaran = baris?['tanpaAnggaran'] == true;
    bool ambilDariPr = baris?['ambilDariPr'] == true;
    // Baris PR yang menjadi sumber dokumen ini. Pada dokumen lama isinya dimuat dari
    // server supaya formulir menampilkan pilihan yang sama seperti saat dibuat.
    List<Map<String, dynamic>> prTerpilih = [];
    int? satkerId = (baris?['satuanKerjaId'] as num?)?.toInt();
    int? jenisId = (baris?['jenisUangMukaId'] as num?)?.toInt();
    int? akunId = (baris?['akunId'] as num?)?.toInt();
    int? workspaceId = (baris?['workspaceId'] as num?)?.toInt();
    String workspaceNama = '${baris?['workspaceNama'] ?? ''}';
    String statusDokumen = '${baris?['statusDokumen'] ?? 'Pengajuan'}';
    DateTime? mulai = _tgl(baris?['mulai']);
    DateTime? sampai = _tgl(baris?['sampai']);
    DateTime? selesai = _tgl(baris?['selesai']);
    double? sisaSaldo;

    if (ubah && ambilDariPr) {
      try {
        final res = await ApiClient.instance.aksi('uang_muka_cari_pr', {'id': baris['id']});
        for (final pr in ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>()) {
          for (final b in ((pr['baris'] as List?) ?? []).cast<Map<String, dynamic>>()) {
            if (b['milikDokumenIni'] == true) {
              prTerpilih.add({...b, 'prKode': pr['kode']});
            }
          }
        }
      } catch (_) {
        // Gagal memuat bukan alasan menolak membuka formulir; pengguna dapat
        // memilih ulang barisnya, dan server tetap memegang data yang tersimpan.
      }
    }

    // Akun dipilih dari bagan akun yang sama dengan modul Akuntansi.
    List<Map<String, dynamic>> daftarAkun = [];
    try {
      final res = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
      daftarAkun = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
    } catch (_) {
      // Biarkan kosong; pemilih akan tampil tanpa pilihan dan server tetap memvalidasi.
    }

    if (!mounted) return;
    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> hitungSisa() async {
            if (tanpaAnggaran || ambilDariPr || workspaceId == null) {
              setDialog(() => sisaSaldo = null);
              return;
            }
            try {
              final res = await ApiClient.instance.aksi('uang_muka_saldo', {
                'workspaceId': workspaceId,
                if (ubah) 'id': baris['id'],
                if (mulai != null) 'tanggal': _fmt.format(mulai!),
              });
              setDialog(() => sisaSaldo = (res['saldo'] as num?)?.toDouble());
            } catch (_) {
              setDialog(() => sisaSaldo = null);
            }
          }

          Future<void> pilihTanggal(String jenisTgl) async {
            final awal = jenisTgl == 'mulai'
                ? mulai
                : jenisTgl == 'sampai'
                    ? sampai
                    : selesai;
            final t = await showDatePicker(
              context: c,
              initialDate: awal ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (t == null) return;
            setDialog(() {
              if (jenisTgl == 'mulai') {
                mulai = t;
              } else if (jenisTgl == 'sampai') {
                sampai = t;
              } else {
                selesai = t;
              }
            });
            if (jenisTgl == 'mulai') await hitungSisa();
          }

          return AlertDialog(
            title: Text(ubah ? 'Ubah Pengajuan Uang Muka' : 'Pengajuan Uang Muka Baru'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _isian('Judul Pengajuan', nama, wajib: true),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tanpa Anggaran'),
                    subtitle: const Text(
                        'Tidak membebani anggaran; Satuan Kerja dan Akun menjadi wajib.'),
                    value: tanpaAnggaran,
                    onChanged: (v) {
                      setDialog(() => tanpaAnggaran = v);
                      hitungSisa();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Diambil dari Permintaan Pengadaan (PR)'),
                    subtitle: const Text(
                        'Nilainya dihitung dari baris PR yang dipilih; anggaran tidak '
                        'dipotong lagi karena PR-nya sudah memotong.'),
                    value: ambilDariPr,
                    onChanged: (v) {
                      setDialog(() {
                        ambilDariPr = v;
                        if (!v) prTerpilih = [];
                      });
                      hitungSisa();
                    },
                  ),
                  const SizedBox(height: 8),
                  _dropdownInt(
                    label: 'Satuan Kerja',
                    nilai: satkerId,
                    opsi: _satker,
                    onChanged: (v) => setDialog(() => satkerId = v),
                  ),
                  if (ambilDariPr) ...[
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Baris Permintaan Pengadaan *',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: satkerId == null
                            ? 'Pilih Satuan Kerja dulu agar daftar PR-nya menyempit.'
                            : null,
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(prTerpilih.isEmpty
                              ? 'Belum ada baris PR yang dipilih'
                              : '${prTerpilih.length} baris dipilih'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final hasil = await _pilihBarisPr(
                              satkerId: satkerId,
                              idDokumen: ubah ? baris['id'] as int? : null,
                              terpilihAwal: prTerpilih,
                            );
                            if (hasil == null) return;
                            setDialog(() {
                              prTerpilih = hasil;
                              // Nilai mengikuti baris PR, sama seperti layar ZK yang
                              // mengisi kolom Nilai begitu PR-nya dipilih.
                              double t = 0;
                              for (final b in hasil) {
                                t += (b['total'] as num?)?.toDouble() ?? 0;
                              }
                              nilai.text = t == 0 ? '' : '${t.toInt()}';
                            });
                          },
                          child: const Text('Pilih'),
                        ),
                      ]),
                    ),
                    if (prTerpilih.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: prTerpilih
                              .map((b) => Text(
                                    '• ${b['prKode'] ?? ''} — '
                                    '${b['kodeAsset'] ?? ''} ${b['namaAsset'] ?? ''} '
                                    '(${_uang.format((b['total'] as num?) ?? 0)})',
                                    style: const TextStyle(fontSize: 12),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                  if (!tanpaAnggaran && !ambilDariPr) ...[
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Anggaran *',
                          border: OutlineInputBorder(),
                          isDense: true),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            workspaceNama.isEmpty ? 'Belum dipilih' : workspaceNama,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final w = await _pilihAnggaran();
                            if (w == null) return;
                            setDialog(() {
                              workspaceId = (w['id'] as num?)?.toInt();
                              workspaceNama =
                                  '${w['kode'] ?? ''} ${w['nama'] ?? ''}'.trim();
                            });
                            await hitungSisa();
                          },
                          child: const Text('Pilih'),
                        ),
                      ]),
                    ),
                    if (sisaSaldo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Sisa saldo anggaran: ${_uang.format(sisaSaldo)}'
                            '${_saldoHarusCukup ? ' — pengajuan tidak boleh melebihi ini' : ''}',
                            style: TextStyle(
                                fontSize: 12,
                                color: _saldoHarusCukup
                                    ? AppColors.danger
                                    : AppColors.textSecondaryOf(context)),
                          ),
                        ),
                      ),
                  ],
                  // Akun tidak dipakai pada pengajuan berbasis PR -- di layar ZK pun
                  // barisnya hanya muncul ketika "tanpa anggaran" DAN bukan dari PR.
                  if (!ambilDariPr) ...[
                    const SizedBox(height: 12),
                    PemilihAkunField(
                      label: 'Akun',
                      daftar: daftarAkun,
                      nilai: akunId,
                      helperText: tanpaAnggaran
                          ? 'Wajib diisi untuk pengajuan tanpa anggaran.'
                          : 'Opsional bila pengajuan membebani anggaran.',
                      onChanged: (v) => setDialog(() => akunId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _dropdownInt(
                    label: 'Jenis Uang Muka (Akun Penerima)',
                    nilai: jenisId,
                    opsi: _jenis,
                    onChanged: (v) => setDialog(() => jenisId = v),
                  ),
                  const SizedBox(height: 12),
                  _isian('Nilai Pengajuan', nilai, wajib: true, angka: true),
                  _tombolTanggal('Tanggal Mulai *', mulai, () => pilihTanggal('mulai')),
                  _tombolTanggal('Tanggal Sampai *', sampai, () => pilihTanggal('sampai')),
                  _tombolTanggal('Tanggal Laporan *', selesai, () => pilihTanggal('selesai')),
                  const SizedBox(height: 12),
                  _isian('Keterangan', keterangan),
                  DropdownButtonFormField<String>(
                    value: _daftarStatus.contains(statusDokumen)
                        ? statusDokumen
                        : _daftarStatus.first,
                    decoration: const InputDecoration(
                        labelText: 'Status', border: OutlineInputBorder(), isDense: true),
                    items: _daftarStatus
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setDialog(() => statusDokumen = v ?? 'Pengajuan'),
                  ),
                ]),
              ),
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

    // Diperiksa di sini supaya penggunanya tidak menunggu perjalanan ke server hanya
    // untuk diberi tahu satu kolom kosong. Server TETAP memeriksanya ulang -- ini
    // hanya mempercepat pesannya, bukan memindahkan aturannya ke layar.
    if (nama.text.trim().isEmpty) {
      _pesan('Judul Pengajuan belum diisi.');
      return;
    }
    final nilaiAngka = double.tryParse(nilai.text.trim().replaceAll('.', '')) ?? 0;
    // Pada pengajuan berbasis PR nilainya datang dari baris PR yang dipilih, jadi
    // kolomnya memang boleh kosong -- sama seperti aturan di server.
    if (!ambilDariPr && nilaiAngka <= 0) {
      _pesan('Nilai Pengajuan belum diisi.');
      return;
    }

    final idLokal = ubah ? null : MasterOffline.idSementaraBaru();
    final payload = <String, dynamic>{
      if (ubah) 'id': baris['id'],
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'tanpaAnggaran': tanpaAnggaran,
      'ambilDariPr': ambilDariPr,
      if (ambilDariPr)
        'prDetailIds': prTerpilih.map((b) => (b['id'] as num).toInt()).toList(),
      'satuanKerjaId': satkerId ?? 0,
      'akunId': akunId ?? 0,
      'workspaceId': workspaceId ?? 0,
      'jenisUangMukaId': jenisId ?? 0,
      'nilai': nilaiAngka,
      if (mulai != null) 'mulai': _fmt.format(mulai!),
      if (sampai != null) 'sampai': _fmt.format(sampai!),
      if (selesai != null) 'selesai': _fmt.format(selesai!),
      'statusDokumen': statusDokumen,
    };
    await _kirimLokalDulu(
      'uang_muka_simpan',
      payload,
      kunci: ubah ? 'uang_muka:${baris['id']}' : 'uang_muka:baru:$idLokal',
      idLokal: idLokal,
      rowLokal: {
        ...(baris ?? const <String, dynamic>{}),
        'id': ubah ? baris['id'] : idLokal,
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'nilai': nilaiAngka,
        'statusDokumen': statusDokumen,
        'tanpaAnggaran': tanpaAnggaran,
        'ambilDariPr': ambilDariPr,
        'prDetailIds': prTerpilih.map((b) => (b['id'] as num).toInt()).toList(),
        'satuanKerjaId': satkerId,
        'workspaceId': workspaceId,
        'workspaceNama': workspaceNama,
        'akunId': akunId,
        'jenisUangMukaId': jenisId,
        if (mulai != null) 'mulai': _fmt.format(mulai!),
        if (sampai != null) 'sampai': _fmt.format(sampai!),
        if (selesai != null) 'selesai': _fmt.format(selesai!),
      },
    );
  }

  static DateTime? _tgl(Object? v) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Widget _isian(String label, TextEditingController c,
          {bool wajib = false, bool angka = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: angka ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: wajib ? '$label *' : label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _dropdownInt({
    required String label,
    required int? nilai,
    required List<Map<String, dynamic>> opsi,
    required ValueChanged<int?> onChanged,
  }) {
    final ada = opsi.any((e) => (e['id'] as num?)?.toInt() == nilai);
    return DropdownButtonFormField<int>(
      value: ada ? nilai : null,
      isExpanded: true,
      decoration: InputDecoration(
          labelText: label, border: const OutlineInputBorder(), isDense: true),
      items: opsi
          .map((e) => DropdownMenuItem(
                value: (e['id'] as num?)?.toInt(),
                child: Text('${e['nama'] ?? ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _tombolTanggal(String label, DateTime? nilai, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.event, size: 18),
            label: Text('$label: ${nilai == null ? '-' : _fmt.format(nilai)}'),
          ),
        ),
      );

  // ------------------------------------------------------------- tampilan

  AppTableCell _aksiBaris(Map<String, dynamic> b) {
    final status = '${b['statusDokumen'] ?? ''}';
    final terkunci = b['sudahDijurnal'] == true;
    return AppTableCell(
      width: 208,
      align: TextAlign.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Cetak memakai templat yang sama dengan layar ZK -- lihat keuangan_cetak_util.
        // Muara dokumen keuangan: DPC (Daftar Pengajuan Transfer). Hanya dokumen
        // yang sudah disetujui yang boleh masuk, dan sekali masuk tidak diulang --
        // server memperlakukan penautannya sebagai idempoten.
        if (!_tampilkanTerhapus && _boleh('approve') && status == 'Disetujui')
          b['dpcAda'] == true
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Sudah di daftar transfer'
                      '${(b['dpcKode'] ?? '').toString().isEmpty ? '' : ' (${b['dpcKode']})'}',
                  icon: const Icon(Icons.local_atm, size: 18, color: AppColors.success),
                  onPressed: null,
                )
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Ajukan ke proses transfer',
                  icon: const Icon(Icons.send_outlined, size: 18),
                  onPressed: _sibuk
                      ? null
                      : () async {
                          if (await _konfirmasi('Ajukan ke proses transfer?',
                              '${b['kode']} — ${b['nama']}\n'
                              'Dokumen masuk daftar pengajuan transfer bagian keuangan.',
                              'Ajukan')) {
                            await _kirimLokalDulu(
                                'uang_muka_ajukan_transfer', {'id': b['id']},
                                kunci: 'uang_muka-dpc:${b['id']}',
                                rowLokal: {
                                  ...b,
                                  'dpcAda': true,
                                  'dpcStatus': 'Menunggu transfer',
                                });
                          }
                        },
                ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Cetak / pratinjau',
          icon: const Icon(Icons.print_outlined, size: 18),
          onPressed: _sibuk || _tampilkanTerhapus
              ? null
              : () => cetakDokumenKeuangan(context,
                  modul: 'uang_muka',
                  id: (b['id'] as num).toInt(),
                  kode: '${b['kode'] ?? ''}'),
        ),
        if (_tampilkanTerhapus && _boleh('create'))
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Pulihkan sebagai dokumen baru',
            icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
            onPressed: _sibuk ? null : () => _pulihkanBaris(b),
          ),
        if (!_tampilkanTerhapus && _boleh('update') && !terkunci)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ubah pengajuan',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: _sibuk ? null : () => _form(b),
          ),
        if (_boleh('approve') && !terkunci && status != 'Disetujui')
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Setujui',
            icon: const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
            onPressed: _sibuk
                ? null
                : () async {
                    if (await _konfirmasi('Setujui pengajuan?',
                        '${b['kode']} — ${b['nama']}\nNilai ${_uang.format((b['nilai'] as num?) ?? 0)}',
                        'Setujui')) {
                      await _kirimLokalDulu('uang_muka_setujui', {'id': b['id']},
                          kunci: 'uang_muka:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Disetujui'});
                    }
                  },
          ),
        if (_boleh('reject') && !terkunci && status != 'Ditolak')
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Tolak',
            icon: const Icon(Icons.cancel_outlined, size: 18),
            onPressed: _sibuk
                ? null
                : () async {
                    if (await _konfirmasi('Tolak pengajuan?',
                        '${b['kode']} — ${b['nama']}', 'Tolak')) {
                      await _kirimLokalDulu('uang_muka_tolak', {'id': b['id']},
                          kunci: 'uang_muka:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Ditolak'});
                    }
                  },
          ),
        if (_boleh('delete') && !terkunci)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus pengajuan',
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
            onPressed: _sibuk ? null : () => _hapusBaris(b),
          ),
      ]),
    );
  }


  /// Hapus: server menghapus sungguhan (riwayatnya ada pada audit trail server),
  /// sedangkan SALINAN LOKAL hanya DITANDAI terhapus -- barisnya tetap tersimpan
  /// sehingga masih bisa dilihat dan datanya dipakai untuk memulihkan.
  /// Hapus: server menghapus sungguhan (jejaknya ada pada audit trail server),
  /// sedangkan di perangkat penandaannya diserahkan ke MasterOffline supaya
  /// pembatalannya ikut membuang perintah hapus yang masih mengantre.
  Future<void> _hapusBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Hapus pengajuan ini?',
        '${b['kode']} — ${b['nama']}\n\n'
            'Di perangkat ini barisnya hanya ditandai terhapus (masih bisa dilihat '
            'lewat penyaring "Terhapus"), sedangkan di server benar-benar dihapus.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'uang_muka_hapus',
      {'id': b['id']},
      kunci: 'uang_muka:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  /// Membatalkan penghapusan yang MASIH mengantre di perangkat.
  ///
  /// Begitu hapusnya terkirim, server sudah benar-benar menghapus dokumennya dan
  /// pengembalian datanya ditempuh lewat tabel audit di sisi server -- bukan dari
  /// layar ini. Karena itu [MasterOffline.pulihkanLokal] mengembalikan false bila
  /// barisnya sudah tidak bertanda.
  Future<void> _pulihkanBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Batalkan penghapusan pengajuan ini?',
        '${b['kode']} — ${b['nama']}\n\n'
            'Berlaku selama penghapusannya belum terkirim ke server. Bila sudah '
            'terkirim, pengembalian datanya dilakukan lewat catatan audit di '
            'server, bukan dari layar ini.',
        'Batalkan penghapusan')) {
      return;
    }
    setStateIfMounted(() => _sibuk = true);
    try {
      final berhasil = await MasterOffline.pulihkanLokal(
          _cacheKey, b['id'], kunci: 'uang_muka:${b['id']}');
      _pesan(berhasil
          ? 'Penghapusan dibatalkan.'
          : 'Tidak dapat dibatalkan: penghapusannya sudah terkirim ke server. '
              'Pemulihan data dilakukan lewat catatan audit di server.');
      await _muatDaftar();
    } finally {
      if (mounted) setStateIfMounted(() => _sibuk = false);
    }
  }

  /// Dua tab pada setiap menu Keuangan: "Dasbor" (ringkasan angka) dan daftar
  /// datanya -- susunan yang SAMA dengan keenam menu Pengadaan supaya berpindah
  /// grup menu tidak menuntut penyesuaian kebiasaan.
  Widget _bungkusTab(Widget isiData) => DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Dasbor'),
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Pengajuan'),
          ]),
          Expanded(
            child: TabBarView(children: [
              const PengadaanDasborTab(
                  tahap: 'uang_muka',
                  aksi: 'keuangan_dasbor',
                  namaParam: 'modul'),
              isiData,
            ]),
          ),
        ]),
      );

  Widget _penyaring() => Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 240,
            child: AppSearchField(
              controller: _cari,
              hintText: 'Cari kode / judul',
              onChanged: (_) => _muatDaftar(),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              value: _statusFilter.isEmpty ? '' : _statusFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status', isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('Semua status')),
                ..._daftarStatus.map((s) => DropdownMenuItem(value: s, child: Text(s))),
              ],
              onChanged: (v) => setStateIfMounted(() => _statusFilter = v ?? ''),
            ),
          ),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<int>(
              value: _satkerFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Satuan Kerja', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Semua satuan kerja')),
                ..._satker.map((e) => DropdownMenuItem(
                      value: (e['id'] as num?)?.toInt(),
                      child: Text('${e['nama'] ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setStateIfMounted(() => _satkerFilter = v),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                initialDateRange: _dari != null && _sampai != null
                    ? DateTimeRange(start: _dari!, end: _sampai!)
                    : null,
              );
              if (r == null) return;
              setStateIfMounted(() {
                _dari = r.start;
                _sampai = r.end;
              });
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_dari == null
                ? 'Rentang Tanggal Mulai'
                : '${_fmt.format(_dari!)} s/d ${_fmt.format(_sampai!)}'),
          ),
          FilterChip(
            label: const Text('Belum ada LPJ'),
            selected: _belumLpj,
            onSelected: (v) => setStateIfMounted(() => _belumLpj = v),
          ),
          FilterChip(
            label: Text(_jumlahTerhapus == 0
                ? 'Terhapus'
                : 'Terhapus ($_jumlahTerhapus)'),
            selected: _tampilkanTerhapus,
            onSelected: (v) => setStateIfMounted(() => _tampilkanTerhapus = v),
          ),
          FilledButton.icon(
            onPressed: _memuat ? null : _muatDaftar,
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            label: const Text('Terapkan'),
          ),
          if (_boleh('create'))
            FilledButton.icon(
              onPressed: _sibuk ? null : () => _form(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Pengajuan Baru'),
            ),
          if (_sibuk)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.uangMuka,
      judul: 'Uang Muka (Cash Advance)',
      subjudul: 'Pengajuan dana di muka beserta persetujuannya',
      scrollable: false,
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _muatSemua,
          tooltip: 'Muat ulang'),
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _muatSemua,
            tooltip: 'Muat ulang')
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _penyaring(),
        if (!_memuat && _galat == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_data.length} pengajuan • total ${_uang.format(_totalNilai)}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
        Expanded(
          child: _bungkusTab(_memuat
              ? const Center(child: CircularProgressIndicator())
              : _galat != null
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_galat!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _muatSemua, child: const Text('Coba lagi')),
                      ]),
                    ))
                  : AppDataTable(
                      minWidth: 1120,
                      emptyText: 'Belum ada pengajuan uang muka untuk penyaring ini.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Judul', flex: 4),
                        AppTableColumn('Satuan Kerja', flex: 3),
                        AppTableColumn('Anggaran', flex: 3),
                        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                        AppTableColumn('Periode', flex: 3),
                        AppTableColumn('Status', flex: 2),
                        AppTableColumn('Aksi', width: 176, align: TextAlign.center),
                      ],
                      rows: _terlihat
                          .map((b) => AppTableRowData(cells: [
                                AppTableCell.text('${b['kode'] ?? ''}', flex: 2),
                                AppTableCell.text('${b['nama'] ?? ''}', flex: 4),
                                AppTableCell.text('${b['satuanKerjaNama'] ?? ''}', flex: 3),
                                AppTableCell.text(
                                    b['tanpaAnggaran'] == true
                                        ? 'Tanpa anggaran'
                                        : '${b['workspaceNama'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    _uang.format((b['nilai'] as num?) ?? 0),
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text(
                                    '${b['mulai'] ?? ''} s/d ${b['sampai'] ?? ''}',
                                    flex: 3),
                                AppTableCell.text(
                                    '${b['statusDokumen'] ?? ''}'
                                    '${b['sudahDijurnal'] == true ? ' • terjurnal' : ''}'
                                    '${b['punyaLpj'] == true ? ' • ada LPJ' : ''}'
                                    '${b['dpcAda'] == true ? ' • di daftar transfer' : ''}',
                                    flex: 2),
                                _aksiBaris(b),
                              ]))
                          .toList(),
                    )),
        ),
      ]),
    );
  }
}
