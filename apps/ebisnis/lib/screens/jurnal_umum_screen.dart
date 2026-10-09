import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/accurate_jurnal_xlsx.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/pemilih_anggaran.dart';
import '../widgets/penanda_data_tersimpan.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

/// Layar **Jurnal Umum** — pencatatan jurnal manual dari POS.
///
/// Padanan layar ZK `GrupTransaksiAction` + `TransaksiJurnalUmumHelper`, memakai entitas yang sama
/// (`GrupTransaksi` sebagai kepala, `Transaksi` sebagai baris) sehingga jurnal dari POS dan dari ZK
/// berada di satu buku besar yang sama.
///
/// Alur yang dipakai layar ini sengaja dua tahap:
/// **isi jurnal → simpan sebagai DRAF → periksa → POSTING**. Selama masih draf, jurnal belum
/// terbaca laporan keuangan (semua laporan menyaring jurnal terposting), jadi salah ketik masih
/// bisa diperbaiki. Setelah diposting, jurnal terkunci; untuk mengoreksinya harus dibatalkan
/// posting-nya lebih dulu.
class _HasilGagalUpload {
  final String noBukti;
  final String tanggal;
  final String keterangan;
  final String pesan;
  final String penyebab;
  final String solusi;

  const _HasilGagalUpload({
    required this.noBukti,
    required this.tanggal,
    required this.keterangan,
    required this.pesan,
    required this.penyebab,
    required this.solusi,
  });
}

class JurnalUmumScreen extends StatefulWidget {
  const JurnalUmumScreen({super.key});

  @override
  State<JurnalUmumScreen> createState() => _JurnalUmumScreenState();
}

class _JurnalUmumScreenState extends State<JurnalUmumScreen> {
  final _fmtTanggal = DateFormat('yyyy-MM-dd');
  final _fmtAngka = NumberFormat.decimalPattern('id');

  bool _memuat = true;
  bool _sibuk = false;
  String? _galat;
  List<Map<String, dynamic>> _jurnal = [];
  List<Map<String, dynamic>> _jenisTransaksi = [];
  List<Map<String, dynamic>> _akun = [];
  String _tanggalClosing = '';
  bool _dariCache = false;

  late DateTime _mulai;
  late DateTime _sampai;
  String _cari = '';
  String _status = '';

  @override
  void initState() {
    super.initState();
    final kini = DateTime.now();
    _mulai = DateTime(kini.year, kini.month, 1);
    _sampai = DateTime(kini.year, kini.month + 1, 0);
    _muat();
  }

  static final _polaTanggalIso = RegExp(r'^\d{4}-\d{2}-\d{2}');

  /// Filter layar diterapkan ulang di sisi klien: emisi cache
  /// [MasterOffline.daftarCacheDulu] berisi SEMUA baris yang pernah terlihat,
  /// bukan hanya periode/status/kata yang sedang dipilih. Tanggal yang tidak
  /// berformat yyyy-MM-dd tidak disaring (permisif -- lebih baik baris ekstra
  /// ber-penanda daripada baris hilang diam-diam).
  bool _lolosFilterLokal(Map<String, dynamic> j) {
    final tanggal = '${j['tanggal'] ?? ''}';
    if (_polaTanggalIso.hasMatch(tanggal)) {
      if (tanggal.compareTo(_fmtTanggal.format(_mulai)) < 0 ||
          tanggal.compareTo(_fmtTanggal.format(_sampai)) > 0) {
        return false;
      }
    }
    if (_status == 'draf' && j['terposting'] == true) return false;
    if (_status == 'terposting' && j['terposting'] != true) return false;
    final cari = _cari.trim().toLowerCase();
    if (cari.isNotEmpty &&
        !'${j['kode'] ?? ''} ${j['keterangan'] ?? ''}'
            .toLowerCase()
            .contains(cari)) {
      return false;
    }
    return true;
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _galat = null;
    });
    try {
      // Baca lokal-dulu. Kunci cache SAMA dengan cacheKey editor draf
      // ('master:jurnal_umum', lihat prosesSimpanMaster di bawah) supaya draf
      // yang diketik saat offline langsung tampil di daftar. Guard tanggal
      // closing tetap ditegakkan server saat simpan/posting.
      await MasterOffline.daftarCacheDulu(
          'jurnal_umum_list',
          {
            'mulai': _fmtTanggal.format(_mulai),
            'sampai': _fmtTanggal.format(_sampai),
            'cari': _cari,
            'status': _status,
          },
          'master:jurnal_umum', onData: (hasil) {
        if (!mounted) return;
        final baris =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        final hakBaru = hasil['hak'];
        setStateIfMounted(() {
          // Hanya emisi SERVER yang membawa hak; snapshot cache tidak, dan
          // menimpanya dgn peta kosong akan memadamkan tombol tanpa alasan.
          if (hakBaru is Map) {
            _hak = hakBaru.map((k, v) => MapEntry('$k', v == true));
          }
          _jurnal = baris.where(_lolosFilterLokal).toList();
          _dariCache = hasil['offline'] == true;
          if (hasil['dariServer'] == true) {
            _tanggalClosing = '${hasil['tanggalClosing'] ?? ''}';
          }
          _memuat = false;
        });
      });
      final jenis = await MasterOffline.daftarDenganCache(
          'jurnal_umum_jenis_transaksi',
          const {},
          'master:jurnal_jenis_transaksi');
      // Daftar akun dipakai pemilih akun di editor; sekali muat, dipakai semua baris.
      final akun = await MasterOffline.daftarDenganCache(
          'akun_list', {'limit': 5000}, 'master:akun');
      if (!mounted) return;
      setStateIfMounted(() {
        _jenisTransaksi =
            ((jenis['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _akun = ((akun['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _memuat = false;
      });
    } catch (e) {
      setStateIfMounted(() {
        _galat = '$e';
        _memuat = false;
      });
    }
  }

  Future<void> _pilihTanggal(bool awal) async {
    final pilih = await showDatePicker(
      context: context,
      initialDate: awal ? _mulai : _sampai,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (pilih == null) return;
    setStateIfMounted(() {
      if (awal) {
        _mulai = pilih;
      } else {
        _sampai = pilih;
      }
    });
    await _muat();
  }

  Future<void> _bukaEditor({Map<String, dynamic>? jurnal}) async {
    if (_akun.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bagan akun belum termuat. Coba muat ulang halaman.')));
      return;
    }
    List<Map<String, dynamic>> barisAwal = [];
    Map<String, dynamic>? kepala;
    if (jurnal != null) {
      setStateIfMounted(() => _sibuk = true);
      try {
        final d = await ApiClient.instance
            .aksi('jurnal_umum_detail', {'id': jurnal['id']});
        kepala = (d['kepala'] as Map?)?.cast<String, dynamic>();
        barisAwal = ((d['baris'] as List?) ?? []).cast<Map<String, dynamic>>();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Gagal memuat jurnal: $e')));
        }
        setStateIfMounted(() => _sibuk = false);
        return;
      }
      setStateIfMounted(() => _sibuk = false);
    }
    if (!mounted) return;
    final tersimpan = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditorJurnal(
        akun: _akun,
        jenisTransaksi: _jenisTransaksi,
        tanggalClosing: _tanggalClosing,
        kepala: kepala,
        barisAwal: barisAwal,
      ),
    );
    if (tersimpan == true) await _muat();
  }

  /// Hak per aksi dari peladen (grid CRUD TbmroleAction) -- dipakai MEMADAMKAN
  /// tombol; gerbang sebenarnya tetap pemeriksaan di peladen. Kunci yang tidak
  /// dikirim dianggap BOLEH, sama seperti bawaan peladen.
  ///
  /// Empat wewenangnya sengaja tidak digabung: memposting ke buku besar
  /// (`approve`) bukan turunan dari boleh menyimpan draf (`create`), dan
  /// membatalkan posting (`reject`) berbeda lagi.
  Map<String, bool> _hak = const {};

  bool _boleh(String aksi) => _hak[aksi] != false;

  Future<void> _aksiJurnal(Map<String, dynamic> j, String aksi) async {
    final terposting = j['terposting'] == true;
    String tanya;
    if (aksi == 'jurnal_umum_posting') {
      tanya =
          'Posting jurnal ${j['kode']} ke buku besar? Setelah diposting, jurnal '
          'ikut terbaca laporan keuangan dan tidak dapat diubah lagi.';
    } else if (aksi == 'jurnal_umum_batal_posting') {
      tanya =
          'Batalkan posting jurnal ${j['kode']}? Jurnal kembali menjadi draf dan '
          'ditarik keluar dari laporan keuangan.';
    } else {
      tanya =
          'Hapus jurnal ${j['kode']} beserta seluruh barisnya? Tindakan ini tidak '
          'dapat dibatalkan.';
    }
    if (terposting && aksi == 'jurnal_umum_hapus') return;
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: Text(tanya),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lanjut')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final hasil = await ApiClient.instance.aksi(aksi, {'id': j['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Selesai.'}')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _postingSemuaDraf() async {
    final draf = _jurnal.where((j) => j['terposting'] != true).toList();
    if (draf.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada jurnal draf pada periode ini.')));
      return;
    }
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Posting Semua Draf'),
        content:
            Text('${draf.length} jurnal draf akan diposting ke buku besar. '
                'Jurnal yang tidak seimbang akan dilewati.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Posting')),
        ],
      ),
    );
    if (setuju != true) return;
    setStateIfMounted(() => _sibuk = true);
    try {
      final ids = draf.map((e) => e['id']).toList();
      final hasil =
          await ApiClient.instance.aksi('jurnal_umum_posting', {'ids': ids});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Selesai.'}')));
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _tampilkanDialogDownload() async {
    String formatTerpilih = 'accurate';
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.file_download_outlined, color: Colors.blue),
              SizedBox(width: 8),
              Text('Pilih Format Download'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih format berkas untuk mengunduh daftar Jurnal Umum periode ini:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                value: 'accurate',
                groupValue: formatTerpilih,
                title: const Text('Accurate (Histori Buku Besar Jurnal .xlsx)'),
                subtitle: const Text(
                  'Format standar Accurate (template Histori Buku Besar), cocok untuk impor/ekspor antar sistem.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (val) =>
                    setDialogState(() => formatTerpilih = val ?? 'accurate'),
              ),
              RadioListTile<String>(
                value: 'standar',
                groupValue: formatTerpilih,
                title: const Text('Format Standar (.xlsx)'),
                subtitle: const Text(
                  'Format tabel sederhana dengan rincian kolom akun, debet, dan kredit.',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (val) =>
                    setDialogState(() => formatTerpilih = val ?? 'standar'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, formatTerpilih),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );

    if (hasil == null || !mounted) return;
    await _prosesDownload(hasil);
  }

  Future<void> _prosesDownload(String format) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final res = await ApiClient.instance.aksi('jurnal_umum_list', {
        'mulai': _fmtTanggal.format(_mulai),
        'sampai': _fmtTanggal.format(_sampai),
        'status': _status,
        'cari': _cari,
        'denganBaris': true,
        'limit': 1000,
      });

      final rawData =
          ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();

      final dataLengkap = <Map<String, dynamic>>[];
      for (final j in rawData) {
        final jMap = Map<String, dynamic>.from(j);
        final baris = jMap['baris'] as List?;
        if (baris == null ||
            (baris.isEmpty && (jMap['jumlahBaris'] as num? ?? 0) > 0)) {
          try {
            final d = await ApiClient.instance
                .aksi('jurnal_umum_detail', {'id': jMap['id']});
            jMap['baris'] = d['baris'];
          } catch (_) {}
        }
        dataLengkap.add(jMap);
      }

      final namaToko = Sesi.instance.namaTokoFilter.isNotEmpty &&
              Sesi.instance.namaTokoFilter != 'Semua Toko'
          ? Sesi.instance.namaTokoFilter
          : (Sesi.instance.tokoNama.isNotEmpty
              ? Sesi.instance.tokoNama
              : 'Toko');

      Uint8List bytes;
      String namaBerkas;
      if (format == 'accurate') {
        bytes = buildAccurateJurnalXlsx(
          namaToko: namaToko,
          mulai: _mulai,
          sampai: _sampai,
          daftarJurnal: dataLengkap,
        );
        namaBerkas =
            'Histori Buku Besar (Jurnal) ${_fmtTanggal.format(_mulai)}_sd_${_fmtTanggal.format(_sampai)}.xlsx';
      } else {
        bytes = buildStandarJurnalXlsx(
          namaToko: namaToko,
          mulai: _mulai,
          sampai: _sampai,
          daftarJurnal: dataLengkap,
        );
        namaBerkas =
            'Jurnal_Umum_${_fmtTanggal.format(_mulai)}_sd_${_fmtTanggal.format(_sampai)}.xlsx';
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Berkas Jurnal Umum',
        fileName: namaBerkas,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );

      if (savePath != null) {
        final f = File(savePath);
        if (!f.existsSync() || (await f.length()) == 0) {
          await f.writeAsBytes(bytes);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berkas berhasil diunduh: $savePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mendownload berkas: $e')),
        );
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _tampilkanDialogUpload() async {
    if (!(Sesi.instance.isAdmin && (_boleh('create') || _boleh('edit')))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Hanya Administrator dengan hak Tambah/Edit yang dapat mengunggah berkas.')),
      );
      return;
    }

    String formatTerpilih = 'accurate';
    final hasil = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.file_upload_outlined, color: Colors.green),
              SizedBox(width: 8),
              Text('Pilih Format Upload'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih format berkas Excel yang akan diunggah:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              RadioListTile<String>(
                value: 'accurate',
                groupValue: formatTerpilih,
                title: const Text('Accurate (Histori Buku Besar Jurnal .xlsx)'),
                subtitle: const Text(
                  'Format resmi Accurate (contoh: Downloads/Histori Buku Besar (Jurnal).xlsx).',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (val) =>
                    setDialogState(() => formatTerpilih = val ?? 'accurate'),
              ),
              RadioListTile<String>(
                value: 'standar',
                groupValue: formatTerpilih,
                title: const Text('Format Standar (.xlsx)'),
                subtitle: const Text(
                  'Format lainnya (pengembangan mendatang).',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: null, // Dinonaktifkan sementara sesuai kebutuhan user
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, formatTerpilih),
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('Pilih Berkas'),
            ),
          ],
        ),
      ),
    );

    if (hasil == null || !mounted) return;
    await _prosesUpload(hasil);
  }

  Future<void> _prosesUpload(String format) async {
    if (format != 'accurate') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Format selain Accurate belum didukung saat ini.')),
      );
      return;
    }

    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih Berkas Excel Accurate',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (res == null || res.files.isEmpty) return;

      final file = res.files.first;
      Uint8List? bytes = file.bytes;
      if (bytes == null && file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Berkas yang dipilih kosong atau tidak terbaca.');
      }

      setStateIfMounted(() => _sibuk = true);

      // Parse menggunakan parser Accurate
      final hasilParse = parseAccurateJurnalXlsx(bytes, daftarAkun: _akun);

      setStateIfMounted(() => _sibuk = false);

      if (hasilParse.daftarJurnal.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Tidak ada data transaksi jurnal yang terbaca dari berkas Excel tersebut.')),
        );
        return;
      }

      if (!mounted) return;

      // 1. DIALOG PRATINJAU (PREVIEW) SEBELUM UPLOAD
      final konfirmasi = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final totalJurnal = hasilParse.daftarJurnal.length;
          final totalClosing = hasilParse.daftarJurnal.where((j) =>
              _tanggalClosing.isNotEmpty &&
              j.tanggal.isNotEmpty &&
              j.tanggal.compareTo(_tanggalClosing) <= 0).length;
          final totalAda = hasilParse.daftarJurnal.where((j) =>
              _jurnal.any((x) =>
                  '${x['kode'] ?? ''}'.trim() == j.noBukti.trim())).length;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.table_view_outlined, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pratinjau Impor Jurnal Umum',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        '${file.name} — $totalJurnal transaksi jurnal (${hasilParse.totalBarisMentah} baris)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // KPI Ringkasan
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _itemStatistikPreview('Total Jurnal', '$totalJurnal', Colors.blue.shade900),
                        _itemStatistikPreview('Total Debet', _rp(hasilParse.totalDebet), Colors.green.shade800),
                        _itemStatistikPreview('Total Kredit', _rp(hasilParse.totalKredit), Colors.green.shade800),
                        _itemStatistikPreview('Timpa Ulang', '$totalAda', Colors.indigo),
                        if (totalClosing > 0)
                          _itemStatistikPreview('Terkunci Closing', '$totalClosing', Colors.red.shade700),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (totalClosing > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_clock, size: 16, color: Colors.red.shade800),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ada $totalClosing transaksi yang masuk periode closing buku (sampai $_tanggalClosing) dan akan LANGSUNG DITOLAK server.',
                              style: TextStyle(fontSize: 11, color: Colors.red.shade900, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Tabel Pratinjau Jurnal
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ListView.separated(
                        itemCount: hasilParse.daftarJurnal.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final j = hasilParse.daftarJurnal[idx];
                          final isClosing = _tanggalClosing.isNotEmpty &&
                              j.tanggal.isNotEmpty &&
                              j.tanggal.compareTo(_tanggalClosing) <= 0;
                          final isAda = _jurnal.any((x) =>
                              '${x['kode'] ?? ''}'.trim() == j.noBukti.trim());
                          final akunKurang = j.rincian.any((b) => b.akunId == null || b.akunId! <= 0);

                          String labelStatus;
                          Color warnaBadge;
                          if (isClosing) {
                            labelStatus = 'Terkunci Closing (Ditolak)';
                            warnaBadge = Colors.red;
                          } else if (!j.isSeimbang) {
                            labelStatus = 'Tidak Seimbang';
                            warnaBadge = Colors.red.shade700;
                          } else if (akunKurang) {
                            labelStatus = 'Akun Belum Ada';
                            warnaBadge = Colors.orange.shade800;
                          } else if (isAda) {
                            labelStatus = 'Timpa Ulang (Belum Closing)';
                            warnaBadge = Colors.blue;
                          } else {
                            labelStatus = 'Jurnal Baru';
                            warnaBadge = Colors.green.shade700;
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 140,
                                  child: Text(
                                    j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(j.tanggal, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ),
                                Expanded(
                                  child: Text(
                                    j.keterangan,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    _rp(j.totalDebet),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: warnaBadge.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: warnaBadge.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    labelStatus,
                                    style: TextStyle(fontSize: 10, color: warnaBadge, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text('Mulai Upload ($totalJurnal Jurnal)'),
              ),
            ],
          );
        },
      );

      if (konfirmasi != true || !mounted) return;

      // 2. PROSES UPLOAD DENGAN PROGRESS BAR & PERSENTASE (SEPERTI STOK BARANG)
      final total = hasilParse.daftarJurnal.length;
      int selesai = 0;
      int berhasil = 0;
      final gagalList = <_HasilGagalUpload>[];
      String statusTeks = 'Mempersiapkan transaksi...';

      final defaultJenisId = _jenisTransaksi.isNotEmpty
          ? (_jenisTransaksi.first['id'] as num?)?.toInt()
          : null;

      // Tampilkan Modal Dialog Progress
      late void Function(void Function()) setDialogProgress;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctxProg) => StatefulBuilder(
          builder: (ctxProg, setStateDialog) {
            setDialogProgress = setStateDialog;
            final progres = total > 0 ? (selesai / total).clamp(0.0, 1.0) : 0.0;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(24),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.blue),
                    const SizedBox(height: 14),
                    const Text(
                      'Mengunggah Jurnal Umum',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progres,
                        minHeight: 10,
                        backgroundColor: Colors.blue.withValues(alpha: 0.15),
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Memproses $selesai dari $total jurnal (${(progres * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusTeks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // Loop pengiriman tiap transaksi secara real-time
      for (final j in hasilParse.daftarJurnal) {
        if (!mounted) break;
        setDialogProgress(() {
          statusTeks = 'Mengunggah: ${j.noBukti.isNotEmpty ? j.noBukti : j.keterangan}...';
        });

        // Validasi awal closing di sisi klien
        if (_tanggalClosing.isNotEmpty &&
            j.tanggal.isNotEmpty &&
            j.tanggal.compareTo(_tanggalClosing) <= 0) {
          gagalList.add(_HasilGagalUpload(
            noBukti: j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
            tanggal: j.tanggal,
            keterangan: j.keterangan,
            pesan: 'Sudah masuk periode closing buku sampai $_tanggalClosing.',
            penyebab: 'Tanggal transaksi (${j.tanggal}) berada di dalam periode tutup buku sampai $_tanggalClosing.',
            solusi: 'Minta bagian keuangan membuka kembali periode closing buku di menu Akuntansi/ZK bila data perlu diubah.',
          ));
          selesai++;
          setDialogProgress(() {});
          continue;
        }

        // Validasi akun lengkap
        if (!j.rincian.every((b) => b.akunId != null && b.akunId! > 0)) {
          final akunTakAda = j.rincian
              .where((b) => b.akunId == null || b.akunId! <= 0)
              .map((b) => b.kodeAkun)
              .join(', ');
          gagalList.add(_HasilGagalUpload(
            noBukti: j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
            tanggal: j.tanggal,
            keterangan: j.keterangan,
            pesan: 'Akun belum terdaftar di sistem.',
            penyebab: 'Kode akun ($akunTakAda) belum terdaftar pada bagan akun AIS.',
            solusi: 'Daftarkan kode akun tersebut di menu Master Bagan Akun sebelum mengimpor.',
          ));
          selesai++;
          setDialogProgress(() {});
          continue;
        }

        // Validasi keseimbangan
        if (!j.isSeimbang) {
          gagalList.add(_HasilGagalUpload(
            noBukti: j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
            tanggal: j.tanggal,
            keterangan: j.keterangan,
            pesan: 'Total debet dan kredit tidak seimbang.',
            penyebab: 'Total debet (${_rp(j.totalDebet)}) != Total kredit (${_rp(j.totalKredit)}).',
            solusi: 'Koreksi nominal debet dan kredit pada berkas Excel agar seimbang.',
          ));
          selesai++;
          setDialogProgress(() {});
          continue;
        }

        // Kirim ke server
        try {
          final payload = j.toPayloadSimpan(jenisTransaksiId: defaultJenisId);
          final resSimpan = await ApiClient.instance.aksi('jurnal_umum_simpan', payload);
          if (resSimpan['status'] == '00') {
            berhasil++;
          } else {
            gagalList.add(_HasilGagalUpload(
              noBukti: j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
              tanggal: j.tanggal,
              keterangan: j.keterangan,
              pesan: '${resSimpan['message'] ?? 'Ditolak oleh sistem'}',
              penyebab: '${resSimpan['penyebab'] ?? resSimpan['message'] ?? 'Galat validasi basis data'}',
              solusi: '${resSimpan['solusi'] ?? 'Periksa data transaksi pada berkas Excel.'}',
            ));
          }
        } catch (e) {
          gagalList.add(_HasilGagalUpload(
            noBukti: j.noBukti.isEmpty ? '(Tanpa No Bukti)' : j.noBukti,
            tanggal: j.tanggal,
            keterangan: j.keterangan,
            pesan: '$e',
            penyebab: 'Galat jaringan atau server: $e',
            solusi: 'Periksa koneksi jaringan server AIS Anda lalu coba simpan ulang.',
          ));
        }

        selesai++;
        setDialogProgress(() {});
      }

      // Tutup dialog progress
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // 3. DIALOG LAPORAN HASIL UPLOAD (BERHASIL, GAGAL, PENYEBAB & SOLUSI)
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctxLap) => AlertDialog(
          title: Row(
            children: [
              Icon(
                gagalList.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: gagalList.isEmpty ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('Laporan Hasil Upload Jurnal'),
            ],
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // KPI Statistik
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            children: [
                              Text('$total',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900)),
                              const SizedBox(height: 2),
                              const Text('Total Diproses', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            children: [
                              Text('$berhasil',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900)),
                              const SizedBox(height: 2),
                              const Text('Berhasil Diimpor', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: gagalList.isEmpty ? Colors.grey.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: gagalList.isEmpty ? Colors.grey.shade300 : Colors.red.shade200),
                          ),
                          child: Column(
                            children: [
                              Text('${gagalList.length}',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: gagalList.isEmpty ? Colors.grey : Colors.red.shade900)),
                              const SizedBox(height: 2),
                              const Text('Gagal / Ditolak', style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (gagalList.isNotEmpty) ...[
                    Text(
                      'Rincian Transaksi yang Gagal / Ditolak (${gagalList.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: gagalList.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final g = gagalList[i];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                                    const SizedBox(width: 6),
                                    Text(
                                      'No Bukti: ${g.noBukti} (${g.tanggal})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                                if (g.keterangan.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2, left: 22),
                                    child: Text(
                                      g.keterangan,
                                      style: const TextStyle(fontSize: 11, color: Colors.black87),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(left: 22),
                                  child: Text(
                                    'Penyebab: ${g.penyebab}',
                                    style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(left: 22, top: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.lightbulb_outline, size: 14, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Solusi: ${g.solusi}',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.blueAccent,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Seluruh transaksi jurnal berhasil diimpor sebagai Draf ke sistem ebisnis.',
                              style: TextStyle(fontSize: 12, color: Colors.green),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctxLap);
              },
              child: const Text('Tutup & Segarkan Data'),
            ),
          ],
        ),
      );

      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengimpor berkas: $e')),
        );
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Widget _itemStatistikPreview(String label, String nilai, Color warna) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(nilai,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 13, color: warna)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _sibuk = true);
    try {
      final res = await ApiClient.instance.aksi('jurnal_umum_list', {
        'mulai': _fmtTanggal.format(_mulai),
        'sampai': _fmtTanggal.format(_sampai),
        'status': _status,
        'cari': _cari,
        'denganBaris': true,
        'limit': 1000,
      });

      final rawData =
          ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();

      final dataLengkap = <Map<String, dynamic>>[];
      for (final j in rawData) {
        final jMap = Map<String, dynamic>.from(j);
        final baris = jMap['baris'] as List?;
        if (baris == null ||
            (baris.isEmpty && (jMap['jumlahBaris'] as num? ?? 0) > 0)) {
          try {
            final d = await ApiClient.instance
                .aksi('jurnal_umum_detail', {'id': jMap['id']});
            jMap['baris'] = d['baris'];
          } catch (_) {}
        }
        dataLengkap.add(jMap);
      }

      final namaToko = Sesi.instance.namaTokoFilter.isNotEmpty &&
              Sesi.instance.namaTokoFilter != 'Semua Toko'
          ? Sesi.instance.namaTokoFilter
          : (Sesi.instance.tokoNama.isNotEmpty
              ? Sesi.instance.tokoNama
              : 'Toko');

      final pdf = pw.Document();
      final judulStatus = _status == 'draf'
          ? ' (Draf Saja)'
          : (_status == 'terposting' ? ' (Terposting Saja)' : '');

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          header: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(namaToko,
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Hal. ${context.pageNumber} / ${context.pagesCount}',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Text('LAPORAN JURNAL UMUM$judulStatus',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  'Periode: ${_fmtTanggal.format(_mulai)} s/d ${_fmtTanggal.format(_sampai)}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.Divider(thickness: 1, height: 12),
            ],
          ),
          build: (pw.Context context) {
            final rows = <pw.TableRow>[
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('No Bukti',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Tanggal',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Keterangan & Rincian Akun',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Debet (Rp)',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Kredit (Rp)',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('Status',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                ],
              ),
            ];

            double totalDebet = 0;
            double totalKredit = 0;

            for (final j in dataLengkap) {
              final kode = '${j['kode'] ?? ''}';
              final tgl = '${j['tanggal'] ?? ''}';
              final ket = '${j['keterangan'] ?? ''}';
              final terposting = j['terposting'] == true;
              final d = (j['totalDebet'] as num?)?.toDouble() ?? 0.0;
              final k = (j['totalKredit'] as num?)?.toDouble() ?? 0.0;
              totalDebet += d;
              totalKredit += k;

              final barisList =
                  (j['baris'] as List?)?.cast<Map<String, dynamic>>() ?? [];

              rows.add(
                pw.TableRow(
                  children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(kode,
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(tgl,
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(ket,
                              style: pw.TextStyle(
                                  fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          if (barisList.isNotEmpty)
                            ...barisList.map((b) {
                              final dLine =
                                  (b['debet'] as num?)?.toDouble() ?? 0.0;
                              final kLine =
                                  (b['kredit'] as num?)?.toDouble() ?? 0.0;
                              final nominal =
                                  dLine > 0 ? _rp(dLine) : _rp(kLine);
                              final posisi = dLine > 0 ? '(D)' : '(K)';
                              return pw.Text(
                                '  • ${b['kodeAkun'] ?? ''} ${b['namaAkun'] ?? ''} $posisi $nominal',
                                style: const pw.TextStyle(
                                    fontSize: 7, color: PdfColors.grey800),
                              );
                            }),
                        ],
                      ),
                    ),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(_rp(d),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(_rp(k),
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(terposting ? 'Terposting' : 'Draf',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                                fontSize: 8,
                                color: terposting
                                    ? PdfColors.green800
                                    : PdfColors.orange800))),
                  ],
                ),
              );
            }

            rows.add(
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('TOTAL',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('')),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('${dataLengkap.length} Transaksi',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(_rp(totalDebet),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(_rp(totalKredit),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('')),
                ],
              ),
            );

            return [
              pw.Table(
                border:
                    pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2),
                  1: pw.FlexColumnWidth(1.5),
                  2: pw.FlexColumnWidth(5),
                  3: pw.FlexColumnWidth(2),
                  4: pw.FlexColumnWidth(2),
                  5: pw.FlexColumnWidth(1.5),
                },
                children: rows,
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name:
            'Jurnal_Umum_${_fmtTanggal.format(_mulai)}_${_fmtTanggal.format(_sampai)}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e')),
        );
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<void> _cetakVoucher(Map<String, dynamic> j) async {
    setStateIfMounted(() => _sibuk = true);
    try {
      var baris = (j['baris'] as List?)?.cast<Map<String, dynamic>>();
      if (baris == null || baris.isEmpty) {
        final d = await ApiClient.instance
            .aksi('jurnal_umum_detail', {'id': j['id']});
        baris = ((d['baris'] as List?) ?? []).cast<Map<String, dynamic>>();
      }

      final namaToko = Sesi.instance.namaTokoFilter.isNotEmpty &&
              Sesi.instance.namaTokoFilter != 'Semua Toko'
          ? Sesi.instance.namaTokoFilter
          : (Sesi.instance.tokoNama.isNotEmpty
              ? Sesi.instance.tokoNama
              : 'Toko Al-Bahjah');

      final kode = '${j['kode'] ?? '-'}';
      final tanggal = '${j['tanggal'] ?? '-'}';
      final keterangan = '${j['keterangan'] ?? '-'}';
      final d = (j['totalDebet'] as num?)?.toDouble() ?? 0.0;
      final k = (j['totalKredit'] as num?)?.toDouble() ?? 0.0;

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            final tableRows = <pw.TableRow>[
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('No',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Kode Akun',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Nama Perkiraan / Akun',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Keterangan Baris',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Debet (Rp)',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('Kredit (Rp)',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                ],
              ),
            ];

            int no = 1;
            for (final b in (baris ?? [])) {
              final dLine = (b['debet'] as num?)?.toDouble() ?? 0.0;
              final kLine = (b['kredit'] as num?)?.toDouble() ?? 0.0;
              tableRows.add(
                pw.TableRow(
                  children: [
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('$no',
                            style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('${b['kodeAkun'] ?? ''}',
                            style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('${b['namaAkun'] ?? ''}',
                            style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('${b['keterangan'] ?? ''}',
                            style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(dLine > 0 ? _rp(dLine) : '-',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(kLine > 0 ? _rp(kLine) : '-',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
              );
              no++;
            }

            tableRows.add(
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('TOTAL',
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(_rp(d),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(_rp(k),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold, fontSize: 9))),
                ],
              ),
            );

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(namaToko,
                            style: pw.TextStyle(
                                fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2),
                        pw.Text('BUKTI VOUCHER TRANSAKSI KAS & BANK',
                            style: pw.TextStyle(
                                fontSize: 12,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blueGrey800)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('No. Voucher: $kode',
                            style: pw.TextStyle(
                                fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Tanggal: $tanggal',
                            style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                            'Status: ${j['terposting'] == true ? 'TERPOSTING' : 'DRAF'}',
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: j['terposting'] == true
                                    ? PdfColors.green800
                                    : PdfColors.orange800)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(height: 16, thickness: 1),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                          width: 100,
                          child: pw.Text('Keterangan / Uraian:',
                              style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold))),
                      pw.Expanded(
                          child: pw.Text(keterangan,
                              style: const pw.TextStyle(fontSize: 9))),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(0.6),
                    1: pw.FlexColumnWidth(2),
                    2: pw.FlexColumnWidth(3.5),
                    3: pw.FlexColumnWidth(3.5),
                    4: pw.FlexColumnWidth(2),
                    5: pw.FlexColumnWidth(2),
                  },
                  children: tableRows,
                ),
                pw.SizedBox(height: 36),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _kolomTandaTanganPdf('Dibuat Oleh:', '( Kasir / Staf )'),
                    _kolomTandaTanganPdf(
                        'Diperiksa Oleh:', '( Akuntansi / Admin )'),
                    _kolomTandaTanganPdf(
                        'Disetujui Oleh:', '( Pimpinan / Manager )'),
                    _kolomTandaTanganPdf('Diterima Oleh:', '( Penerima Dana )'),
                  ],
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'Voucher_$kode.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak Voucher: $e')),
        );
      }
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  static pw.Widget _kolomTandaTanganPdf(String judul, String nama) {
    return pw.Container(
      width: 110,
      child: pw.Column(
        children: [
          pw.Text(judul, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 48),
          pw.Container(height: 0.5, color: PdfColors.black),
          pw.SizedBox(height: 3),
          pw.Text(nama, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  String _rp(num? v) => _fmtAngka.format((v ?? 0).round());

  @override
  Widget build(BuildContext context) {
    final draf = _jurnal.where((j) => j['terposting'] != true).length;
    final bolehUpload =
        Sesi.instance.isAdmin && (_boleh('create') || _boleh('edit'));

    return AppShell(
      menuAktif: MenuEBisnis.jurnalUmum,
      judul: 'Jurnal Umum',
      subjudul: 'Jurnal manual: koreksi, penyesuaian, biaya, dan saldo awal',
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sibuk || !_boleh('create') ? null : () => _bukaEditor(),
        icon: const Icon(Icons.post_add),
        label: const Text('Jurnal Baru'),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pilihTanggal(true),
                icon: const Icon(Icons.event, size: 18),
                label: Text('Mulai ${_fmtTanggal.format(_mulai)}'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pilihTanggal(false),
                icon: const Icon(Icons.event_available, size: 18),
                label: Text('Sampai ${_fmtTanggal.format(_sampai)}'),
              ),
              SizedBox(
                width: 240,
                child: AppSearchField(
                  labelText: 'Cari kode / keterangan',
                  debounce: Duration.zero,
                  onChanged: (v) => _cari = v,
                  onSubmitted: (_) => _muat(),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  value: _status,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Status', isDense: true),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Semua status')),
                    DropdownMenuItem(value: 'draf', child: Text('Draf saja')),
                    DropdownMenuItem(
                        value: 'terposting', child: Text('Terposting saja')),
                  ],
                  onChanged: (v) {
                    setStateIfMounted(() => _status = v ?? '');
                    _muat();
                  },
                ),
              ),
              FilledButton.icon(
                  onPressed: _memuat ? null : _muat,
                  icon: const Icon(Icons.filter_alt_outlined, size: 18),
                  label: const Text('Terapkan')),
              OutlinedButton.icon(
                  onPressed:
                      _memuat || _sibuk ? null : _tampilkanDialogDownload,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Download')),
              if (bolehUpload)
                OutlinedButton.icon(
                    onPressed: _memuat || _sibuk ? null : _tampilkanDialogUpload,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Upload')),
              OutlinedButton.icon(
                  onPressed: _memuat || _sibuk ? null : _cetakPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Cetak PDF')),
              if (draf > 0)
                OutlinedButton.icon(
                    // Posting massal memakai wewenang yang sama dgn posting
                    // satu baris: approve, bukan create.
                    onPressed:
                        _sibuk || !_boleh('approve') ? null : _postingSemuaDraf,
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: Text('Posting Semua Draf ($draf)')),
              if (_sibuk)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
        if (draf > 0 && _status == 'terposting')
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Terdapat $draf Draf Jurnal pada periode ini yang belum diposting (tersembunyi karena filter "Terposting saja").',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
              TextButton(
                onPressed: () {
                  setStateIfMounted(() => _status = '');
                  _muat();
                },
                child: const Text('Tampilkan Semua'),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        // Nominal debet/kredit dari salinan tersimpan wajib dinyatakan
        // terang-terangan.
        PenandaDataTersimpan(tampil: _dariCache),
        if (_tanggalClosing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.lock_clock, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Buku sudah ditutup sampai $_tanggalClosing — jurnal bertanggal sebelum '
                    'itu akan ditolak sistem.',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _galat != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_galat!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _muat, child: const Text('Coba lagi')),
                    ]))
                  : AppDataTable(
                      minWidth: 980,
                      emptyText: 'Belum ada jurnal umum pada periode ini. '
                          'Tekan "Jurnal Baru" untuk membuat.',
                      columns: const [
                        AppTableColumn('Kode', flex: 3),
                        AppTableColumn('Tanggal', flex: 2),
                        AppTableColumn('Keterangan', flex: 5),
                        AppTableColumn('Mata Anggaran', flex: 4),
                        AppTableColumn('Debet',
                            flex: 2, align: TextAlign.right),
                        AppTableColumn('Kredit',
                            flex: 2, align: TextAlign.right),
                        AppTableColumn('Status', flex: 2),
                        AppTableColumn('Aksi', width: 64),
                      ],
                      rows: _jurnal.map((j) {
                        final terposting = j['terposting'] == true;
                        return AppTableRowData(cells: [
                          AppTableCell.text('${j['kode'] ?? ''}', flex: 3),
                          AppTableCell.text('${j['tanggal'] ?? ''}', flex: 2),
                          AppTableCell.text(
                              '${j['keterangan'] ?? ''}'
                              '${(j['jumlahBaris'] ?? 0) > 0 ? '  (${j['jumlahBaris']} baris)' : ''}',
                              flex: 5),
                          AppTableCell.text(
                              '${j['workspaceKode'] ?? ''}'
                                          '${(j['workspaceKode'] ?? '').toString().isNotEmpty && (j['workspaceNama'] ?? '').toString().isNotEmpty ? ' — ' : ''}'
                                          '${j['workspaceNama'] ?? ''}'
                                      .trim()
                                      .isEmpty
                                  ? '-'
                                  : '${j['workspaceKode'] ?? ''}'
                                      '${(j['workspaceKode'] ?? '').toString().isNotEmpty && (j['workspaceNama'] ?? '').toString().isNotEmpty ? ' — ' : ''}'
                                      '${j['workspaceNama'] ?? ''}',
                              flex: 4),
                          AppTableCell.text(_rp(j['totalDebet'] as num?),
                              flex: 2, align: TextAlign.right),
                          AppTableCell.text(_rp(j['totalKredit'] as num?),
                              flex: 2, align: TextAlign.right),
                          AppTableCell(
                            flex: 2,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(terposting ? 'Terposting' : 'Draf',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                          AppTableCell(
                            width: 64,
                            align: TextAlign.center,
                            child: AksiBarisMenu(aksi: [
                              AksiBaris(
                                  ikon: terposting
                                      ? Icons.visibility_outlined
                                      : Icons.edit_outlined,
                                  label: terposting ? 'Lihat' : 'Ubah',
                                  onTap: _sibuk
                                      ? null
                                      : () => _bukaEditor(jurnal: j)),
                              AksiBaris(
                                  ikon: Icons.receipt_long_outlined,
                                  label: 'Cetak Voucher',
                                  onTap: _sibuk
                                      ? null
                                      : () => _cetakVoucher(j)),
                              // Posting dan Batalkan posting dahulu saling
                              // menggantikan; kini keduanya tetap tampil dan yang
                              // tidak berlaku hanya diredupkan.
                              AksiBaris(
                                  ikon: Icons.check_circle_outline,
                                  label: 'Posting ke buku besar',
                                  onTap:
                                      _sibuk || terposting || !_boleh('approve')
                                          ? null
                                          : () => _aksiJurnal(
                                              j, 'jurnal_umum_posting')),
                              AksiBaris(
                                  ikon: Icons.undo,
                                  label: 'Batalkan posting',
                                  onTap:
                                      _sibuk || !terposting || !_boleh('reject')
                                          ? null
                                          : () => _aksiJurnal(
                                              j, 'jurnal_umum_batal_posting')),
                              AksiBaris(
                                  ikon: Icons.delete_outline,
                                  label: 'Hapus',
                                  merusak: true,
                                  onTap: _sibuk ||
                                          terposting ||
                                          !_boleh('delete')
                                      ? null
                                      : () =>
                                          _aksiJurnal(j, 'jurnal_umum_hapus')),
                            ]),
                          ),
                        ]);
                      }).toList(),
                    ),
        ),
      ]),
    );
  }
}

/// Editor satu jurnal: kepala + baris debet/kredit, dengan indikator keseimbangan.
class _EditorJurnal extends StatefulWidget {
  const _EditorJurnal({
    required this.akun,
    required this.jenisTransaksi,
    required this.tanggalClosing,
    required this.kepala,
    required this.barisAwal,
  });

  final List<Map<String, dynamic>> akun;
  final List<Map<String, dynamic>> jenisTransaksi;
  final String tanggalClosing;
  final Map<String, dynamic>? kepala;
  final List<Map<String, dynamic>> barisAwal;

  @override
  State<_EditorJurnal> createState() => _EditorJurnalState();
}

class _BarisJurnal {
  int? akunId;
  final TextEditingController debet = TextEditingController();
  final TextEditingController kredit = TextEditingController();
  final TextEditingController keterangan = TextEditingController();

  void buang() {
    debet.dispose();
    kredit.dispose();
    keterangan.dispose();
  }
}

class _EditorJurnalState extends State<_EditorJurnal> {
  final _fmtTanggal = DateFormat('yyyy-MM-dd');
  final _fmtAngka = NumberFormat.decimalPattern('id');
  final _keterangan = TextEditingController();
  final _penerima = TextEditingController();
  final _nomorCek = TextEditingController();
  final List<_BarisJurnal> _baris = [];
  DateTime _tanggal = DateTime.now();
  int? _jenisId;
  String? _workspaceId;
  String? _anggaranNama;
  bool _menyimpan = false;
  String? _pesan;

  bool get _terkunci => widget.kepala?['terposting'] == true;

  @override
  void initState() {
    super.initState();
    final k = widget.kepala;
    if (k != null) {
      String ket = '${k['keterangan'] ?? ''}';
      // Ekstrak tag penerima dan no ref jika ada
      final regPenerima = RegExp(r'\(Penerima:\s*([^\)]+)\)');
      final regCek = RegExp(r'\[No Cek/Ref:\s*([^\]]+)\]');
      final mPen = regPenerima.firstMatch(ket);
      if (mPen != null) {
        _penerima.text = mPen.group(1)?.trim() ?? '';
        ket = ket.replaceAll(regPenerima, '').trim();
      }
      final mCek = regCek.firstMatch(ket);
      if (mCek != null) {
        _nomorCek.text = mCek.group(1)?.trim() ?? '';
        ket = ket.replaceAll(regCek, '').trim();
      }
      _keterangan.text = ket;
      final t = '${k['tanggal'] ?? ''}';
      if (t.isNotEmpty) {
        _tanggal = DateTime.tryParse(t) ?? DateTime.now();
      }
      final jid = k['jenisTransaksiId'];
      _jenisId = jid is num ? jid.toInt() : null;
      final wsTeks = '${k['workspaceIdTeks'] ?? ''}'.trim();
      final wsAngka = k['workspaceId'];
      _workspaceId = wsTeks.isNotEmpty
          ? wsTeks
          : wsAngka == null
              ? null
              : '$wsAngka';
      final label = '${k['workspaceLabel'] ?? ''}'.trim();
      _anggaranNama = label.isEmpty ? null : label;
    }
    if (widget.barisAwal.isEmpty) {
      _tambahBaris();
      _tambahBaris();
    } else {
      for (final b in widget.barisAwal) {
        final row = _BarisJurnal();
        row.akunId = (b['akunId'] as num?)?.toInt();
        final d = (b['debet'] as num?)?.toDouble() ?? 0;
        final k2 = (b['kredit'] as num?)?.toDouble() ?? 0;
        if (d > 0) row.debet.text = d.toStringAsFixed(0);
        if (k2 > 0) row.kredit.text = k2.toStringAsFixed(0);
        row.keterangan.text = '${b['keterangan'] ?? ''}';
        _baris.add(row);
      }
    }
  }

  @override
  void dispose() {
    _keterangan.dispose();
    _penerima.dispose();
    _nomorCek.dispose();
    for (final b in _baris) {
      b.buang();
    }
    super.dispose();
  }

  void _tambahBaris() => setStateIfMounted(() => _baris.add(_BarisJurnal()));

  void _hapusBaris(int i) {
    if (_baris.length <= 2) return;
    setStateIfMounted(() {
      _baris.removeAt(i).buang();
    });
  }

  double _angka(TextEditingController c) {
    final t = c.text
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  double get _totalDebet => _baris.fold(0.0, (a, b) => a + _angka(b.debet));
  double get _totalKredit => _baris.fold(0.0, (a, b) => a + _angka(b.kredit));
  double get _selisih => _totalDebet - _totalKredit;

  /// Baris yang terisi Debet DAN Kredit sekaligus. Satu baris hanya boleh
  /// mewakili satu sisi; server menolaknya, dan menjumlahkan kedua kolomnya
  /// membuat selisihnya nol sehingga layar sempat menyebutnya "Seimbang".
  bool _duaSisi(_BarisJurnal b) => _angka(b.debet) > 0 && _angka(b.kredit) > 0;

  /// Baris yang benar-benar dapat dikirim: berakun dan terisi tepat satu sisi.
  int get _barisSah => _baris
      .where((b) =>
          b.akunId != null &&
          !_duaSisi(b) &&
          (_angka(b.debet) > 0 || _angka(b.kredit) > 0))
      .length;

  bool get _adaDuaSisi => _baris.any(_duaSisi);

  /// "Seimbang" hanya boleh muncul bila jurnalnya memang dapat disimpan:
  /// minimal dua baris sah, tidak ada baris bersisi ganda, dan selisihnya nol.
  bool get _seimbang =>
      _selisih.abs() < 0.005 &&
      _totalDebet > 0 &&
      !_adaDuaSisi &&
      _barisSah >= 2;

  /// Alasan jurnal belum dapat disimpan, kalimatnya SAMA dengan yang dipakai
  /// server -- diperiksa di sini supaya penggunanya tidak menunggu perjalanan
  /// ke server hanya untuk diberi tahu. Server tetap memeriksanya ulang.
  String? get _alasanBelumBisaSimpan {
    if (_keterangan.text.trim().isEmpty) {
      return 'Keterangan jurnal wajib diisi supaya mudah ditelusuri di buku besar.';
    }
    for (var i = 0; i < _baris.length; i++) {
      final b = _baris[i];
      final d = _angka(b.debet);
      final k = _angka(b.kredit);
      if (b.akunId == null && d == 0 && k == 0) continue; // baris kosong
      if (b.akunId == null) {
        return 'Baris ke-${i + 1}: akun belum dipilih.';
      }
      if (d > 0 && k > 0) {
        return 'Baris ke-${i + 1}: satu baris hanya boleh diisi debet ATAU kredit.';
      }
      if (d == 0 && k == 0) {
        return 'Baris ke-${i + 1}: nilainya masih nol.';
      }
    }
    if (_barisSah < 2) {
      return 'Jurnal minimal 2 baris: satu sisi debet dan satu sisi kredit.';
    }
    if (_selisih.abs() >= 0.005) {
      return 'Jurnal belum seimbang. Selisihnya ${_rp(_selisih.abs())}.';
    }
    return null;
  }

  /// Teks tooltip tombol penyeimbang: menyebut angkanya, bukan sekadar "seimbangkan".
  String _rpSelisihTooltip() =>
      _selisih.abs() < 0.005 ? 'sudah seimbang' : _rp(_selisih.abs());

  /// Mengisi sisi penyeimbang pada baris ini sebesar selisih yang tersisa.
  void _seimbangkan(_BarisJurnal b) {
    final kurangKredit = _selisih; // debet lebih besar -> butuh kredit
    setStateIfMounted(() {
      if (kurangKredit > 0) {
        b.debet.text = '';
        b.kredit.text = kurangKredit.round().toString();
      } else if (kurangKredit < 0) {
        b.kredit.text = '';
        b.debet.text = (-kurangKredit).round().toString();
      }
    });
  }

  Future<void> _simpan({bool postingLangsung = false}) async {
    // Diperiksa di layar lebih dulu supaya penggunanya menerima alasan yang
    // TEPAT seketika. Sebelumnya penolakan server sempat tersamar menjadi pesan
    // generik, dan itulah yang membuat pengguna mengira jurnal tidak bisa diinput.
    final alasan = _alasanBelumBisaSimpan;
    if (alasan != null) {
      setStateIfMounted(() => _pesan = alasan);
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _pesan = null;
    });
    try {
      final baris = <Map<String, dynamic>>[];
      for (final b in _baris) {
        final d = _angka(b.debet);
        final k = _angka(b.kredit);
        if (b.akunId == null && d == 0 && k == 0) {
          continue; // baris kosong diabaikan
        }
        baris.add({
          'akunId': b.akunId ?? 0,
          'debet': d,
          'kredit': k,
          'keterangan': b.keterangan.text.trim(),
        });
      }

      // Format keterangan lengkap menyertakan informasi penerima transfer & no cek
      String ketFinal = _keterangan.text.trim();
      final pen = _penerima.text.trim();
      final noC = _nomorCek.text.trim();
      if (pen.isNotEmpty) {
        ketFinal += ' (Penerima: $pen)';
      }
      if (noC.isNotEmpty) {
        ketFinal += ' [No Cek/Ref: $noC]';
      }

      // Lokal-dulu untuk PENYIMPANAN draf jurnal. Yang tetap wajib daring adalah
      // POSTING-nya (jurnal_umum_posting) -- itu "journal posting" pada spec 13.3
      // dan dikunci uji master_offline_kontrak_test. Menyimpan draf tidak memakai
      // id balasan server, jadi aman diantre.
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'jurnal_umum_simpan',
        kunci: widget.kepala?['id'] != null
            ? 'jurnal_umum:${widget.kepala!['id']}'
            : 'jurnal_umum:baru:${DateTime.now().microsecondsSinceEpoch}',
        cacheKey: 'master:jurnal_umum',
        rowLokal: {
          if (widget.kepala?['id'] != null) 'id': widget.kepala!['id'],
          'tanggal': _fmtTanggal.format(_tanggal),
          'keterangan': ketFinal,
          if (_workspaceId != null) 'workspaceIdTeks': _workspaceId,
          if (_anggaranNama != null) 'workspaceNama': _anggaranNama,
        },
        body: {
          if (widget.kepala?['id'] != null) 'id': widget.kepala!['id'],
          'tanggal': _fmtTanggal.format(_tanggal),
          'keterangan': ketFinal,
          'jenisTransaksiId': _jenisId ?? 0,
          if (_workspaceId != null) 'workspaceIdTeks': _workspaceId,
          'baris': baris,
        },
      );
      if (!mounted) return;
      if (!ApiClient.statusResponsSukses(hasil['status'])) {
        setStateIfMounted(
            () => _pesan = '${hasil['message'] ?? 'Gagal menyimpan.'}');
        return;
      }

      // Jika pengguna memilih Simpan & Posting Langsung, eksekusi posting ke buku besar
      if (postingLangsung) {
        final idJurnal = hasil['id'] ?? widget.kepala?['id'];
        if (idJurnal != null) {
          try {
            final resPost = await ApiClient.instance.aksi('jurnal_umum_posting', {'id': idJurnal});
            if (mounted && ApiClient.statusResponsSukses(resPost['status'])) {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop(true);
              messenger.showSnackBar(
                  SnackBar(content: Text('Jurnal ${hasil['kode'] ?? ''} berhasil disimpan dan langsung diposting ke buku besar.')));
              return;
            }
          } catch (ePost) {
            // Jika posting gagal (misal koneksi atau validasi), jurnal tetap tersimpan sebagai draf
            if (mounted) {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(context).pop(true);
              messenger.showSnackBar(
                  SnackBar(content: Text('Jurnal tersimpan sebagai draf, namun gagal diposting otomatis: $ePost')));
              return;
            }
          }
        }
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
          SnackBar(content: Text('${hasil['message'] ?? 'Tersimpan.'}')));
    } catch (e) {
      setStateIfMounted(() => _pesan = 'Gagal menyimpan: $e');
    } finally {
      setStateIfMounted(() => _menyimpan = false);
    }
  }

  String _rp(double v) => _fmtAngka.format(v.round());

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(
                    _terkunci
                        ? 'Jurnal ${widget.kepala?['kode'] ?? ''} (terposting — hanya dilihat)'
                        : widget.kepala == null
                            ? 'Jurnal Umum Baru'
                            : 'Ubah Jurnal ${widget.kepala?['kode'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 8),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _terkunci
                        ? null
                        : () async {
                            final p = await showDatePicker(
                                context: context,
                                initialDate: _tanggal,
                                firstDate: DateTime(2015),
                                lastDate: DateTime(2100));
                            if (p != null) {
                              setStateIfMounted(() {
                                if (p.year != _tanggal.year) {
                                  _workspaceId = null;
                                  _anggaranNama = null;
                                }
                                _tanggal = p;
                              });
                            }
                          },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Tanggal ${_fmtTanggal.format(_tanggal)}'),
                  ),
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int?>(
                      value: _jenisId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Jenis Transaksi (penomoran)',
                          isDense: true),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('-- Otomatis (JU) --')),
                        ...widget.jenisTransaksi
                            .map((j) => DropdownMenuItem<int?>(
                                  value: (j['id'] as num?)?.toInt(),
                                  child: Text(
                                      '${j['kode'] ?? ''} ${j['nama'] ?? ''}',
                                      overflow: TextOverflow.ellipsis),
                                )),
                      ],
                      onChanged: _terkunci
                          ? null
                          : (v) => setStateIfMounted(() => _jenisId = v),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _keterangan,
                      readOnly: _terkunci,
                      decoration: const InputDecoration(
                          labelText: 'Keterangan jurnal *', isDense: true),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _penerima,
                      readOnly: _terkunci,
                      decoration: const InputDecoration(
                          labelText: 'Penerima / Dibayarkan Kepada (opsional)',
                          isDense: true),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _nomorCek,
                      readOnly: _terkunci,
                      decoration: const InputDecoration(
                          labelText: 'No Cek / Giro / Bukti Ref (opsional)',
                          isDense: true),
                    ),
                  ),
                  SizedBox(
                    width: 920,
                    child: PemilihAnggaranField(
                      aksiCari: 'jurnal_umum_cari_anggaran',
                      workspaceId: _workspaceId,
                      namaAnggaran: _anggaranNama,
                      tahun: _tanggal.year,
                      enabled: !_terkunci,
                      helperText:
                          'Opsional. Jika dipilih, nilai debet jurnal menjadi realisasi mata anggaran dan tampil di laporan realisasi.',
                      onDipilih: (w) => setStateIfMounted(() {
                        if (w == null) {
                          _workspaceId = null;
                          _anggaranNama = null;
                          return;
                        }
                        _workspaceId = '${w['idTeks'] ?? w['id']}';
                        _anggaranNama =
                            '${w['kode'] ?? ''} — ${w['nama'] ?? ''}';
                        final akun = (w['akunId'] as num?)?.toInt();
                        if (akun != null &&
                            akun > 0 &&
                            _baris.isNotEmpty &&
                            _baris.first.akunId == null) {
                          _baris.first.akunId = akun;
                        }
                      }),
                    ),
                  ),
                ]),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _baris.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final b = _baris[i];
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: PemilihAkunField(
                            label: 'Akun baris ${i + 1}',
                            daftar: widget.akun,
                            nilai: b.akunId,
                            onChanged: _terkunci
                                ? (_) {}
                                : (v) => setStateIfMounted(() => b.akunId = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: b.debet,
                            readOnly: _terkunci,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                                labelText: 'Debet',
                                isDense: true,
                                errorText:
                                    _duaSisi(b) ? 'pilih salah satu' : null),
                            // Satu baris hanya mewakili SATU sisi. Mengisi Debet mengosongkan
                            // Kredit pada baris yang sama, supaya keadaan yang ditolak server
                            // tidak mungkin terbentuk lewat layar.
                            onChanged: (v) => setStateIfMounted(() {
                              if (_angka(b.debet) > 0) {
                                b.kredit.clear();
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: b.kredit,
                            readOnly: _terkunci,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                                labelText: 'Kredit',
                                isDense: true,
                                errorText:
                                    _duaSisi(b) ? 'pilih salah satu' : null),
                            onChanged: (v) => setStateIfMounted(() {
                              if (_angka(b.kredit) > 0) {
                                b.debet.clear();
                              }
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: b.keterangan,
                            readOnly: _terkunci,
                            decoration: const InputDecoration(
                                labelText: 'Keterangan baris', isDense: true),
                          ),
                        ),
                        // Menawarkan sisi penyeimbang sebesar selisih yang tersisa. Inilah
                        // langkah yang paling sering dilewatkan: jurnal butuh lawan baris,
                        // bukan dua kolom pada baris yang sama.
                        IconButton(
                          tooltip:
                              'Isikan sisi penyeimbang (${_rpSelisihTooltip()})',
                          onPressed: _terkunci ||
                                  _selisih.abs() < 0.005 ||
                                  _angka(b.debet) > 0 ||
                                  _angka(b.kredit) > 0
                              ? null
                              : () => _seimbangkan(b),
                          icon: const Icon(Icons.balance, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Hapus baris',
                          onPressed: _terkunci || _baris.length <= 2
                              ? null
                              : () => _hapusBaris(i),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ]);
                },
              ),
            ),
            const SizedBox(height: 8),
            if (!_terkunci)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Tiap baris diisi SALAH SATU: Debet atau Kredit. Jurnal perlu '
                      'minimal dua baris yang saling melawan, dan totalnya harus sama.',
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).hintColor),
                    ),
                  ),
                ]),
              ),
            Row(children: [
              if (!_terkunci)
                OutlinedButton.icon(
                    onPressed: _tambahBaris,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Baris')),
              const Spacer(),
              Text('Debet ${_rp(_totalDebet)}   Kredit ${_rp(_totalKredit)}   ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              // Label ini dulu hanya membandingkan dua jumlah kolom, sehingga satu
              // baris berisi Debet DAN Kredit sama besar tampak "Seimbang" padahal
              // pasti ditolak server. Kini ia menyebut ALASAN yang sesungguhnya.
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                    _seimbang ? Icons.check_circle : Icons.error_outline,
                    size: 16),
                label: Text(_seimbang
                    ? 'Siap disimpan'
                    : _adaDuaSisi
                        ? 'Ada baris berisi dua sisi'
                        : _barisSah < 2
                            ? 'Perlu minimal 2 baris'
                            : 'Selisih ${_rp(_selisih.abs())}'),
              ),
            ]),
            if (_pesan != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_pesan!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(_terkunci ? 'Tutup' : 'Batal')),
              const SizedBox(width: 8),
              if (!_terkunci) ...[
                OutlinedButton.icon(
                  onPressed: _menyimpan || !_seimbang
                      ? null
                      : () => _simpan(postingLangsung: false),
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan Draf'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _menyimpan || !_seimbang
                      ? null
                      : () => _simpan(postingLangsung: true),
                  icon: _menyimpan
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Simpan & Posting Langsung'),
                ),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
