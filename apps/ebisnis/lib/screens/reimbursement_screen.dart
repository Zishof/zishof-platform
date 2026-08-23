import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pemilih_anggaran.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';
import 'keuangan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';

/// Layar **Reimbursement Pegawai** -- padanan layar ZK
/// `ais.action.master.akunting.ReimbursementPegawaiAction`.
///
/// Nilai dokumen DIHITUNG DARI RINCIAN oleh server (hanya baris biaya yang
/// dijumlahkan, dan baris biaya tidak boleh bernilai nol), sehingga angkanya
/// tidak pernah berbeda antara kanal ini dan layar ZK. Seperti layar Keuangan
/// lainnya: dua tab (Dasbor & data), tombol cetak dgn templat yang sama, tulis
/// lokal-dulu, dan penghapusan yang di perangkat hanya menandai barisnya.
class ReimbursementScreen extends StatefulWidget {
  const ReimbursementScreen({super.key});

  @override
  State<ReimbursementScreen> createState() => _ReimbursementScreenState();
}

class _ReimbursementScreenState extends State<ReimbursementScreen> {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  /// Kunci salinan lokal daftar ini.
  static const String _cacheKey = 'master:reimbursement';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _jenis = [];
  List<Map<String, dynamic>> _satker = [];

  /// Bagan akun untuk pemilih akun biaya pada rincian.
  /// Jenis pengeluaran: tiap baris rincian memilih salah satunya, dan AKUN-nya
  /// diturunkan dari sana. Bila admin belum memetakan akunnya, server menolak
  /// dengan pesan yang menyebut siapa yang harus melengkapi.
  List<Map<String, dynamic>> _jenisPengeluaran = [];
  List<String> _daftarStatus = const ['Pengajuan', 'Disetujui', 'Ditolak'];
  Map<String, bool> _hak = const {};
  double _totalNilai = 0;

  final _cari = TextEditingController();
  String _statusFilter = '';
  int? _satkerFilter;
  int? _jenisFilter;
  DateTime? _dari;
  DateTime? _sampai;
  bool _belumDiganti = false;

  /// Baris yang dihapus di perangkat ini: TIDAK dibuang dari salinan lokal,
  /// hanya ditandai, supaya penghapusannya masih dapat dibatalkan selama belum
  /// terkirim. Penandaannya dikerjakan MasterOffline (kunci `_dihapus`), bukan
  /// oleh layar ini -- lihat catatan pada [_hapusBaris].
  bool _tampilkanTerhapus = false;

  /// Diisi dari [MasterOffline.daftarTerhapusLokal]. Tidak bisa diambil dari [_data]
  /// karena `daftarCacheDulu` memang MENYARING baris bertanda `_dihapus` supaya
  /// tidak muncul di layar mana pun.
  List<Map<String, dynamic>> _terhapus = const [];

  List<Map<String, dynamic>> get _terlihat =>
      _tampilkanTerhapus ? _terhapus : _data;

  int get _jumlahTerhapus => _terhapus.length;

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
      final opsi = await ApiClient.instance.aksi('reimbursement_opsi', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _jenis = ((opsi['jenisReimbursement'] as List?) ?? []).cast<Map<String, dynamic>>();
        _satker = ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _daftarStatus = ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
        _jenisPengeluaran =
            ((opsi['jenisPengeluaran'] as List?) ?? []).cast<Map<String, dynamic>>();
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
      // Baca SALINAN LOKAL dulu: daftar tetap terbuka saat jaringan mati.
      await MasterOffline.daftarCacheDulu(
        'reimbursement_daftar',
        {
          if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
          if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
          if (_satkerFilter != null) 'satuanKerjaId': _satkerFilter,
          if (_dari != null) 'dari': _fmt.format(_dari!),
          if (_sampai != null) 'sampai': _fmt.format(_sampai!),
          if (_belumDiganti) 'belumDiganti': true,
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

  bool _boleh(String aksi) => _hak[aksi] != false;

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  /// Tulis LOKAL DULU lalu kirim (prosesSimpanMaster).
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
        entitas: 'reimbursement',
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

  /// Apakah jenis reimbursement ini membebani anggaran. Jawabannya datang dari server
  /// (`menggunakanAnggaran` pada aksi opsi) supaya layar tidak menebak aturan yang
  /// tetap diperiksa ulang saat menyimpan.
  bool _pakaiAnggaran(int? jenisId) {
    for (final e in _jenis) {
      if ((e['id'] as num?)?.toInt() == jenisId) {
        return e['menggunakanAnggaran'] == true;
      }
    }
    return false;
  }

  /// Pemilih pegawai penerima penggantian.
  Future<Map<String, dynamic>?> _pilihPegawai() async {
    final cari = TextEditingController();
    List<Map<String, dynamic>> hasil = [];
    bool memuat = false;
    bool sudahMuat = false;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Future<void> jalankan() async {
            setD(() => memuat = true);
            try {
              final res = await ApiClient.instance
                  .aksi('reimbursement_cari_pegawai', {'cari': cari.text.trim()});
              hasil = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setD(() => memuat = false);
            }
          }

          if (!sudahMuat) {
            sudahMuat = true;
            WidgetsBinding.instance.addPostFrameCallback((_) => jalankan());
          }

          return AlertDialog(
            title: const Text('Pilih Pegawai Penerima'),
            content: SizedBox(
              width: 560,
              height: 400,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: cari,
                      hintText: 'Cari nama pegawai',
                      onChanged: (_) => jalankan(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: jalankan, child: const Text('Cari')),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: memuat
                      ? const Center(child: CircularProgressIndicator())
                      : hasil.isEmpty
                          ? const Center(child: Text('Tidak ada pegawai yang cocok.'))
                          : ListView.builder(
                              itemCount: hasil.length,
                              itemBuilder: (_, i) {
                                final p = hasil[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${p['nama'] ?? ''}'),
                                  subtitle: Text('${p['satuanKerja'] ?? '-'}'),
                                  onTap: () => Navigator.pop(c, p),
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

  /// Meminta catatan atasan. Wajib pada penolakan maupun permintaan revisi -- tanpa
  /// alasan, pengaju tidak tahu apa yang harus diperbaiki, dan server menolaknya.
  Future<String?> _mintaCatatan(String judul) async {
    final catatan = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: catatan,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Catatan untuk pengaju *',
                helperText: 'Wajib diisi — server menolak tanpa alasan.',
                border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kirim')),
        ],
      ),
    );
    if (ok != true) return null;
    return catatan.text.trim();
  }

  // ------------------------------------------------------------- formulir

  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    int? satkerId = (baris?['satuanKerjaId'] as num?)?.toInt();
    int? jenisId = (baris?['jenisReimbursementId'] as num?)?.toInt();
    int? pegawaiId = (baris?['pegawaiId'] as num?)?.toInt();
    String pegawaiNama = '${baris?['pegawaiNama'] ?? ''}';
    int? workspaceId = (baris?['workspaceId'] as num?)?.toInt();
    String workspaceNama = '${baris?['workspaceNama'] ?? ''}';
    DateTime? tanggal = _tgl(baris?['tanggalPengeluaran']);
    String statusDokumen = '${baris?['statusDokumen'] ?? 'Pengajuan'}';
    final rincian = <Map<String, dynamic>>[
      ...(((baris?['rincian'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
    ];
    double nilaiHitung = (baris?['nilai'] as num?)?.toDouble() ?? 0;
    String masalahRincian = '';

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> hitung() async {
            try {
              final res =
                  await ApiClient.instance.aksi('reimbursement_hitung', {'rincian': rincian});
              setDialog(() {
                nilaiHitung = (res['nilai'] as num?)?.toDouble() ?? 0;
                masalahRincian = '${res['masalah'] ?? ''}';
              });
            } catch (_) {
              // Biarkan angka lama; server tetap menghitung ulang saat menyimpan.
            }
          }

          Future<void> formBaris([int? indeks]) async {
            final b = indeks == null ? <String, dynamic>{} : rincian[indeks];
            final uraian = TextEditingController(text: '${b['uraian'] ?? ''}');
            final jumlah = TextEditingController(
                text: b['jumlah'] == null ? '' : '${(b['jumlah'] as num).toInt()}');
            int? akunId = (b['akun'] as num?)?.toInt();
            int? jenisPengeluaranId = (b['jenisPengeluaran'] as num?)?.toInt();
            final ok = await showDialog<bool>(
              context: c,
              builder: (d) => StatefulBuilder(
                builder: (d, setD) => AlertDialog(
                title: Text(indeks == null ? 'Tambah Rincian Biaya' : 'Ubah Rincian Biaya'),
                content: SizedBox(
                  width: 460,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: uraian,
                        decoration: const InputDecoration(
                            labelText: 'Uraian', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 12),
                    TextField(
                        controller: jumlah,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Jumlah *',
                            helperText: 'Tidak boleh nol — server menolaknya.',
                            border: OutlineInputBorder(),
                            isDense: true)),
                    const SizedBox(height: 12),
                    // Akun baris diturunkan dari JENIS PENGELUARAN, tidak dipilih
                    // langsung. Bila admin belum memetakan akunnya, server menolak dengan
                    // pesan yang menyebut siapa yang harus melengkapi -- karena itu jenis
                    // yang akunnya kosong tetap ditampilkan, bukan disembunyikan.
                    _dropdownInt(
                      label: 'Jenis Pengeluaran *',
                      nilai: jenisPengeluaranId,
                      opsi: _jenisPengeluaran,
                      onChanged: (v) => setD(() {
                        jenisPengeluaranId = v;
                        akunId = null;
                        for (final e in _jenisPengeluaran) {
                          if ((e['id'] as num?)?.toInt() == v) {
                            akunId = (e['akunId'] as num?)?.toInt();
                          }
                        }
                      }),
                    ),
                    if (jenisPengeluaranId != null && akunId == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'Akun untuk jenis ini belum dipetakan administrator — '
                              'baris ini akan ditolak saat disimpan.',
                              style: TextStyle(fontSize: 12, color: AppColors.danger)),
                        ),
                      ),
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true), child: const Text('Simpan')),
                ],
              ),
              ),
            );
            if (ok != true) return;
            // 'key' menandai baris BIAYA (yang ikut dijumlahkan server); baris tanpa
            // key pada layar ZK hanya pengelompok tampilan.
            final key = b['key'] ??
                (rincian.fold<int>(0, (m, e) => ((e['key'] as num?)?.toInt() ?? 0) > m
                    ? (e['key'] as num).toInt()
                    : m) +
                    1);
            final data = <String, dynamic>{
              'key': key,
              'uraian': uraian.text.trim(),
              'jumlah': double.tryParse(jumlah.text.trim()) ?? 0,
              if (akunId != null) 'akun': akunId,
              if (jenisPengeluaranId != null) 'jenisPengeluaran': jenisPengeluaranId,
            };
            setDialog(() {
              if (indeks == null) {
                rincian.add(data);
              } else {
                rincian[indeks] = data;
              }
            });
            await hitung();
          }

          return AlertDialog(
            title: Text(ubah ? 'Ubah Pengajuan Reimbursement' : 'Pengajuan Reimbursement Baru'),
            content: SizedBox(
              width: 660,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _dropdownInt(
                    label: 'Satuan Kerja *',
                    nilai: satkerId,
                    opsi: _satker,
                    onChanged: (v) => setDialog(() => satkerId = v),
                  ),
                  const SizedBox(height: 12),
                  _isian('Judul Pengajuan', nama, wajib: true),
                  // Jenis reimbursement menentukan apakah pengajuan membebani anggaran.
                  // Bila memakai anggaran, anggarannya wajib dipilih; bila tidak, akun
                  // biayanya diambil dari jenis itu sendiri.
                  _dropdownInt(
                    label: 'Jenis Reimbursement *',
                    nilai: jenisId,
                    opsi: _jenis,
                    onChanged: (v) => setDialog(() {
                      jenisId = v;
                      if (!_pakaiAnggaran(v)) {
                        workspaceId = null;
                        workspaceNama = '';
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Pegawai Penerima *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    child: Row(children: [
                      Expanded(
                        child: Text(pegawaiNama.isEmpty ? 'Belum dipilih' : pegawaiNama,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      TextButton(
                        onPressed: () async {
                          final p = await _pilihPegawai();
                          if (p == null) return;
                          setDialog(() {
                            pegawaiId = (p['id'] as num?)?.toInt();
                            pegawaiNama = '${p['nama'] ?? ''}';
                          });
                        },
                        child: const Text('Pilih'),
                      ),
                    ]),
                  ),
                  if (_pakaiAnggaran(jenisId)) ...[
                    const SizedBox(height: 12),
                    PemilihAnggaranField(
                      aksiCari: 'reimbursement_cari_anggaran',
                      workspaceId: workspaceId == null ? null : '$workspaceId',
                      namaAnggaran: workspaceNama.isEmpty ? null : workspaceNama,
                      tahun: tanggal?.year,
                      helperText: 'Wajib untuk jenis reimbursement ini.',
                      onDipilih: (w) => setDialog(() {
                        if (w == null) {
                          workspaceId = null;
                          workspaceNama = '';
                          return;
                        }
                        workspaceId = (w['id'] as num?)?.toInt();
                        workspaceNama = '${w['kode'] ?? ''} \u2014 ${w['nama'] ?? ''}';
                      }),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _tombolTanggal('Tanggal Pengeluaran *', tanggal, () async {
                    final t = await showDatePicker(
                        context: c,
                        initialDate: tanggal ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (t == null) return;
                    setDialog(() => tanggal = t);
                  }),
                  Row(children: [
                    const Expanded(
                        child: Text('Rincian Biaya',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () => formBaris(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah Baris'),
                    ),
                  ]),
                  if (rincian.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Belum ada rincian. Nilai dokumen dihitung dari rincian ini.'),
                    )
                  else
                    ...rincian.asMap().entries.map((e) {
                      final b = e.value;
                      // Merah bila belum layak dijurnal: nilainya nol ATAU akunnya kosong.
                      final nol = ((b['jumlah'] as num?)?.toDouble() ?? 0) == 0 ||
                          b['akun'] == null;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['uraian'] ?? '(tanpa uraian)'}'),
                        subtitle: Text(
                          '${_uang.format((b['jumlah'] as num?) ?? 0)}'
                          '${b['anggaranNama'] == null ? '' : ' • ${b['anggaranNama']}'}',
                          style: TextStyle(color: nol ? AppColors.danger : null),
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => formBaris(e.key),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            onPressed: () async {
                              setDialog(() => rincian.removeAt(e.key));
                              await hitung();
                            },
                          ),
                        ]),
                      );
                    }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      masalahRincian.isNotEmpty
                          ? masalahRincian
                          : 'Nilai dokumen ${_uang.format(nilaiHitung)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: masalahRincian.isNotEmpty ? AppColors.danger : null),
                    ),
                  ),
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

    final idLokal = ubah ? null : MasterOffline.idSementaraBaru();
    await _kirimLokalDulu(
      'reimbursement_simpan',
      {
        if (ubah) 'id': baris['id'],
        'satuanKerjaId': satkerId ?? 0,
        'nama': nama.text.trim(),
        'jenisReimbursementId': jenisId ?? 0,
        'pegawaiId': pegawaiId ?? 0,
        if (workspaceId != null) 'workspaceId': workspaceId,
        if (tanggal != null) 'tanggalPengeluaran': _fmt.format(tanggal!),
        'keterangan': keterangan.text.trim(),
        'rincian': rincian,
        'statusDokumen': statusDokumen,
      },
      kunci: ubah ? 'reimbursement:${baris['id']}' : 'reimbursement:baru:$idLokal',
      idLokal: idLokal,
      rowLokal: {
        ...(baris ?? const <String, dynamic>{}),
        'id': ubah ? baris['id'] : idLokal,
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'nilai': nilaiHitung,
        'statusDokumen': statusDokumen,
        'satuanKerjaId': satkerId,
        'jenisReimbursementId': jenisId,
        'pegawaiId': pegawaiId,
        'pegawaiNama': pegawaiNama,
        'rincian': rincian,
        if (tanggal != null) 'tanggalPengeluaran': _fmt.format(tanggal!),
      },
    );
  }

  /// Hapus: server menghapus sungguhan, salinan lokal hanya DITANDAI.
  Future<void> _hapusBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Hapus dokumen ini?',
        '${b['kode']} — ${b['nama']}\n\n'
            'Di perangkat ini barisnya hanya ditandai terhapus (masih bisa dilihat '
            'lewat penyaring "Terhapus"), sedangkan di server benar-benar dihapus.',
        'Hapus')) {
      return;
    }
    // Hapus lunak di sisi LOKAL diserahkan ke MasterOffline (menandai `_dihapus`
    // + `_dihapusPada`, lalu menyaringnya dari daftar). Sisi SERVER menerima
    // hapus BIASA; jejaknya sudah ditangani audit Hibernate di sana.
    await _kirimLokalDulu(
      'reimbursement_hapus',
      {'id': b['id']},
      kunci: 'reimbursement:${b['id']}',
      rowLokal: {'id': b['id']},
      hapusLokal: true,
    );
  }

  /// Membatalkan penghapusan yang MASIH mengantre di perangkat.
  ///
  /// Begitu hapusnya terkirim, server sudah benar-benar menghapus dokumennya
  /// dan pengembalian datanya ditempuh lewat tabel audit di sisi server --
  /// bukan dari layar ini. Karena itu tombolnya hanya berlaku selama antreannya
  /// belum jalan, dan [MasterOffline.pulihkanLokal] mengembalikan false bila
  /// barisnya sudah tidak bertanda.
  Future<void> _pulihkanBaris(Map<String, dynamic> b) async {
    if (!await _konfirmasi(
        'Batalkan penghapusan dokumen ini?',
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
          _cacheKey, b['id'], kunci: 'reimbursement:${b['id']}');
      _pesan(berhasil
          ? 'Penghapusan dibatalkan.'
          : 'Tidak dapat dibatalkan: penghapusannya sudah terkirim ke server. '
              'Pemulihan data dilakukan lewat catatan audit di server.');
      await _muatDaftar();
    } finally {
      if (mounted) setStateIfMounted(() => _sibuk = false);
    }
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

  AppTableCell _aksiBaris(Map<String, dynamic> b) {
    final status = '${b['statusDokumen'] ?? ''}';
    final terkunci = b['sudahDijurnal'] == true;
    return AppTableCell(
      width: 200,
      align: TextAlign.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Cetak / pratinjau',
          icon: const Icon(Icons.print_outlined, size: 18),
          onPressed: _sibuk || _tampilkanTerhapus
              ? null
              : () => cetakDokumenKeuangan(context,
                  modul: 'reimbursement',
                  id: (b['id'] as num).toInt(),
                  kode: '${b['kode'] ?? ''}'),
        ),
        if (_tampilkanTerhapus && _boleh('delete'))
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Batalkan penghapusan (selama belum terkirim)',
            icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
            onPressed: _sibuk ? null : () => _pulihkanBaris(b),
          ),
        if (!_tampilkanTerhapus && _boleh('update') && !terkunci)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ubah dokumen',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: _sibuk ? null : () => _form(b),
          ),
        if (!_tampilkanTerhapus && _boleh('approve') && !terkunci && status != 'Disetujui')
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Setujui',
            icon: const Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
            onPressed: _sibuk
                ? null
                : () async {
                    if (await _konfirmasi('Setujui pengeluaran?',
                        '${b['kode']} — ${b['nama']}\nNilai ${_uang.format((b['nilai'] as num?) ?? 0)}',
                        'Setujui')) {
                      await _kirimLokalDulu('reimbursement_setujui', {'id': b['id']},
                          kunci: 'reimbursement:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Disetujui'});
                    }
                  },
          ),
        // Dua keputusan negatif yang BERBEDA, dan itulah yang membedakan modul ini:
        // "Minta Revisi" mengembalikan pengajuan kepada pengaju untuk diperbaiki,
        // sedangkan "Tolak" menutupnya. Keduanya menuntut catatan atasan.
        if (!_tampilkanTerhapus && _boleh('reject') && !terkunci && status != 'Revisi')
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Minta revisi',
            icon: const Icon(Icons.undo, size: 18),
            onPressed: _sibuk
                ? null
                : () async {
                    final catatan = await _mintaCatatan('Minta Revisi Pengajuan');
                    if (catatan == null) return;
                    await _kirimLokalDulu(
                        'reimbursement_revisi', {'id': b['id'], 'catatanAtasan': catatan},
                        kunci: 'reimbursement:${b['id']}',
                        rowLokal: {...b, 'statusDokumen': 'Revisi', 'catatanAtasan': catatan});
                  },
          ),
        if (!_tampilkanTerhapus && _boleh('reject') && !terkunci && status != 'Ditolak')
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Tolak',
            icon: const Icon(Icons.cancel_outlined, size: 18),
            onPressed: _sibuk
                ? null
                : () async {
                    final catatan = await _mintaCatatan('Tolak Pengajuan');
                    if (catatan == null) return;
                    await _kirimLokalDulu(
                        'reimbursement_tolak', {'id': b['id'], 'catatanAtasan': catatan},
                        kunci: 'reimbursement:${b['id']}',
                        rowLokal: {...b, 'statusDokumen': 'Ditolak', 'catatanAtasan': catatan});
                  },
          ),
        if (!_tampilkanTerhapus && _boleh('delete') && !terkunci)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus dokumen',
            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
            onPressed: _sibuk ? null : () => _hapusBaris(b),
          ),
      ]),
    );
  }

  /// Dua tab: Dasbor & data -- susunan yang sama dengan menu Pengadaan.
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
                  tahap: 'reimbursement', aksi: 'keuangan_dasbor', namaParam: 'modul'),
              isiData,
            ]),
          ),
        ]),
      );

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
                width: 210,
                child: DropdownButtonFormField<int>(
                  value: _jenisFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Jenis Kas Kecil', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Semua jenis')),
                    ..._jenis.map((e) => DropdownMenuItem(
                          value: (e['id'] as num?)?.toInt(),
                          child: Text('${e['nama'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) => setStateIfMounted(() => _jenisFilter = v),
                ),
              ),
              SizedBox(
                width: 210,
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
                    ? 'Rentang Tanggal Laporan'
                    : '${_fmt.format(_dari!)} s/d ${_fmt.format(_sampai!)}'),
              ),
              FilterChip(
                label: const Text('Belum diganti'),
                selected: _belumDiganti,
                onSelected: (v) => setStateIfMounted(() => _belumDiganti = v),
              ),
              FilterChip(
                label: Text(
                    _jumlahTerhapus == 0 ? 'Terhapus' : 'Terhapus ($_jumlahTerhapus)'),
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
      menuAktif: MenuEBisnis.reimbursement,
      judul: 'Reimbursement Pegawai',
      subjudul: 'Penggantian biaya pegawai beserta alur persetujuannya',
      scrollable: false,
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh), onPressed: _muatSemua, tooltip: 'Muat ulang'),
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
                '${_terlihat.length} dokumen • total ${_uang.format(_totalNilai)}',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),
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
                        FilledButton(onPressed: _muatSemua, child: const Text('Coba lagi')),
                      ]),
                    ))
                  : AppDataTable(
                      minWidth: 1140,
                      emptyText: _tampilkanTerhapus
                          ? 'Tidak ada penghapusan yang masih menunggu kirim di perangkat ini.'
                          : 'Belum ada pengajuan reimbursement untuk penyaring ini.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Judul', flex: 4),
                        AppTableColumn('Pegawai', flex: 3),
                        AppTableColumn('Satuan Kerja', flex: 3),
                        AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                        AppTableColumn('Tanggal', flex: 2),
                        AppTableColumn('Status', flex: 2),
                        AppTableColumn('Aksi', width: 200, align: TextAlign.center),
                      ],
                      rows: _terlihat
                          .map((b) => AppTableRowData(cells: [
                                AppTableCell.text('${b['kode'] ?? ''}', flex: 2),
                                AppTableCell.text('${b['nama'] ?? ''}', flex: 4),
                                AppTableCell.text('${b['pegawaiNama'] ?? ''}', flex: 3),
                                AppTableCell.text('${b['satuanKerjaNama'] ?? ''}', flex: 3),
                                AppTableCell.text(_uang.format((b['nilai'] as num?) ?? 0),
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text('${b['tanggalPengeluaran'] ?? ''}', flex: 2),
                                AppTableCell.text(
                                    '${b['statusDokumen'] ?? ''}'
                                    '${b['sudahDijurnal'] == true ? ' • terjurnal' : ''}'
                                    '${b['sudahDiganti'] == true ? ' • sudah diganti' : ''}',
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
