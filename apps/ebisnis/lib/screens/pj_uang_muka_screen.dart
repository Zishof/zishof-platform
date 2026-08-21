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
import '../widgets/safe_state.dart';

/// Layar **Pertanggungjawaban Uang Muka (LPJ)** -- padanan layar ZK
/// `ais.action.master.akunting.PertangungjawabanAction`.
///
/// Nilai LPJ TIDAK dihitung di sini: rincian dikirim ke server dan server yang
/// menjumlahkannya dengan rumus yang sama persis dengan layar ZK (PPN menambah,
/// PPh memotong bila konfigurasi `pph_mengurangi_lpj` menyala). Layar hanya
/// menampilkan hasil hitungan itu supaya angkanya tidak pernah berbeda antar kanal.
class PjUangMukaScreen extends StatefulWidget {
  const PjUangMukaScreen({super.key});

  @override
  State<PjUangMukaScreen> createState() => _PjUangMukaScreenState();
}

class _PjUangMukaScreenState extends State<PjUangMukaScreen> {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  /// Kunci salinan lokal daftar ini -- dipakai baca cache-dulu dan
  /// penerapan optimistis hasil tulis.
  static const String _cacheKey = 'master:pj_uang_muka';

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;

  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _jenisPajak = [];
  List<Map<String, dynamic>> _satker = [];
  List<String> _daftarStatus = const ['Pengajuan', 'Disetujui', 'Ditolak'];
  Map<String, bool> _hak = const {};
  bool _pphMengurangi = false;
  double _totalNilai = 0;
  double _totalDikembalikan = 0;

  final _cari = TextEditingController();
  String _statusFilter = '';
  int? _satkerFilter;
  DateTime? _dari;
  DateTime? _sampai;
  bool _belumDikembalikan = false;

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
      final opsi = await ApiClient.instance.aksi('pj_uang_muka_opsi', {});
      if (!mounted) return;
      setStateIfMounted(() {
        _jenisPajak = ((opsi['jenisPajak'] as List?) ?? []).cast<Map<String, dynamic>>();
        _satker = ((opsi['satuanKerja'] as List?) ?? []).cast<Map<String, dynamic>>();
        _daftarStatus = ((opsi['daftarStatus'] as List?) ?? []).map((e) => '$e').toList();
        _pphMengurangi = opsi['pphMengurangiLpj'] == true;
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
        'pj_uang_muka_daftar',
        {
        if (_cari.text.trim().isNotEmpty) 'cari': _cari.text.trim(),
        if (_statusFilter.isNotEmpty) 'statusFilter': _statusFilter,
        if (_satkerFilter != null) 'satuanKerjaId': _satkerFilter,
        if (_dari != null) 'dari': _fmt.format(_dari!),
        if (_sampai != null) 'sampai': _fmt.format(_sampai!),
        if (_belumDikembalikan) 'belumDikembalikan': true,
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
        _totalDikembalikan = (hasil['totalDikembalikan'] as num?)?.toDouble() ?? 0;
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
        entitas: 'pj_uang_muka',
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

  /// Pemilih uang muka: hanya yang sudah DISETUJUI dan belum punya LPJ.
  Future<Map<String, dynamic>?> _pilihUangMuka(int? idLpj) async {
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
              final res = await ApiClient.instance.aksi('pj_uang_muka_cari_uang_muka', {
                'cari': cari.text.trim(),
                if (idLpj != null) 'id': idLpj,
              });
              hasil = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
            } catch (e) {
              _pesan('$e');
            } finally {
              setDialog(() => memuat = false);
            }
          }

          return AlertDialog(
            title: const Text('Pilih Uang Muka'),
            content: SizedBox(
              width: 620,
              height: 420,
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: cari,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Cari kode / judul uang muka',
                          border: OutlineInputBorder(),
                          isDense: true),
                      onSubmitted: (_) => jalankan(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: jalankan, child: const Text('Cari')),
                ]),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Hanya uang muka berstatus Disetujui dan belum punya LPJ yang tampil.',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: memuat
                      ? const Center(child: CircularProgressIndicator())
                      : hasil.isEmpty
                          ? const Center(child: Text('Ketik kata kunci lalu tekan Cari.'))
                          : ListView.builder(
                              itemCount: hasil.length,
                              itemBuilder: (_, i) {
                                final u = hasil[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${u['kode'] ?? ''} — ${u['nama'] ?? ''}'),
                                  subtitle: Text(
                                      'Nilai ${_uang.format((u['nilai'] as num?) ?? 0)}'
                                      ' • ${u['satuanKerja'] ?? '-'}'
                                      ' • ${u['mulai'] ?? ''} s/d ${u['sampai'] ?? ''}'),
                                  onTap: () => Navigator.pop(c, u),
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
    final namaSponsor = TextEditingController(text: '${baris?['namaSponsor'] ?? ''}');
    final dariSponsor = TextEditingController(
        text: ((baris?['dariSponsor'] as num?)?.toDouble() ?? 0) == 0
            ? ''
            : '${((baris?['dariSponsor'] as num?) ?? 0).toInt()}');
    final dikembalikan = TextEditingController(
        text: ((baris?['dikembalikan'] as num?)?.toDouble() ?? 0) == 0
            ? ''
            : '${((baris?['dikembalikan'] as num?) ?? 0).toInt()}');
    int? uangMukaId = (baris?['uangMukaId'] as num?)?.toInt();
    String uangMukaLabel = ubah
        ? '${baris['uangMukaKode'] ?? ''} — ${baris['uangMukaNama'] ?? ''}'
        : '';
    double uangMukaNilai = (baris?['uangMukaNilai'] as num?)?.toDouble() ?? 0;
    DateTime? tanggalStor = _tgl(baris?['tanggalStor']);
    String statusDokumen = '${baris?['statusDokumen'] ?? 'Pengajuan'}';
    final rincian = <Map<String, dynamic>>[
      ...(((baris?['rincian'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
    ];
    double nilaiHitung = (baris?['nilai'] as num?)?.toDouble() ?? 0;
    double pajakHitung = (baris?['pajak'] as num?)?.toDouble() ?? 0;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) {
          Future<void> hitung() async {
            try {
              final res = await ApiClient.instance
                  .aksi('pj_uang_muka_hitung', {'rincian': rincian});
              setDialog(() {
                nilaiHitung = (res['nilai'] as num?)?.toDouble() ?? 0;
                pajakHitung = (res['pajak'] as num?)?.toDouble() ?? 0;
              });
            } catch (_) {
              // Biarkan angka lama; server tetap menghitung ulang saat menyimpan.
            }
          }

          Future<void> formBaris([int? indeks]) async {
            final b = indeks == null ? <String, dynamic>{} : rincian[indeks];
            final uraian = TextEditingController(text: '${b['uraian'] ?? ''}');
            final jumlah = TextEditingController(
                text: (b['jumlah'] == null) ? '' : '${(b['jumlah'] as num).toInt()}');
            final ppn = TextEditingController(
                text: (b['ppn'] == null) ? '' : '${b['ppn']}');
            int? pajakId = (b['pajak'] as num?)?.toInt();
            final ok = await showDialog<bool>(
              context: c,
              builder: (d) => StatefulBuilder(
                builder: (d, setD) => AlertDialog(
                  title: Text(indeks == null ? 'Tambah Rincian' : 'Ubah Rincian'),
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
                              labelText: 'Jumlah *', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(
                          controller: ppn,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'PPN (%)',
                              helperText: 'Menambah nilai baris.',
                              border: OutlineInputBorder(),
                              isDense: true)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: pajakId,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: 'PPh (Jenis Pajak)',
                            helperText: _pphMengurangi
                                ? 'Memotong nilai LPJ (konfigurasi pph_mengurangi_lpj menyala).'
                                : 'Dicatat sebagai pajak, tidak memotong nilai LPJ.',
                            border: const OutlineInputBorder(),
                            isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Tanpa PPh')),
                          ..._jenisPajak.map((p) => DropdownMenuItem(
                                value: (p['id'] as num?)?.toInt(),
                                child: Text(
                                    '${p['nama'] ?? ''} (${p['persen'] ?? 0}%)',
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) => setD(() => pajakId = v),
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
            final data = <String, dynamic>{
              'uraian': uraian.text.trim(),
              'jumlah': double.tryParse(jumlah.text.trim()) ?? 0,
              if (ppn.text.trim().isNotEmpty) 'ppn': double.tryParse(ppn.text.trim()) ?? 0,
              if (pajakId != null) 'pajak': pajakId,
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
            title: Text(ubah ? 'Ubah Pertanggungjawaban' : 'Pertanggungjawaban Baru'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                        labelText: 'Uang Muka *',
                        border: OutlineInputBorder(),
                        isDense: true),
                    child: Row(children: [
                      Expanded(
                        child: Text(uangMukaLabel.isEmpty ? 'Belum dipilih' : uangMukaLabel,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      TextButton(
                        onPressed: () async {
                          final u = await _pilihUangMuka(ubah ? baris['id'] as int? : null);
                          if (u == null) return;
                          setDialog(() {
                            uangMukaId = (u['id'] as num?)?.toInt();
                            uangMukaLabel = '${u['kode'] ?? ''} — ${u['nama'] ?? ''}';
                            uangMukaNilai = (u['nilai'] as num?)?.toDouble() ?? 0;
                          });
                        },
                        child: const Text('Pilih'),
                      ),
                    ]),
                  ),
                  if (uangMukaNilai > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Nilai uang muka ${_uang.format(uangMukaNilai)} — '
                          'LPJ tidak boleh melebihi angka ini.',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _isian('Judul Pengajuan', nama, wajib: true),
                  // --- rincian
                  Row(children: [
                    const Expanded(
                        child: Text('Rincian Penggunaan',
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
                      child: Text('Belum ada rincian. Nilai LPJ dihitung dari rincian ini.'),
                    )
                  else
                    ...rincian.asMap().entries.map((e) {
                      final b = e.value;
                      final pajakNama = _jenisPajak.firstWhere(
                          (p) => (p['id'] as num?)?.toInt() == (b['pajak'] as num?)?.toInt(),
                          orElse: () => const {})['nama'];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['uraian'] ?? '(tanpa uraian)'}'),
                        subtitle: Text(
                            '${_uang.format((b['jumlah'] as num?) ?? 0)}'
                            '${b['ppn'] != null ? ' • PPN ${b['ppn']}%' : ''}'
                            '${pajakNama != null ? ' • PPh $pajakNama' : ''}'),
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
                      'Nilai LPJ ${_uang.format(nilaiHitung)}'
                      '   •   Pajak ${_uang.format(pajakHitung)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _isian('Dikembalikan (sisa dana)', dikembalikan, angka: true),
                  _tombolTanggal('Tanggal Stor', tanggalStor, () async {
                    final t = await showDatePicker(
                        context: c,
                        initialDate: tanggalStor ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100));
                    if (t != null) setDialog(() => tanggalStor = t);
                  }),
                  const SizedBox(height: 4),
                  _isian('Nama Sponsor', namaSponsor),
                  _isian('Dana dari Sponsor', dariSponsor, angka: true),
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
    final payload = <String, dynamic>{
      if (ubah) 'id': baris['id'],
      'uangMukaId': uangMukaId ?? 0,
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'rincian': rincian,
      'dikembalikan': double.tryParse(dikembalikan.text.trim()) ?? 0,
      if (tanggalStor != null) 'tanggalStor': _fmt.format(tanggalStor!),
      'namaSponsor': namaSponsor.text.trim(),
      'dariSponsor': double.tryParse(dariSponsor.text.trim()) ?? 0,
      'statusDokumen': statusDokumen,
    };
    await _kirimLokalDulu(
      'pj_uang_muka_simpan',
      payload,
      kunci: ubah ? 'pj_uang_muka:${baris['id']}' : 'pj_uang_muka:baru:$idLokal',
      idLokal: idLokal,
      rowLokal: {
        ...(baris ?? const <String, dynamic>{}),
        'id': ubah ? baris['id'] : idLokal,
        'nama': nama.text.trim(),
        'keterangan': keterangan.text.trim(),
        'rincian': rincian,
        'nilai': nilaiHitung,
        'pajak': pajakHitung,
        'dikembalikan': double.tryParse(dikembalikan.text.trim()) ?? 0,
        'statusDokumen': statusDokumen,
        'uangMukaId': uangMukaId,
        'uangMukaNilai': uangMukaNilai,
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
    final terkunci = b['sudahDijurnal'] == true ||
        b['sudahDijurnalPajak'] == true ||
        b['sudahDijurnalPengembalian'] == true;
    return AppTableCell(
      width: 176,
      align: TextAlign.center,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // Cetak memakai templat yang sama dengan layar ZK -- lihat keuangan_cetak_util.
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Cetak / pratinjau',
          icon: const Icon(Icons.print_outlined, size: 18),
          onPressed: _sibuk || _tampilkanTerhapus
              ? null
              : () => cetakDokumenKeuangan(context,
                  modul: 'pj_uang_muka',
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
            tooltip: 'Ubah LPJ',
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
                    if (await _konfirmasi('Setujui LPJ?',
                        '${b['kode']} — ${b['nama']}\nNilai ${_uang.format((b['nilai'] as num?) ?? 0)}',
                        'Setujui')) {
                      await _kirimLokalDulu('pj_uang_muka_setujui', {'id': b['id']},
                          kunci: 'pj_uang_muka:${b['id']}',
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
                    if (await _konfirmasi(
                        'Tolak LPJ?', '${b['kode']} — ${b['nama']}', 'Tolak')) {
                      await _kirimLokalDulu('pj_uang_muka_tolak', {'id': b['id']},
                          kunci: 'pj_uang_muka:${b['id']}',
                          rowLokal: {...b, 'statusDokumen': 'Ditolak'});
                    }
                  },
          ),
        if (_boleh('delete') && !terkunci)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hapus LPJ',
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
        'Hapus LPJ ini?',
        '${b['kode']} — ${b['nama']}\n\n'
            'Di perangkat ini barisnya hanya ditandai terhapus (masih bisa dilihat '
            'lewat penyaring "Terhapus"), sedangkan di server benar-benar dihapus.',
        'Hapus')) {
      return;
    }
    await _kirimLokalDulu(
      'pj_uang_muka_hapus',
      {'id': b['id']},
      kunci: 'pj_uang_muka:${b['id']}',
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
        'Batalkan penghapusan LPJ ini?',
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
          _cacheKey, b['id'], kunci: 'pj_uang_muka:${b['id']}');
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
            Tab(icon: Icon(Icons.list_alt_outlined, size: 18), text: 'LPJ'),
          ]),
          Expanded(
            child: TabBarView(children: [
              const PengadaanDasborTab(
                  tahap: 'pj_uang_muka',
                  aksi: 'keuangan_dasbor',
                  namaParam: 'modul'),
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
                width: 260,
                child: TextField(
                  controller: _cari,
                  decoration: const InputDecoration(
                      labelText: 'Cari kode LPJ / judul / kode uang muka',
                      prefixIcon: Icon(Icons.search),
                      isDense: true),
                  onSubmitted: (_) => _muatDaftar(),
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
                    ? 'Rentang Tanggal Dibuat'
                    : '${_fmt.format(_dari!)} s/d ${_fmt.format(_sampai!)}'),
              ),
              FilterChip(
                label: const Text('Sisa dana belum distor'),
                selected: _belumDikembalikan,
                onSelected: (v) => setStateIfMounted(() => _belumDikembalikan = v),
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
                  label: const Text('LPJ Baru'),
                ),
              if (_sibuk)
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
      );

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.pjUangMuka,
      judul: 'Pertanggungjawaban Uang Muka',
      subjudul: 'Laporan penggunaan dana beserta pengembalian sisanya',
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
                '${_data.length} LPJ • total ${_uang.format(_totalNilai)}'
                ' • dikembalikan ${_uang.format(_totalDikembalikan)}',
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
                      minWidth: 1180,
                      emptyText: 'Belum ada pertanggungjawaban untuk penyaring ini.',
                      columns: const [
                        AppTableColumn('Kode', flex: 2),
                        AppTableColumn('Judul', flex: 4),
                        AppTableColumn('Uang Muka', flex: 3),
                        AppTableColumn('Nilai LPJ', flex: 2, align: TextAlign.right),
                        AppTableColumn('Pajak', flex: 2, align: TextAlign.right),
                        AppTableColumn('Dikembalikan', flex: 2, align: TextAlign.right),
                        AppTableColumn('Status', flex: 2),
                        AppTableColumn('Aksi', width: 176, align: TextAlign.center),
                      ],
                      rows: _terlihat
                          .map((b) => AppTableRowData(cells: [
                                AppTableCell.text('${b['kode'] ?? ''}', flex: 2),
                                AppTableCell.text('${b['nama'] ?? ''}', flex: 4),
                                AppTableCell.text(
                                    '${b['uangMukaKode'] ?? ''} ${b['uangMukaNama'] ?? ''}'.trim(),
                                    flex: 3),
                                AppTableCell.text(_uang.format((b['nilai'] as num?) ?? 0),
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text(_uang.format((b['pajak'] as num?) ?? 0),
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text(
                                    '${_uang.format((b['dikembalikan'] as num?) ?? 0)}'
                                    '${b['telahDikembalikan'] == true ? ' ✓' : ''}',
                                    flex: 2, align: TextAlign.right),
                                AppTableCell.text(
                                    '${b['statusDokumen'] ?? ''}'
                                    '${b['sudahDijurnal'] == true ? ' • terjurnal' : ''}',
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
