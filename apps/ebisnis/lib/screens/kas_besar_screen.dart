import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/master_offline.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/pemilih_anggaran.dart';
import '../widgets/app_shell.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/safe_state.dart';
import 'keuangan_cetak_util.dart';
import 'pengadaan_dasbor_tab.dart';

/// Layar **Kas Besar** -- padanan layar ZK
/// `ais.action.master.akunting.KasBesarAction`.
///
/// Nilai dokumen DIHITUNG DARI RINCIAN oleh server (hanya baris biaya yang
/// dijumlahkan, dan baris biaya tidak boleh bernilai nol), sehingga angkanya
/// tidak pernah berbeda antara kanal ini dan layar ZK. Seperti layar Keuangan
/// lainnya: dua tab (Dasbor & data), tombol cetak dgn templat yang sama, tulis
/// lokal-dulu, dan penghapusan yang di perangkat hanya menandai barisnya.
class KasBesarScreen extends StatefulWidget {
  const KasBesarScreen({super.key});

  @override
  State<KasBesarScreen> createState() => _KasBesarScreenState();
}

class _KasBesarScreenState extends State<KasBesarScreen> {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  /// Kunci salinan lokal daftar ini.
  static const String _cacheKey = 'master:kas_besar';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _jenis = [];
  List<Map<String, dynamic>> _satker = [];

  /// Bagan akun untuk pemilih akun biaya pada rincian.
  List<Map<String, dynamic>> _akun = [];
  List<String> _daftarStatus = const ['Pengajuan', 'Disetujui', 'Ditolak'];
  Map<String, bool> _hak = const {};
  double _totalNilai = 0;

  final _cari = TextEditingController();
  String _statusFilter = '';
  int? _satkerFilter;
  int? _jenisFilter;
  DateTime? _dari;
  DateTime? _sampai;
  bool _belumPj = false;

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
      final opsi = await ApiClient.instance.aksi('kas_besar_opsi', {});
      final res = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
      if (!mounted) return;
      setStateIfMounted(() {
        _jenis = ((opsi['jenisKasBesar'] as List?) ?? []).cast<Map<String, dynamic>>();
        _satker = ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _daftarStatus = ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
        _akun = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
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
        'kas_besar_daftar',
        {
          if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
          if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
          if (_satkerFilter != null) 'satuanKerjaId': _satkerFilter,
          if (_jenisFilter != null) 'jenisKasBesarId': _jenisFilter,
          if (_dari != null) 'dari': _fmt.format(_dari!),
          if (_sampai != null) 'sampai': _fmt.format(_sampai!),
          if (_belumPj) 'belumPj': true,
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
        entitas: 'kas_besar',
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

  /// Pemilih dokumen Kas Kecil (untuk dokumen yang diambil dari kas kecil).
  Future<Map<String, dynamic>?> _pilihKasKecil() async {
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
                  .aksi('kas_besar_cari_kas_kecil', {'cari': cari.text.trim()});
              hasil = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memuat = false);
            }
          }

          return AlertDialog(
            title: const Text('Pilih Kas Kecil'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: AppSearchField(
                      controller: cari,
                      hintText: 'Cari kode / judul kas kecil',
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
                                final k = hasil[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${k['kode'] ?? ''} — ${k['nama'] ?? ''}'),
                                  subtitle: Text(
                                      'Nilai ${_uang.format((k['nilai'] as num?) ?? 0)}'
                                      ' • ${k['statusDokumen'] ?? '-'}'
                                      ' • ${k['satuanKerja'] ?? '-'}'),
                                  onTap: () => Navigator.pop(c, k),
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

  // ------------------------------------------------------------- formulir

  Future<void> _form([Map<String, dynamic>? baris]) async {
    final ubah = baris != null;
    final nama = TextEditingController(text: '${baris?['nama'] ?? ''}');
    final keterangan = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    int? satkerId = (baris?['satuanKerjaId'] as num?)?.toInt();
    int? jenisId = (baris?['jenisKasBesarId'] as num?)?.toInt();
    bool ambilDariKasKecil = baris?['ambilDariKasKecil'] == true;
    int? kasKecilId = (baris?['kasKecilId'] as num?)?.toInt();
    String kasKecilLabel = '${baris?['kasKecilKode'] ?? ''}';
    DateTime? tanggal = _tgl(baris?['tanggal']);
    String statusDokumen = '${baris?['statusDokumen'] ?? 'Pengajuan'}';
    final rincian = <Map<String, dynamic>>[
      ...(((baris?['rincian'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
    ];
    double nilaiHitung = (baris?['nilai'] as num?)?.toDouble() ?? 0;
    bool adaBarisNol = false;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> hitung() async {
            try {
              final res =
                  await ApiClient.instance.aksi('kas_besar_hitung', {'rincian': rincian});
              setDialog(() {
                nilaiHitung = (res['nilai'] as num?)?.toDouble() ?? 0;
                adaBarisNol = res['adaBarisNol'] == true;
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
            String? workspaceId = b['workspace']?.toString();
            String? anggaranNama = b['anggaranNama'] as String?;
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
                    // Akun biaya menentukan ke mana pengeluaran ini dijurnal.
                    PemilihAkunField(
                      label: 'Akun Biaya',
                      daftar: _akun,
                      nilai: akunId,
                      helperText: 'Dipakai server untuk menebak anggarannya.',
                      onChanged: (v) => setD(() => akunId = v),
                    ),
                    const SizedBox(height: 12),
                    // Anggaran per baris: inilah yang memotong pagu di
                    // rab.penggunaan_anggaran, sama seperti banbox anggaran di ZK.
                    PemilihAnggaranField(
                      aksiCari: 'kas_besar_cari_anggaran',
                      workspaceId: workspaceId,
                      namaAnggaran: anggaranNama,
                      tahun: tanggal?.year,
                      onDipilih: (w) => setD(() {
                        if (w == null) {
                          workspaceId = null;
                          anggaranNama = null;
                          return;
                        }
                        workspaceId = '${w['idTeks'] ?? w['id']}';
                        anggaranNama = '${w['kode'] ?? ''} — ${w['nama'] ?? ''}';
                        final a = (w['akunId'] as num?)?.toInt();
                        if (a != null && a > 0) akunId = a;
                      }),
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
              if (workspaceId != null) 'workspace': workspaceId,
              if (anggaranNama != null) 'anggaranNama': anggaranNama,
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
            title: Text(ubah ? 'Ubah Pengeluaran Kas Besar' : 'Pengeluaran Kas Besar Baru'),
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
                  _isian('Judul Pengeluaran', nama, wajib: true),
                  _dropdownInt(
                    label: 'Jenis Kas Besar *',
                    nilai: jenisId,
                    opsi: _jenis,
                    onChanged: (v) => setDialog(() => jenisId = v),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Diambil dari Kas Kecil'),
                    subtitle: const Text('Bila dicentang, dokumen kas kecilnya wajib dipilih.'),
                    value: ambilDariKasKecil,
                    onChanged: (v) => setDialog(() => ambilDariKasKecil = v),
                  ),
                  if (ambilDariKasKecil)
                    InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Kas Kecil *',
                          border: OutlineInputBorder(),
                          isDense: true),
                      child: Row(children: [
                        Expanded(
                          child: Text(kasKecilLabel.isEmpty ? 'Belum dipilih' : kasKecilLabel,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        TextButton(
                          onPressed: () async {
                            final k = await _pilihKasKecil();
                            if (k == null) return;
                            setDialog(() {
                              kasKecilId = (k['id'] as num?)?.toInt();
                              kasKecilLabel = '${k['kode'] ?? ''} — ${k['nama'] ?? ''}';
                            });
                          },
                          child: const Text('Pilih'),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 12),
                  _tombolTanggal('Tanggal Laporan *', tanggal, () async {
                    final t = await showDatePicker(
                        context: c,
                        initialDate: tanggal ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (t != null) setDialog(() => tanggal = t);
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
                      final nol = ((b['jumlah'] as num?)?.toDouble() ?? 0) == 0;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['uraian'] ?? '(tanpa uraian)'}'),
                        subtitle: Text(
                          _uang.format((b['jumlah'] as num?) ?? 0),
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
                      adaBarisNol
                          ? 'Ada rincian bernilai nol — perbaiki dulu'
                          : 'Nilai dokumen ${_uang.format(nilaiHitung)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: adaBarisNol ? AppColors.danger : null),
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
      'kas_besar_simpan',
      {
        if (ubah) 'id': baris['id'],
        'satuanKerjaId': satkerId ?? 0,
        'nama': nama.text.trim(),
        'jenisKasBesarId': jenisId ?? 0,
        'ambilDariKasKecil': ambilDariKasKecil,
        'kasKecilId': kasKecilId ?? 0,
        if (tanggal != null) 'tanggal': _fmt.format(tanggal!),
        'keterangan': keterangan.text.trim(),
        'rincian': rincian,
        'statusDokumen': statusDokumen,
      },
      kunci: ubah ? 'kas_besar:${baris['id']}' : 'kas_besar:baru:$idLokal',
      idLokal: idLokal,
      rowLokal: {
        ...(baris ?? const <String, dynamic>{}),
        'id': ubah ? baris['id'] : idLokal,
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'nilai': nilaiHitung,
        'statusDokumen': statusDokumen,
        'satuanKerjaId': satkerId,
        'jenisKasBesarId': jenisId,
        'ambilDariKasKecil': ambilDariKasKecil,
        'kasKecilId': kasKecilId,
        'rincian': rincian,
        if (tanggal != null) 'tanggal': _fmt.format(tanggal!),
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
      'kas_besar_hapus',
      {'id': b['id']},
      kunci: 'kas_besar:${b['id']}',
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
          _cacheKey, b['id'], kunci: 'kas_besar:${b['id']}');
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
      width: 232,
      align: TextAlign.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
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
                                'kas_besar_ajukan_transfer', {'id': b['id']},
                                kunci: 'kas_besar-dpc:${b['id']}',
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
                  modul: 'kas_besar',
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
                      await _kirimLokalDulu('kas_besar_setujui', {'id': b['id']},
                          kunci: 'kas_besar:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Disetujui'});
                    }
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
                    if (await _konfirmasi(
                        'Tolak pengeluaran?', '${b['kode']} — ${b['nama']}', 'Tolak')) {
                      await _kirimLokalDulu('kas_besar_tolak', {'id': b['id']},
                          kunci: 'kas_besar:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Ditolak'});
                    }
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
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'Pengeluaran'),
          ]),
          Expanded(
            child: TabBarView(children: [
              const PengadaanDasborTab(
                  tahap: 'kas_besar', aksi: 'keuangan_dasbor', namaParam: 'modul'),
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
                  decoration: const InputDecoration(labelText: 'Jenis Kas Besar', isDense: true),
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
                label: const Text('Belum ada PJ'),
                selected: _belumPj,
                onSelected: (v) => setStateIfMounted(() => _belumPj = v),
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
                  label: const Text('Pengeluaran Baru'),
                ),
              if (_sibuk)
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kasBesar,
      judul: 'Kas Besar',
      subjudul: 'Pengeluaran kas besar beserta persetujuannya',
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
                          : 'Belum ada pengeluaran kas besar untuk penyaring ini.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Judul', flex: 4),
                        AppTableColumn('Jenis', flex: 3),
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
                                AppTableCell.text('${b['jenisKasBesarNama'] ?? ''}', flex: 3),
                                AppTableCell.text('${b['satuanKerjaNama'] ?? ''}', flex: 3),
                                AppTableCell.text(_uang.format((b['nilai'] as num?) ?? 0),
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text('${b['tanggal'] ?? ''}', flex: 2),
                                AppTableCell.text(
                                    '${b['statusDokumen'] ?? ''}'
                                    '${b['sudahDijurnal'] == true ? ' • terjurnal' : ''}'
                                    '${b['punyaPj'] == true ? ' • ada PJ' : ''}'
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
