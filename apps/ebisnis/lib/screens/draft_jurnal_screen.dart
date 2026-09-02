import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/safe_state.dart';

/// Dasbor **Draft Jurnal**: satu tempat untuk melihat pekerjaan posting yang masih
/// menggantung, padanan `draft_jurnal.zul` di web.
///
/// Angkanya datang dari aksi `draft_jurnal_ringkasan`, yang di server dihitung
/// `DraftJurnalRingkasanUtil` -- mesin yang sama dengan layar ZK. Tidak ada webview
/// atau iframe di sini: seluruh isinya data JSON yang dirender natif, sehingga tetap
/// bekerja pada Desktop maupun Android dan mengikuti tema aplikasi.
class DraftJurnalScreen extends StatefulWidget {
  const DraftJurnalScreen({super.key});

  @override
  State<DraftJurnalScreen> createState() => _DraftJurnalScreenState();
}

class _DraftJurnalScreenState extends State<DraftJurnalScreen> with JejakGalat {
  static final _tanggalIso = DateFormat('yyyy-MM-dd');
  static final _tanggalTampil = DateFormat('dd-MM-yyyy');
  static final _angka = NumberFormat.decimalPattern('id_ID');

  bool _memuat = true;
  bool _mengunduh = false;
  String? _pesanError;
  List<Map<String, dynamic>> _baris = [];
  int _draft = 0;
  int _posting = 0;
  int _closing = 0;
  String _kategoriAktif = 'semua';

  static const List<Map<String, String>> _kategoriPilihan = [
    {'id': 'semua', 'nama': 'Draft Jurnal'},
    {'id': 'jurnal_umum', 'nama': 'Jurnal Umum'},
    {'id': 'uang_muka_kas', 'nama': 'Uang Muka dan Kas'},
    {'id': 'pajak', 'nama': 'Pajak'},
    {'id': 'transaksi_vendor', 'nama': 'Transaksi Vendor'},
    {'id': 'gaji', 'nama': 'Gaji'},
    {'id': 'siswa_mahasiswa', 'nama': 'Siswa dan Mahasiswa'},
    {'id': 'fixed_asset', 'nama': 'Fixed Asset & Penyusutan'},
    {'id': 'pengajuan_transfer', 'nama': 'Pengajuan Transfer'},
    {'id': 'transitori', 'nama': 'Transitori'},
    {'id': 'closing', 'nama': 'Closing'},
    {'id': 'posting_penjualan', 'nama': 'Posting Penjualan'},
  ];

  String get _namaKategoriAktif {
    for (final kategori in _kategoriPilihan) {
      if (kategori['id'] == _kategoriAktif) {
        return kategori['nama']!;
      }
    }
    return 'Draft Jurnal';
  }

  /// Rentang bawaan menyalin layar ZK: enam bulan ke belakang sampai besok, supaya
  /// jurnal yang baru dicatat hari ini pasti ikut terlihat.
  late DateTime _mulai = DateTime.now().subtract(const Duration(days: 183));
  late DateTime _sampai = DateTime.now().add(const Duration(days: 1));

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
      final hasil = await ApiClient.instance.aksi('draft_jurnal_ringkasan', {
        'mulai': _tanggalIso.format(_mulai),
        'sampai': _tanggalIso.format(_sampai),
      });
      setStateIfMounted(() {
        _baris = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _draft = (hasil['draft'] as num?)?.toInt() ?? 0;
        _posting = (hasil['posting'] as num?)?.toInt() ?? 0;
        _closing = (hasil['closing'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _unduhExcel() async {
    final data = _barisTerfilter;
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada data yang dapat diunduh.')),
      );
      return;
    }

    setStateIfMounted(() => _mengunduh = true);
    try {
      final bytes = buildSimpleXlsx(
        sheetName: _namaKategoriAktif,
        headers: const [
          'Nama Jurnal',
          'Kategori',
          'Draft',
          'Terposting',
          'Closing',
          'Uraian',
        ],
        rows: data.map((baris) {
          return <dynamic>[
            '${baris['nama'] ?? '-'}',
            '${baris['kategoriNama'] ?? _namaKategoriAktif}',
            (baris['draft'] as num?)?.toInt() ?? 0,
            (baris['posting'] as num?)?.toInt() ?? 0,
            (baris['closing'] as num?)?.toInt() ?? 0,
            '${baris['uraian'] ?? '-'}',
          ];
        }).toList(growable: false),
      );
      final namaBerkas =
          'draft_jurnal_${_tanggalIso.format(_mulai).replaceAll('-', '')}'
          '_${_tanggalIso.format(_sampai).replaceAll('-', '')}.xlsx';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan $_namaKategoriAktif',
        fileName: namaBerkas,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Data tersimpan di $path')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        snackbarGalat(
          context,
          error,
          aktivitas: 'Mengunduh data draft jurnal',
        );
      }
    } finally {
      setStateIfMounted(() => _mengunduh = false);
    }
  }

  Future<void> _pilihTanggal({required bool awal}) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: awal ? _mulai : _sampai,
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      if (awal) {
        _mulai = hasil;
      } else {
        _sampai = hasil;
      }
    });
    await _muat();
  }

  String _kategoriBaris(Map<String, dynamic> baris) {
    final kategori = '${baris['kategori'] ?? ''}'.trim();
    if (kategori.isNotEmpty) return kategori;

    // Kompatibilitas dengan server lama yang belum mengirim field kategori.
    final kunci = '${baris['kunci'] ?? ''}'.trim().toLowerCase();
    if (kunci == 'jurnal_umum') return 'jurnal_umum';
    if (<String>{
      'uang_muka',
      'pj_uang_muka',
      'kas_kecil',
      'kas_besar',
      'pj_kas_besar',
      'penggantian_kas_kecil',
      'dana_talangan',
    }.contains(kunci)) {
      return 'uang_muka_kas';
    }
    if (kunci == 'pajak') return 'pajak';
    if (<String>{
      'penerimaan_tagihan_vendor',
      'pekerjaan_vendor',
      'dp_vendor',
      'dp_pekerjaan_vendor',
      'jurnal_balik_dp_pekerjaan',
    }.contains(kunci)) {
      return 'transaksi_vendor';
    }
    if (kunci == 'gaji') return 'gaji';
    if (kunci == 'mahasiswa' || kunci == 'siswa') {
      return 'siswa_mahasiswa';
    }
    if (kunci == 'penyusutan') return 'fixed_asset';
    if (kunci == 'pengajuan_transfer') return 'pengajuan_transfer';
    if (kunci == 'transitori') return 'transitori';
    if (kunci == 'closing') return 'closing';
    if (kunci == 'posting_hpp') return 'posting_penjualan';
    return 'semua';
  }

  List<Map<String, dynamic>> get _barisTerfilter {
    if (_kategoriAktif == 'semua') return _baris;
    return _baris
        .where((baris) => _kategoriBaris(baris) == _kategoriAktif)
        .toList(growable: false);
  }

  int _jumlahStatus(String status) {
    if (_kategoriAktif == 'semua') {
      if (status == 'draft') return _draft;
      if (status == 'posting') return _posting;
      return _closing;
    }
    var jumlah = 0;
    for (final baris in _barisTerfilter) {
      jumlah += (baris[status] as num?)?.toInt() ?? 0;
    }
    return jumlah;
  }

  int get _draftTerfilter => _jumlahStatus('draft');
  int get _postingTerfilter => _jumlahStatus('posting');
  int get _closingTerfilter => _jumlahStatus('closing');
  int get _totalTerfilter =>
      _draftTerfilter + _postingTerfilter + _closingTerfilter;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.draftJurnal,
      judul: 'Draft Jurnal',
      subjudul: 'Ringkasan kesiapan posting jurnal seluruh modul',
      aksiHeader: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _muat,
          tooltip: 'Muat ulang'),
      actionsAppBar: [
        IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _muat,
            tooltip: 'Muat ulang')
      ],
      // Badannya SUDAH menggulir sendiri (ListView). Tanpa baris ini AppShell
      // membungkusnya lagi dengan SingleChildScrollView, sehingga ListView-nya
      // menerima tinggi tak terbatas -- Flutter melempar galat tata letak dan
      // seluruh badan layar tidak tergambar sama sekali (tampak kosong).
      scrollable: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _navigasiKategori(),
          const SizedBox(height: 12),
          _filter(),
          const SizedBox(height: 12),
          if (_pesanError != null) ...[
            AppInfoBanner(
              icon: Icons.error_outline,
              color: AppColors.danger,
              text: _pesanError!,
              detail: detailUntuk(_pesanError),
            ),
            const SizedBox(height: 12),
          ],
          if (_memuat)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()))
          else ...[
            _kartuRingkasan(),
            const SizedBox(height: 12),
            _kesiapanClosing(),
            const SizedBox(height: 12),
            _tabel(),
          ],
        ],
      ),
    );
  }

  Widget _filter() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Tanggal',
                style: TextStyle(fontWeight: FontWeight.w600)),
            OutlinedButton.icon(
              onPressed: () => _pilihTanggal(awal: true),
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_tanggalTampil.format(_mulai)),
            ),
            const Text('s.d.'),
            OutlinedButton.icon(
              onPressed: () => _pilihTanggal(awal: false),
              icon: const Icon(Icons.event, size: 16),
              label: Text(_tanggalTampil.format(_sampai)),
            ),
            FilledButton.icon(
              onPressed: _memuat ? null : _muat,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Tampilkan'),
            ),
            OutlinedButton.icon(
              onPressed: _memuat || _mengunduh ? null : _unduhExcel,
              icon: _mengunduh
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 18),
              label: Text(_mengunduh ? 'Menyiapkan...' : 'Download'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigasiKategori() {
    return Card(
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: _kategoriPilihan.map((kategori) {
            final id = kategori['id']!;
            final dipilih = id == _kategoriAktif;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: dipilih,
                label: Text(kategori['nama']!),
                onSelected: (_) => setStateIfMounted(() {
                  _kategoriAktif = id;
                }),
              ),
            );
          }).toList(growable: false),
        ),
      ),
    );
  }

  Widget _kartuRingkasan() {
    return LayoutBuilder(builder: (context, batas) {
      final kolom = batas.maxWidth >= 900
          ? 4
          : batas.maxWidth >= 520
              ? 2
              : 1;
      final lebar = (batas.maxWidth - ((kolom - 1) * 10)) / kolom;
      final kartu = <Widget>[
        _kartu('Draft', _draftTerfilter, 'Belum diposting', AppColors.warning),
        _kartu('Terposting', _postingTerfilter, 'Sudah menjadi jurnal',
            AppColors.success),
        _kartu('Closing', _closingTerfilter, 'Sudah dikunci periode',
            AppColors.info),
        _kartu('Total Aktivitas', _totalTerfilter, 'Semua status',
            AppColors.primary),
      ];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: kartu
            .map((k) => SizedBox(width: lebar, child: k))
            .toList(growable: false),
      );
    });
  }

  Widget _kartu(String judul, int nilai, String keterangan, Color warna) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(judul,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 4),
            Text(_angka.format(nilai),
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: warna)),
            Text(keterangan,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _kesiapanClosing() {
    final rasio =
        _totalTerfilter == 0 ? 0.0 : _closingTerfilter / _totalTerfilter;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Kesiapan closing',
                style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
                'Semakin tinggi bagian closing, semakin banyak jurnal periode ini yang sudah selesai dikunci.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: rasio,
                minHeight: 10,
                backgroundColor: AppColors.latarLembut(AppColors.info),
              ),
            ),
            const SizedBox(height: 6),
            Text(
                '${(rasio * 100).toStringAsFixed(0)}% aktivitas berada pada status closing.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _tabel() {
    final barisTerfilter = _barisTerfilter;
    if (barisTerfilter.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(
              child: Text(
                  'Belum ada aktivitas jurnal pada kelompok dan rentang ini.')),
        ),
      );
    }
    return AppDataTable(
      minWidth: 900,
      columns: const [
        AppTableColumn('Nama Jurnal', width: 260),
        AppTableColumn('Draft', width: 90, align: TextAlign.right),
        AppTableColumn('Terposting', width: 110, align: TextAlign.right),
        AppTableColumn('Closing', width: 90, align: TextAlign.right),
        AppTableColumn('Uraian'),
        AppTableColumn('Aksi', width: 80, align: TextAlign.center),
      ],
      rows: barisTerfilter
          .map((b) => AppTableRowData(cells: [
                AppTableCell(
                    child: Text('${b['nama'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                AppTableCell(child: _angkaSel(b, 'draft', AppColors.warning)),
                AppTableCell(child: _angkaSel(b, 'posting', AppColors.success)),
                AppTableCell(child: _angkaSel(b, 'closing', AppColors.info)),
                AppTableCell(
                    child: Text('${b['keterangan'] ?? ''}',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context)))),
                AppTableCell(child: _aksiBaris(b)),
              ]))
          .toList(),
    );
  }

  /// Angka yang bernilai > 0 dapat diketuk untuk membuka daftar dokumen di baliknya.
  /// Angka nol sengaja tidak dibuat seperti tautan supaya tidak ada janji kosong.
  /// Tombol posting massal per modul.
  ///
  /// Hanya muncul bila server menyatakan modulnya memang punya mesin posting
  /// (`bisaPosting`) DAN pengguna ini berhak memposting modul tersebut
  /// (`bolehPosting`). Menawarkan tombol untuk modul yang ujungnya menolak sama
  /// saja dengan menjanjikan sesuatu yang tidak ada.
  ///
  /// Kedua sebab itu dipisah karena berbeda di mata pengguna: dasbor ini memuat
  /// belasan modul dengan kunci menu berbeda-beda, dan mengatakan "belum
  /// tersedia" kepada orang yang sebenarnya hanya tidak berhak adalah keterangan
  /// yang salah -- ia akan melaporkannya sebagai kerusakan.
  Widget _aksiBaris(Map<String, dynamic> baris) {
    if (baris['bisaPosting'] != true) {
      return Tooltip(
        message: 'Posting massal modul ini belum tersedia dari aplikasi.',
        child: Icon(Icons.remove,
            size: 16, color: AppColors.textSecondaryOf(context)),
      );
    }
    if (baris['bolehPosting'] == false) {
      return Tooltip(
        message: 'Grup pengguna Anda tidak berhak memposting jurnal '
            '${baris['nama'] ?? 'modul ini'}.',
        child: Icon(Icons.lock_outline,
            size: 16, color: AppColors.textSecondaryOf(context)),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Posting / batalkan posting',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (pilihan) => _jalankanPosting(baris, pilihan == 'posting'),
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'posting',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.playlist_add_check),
            title: Text('Posting semua draft'),
          ),
        ),
        PopupMenuItem<String>(
          value: 'batal',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.undo),
            title: Text('Batalkan posting'),
          ),
        ),
      ],
    );
  }

  Future<void> _jalankanPosting(
      Map<String, dynamic> baris, bool posting) async {
    final nama = '${baris['nama'] ?? ''}';
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
            posting ? 'Konfirmasi Posting' : 'Konfirmasi Batalkan Posting'),
        content: Text(posting
            ? 'Posting SEMUA draft jurnal "$nama" pada periode terpilih?'
            : 'Batalkan posting jurnal "$nama"? Jurnal yang SUDAH closing tidak akan dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(posting ? 'Posting' : 'Batalkan')),
        ],
      ),
    );
    if (setuju != true) return;

    try {
      final hasil = await ApiClient.instance.aksi(
        posting ? 'draft_jurnal_posting' : 'draft_jurnal_batal_posting',
        {
          'nama': nama,
          'mulai': _tanggalIso.format(_mulai),
          'sampai': _tanggalIso.format(_sampai),
        },
      );
      if (mounted) {
        // Bila ada dokumen yang dilewati, jawabannya menyebut alasannya dan
        // kalimatnya jadi panjang. Diberi waktu baca lebih lama supaya keterangan
        // itu tidak lewat begitu saja -- justru di situlah yang perlu ditindaklanjuti.
        final dilewati = (hasil['dilewati'] as num?)?.toInt() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: Duration(seconds: dilewati > 0 ? 9 : 4),
            content: Text('${hasil['description'] ?? 'Selesai.'}')));
      }
      await _muat();
    } catch (e) {
      if (mounted) snackbarGalat(context, e, aktivitas: 'posting jurnal');
    }
  }

  /// Angka pada satu kolom status.
  ///
  /// Garis bawah di sini adalah JANJI: angka ini dapat diketuk untuk melihat
  /// dokumen di baliknya. Tidak semua baris dapat menepatinya -- "Posting HPP"
  /// diposting per periode, bukan per dokumen, sehingga tidak ada daftar yang
  /// jujur bisa ditampilkan. Server sudah menyebutkan itu lewat `bisaRincian`,
  /// tetapi layar ini dulu mengabaikannya dan tetap menggarisbawahi angkanya:
  /// pengguna mengetuk, lalu menerima lembar merah berisi penolakan.
  ///
  /// Sekarang baris tanpa rincian tampil TANPA garis bawah, dan ketukannya
  /// menerangkan sebabnya secara lokal -- tanpa memanggil server untuk sesuatu
  /// yang sudah pasti ditolak.
  Widget _angkaSel(Map<String, dynamic> baris, String status, Color warna) {
    final n = (baris[status] as num?)?.toInt() ?? 0;
    // Bawaan `true`: peladen lama belum mengirim bendera ini, dan memadamkan
    // seluruh rincian karena benderanya absen jauh lebih merugikan daripada
    // sesekali menawarkan ketukan yang ditolak.
    final bisaRincian = baris['bisaRincian'] != false;
    final teks = Text(
      _angka.format(n),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w400,
        color: n > 0 ? warna : AppColors.textSecondaryOf(context),
        decoration: n > 0 && bisaRincian ? TextDecoration.underline : null,
        decorationColor: warna,
      ),
    );
    if (n == 0) return teks;
    return InkWell(
      onTap: bisaRincian
          ? () => _bukaRincian(baris, status)
          : () => _terangkanTanpaRincian(baris),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4), child: teks),
    );
  }

  /// Menerangkan kenapa satu baris tidak punya daftar dokumen.
  ///
  /// Kalimatnya datang dari server (`alasanTanpaRincian`) supaya sama persis
  /// dengan pesan penolakan `draft_jurnal_rincian` -- dua penjelasan berbeda
  /// untuk hal yang sama justru membuat pengguna ragu mana yang benar. Kalimat
  /// cadangan hanya dipakai bila peladennya belum mengirimkannya.
  Future<void> _terangkanTanpaRincian(Map<String, dynamic> baris) async {
    final nama = '${baris['nama'] ?? ''}';
    final alasan = '${baris['alasanTanpaRincian'] ?? ''}'.trim();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(nama),
        content: Text(alasan.isNotEmpty
            ? alasan
            : '"$nama" tidak memiliki daftar dokumen yang dapat dirinci.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mengerti')),
        ],
      ),
    );
  }

  Future<void> _bukaRincian(Map<String, dynamic> baris, String status) async {
    final nama = '${baris['nama'] ?? ''}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RincianDraftJurnal(
        nama: nama,
        status: status,
        mulai: _tanggalIso.format(_mulai),
        sampai: _tanggalIso.format(_sampai),
      ),
    );
  }
}

/// Daftar dokumen di balik satu angka dasbor.
///
/// Dibangun server dari KRITERIA YANG SAMA dengan angkanya (`draft_jurnal_rincian`),
/// jadi jumlah baris di sini tidak akan berselisih dengan angka yang barusan diketuk.
class _RincianDraftJurnal extends StatefulWidget {
  final String nama;
  final String status;
  final String mulai;
  final String sampai;

  const _RincianDraftJurnal({
    required this.nama,
    required this.status,
    required this.mulai,
    required this.sampai,
  });

  @override
  State<_RincianDraftJurnal> createState() => _RincianDraftJurnalState();
}

class _RincianDraftJurnalState extends State<_RincianDraftJurnal>
    with JejakGalat {
  static final _rupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  String? _pesanError;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _muat();
  }

  String get _judulStatus => widget.status == 'draft'
      ? 'Draft (belum diposting)'
      : widget.status == 'posting'
          ? 'Terposting'
          : 'Closing';

  double _angka(dynamic nilai) =>
      nilai is num ? nilai.toDouble() : double.tryParse('${nilai ?? ''}') ?? 0;

  List<Map<String, dynamic>> _barisJurnal(Map<String, dynamic> dokumen) =>
      ((dokumen['jurnal'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Widget _nilaiJurnal(double nilai, {bool tebal = false}) => SizedBox(
        width: 112,
        child: Text(
          nilai == 0 ? '-' : _rupiah.format(nilai),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 12,
            fontWeight: tebal ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      );

  Widget _kartuJurnal(Map<String, dynamic> dokumen) {
    final jurnal = _barisJurnal(dokumen);
    final totalDebet = _angka(dokumen['totalDebet']);
    final totalKredit = _angka(dokumen['totalKredit']);
    final seimbang = dokumen['jurnalSeimbang'] == true && jurnal.isNotEmpty;
    final uraian = '${dokumen['uraian'] ?? ''}'.trim();
    final pesan = '${dokumen['pesanJurnal'] ?? ''}'.trim();
    final warnaGaris = Theme.of(context).dividerColor;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: warnaGaris),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uraian.isEmpty ? '(tanpa keterangan)' : uraian,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${dokumen['tanggal'] ?? '-'}  •  Referensi ${dokumen['id'] ?? '-'}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _rupiah.format(_angka(dokumen['nilai'])),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (jurnal.isEmpty)
              AppInfoBanner(
                icon: Icons.account_balance_outlined,
                color: AppColors.warning,
                text: pesan.isEmpty
                    ? 'Preview jurnal belum tersedia untuk dokumen ini.'
                    : pesan,
              )
            else ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('AKUN',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(
                      width: 112,
                      child: Text('DEBET',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(
                      width: 112,
                      child: Text('KREDIT',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              for (final baris in jurnal)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          [
                            '${baris['kodeAkun'] ?? ''}'.trim(),
                            '${baris['namaAkun'] ?? ''}'.trim(),
                          ].where((e) => e.isNotEmpty).join(' — '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      _nilaiJurnal(_angka(baris['debet'])),
                      _nilaiJurnal(_angka(baris['kredit'])),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            seimbang ? Icons.check_circle : Icons.error_outline,
                            size: 16,
                            color:
                                seimbang ? AppColors.success : AppColors.danger,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            seimbang
                                ? 'Jurnal seimbang'
                                : 'Jurnal tidak seimbang',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: seimbang
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _nilaiJurnal(totalDebet, tebal: true),
                    _nilaiJurnal(totalKredit, tebal: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _muat() async {
    try {
      final hasil = await ApiClient.instance.aksi('draft_jurnal_rincian', {
        'nama': widget.nama,
        'status': widget.status,
        'mulai': widget.mulai,
        'sampai': widget.sampai,
        'limit': 200,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.nama,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text('$_judulStatus  •  ${widget.mulai} s.d. ${widget.sampai}',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 12),
            if (_pesanError != null)
              AppInfoBanner(
                icon: Icons.error_outline,
                color: AppColors.danger,
                text: _pesanError!,
                detail: detailUntuk(_pesanError),
              ),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _data.isEmpty && _pesanError == null
                      ? const Center(
                          child: Text('Tidak ada dokumen pada status ini.'))
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _data.length,
                          itemBuilder: (context, i) => _kartuJurnal(_data[i]),
                        ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
