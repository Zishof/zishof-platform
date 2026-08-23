import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
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
  String? _pesanError;
  List<Map<String, dynamic>> _baris = [];
  int _draft = 0;
  int _posting = 0;
  int _closing = 0;

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

  int get _total => _draft + _posting + _closing;

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
            const Text('Tanggal', style: TextStyle(fontWeight: FontWeight.w600)),
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
          ],
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
        _kartu('Draft', _draft, 'Belum diposting', AppColors.warning),
        _kartu('Terposting', _posting, 'Sudah menjadi jurnal', AppColors.success),
        _kartu('Closing', _closing, 'Sudah dikunci periode', AppColors.info),
        _kartu('Total Aktivitas', _total, 'Semua status', AppColors.primary),
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
    final rasio = _total == 0 ? 0.0 : _closing / _total;
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
            Text('${(rasio * 100).toStringAsFixed(0)}% aktivitas berada pada status closing.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondaryOf(context))),
          ],
        ),
      ),
    );
  }

  Widget _tabel() {
    if (_baris.isEmpty) {
      return const Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text('Belum ada aktivitas jurnal pada rentang ini.')),
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
      rows: _baris
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
  /// (`bisaPosting`). Menawarkan tombol untuk modul yang ujungnya menolak sama
  /// saja dengan menjanjikan sesuatu yang tidak ada.
  Widget _aksiBaris(Map<String, dynamic> baris) {
    if (baris['bisaPosting'] != true) {
      return Tooltip(
        message: 'Posting massal modul ini belum tersedia dari aplikasi.',
        child: Icon(Icons.remove,
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

  Future<void> _jalankanPosting(Map<String, dynamic> baris, bool posting) async {
    final nama = '${baris['nama'] ?? ''}';
    final setuju = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(posting ? 'Konfirmasi Posting' : 'Konfirmasi Batalkan Posting'),
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

  Widget _angkaSel(Map<String, dynamic> baris, String status, Color warna) {
    final n = (baris[status] as num?)?.toInt() ?? 0;
    final teks = Text(
      _angka.format(n),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: n > 0 ? FontWeight.w700 : FontWeight.w400,
        color: n > 0 ? warna : AppColors.textSecondaryOf(context),
        decoration: n > 0 ? TextDecoration.underline : null,
        decorationColor: warna,
      ),
    );
    if (n == 0) return teks;
    return InkWell(
      onTap: () => _bukaRincian(baris, status),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4), child: teks),
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
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _data.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final d = _data[i];
                            final nilai = (d['nilai'] as num?)?.toDouble() ?? 0;
                            return ListTile(
                              dense: true,
                              title: Text(
                                  '${d['uraian'] ?? ''}'.trim().isEmpty
                                      ? '(tanpa keterangan)'
                                      : '${d['uraian']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${d['tanggal'] ?? '-'}   •   id ${d['id'] ?? '-'}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Text(_rupiah.format(nilai),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            );
                          },
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
