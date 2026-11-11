import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/simple_xlsx.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import 'app_components.dart';
import 'safe_state.dart';

final _fmtTanggalFile = DateFormat('yyyyMMdd_HHmm');

/// Menampilkan popup/window rincian data universal (95% lebar layar) ketika pengguna
/// mengklik angka pada Dashboard, Kartu KPI, atau sel tabel Laporan.
///
/// Sesuai permintaan manajemen Toko Al-Bahjah & Knowledge Sharing Retail:
/// - Menampilkan daftar rincian data pembentuk angka yang diklik.
/// - Dilengkapi kolom pencarian cepat (filter baris instan).
/// - Dilengkapi tombol **"Download Excel"** (.xlsx) dan **"Cetak PDF"**.
Future<void> tampilkanRincianKlikDialog(
  BuildContext context, {
  required String judul,
  String? subjudul,
  required List<String> kolom,
  required List<List<Object?>> baris,
  String? ringkasanTeks,
  List<Object?>? barisTotal,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogRincianKlik(
      judul: judul,
      subjudul: subjudul,
      kolom: kolom,
      baris: baris,
      ringkasanTeks: ringkasanTeks,
      barisTotal: barisTotal,
    ),
  );
}

class _DialogRincianKlik extends StatefulWidget {
  final String judul;
  final String? subjudul;
  final List<String> kolom;
  final List<List<Object?>> baris;
  final String? ringkasanTeks;
  final List<Object?>? barisTotal;

  const _DialogRincianKlik({
    required this.judul,
    this.subjudul,
    required this.kolom,
    required this.baris,
    this.ringkasanTeks,
    this.barisTotal,
  });

  @override
  State<_DialogRincianKlik> createState() => _DialogRincianKlikState();
}

class _DialogRincianKlikState extends State<_DialogRincianKlik> {
  String _cari = '';
  int _halaman = 1;
  bool _mengekspor = false;
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  List<List<Object?>> get _barisTersaring {
    final q = _cari.trim().toLowerCase();
    if (q.isEmpty) return widget.baris;
    return widget.baris.where((r) {
      for (final cell in r) {
        if ('${cell ?? ''}'.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  List<List<Object?>> _barisHalaman(List<List<Object?>> data) {
    final awal = (_halaman - 1) * kBarisPerHalamanTabel;
    if (awal >= data.length) return const <List<Object?>>[];
    final akhir = (awal + kBarisPerHalamanTabel).clamp(0, data.length);
    return data.sublist(awal, akhir);
  }

  String _namaFileAman(String s) {
    final bersih = s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_').trim();
    return bersih.isEmpty ? 'Rincian_Data' : bersih;
  }

  Future<void> _unduhExcel() async {
    if (_mengekspor) return;
    setStateIfMounted(() => _mengekspor = true);
    try {
      final data = _barisTersaring;
      final semuaBaris = <List<Object?>>[
        ...data,
        if (widget.barisTotal != null) widget.barisTotal!,
      ];
      final bytes = buildSimpleXlsx(
        sheetName: widget.judul,
        headers: widget.kolom,
        rows: semuaBaris,
      );
      final fileName =
          '${_namaFileAman(widget.judul)}_${_fmtTanggalFile.format(DateTime.now())}.xlsx';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Excel ${widget.judul}',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null && path.isNotEmpty) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Berhasil menyimpan Excel: $path')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunduh Excel: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  Future<void> _cetakPdf() async {
    if (_mengekspor) return;
    setStateIfMounted(() => _mengekspor = true);
    try {
      final data = _barisTersaring;
      final semuaBaris = <List<Object?>>[
        ...data,
        if (widget.barisTotal != null) widget.barisTotal!,
      ];
      final doc = pw.Document();
      final landscape = widget.kolom.length >= 6;
      doc.addPage(
        pw.MultiPage(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                widget.judul,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (widget.subjudul != null && widget.subjudul!.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    widget.subjudul!,
                    style: const pw.TextStyle(fontSize: 9.5),
                  ),
                ),
              if (widget.ringkasanTeks != null &&
                  widget.ringkasanTeks!.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text(
                    widget.ringkasanTeks!,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: widget.kolom,
              data: semuaBaris
                  .map((r) => r.map((c) => '${c ?? ''}').toList())
                  .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.blue100),
            ),
          ],
        ),
      );
      await Printing.layoutPdf(
        name:
            '${_namaFileAman(widget.judul)}_${_fmtTanggalFile.format(DateTime.now())}.pdf',
        onLayout: (_) => doc.save(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak PDF: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.95).clamp(360.0, 1680.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(360.0, 980.0);
    final data = _barisTersaring;
    final totalHalaman =
        (data.length / kBarisPerHalamanTabel).ceil().clamp(1, 1 << 30);
    final awalBaris = data.isEmpty ? 0 : (_halaman - 1) * kBarisPerHalamanTabel;
    final dataHalaman = _barisHalaman(data);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.table_view_outlined,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.judul,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (widget.subjudul != null &&
                            widget.subjudul!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              widget.subjudul!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Pilih tindakan rincian',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (aksi) async {
                      switch (aksi) {
                        case 'excel':
                          await _unduhExcel();
                          break;
                        case 'pdf':
                          await _cetakPdf();
                          break;
                        case 'tutup':
                          Navigator.pop(context);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'excel',
                        enabled: !_mengekspor,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.download_outlined),
                          title: Text('Download Excel'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'pdf',
                        enabled: !_mengekspor,
                        child: const ListTile(
                          dense: true,
                          leading: Icon(Icons.picture_as_pdf_outlined),
                          title: Text('Cetak PDF'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem<String>(
                        value: 'tutup',
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.close),
                          title: Text('Tutup'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      hintText: 'Cari di dalam rincian ini...',
                      onChanged: (v) => setStateIfMounted(() {
                        _cari = v;
                        _halaman = 1;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.ringkasanTeks ?? '${data.length} baris rincian',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: data.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada rincian data untuk kriteria ini.',
                          style: TextStyle(
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: AppColors.borderOf(context)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Scrollbar(
                          controller: _vScroll,
                          thumbVisibility: true,
                          trackVisibility: true,
                          child: SingleChildScrollView(
                            controller: _vScroll,
                            child: Scrollbar(
                              controller: _hScroll,
                              thumbVisibility: true,
                              trackVisibility: true,
                              notificationPredicate: (notif) =>
                                  notif.depth == 1,
                              child: SingleChildScrollView(
                                controller: _hScroll,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: dialogWidth - 44,
                                  ),
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      AppColors.pageBgOf(context),
                                    ),
                                    dataRowMinHeight: 38,
                                    dataRowMaxHeight: 52,
                                    columnSpacing: 20,
                                    columns: widget.kolom
                                        .map(
                                          (k) => DataColumn(
                                            label: Text(
                                              k,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    rows: [
                                      ...dataHalaman.map(
                                        (r) => DataRow(
                                          cells: List<DataCell>.generate(
                                            widget.kolom.length,
                                            (i) => DataCell(
                                              SelectableText(
                                                i < r.length
                                                    ? '${r[i] ?? '-'}'
                                                    : '-',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (widget.barisTotal != null &&
                                          widget.barisTotal!.length ==
                                              widget.kolom.length)
                                        DataRow(
                                          color: WidgetStateProperty.all(
                                            AppColors.primary
                                                .withValues(alpha: 0.08),
                                          ),
                                          cells: widget.barisTotal!
                                              .map(
                                                (c) => DataCell(
                                                  SelectableText(
                                                    '${c ?? ''}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              if (data.length > kBarisPerHalamanTabel)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Menampilkan ${awalBaris + 1}–${(awalBaris + dataHalaman.length).clamp(0, data.length)} dari ${data.length} baris',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Halaman sebelumnya',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _halaman > 1
                            ? () => setState(() => _halaman--)
                            : null,
                      ),
                      Text('Halaman $_halaman / $totalHalaman'),
                      IconButton(
                        tooltip: 'Halaman berikutnya',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _halaman < totalHalaman
                            ? () => setState(() => _halaman++)
                            : null,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog otorisasi Supervisor (meminta Username/ID Supervisor & Kata Sandi Supervisor)
/// agar kasir dapat melakukan Edit Transaksi atau Batalkan Transaksi atas persetujuan Supervisor.
/// Jika pengguna saat ini sudah berstatus Supervisor/Admin (`Sesi.instance.bolehSupervisor`),
/// mengembalikan map kosong `{}` (langsung diizinkan tanpa perlu mengetik ulang sandi).
Future<Map<String, String>?> tampilkanDialogOtorisasiSupervisor(
  BuildContext context, {
  required String namaTindakan,
  String? nomorNota,
}) async {
  if (Sesi.instance.bolehKelola || Sesi.instance.isAdmin) {
    return <String, String>{};
  }
  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogOtorisasiSupervisor(
      namaTindakan: namaTindakan,
      nomorNota: nomorNota,
    ),
  );
}

class _DialogOtorisasiSupervisor extends StatefulWidget {
  final String namaTindakan;
  final String? nomorNota;

  const _DialogOtorisasiSupervisor({
    required this.namaTindakan,
    this.nomorNota,
  });

  @override
  State<_DialogOtorisasiSupervisor> createState() =>
      _DialogOtorisasiSupervisorState();
}

class _DialogOtorisasiSupervisorState
    extends State<_DialogOtorisasiSupervisor> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _sembunyi = true;
  bool _memeriksa = false;
  String? _galat;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifikasi() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    if (u.isEmpty || p.isEmpty) {
      setStateIfMounted(
          () => _galat = 'Username dan Kata Sandi Supervisor wajib diisi.');
      return;
    }
    setStateIfMounted(() {
      _memeriksa = true;
      _galat = null;
    });
    try {
      await ApiClient.instance.aksi('verifikasi_supervisor', {
        'supervisor_user_id': u,
        'supervisor_password': p,
        'tindakan': widget.namaTindakan,
      });
      if (!mounted) return;
      Navigator.pop(context, {
        'supervisor_user_id': u,
        'supervisor_password': p,
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // Jika server belum direstart sehingga action verifikasi_supervisor belum dikenal,
      // teruskan kredensial ke action utama (edit_transaksi / batalkan_transaksi) untuk diverifikasi.
      if (msg.toLowerCase().contains('aksi tidak dikenal')) {
        Navigator.pop(context, {
          'supervisor_user_id': u,
          'supervisor_password': p,
        });
        return;
      }
      setStateIfMounted(() {
        _memeriksa = false;
        _galat = msg.replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Otorisasi Supervisor — ${widget.namaTindakan}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tindakan "${widget.namaTindakan}"${widget.nomorNota != null ? ' untuk Nota ${widget.nomorNota}' : ''} memerlukan persetujuan Supervisor atau Kepala Toko.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 14),
            if (_galat != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _galat!,
                  style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _userCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Username / User ID Supervisor',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _sembunyi,
              decoration: InputDecoration(
                labelText: 'Kata Sandi Supervisor',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(_sembunyi
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setStateIfMounted(() => _sembunyi = !_sembunyi),
                ),
              ),
              onSubmitted: (_) => _verifikasi(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _memeriksa ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton.icon(
          onPressed: _memeriksa ? null : _verifikasi,
          icon: _memeriksa
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline, size: 16),
          label:
              Text(_memeriksa ? 'Memverifikasi...' : 'Otorisasi & Lanjutkan'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
