import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../widgets/app_components.dart';
import '../widgets/pemilih_akun.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';

/// Layar siklus akuntansi: **Saldo Awal**, **Jurnal Penyesuaian Berkala**, dan **Tutup Buku**.
///
/// Ketiganya adalah proses yang sebelumnya tidak ada sama sekali, padahal menentukan benar
/// tidaknya Neraca, Buku Besar, dan Neraca Saldo:
/// * tanpa **saldo awal**, laporan selalu berangkat dari nol sehingga kas/persediaan/utang/modal
///   yang sudah ada sebelum sistem dipakai tidak pernah muncul;
/// * tanpa **penyesuaian berkala**, amortisasi/akrual/penyisihan hanya bisa diketik manual tiap
///   bulan dan mudah terlewat;
/// * tanpa **tutup buku**, akun Laba Ditahan tak pernah terisi dan laba antar tahun bercampur.
///
/// Perhitungan seluruhnya di server (aksi `saldo_awal_*`, `penyesuaian_*`, `tutup_buku_*`);
/// layar ini hanya menyajikan draf lebih dulu, lalu memposting setelah disetujui.
class SiklusAkuntansiScreen extends StatefulWidget {
  const SiklusAkuntansiScreen({super.key, this.tabAwal = 0});

  /// 0 Saldo Awal, 1 Jurnal Penyesuaian, 2 Tutup Buku.
  final int tabAwal;

  @override
  State<SiklusAkuntansiScreen> createState() => _SiklusAkuntansiScreenState();
}

class _SiklusAkuntansiScreenState extends State<SiklusAkuntansiScreen>
    with SingleTickerProviderStateMixin, JejakGalat {
  static final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _fmtBulan = DateFormat('yyyy-MM');
  static final NumberFormat _uang = NumberFormat.decimalPattern('id');

  late final TabController _tab;
  bool _sibuk = false;
  String? _galat;

  // --- saldo awal
  List<Map<String, dynamic>> _saldoAwal = [];
  Map<String, dynamic>? _drafSaldoAwal;

  // --- penyesuaian
  List<Map<String, dynamic>> _template = [];
  Map<String, dynamic>? _drafPenyesuaian;
  DateTime _periode = DateTime.now();

  // --- tutup buku
  DateTime _tbMulai = DateTime(DateTime.now().year, 1, 1);
  DateTime _tbSampai = DateTime(DateTime.now().year, 12, 31);
  Map<String, dynamic>? _drafTutupBuku;

  List<Map<String, dynamic>> _akun = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: widget.tabAwal);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setStateIfMounted(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _muatSemua());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final sa = await ApiClient.instance.aksi('saldo_awal_daftar', {});
      final tp = await ApiClient.instance.aksi('penyesuaian_template_daftar', {});
      final ak = await ApiClient.instance.aksi('akun_list', {'limit': 2000});
      if (!mounted) return;
      setStateIfMounted(() {
        _saldoAwal = ((sa['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _template = ((tp['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _akun = ((ak['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = terapkanGalat(e));
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  Future<Map<String, dynamic>?> _aksi(String nama, Map<String, dynamic> body) async {
    setStateIfMounted(() {
      _sibuk = true;
      _galat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi(nama, body);
      return Map<String, dynamic>.from(hasil);
    } catch (e) {
      if (mounted) setStateIfMounted(() => _galat = terapkanGalat(e));
      return null;
    } finally {
      setStateIfMounted(() => _sibuk = false);
    }
  }

  void _pesan(String teks) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(teks)));
  }

  Future<bool> _konfirmasi(String judul, String isi) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(judul),
        content: Text(isi),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('Lanjut')),
        ],
      ),
    );
    return ya == true;
  }

  // ==================================================================== saldo awal

  Future<void> _formSaldoAwal([Map<String, dynamic>? baris]) async {
    int? akunId;
    final kodeAwal = '${baris?['kodeAkun'] ?? ''}';
    for (final a in _akun) {
      if ('${a['kode'] ?? ''}' == kodeAwal) akunId = (a['id'] as num?)?.toInt();
    }
    final debet = TextEditingController(
        text: ((baris?['debet'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    final kredit = TextEditingController(
        text: ((baris?['kredit'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    final ket = TextEditingController(text: '${baris?['keterangan'] ?? ''}');
    DateTime tanggal = DateTime.now();

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(baris == null ? 'Tambah Saldo Awal' : 'Ubah Saldo Awal'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                PemilihAkunField(
                  label: 'Akun',
                  daftar: _akun,
                  nilai: akunId,
                  onChanged: (v) => setDialog(() => akunId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: debet,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Debet')),
                const SizedBox(height: 12),
                TextField(
                    controller: kredit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Kredit')),
                const SizedBox(height: 12),
                TextField(
                    controller: ket,
                    decoration: const InputDecoration(labelText: 'Keterangan')),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final t = await showDatePicker(
                          context: c,
                          initialDate: tanggal,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (t != null) setDialog(() => tanggal = t);
                    },
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Tanggal pembukaan ${_fmt.format(tanggal)}'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) return;
    String kode = '';
    for (final a in _akun) {
      if ((a['id'] as num?)?.toInt() == akunId) kode = '${a['kode'] ?? ''}';
    }
    if (kode.isEmpty) {
      _pesan('Akun belum dipilih.');
      return;
    }
    final hasil = await _aksi('saldo_awal_simpan', {
      'kodeAkun': kode,
      'debet': double.tryParse(debet.text.trim()) ?? 0,
      'kredit': double.tryParse(kredit.text.trim()) ?? 0,
      'keterangan': ket.text.trim(),
      'tanggal': _fmt.format(tanggal),
    });
    if (hasil != null) _pesan('${hasil['message'] ?? 'Tersimpan.'}');
    await _muatSemua();
  }

  Future<void> _hapusSaldoAwal(Map<String, dynamic> baris) async {
    if (!await _konfirmasi('Hapus baris saldo awal?',
        'Baris ${baris['kodeAkun']} akan dihapus. Baris yang sudah diposting tidak dapat dihapus.')) {
      return;
    }
    final hasil = await _aksi('saldo_awal_hapus', {'id': baris['id']});
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    await _muatSemua();
  }

  Future<void> _unggahSaldoAwal() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ['xlsx'], withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.single;
    final raw = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    if (raw == null) {
      _pesan('Berkas Excel tidak dapat dibaca.');
      return;
    }
    final rows = readSimpleXlsx(Uint8List.fromList(raw));
    final baris = <Map<String, dynamic>>[];
    for (final r in rows.skip(1)) {
      final b = r.map((e) => e.trim()).toList();
      if (b.every((e) => e.isEmpty)) continue;
      baris.add({
        'kodeAkun': b.isNotEmpty ? b[0] : '',
        'debet': b.length > 2 ? b[2] : '0',
        'kredit': b.length > 3 ? b[3] : '0',
        'keterangan': b.length > 4 ? b[4] : '',
      });
    }
    if (baris.isEmpty) {
      _pesan('Tidak ada baris berisi di berkas itu.');
      return;
    }
    if (!await _konfirmasi('Unggah ${baris.length} baris saldo awal?',
        'Baris yang belum ada akan dibuat, yang sudah ada diperbarui. Baris yang sudah '
        'diposting dilewati. Kolom: Kode Akun, Nama, Debet, Kredit, Keterangan.')) {
      return;
    }
    final hasil = await _aksi('saldo_awal_impor',
        {'baris': baris, 'tanggal': _fmt.format(DateTime.now())});
    if (hasil != null) {
      final masalah = ((hasil['masalah'] as List?) ?? []).map((e) => '$e').toList();
      _pesan('${hasil['message'] ?? ''}'
          '${masalah.isEmpty ? '' : ' Contoh masalah: ${masalah.first}'}');
    }
    await _muatSemua();
  }

  Future<void> _unduhContohSaldoAwal() async {
    final bytes = buildSimpleXlsx(
      sheetName: 'Saldo Awal',
      headers: const ['Kode Akun', 'Nama Akun', 'Debet', 'Kredit', 'Keterangan'],
      rows: _saldoAwal
          .map((s) => [
                '${s['kodeAkun'] ?? ''}',
                '${s['namaAkun'] ?? ''}',
                (s['debet'] as num?)?.toStringAsFixed(0) ?? '0',
                (s['kredit'] as num?)?.toStringAsFixed(0) ?? '0',
                '${s['keterangan'] ?? ''}',
              ])
          .toList(),
    );
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Saldo Awal',
        fileName: 'Saldo_Awal_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes);
    if (path != null) await File(path).writeAsBytes(bytes);
  }

  Future<void> _drafSaldo() async {
    final hasil = await _aksi('saldo_awal_draft', {});
    if (hasil != null) setStateIfMounted(() => _drafSaldoAwal = hasil);
  }

  Future<void> _postingSaldo() async {
    final d = _drafSaldoAwal;
    if (d == null) {
      await _drafSaldo();
      return;
    }
    if (d['siap'] != true) {
      _pesan('${d['alasan'] ?? 'Belum siap diposting.'}');
      return;
    }
    if (!await _konfirmasi('Posting jurnal pembukaan?',
        'Seluruh saldo awal yang belum diposting akan dijurnal sekali. Selisih debet-kredit '
        'ditempatkan pada akun Modal/Ekuitas Awal. Setelah diposting, koreksi hanya lewat '
        'jurnal penyesuaian.')) {
      return;
    }
    final hasil = await _aksi('saldo_awal_posting', {});
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    setStateIfMounted(() => _drafSaldoAwal = null);
    await _muatSemua();
  }

  // ==================================================================== penyesuaian

  Future<void> _formTemplate([Map<String, dynamic>? t]) async {
    final nama = TextEditingController(text: '${t?['nama'] ?? ''}');
    final nilai = TextEditingController(
        text: ((t?['nilai'] as num?)?.toDouble() ?? 0).toStringAsFixed(0));
    final ket = TextEditingController(text: '${t?['keterangan'] ?? ''}');
    int? debetId;
    int? kreditId;
    for (final a in _akun) {
      final kode = '${a['kode'] ?? ''}';
      if (kode == '${t?['akunDebetKode'] ?? ''}') debetId = (a['id'] as num?)?.toInt();
      if (kode == '${t?['akunKreditKode'] ?? ''}') kreditId = (a['id'] as num?)?.toInt();
    }
    String frekuensi = '${t?['frekuensi'] ?? 'BULANAN'}';
    bool aktif = t == null ? true : t['aktif'] != false;

    final simpan = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(t == null ? 'Tambah Template Penyesuaian' : 'Ubah Template'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nama,
                    decoration: const InputDecoration(
                        labelText: 'Nama *',
                        hintText: 'mis. Amortisasi Sewa Dibayar Dimuka')),
                const SizedBox(height: 12),
                PemilihAkunField(
                    label: 'Akun Debet',
                    daftar: _akun,
                    nilai: debetId,
                    onChanged: (v) => setDialog(() => debetId = v)),
                const SizedBox(height: 12),
                PemilihAkunField(
                    label: 'Akun Kredit',
                    daftar: _akun,
                    nilai: kreditId,
                    onChanged: (v) => setDialog(() => kreditId = v)),
                const SizedBox(height: 12),
                TextField(
                    controller: nilai,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Nilai per periode')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: frekuensi,
                  decoration: const InputDecoration(labelText: 'Frekuensi'),
                  items: const [
                    DropdownMenuItem(value: 'BULANAN', child: Text('Bulanan')),
                    DropdownMenuItem(
                        value: 'TAHUNAN', child: Text('Tahunan (diposting di Desember)')),
                  ],
                  onChanged: (v) => setDialog(() => frekuensi = v ?? 'BULANAN'),
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: ket,
                    decoration: const InputDecoration(labelText: 'Keterangan')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: aktif,
                  onChanged: (v) => setDialog(() => aktif = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    if (simpan != true || !mounted) return;
    String kodeDebet = '';
    String kodeKredit = '';
    for (final a in _akun) {
      if ((a['id'] as num?)?.toInt() == debetId) kodeDebet = '${a['kode'] ?? ''}';
      if ((a['id'] as num?)?.toInt() == kreditId) kodeKredit = '${a['kode'] ?? ''}';
    }
    final hasil = await _aksi('penyesuaian_template_simpan', {
      if (t != null) 'id': t['id'],
      'nama': nama.text.trim(),
      'akunDebetKode': kodeDebet,
      'akunKreditKode': kodeKredit,
      'nilai': double.tryParse(nilai.text.trim()) ?? 0,
      'frekuensi': frekuensi,
      'aktif': aktif,
      'keterangan': ket.text.trim(),
    });
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    await _muatSemua();
  }

  Future<void> _hapusTemplate(Map<String, dynamic> t) async {
    if (!await _konfirmasi('Hapus template?',
        'Template "${t['nama']}" dihapus. Jurnal yang terlanjur terbentuk tetap tersimpan.')) {
      return;
    }
    final hasil = await _aksi('penyesuaian_template_hapus', {'id': t['id']});
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    await _muatSemua();
  }

  Future<void> _drafPenyesuaianJalan() async {
    final hasil = await _aksi(
        'penyesuaian_draft', {'periode': _fmtBulan.format(_periode)});
    if (hasil != null) setStateIfMounted(() => _drafPenyesuaian = hasil);
  }

  Future<void> _postingPenyesuaian(List<dynamic> ids) async {
    if (!await _konfirmasi('Posting jurnal penyesuaian?',
        'Template yang siap akan dijurnal untuk periode ${_fmtBulan.format(_periode)}. '
        'Satu template hanya bisa diposting sekali per periode.')) {
      return;
    }
    final hasil = await _aksi('penyesuaian_posting', {
      'periode': _fmtBulan.format(_periode),
      if (ids.isNotEmpty) 'posting_ids': ids,
    });
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    await _drafPenyesuaianJalan();
  }

  // ==================================================================== tutup buku

  Future<void> _drafTutup() async {
    final hasil = await _aksi('tutup_buku_draft', {
      'mulai': _fmt.format(_tbMulai),
      'sampai': _fmt.format(_tbSampai),
    });
    if (hasil != null) setStateIfMounted(() => _drafTutupBuku = hasil);
  }

  Future<void> _postingTutup() async {
    final d = _drafTutupBuku;
    if (d == null) {
      await _drafTutup();
      return;
    }
    if (d['siap'] != true) {
      _pesan('${d['alasan'] ?? 'Belum siap.'}');
      return;
    }
    if (!await _konfirmasi('Tutup buku periode ini?',
        'Seluruh akun pendapatan & beban pada periode ini dinolkan dan laba/rugi bersihnya '
        'dipindahkan ke Laba Ditahan. Periode yang sudah ditutup tidak bisa ditutup lagi.')) {
      return;
    }
    final hasil = await _aksi('tutup_buku_posting', {
      'mulai': _fmt.format(_tbMulai),
      'sampai': _fmt.format(_tbSampai),
    });
    if (hasil != null) _pesan('${hasil['message'] ?? ''}');
    await _drafTutup();
  }

  // ==================================================================== tampilan

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tab, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: 'Saldo Awal'),
        Tab(text: 'Jurnal Penyesuaian'),
        Tab(text: 'Tutup Buku'),
      ]),
      if (_galat != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_galat!, style: const TextStyle(color: Colors.red)),
            AppDetailGalatOpsional(detail: detailUntuk(_galat)),
          ]),
        ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _tabSaldoAwal(),
          _tabPenyesuaian(),
          _tabTutupBuku(),
        ]),
      ),
    ]);
  }

  Widget _bar(List<Widget> anak) => Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          ...anak,
          if (_sibuk)
            const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      );

  Widget _tabSaldoAwal() {
    final d = _drafSaldoAwal;
    return Column(children: [
      _bar([
        FilledButton.icon(
            onPressed: _sibuk ? null : () => _formSaldoAwal(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah Akun')),
        OutlinedButton.icon(
            onPressed: _sibuk ? null : _unduhContohSaldoAwal,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Download Excel')),
        OutlinedButton.icon(
            onPressed: _sibuk ? null : _unggahSaldoAwal,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Upload Excel')),
        OutlinedButton.icon(
            onPressed: _sibuk ? null : _drafSaldo,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Lihat Draf Jurnal')),
        FilledButton.icon(
            onPressed: _sibuk ? null : _postingSaldo,
            icon: const Icon(Icons.post_add, size: 18),
            label: const Text('Posting Jurnal Pembukaan')),
      ]),
      if (d != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${d['message'] ?? ''}'
                '${d['selisihKeModal'] == null ? '' : '  •  Selisih ke ${d['akunModal']}: '
                    '${_uang.format((d['selisihKeModal'] as num).toDouble())}'}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      Expanded(
        child: AppDataTable(
          minWidth: 860,
          emptyText: 'Belum ada saldo awal. Tambahkan per akun atau unggah dari Excel.',
          columns: const [
            AppTableColumn('Kode', flex: 2),
            AppTableColumn('Nama Akun', flex: 4),
            AppTableColumn('Debet', flex: 2, align: TextAlign.right),
            AppTableColumn('Kredit', flex: 2, align: TextAlign.right),
            AppTableColumn('Status', flex: 2),
            AppTableColumn('Aksi', flex: 2),
          ],
          rows: _saldoAwal.map((s) {
            final sudah = s['sudahDiposting'] == true;
            return AppTableRowData(cells: [
              AppTableCell.text('${s['kodeAkun'] ?? ''}', flex: 2),
              AppTableCell.text('${s['namaAkun'] ?? ''}', flex: 4),
              AppTableCell.text(_uang.format((s['debet'] as num?)?.toDouble() ?? 0),
                  flex: 2, align: TextAlign.right),
              AppTableCell.text(_uang.format((s['kredit'] as num?)?.toDouble() ?? 0),
                  flex: 2, align: TextAlign.right),
              AppTableCell.text(sudah ? 'Sudah diposting' : 'Belum diposting', flex: 2),
              AppTableCell(
                flex: 2,
                child: sudah
                    ? const SizedBox.shrink()
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            tooltip: 'Ubah',
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: _sibuk ? null : () => _formSaldoAwal(s)),
                        IconButton(
                            tooltip: 'Hapus',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: _sibuk ? null : () => _hapusSaldoAwal(s)),
                      ]),
              ),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _tabPenyesuaian() {
    final d = _drafPenyesuaian;
    final rincian =
        ((d?['rincian'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Column(children: [
      _bar([
        FilledButton.icon(
            onPressed: _sibuk ? null : () => _formTemplate(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah Template')),
        OutlinedButton.icon(
          onPressed: _sibuk
              ? null
              : () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: _periode,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (t != null) {
                    setStateIfMounted(() => _periode = t);
                    await _drafPenyesuaianJalan();
                  }
                },
          icon: const Icon(Icons.event, size: 18),
          label: Text('Periode ${_fmtBulan.format(_periode)}'),
        ),
        OutlinedButton.icon(
            onPressed: _sibuk ? null : _drafPenyesuaianJalan,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Lihat Draf')),
        FilledButton.icon(
            onPressed: _sibuk ? null : () => _postingPenyesuaian(const []),
            icon: const Icon(Icons.post_add, size: 18),
            label: const Text('Posting Semua yang Siap')),
      ]),
      if (d != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${d['message'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall)),
        ),
      Expanded(
        child: rincian.isEmpty
            ? AppDataTable(
                minWidth: 900,
                emptyText:
                    'Belum ada template. Tambahkan sekali, lalu tiap periode cukup diposting.',
                columns: const [
                  AppTableColumn('Nama', flex: 4),
                  AppTableColumn('Debet', flex: 3),
                  AppTableColumn('Kredit', flex: 3),
                  AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                  AppTableColumn('Frekuensi', flex: 2),
                  AppTableColumn('Aksi', flex: 2),
                ],
                rows: _template
                    .map((t) => AppTableRowData(cells: [
                          AppTableCell.text('${t['nama'] ?? ''}', flex: 4),
                          AppTableCell.text('${t['akunDebet'] ?? ''}', flex: 3),
                          AppTableCell.text('${t['akunKredit'] ?? ''}', flex: 3),
                          AppTableCell.text(
                              _uang.format((t['nilai'] as num?)?.toDouble() ?? 0),
                              flex: 2,
                              align: TextAlign.right),
                          AppTableCell.text(
                              '${t['frekuensi'] ?? ''}${t['aktif'] == false ? ' (nonaktif)' : ''}',
                              flex: 2),
                          AppTableCell(
                            flex: 2,
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  tooltip: 'Ubah',
                                  icon: const Icon(Icons.edit, size: 18),
                                  onPressed: _sibuk ? null : () => _formTemplate(t)),
                              IconButton(
                                  tooltip: 'Hapus',
                                  icon: const Icon(Icons.delete_outline, size: 18),
                                  onPressed: _sibuk ? null : () => _hapusTemplate(t)),
                            ]),
                          ),
                        ]))
                    .toList(),
              )
            : AppDataTable(
                minWidth: 900,
                emptyText: 'Tidak ada template.',
                columns: const [
                  AppTableColumn('Nama', flex: 4),
                  AppTableColumn('Debet', flex: 3),
                  AppTableColumn('Kredit', flex: 3),
                  AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
                  AppTableColumn('Status', flex: 4),
                  AppTableColumn('Aksi', flex: 2),
                ],
                rows: rincian.map((r) {
                  final bisa = r['siap'] == true;
                  return AppTableRowData(cells: [
                    AppTableCell.text('${r['nama'] ?? ''}', flex: 4),
                    AppTableCell.text('${r['debet'] ?? ''}', flex: 3),
                    AppTableCell.text('${r['kredit'] ?? ''}', flex: 3),
                    AppTableCell.text(_uang.format((r['nilai'] as num?)?.toDouble() ?? 0),
                        flex: 2, align: TextAlign.right),
                    AppTableCell.text(
                        bisa ? 'Siap diposting' : '${r['alasan'] ?? ''}', flex: 4),
                    AppTableCell(
                      flex: 2,
                      child: bisa
                          ? TextButton(
                              onPressed:
                                  _sibuk ? null : () => _postingPenyesuaian([r['id']]),
                              child: const Text('Posting'))
                          : const SizedBox.shrink(),
                    ),
                  ]);
                }).toList(),
              ),
      ),
    ]);
  }

  Widget _tabTutupBuku() {
    final d = _drafTutupBuku;
    final rincian =
        ((d?['rincian'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Column(children: [
      _bar([
        OutlinedButton.icon(
          onPressed: _sibuk
              ? null
              : () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: _tbMulai,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (t != null) setStateIfMounted(() => _tbMulai = t);
                },
          icon: const Icon(Icons.event, size: 18),
          label: Text('Mulai ${_fmt.format(_tbMulai)}'),
        ),
        OutlinedButton.icon(
          onPressed: _sibuk
              ? null
              : () async {
                  final t = await showDatePicker(
                      context: context,
                      initialDate: _tbSampai,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (t != null) setStateIfMounted(() => _tbSampai = t);
                },
          icon: const Icon(Icons.event_available, size: 18),
          label: Text('Sampai ${_fmt.format(_tbSampai)}'),
        ),
        OutlinedButton.icon(
            onPressed: _sibuk ? null : _drafTutup,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Lihat Draf')),
        FilledButton.icon(
            onPressed: _sibuk ? null : _postingTutup,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Tutup Buku')),
      ]),
      if (d != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${d['message'] ?? ''}'
                '${d['labaBersih'] == null ? '' : '  •  Laba bersih: '
                    '${_uang.format((d['labaBersih'] as num).toDouble())} → ${d['akunLabaDitahan']}'}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
      Expanded(
        child: AppDataTable(
          minWidth: 760,
          emptyText: 'Tekan "Lihat Draf" untuk melihat akun apa saja yang akan ditutup.',
          columns: const [
            AppTableColumn('Kode', flex: 2),
            AppTableColumn('Nama Akun', flex: 5),
            AppTableColumn('Sisi Penutup', flex: 4),
            AppTableColumn('Nilai', flex: 2, align: TextAlign.right),
          ],
          rows: rincian
              .map((r) => AppTableRowData(cells: [
                    AppTableCell.text('${r['kodeAkun'] ?? ''}', flex: 2),
                    AppTableCell.text('${r['namaAkun'] ?? ''}', flex: 5),
                    AppTableCell.text('${r['sisi'] ?? ''}', flex: 4),
                    AppTableCell.text(_uang.format((r['nilai'] as num?)?.toDouble() ?? 0),
                        flex: 2, align: TextAlign.right),
                  ]))
              .toList(),
        ),
      ),
    ]);
  }
}
