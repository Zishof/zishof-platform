import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Jalankan+tampilkan SATU laporan dari katalog (spec §Laporan-Laporan) --
/// form filter dibangun murni dari metadata katalog (`produk`/`pelanggan`/
/// `perToko` flags), TIDAK ada satu pun kode khusus per-laporan di sini.
/// Kontrak `laporan_jalankan`/`laporan_pdf` (r/tglMulai/tglSampai/qProduk/
/// qPelanggan/perToko -> kolom+baris+grup+grandTotal) generik utk ~150
/// laporan sekaligus -- lihat JavaDoc PosApi.prosesLaporanJalankan di server.
class LaporanDetailScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  const LaporanDetailScreen({super.key, required this.item});

  @override
  State<LaporanDetailScreen> createState() => _LaporanDetailScreenState();
}

class _LaporanDetailScreenState extends State<LaporanDetailScreen> {
  final _formatTgl = DateFormat('yyyy-MM-dd');
  DateTime? _tglMulai;
  DateTime? _tglSampai;
  final _controllerProduk = TextEditingController();
  final _controllerPelanggan = TextEditingController();
  bool _perToko = false;

  bool _memuat = false;
  bool _memprosesPdf = false;
  String? _pesanError;
  Map<String, dynamic>? _hasil;

  bool get _adaFilterProduk => widget.item['produk'] == true;
  bool get _adaFilterPelanggan => widget.item['pelanggan'] == true;
  bool get _adaFilterPerToko => widget.item['perToko'] == true;

  @override
  void initState() {
    super.initState();
    final sekarang = DateTime.now();
    _tglMulai = DateTime(sekarang.year, sekarang.month, 1);
    _tglSampai = sekarang;
  }

  @override
  void dispose() {
    _controllerProduk.dispose();
    _controllerPelanggan.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buatPayload() {
    return {
      'r': widget.item['id'],
      if (_tglMulai != null) 'tglMulai': _formatTgl.format(_tglMulai!),
      if (_tglSampai != null) 'tglSampai': _formatTgl.format(_tglSampai!),
      if (_adaFilterProduk && _controllerProduk.text.trim().isNotEmpty) 'qProduk': _controllerProduk.text.trim(),
      if (_adaFilterPelanggan && _controllerPelanggan.text.trim().isNotEmpty) 'qPelanggan': _controllerPelanggan.text.trim(),
      if (_adaFilterPerToko && _perToko) 'perToko': 'true',
    };
  }

  Future<void> _tampilkan() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_jalankan', _buatPayload());
      setStateIfMounted(() => _hasil = hasil);
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _memprosesPdf = true);
    try {
      final hasil = await ApiClient.instance.aksi('laporan_pdf', _buatPayload());
      final b64 = hasil['pdfBase64'] as String?;
      if (b64 == null || b64.isEmpty) throw Exception('Server tidak mengembalikan berkas PDF.');
      final bytes = base64Decode(b64);
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) async => Uint8List.fromList(bytes), name: '${widget.item['id']}.pdf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
    } finally {
      if (mounted) setStateIfMounted(() => _memprosesPdf = false);
    }
  }

  /// Ekspor CSV -- spec meminta CSV di samping PDF utk katalog Laporan-
  /// Laporan (~150 laporan), yg sebelumnya HANYA punya PDF. Dibangun MURNI
  /// client-side dari `_hasil` yg sudah dimuat lewat "Tampilkan" (kolom/baris
  /// SAMA persis dgn yg dirender `_TabelLaporan`) -- tak perlu aksi server
  /// baru, cukup satu kali `laporan_jalankan` melayani PDF (server) & CSV
  /// (klien) sekaligus.
  Future<void> _eksporCsv() async {
    final hasil = _hasil;
    if (hasil == null) return;
    final kolom = ((hasil['kolom'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final baris = ((hasil['baris'] as List?) ?? []).map((e) => List<dynamic>.from(e as List)).toList();
    if (kolom.isEmpty) return;

    String escapeCsv(String s) {
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final buffer = StringBuffer();
    buffer.writeln(kolom.map((k) => escapeCsv((k['l'] as String?) ?? '')).join(','));
    for (final r in baris) {
      buffer.writeln(r.map((v) => escapeCsv(v?.toString() ?? '')).join(','));
    }

    try {
      final bytes = Uint8List.fromList(utf8.encode(buffer.toString()));
      final namaFile = '${(widget.item['judul'] as String? ?? widget.item['id']).toString().replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')}.csv';
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Simpan Laporan (CSV)', fileName: namaFile, bytes: bytes, type: FileType.custom, allowedExtensions: ['csv']);
      if (path == null) return;
      // Sama seperti ekspor Excel Produk -- Desktop hanya mengembalikan path,
      // mobile sudah menulis via `bytes`; tulis ulang idempoten (isi sama).
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV disimpan: $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor CSV: $e')));
    }
  }

  Future<void> _pilihTanggal({required bool mulai}) async {
    final awal = (mulai ? _tglMulai : _tglSampai) ?? DateTime.now();
    final dipilih = await showDatePicker(context: context, initialDate: awal, firstDate: DateTime(2015), lastDate: DateTime(2100));
    if (dipilih != null) {
      setStateIfMounted(() {
        if (mulai) {
          _tglMulai = dipilih;
        } else {
          _tglSampai = dipilih;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: AppBar(
        title: Text(widget.item['judul'] as String? ?? 'Laporan', overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.sidebarBg,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((widget.item['ket'] as String? ?? '').isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(widget.item['ket'] as String,
                      style:
                          TextStyle(color: AppColors.textSecondaryOf(context)))),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _kotakTanggal('Tanggal Mulai', _tglMulai, () => _pilihTanggal(mulai: true))),
                      const SizedBox(width: 12),
                      Expanded(child: _kotakTanggal('Tanggal Sampai', _tglSampai, () => _pilihTanggal(mulai: false))),
                    ],
                  ),
                  if (_adaFilterProduk) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _controllerProduk, decoration: const InputDecoration(labelText: 'Cari Produk', border: OutlineInputBorder(), isDense: true)),
                  ],
                  if (_adaFilterPelanggan) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _controllerPelanggan, decoration: const InputDecoration(labelText: 'Cari Pelanggan', border: OutlineInputBorder(), isDense: true)),
                  ],
                  if (_adaFilterPerToko)
                    CheckboxListTile(value: _perToko, onChanged: (v) => setStateIfMounted(() => _perToko = v ?? false), title: const Text('Tampilkan per Toko'), contentPadding: EdgeInsets.zero, dense: true),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _memuat ? null : _tampilkan,
                          icon: _memuat ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow),
                          label: const Text('Tampilkan'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _hasil == null || _memprosesPdf ? null : _cetakPdf,
                        icon: _memprosesPdf ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _hasil == null ? null : _eksporCsv,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('CSV'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_pesanError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.latarLembut(AppColors.danger), borderRadius: BorderRadius.circular(8)),
                child: Text(_pesanError!, style: const TextStyle(color: AppColors.danger)),
              ),
            if (_hasil != null) _TabelLaporan(hasil: _hasil!),
          ],
        ),
      ),
    );
  }

  Widget _kotakTanggal(String label, DateTime? nilai, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        child: Text(nilai == null ? '-' : DateFormat('dd-MM-yyyy').format(nilai)),
      ),
    );
  }
}

/// Render generik tabel `kolom`/`baris` + logika grup/subtotal/grand-total
/// (padanan `laporan-renderer.js`/`LaporanKantinPdf.buildTable` -- lihat
/// JavaDoc kelas ini di server utk aturan lengkap): kolom `t=="tgl"` sudah
/// diformat server (`dd-MM-yyyy HH:mm`), `t=="num"` diformat id-ID di sini
/// (integer utk label berawalan Jml/Jumlah, 2 desimal lainnya, negatif
/// dikurung). Kolom `grup>=0` memicu baris header-grup + subtotal per
/// perubahan nilai; `grandTotal` menambah baris total keseluruhan di akhir.
class _TabelLaporan extends StatefulWidget {
  final Map<String, dynamic> hasil;
  const _TabelLaporan({required this.hasil});

  @override
  State<_TabelLaporan> createState() => _TabelLaporanState();
}

class _TabelLaporanState extends State<_TabelLaporan> {
  static const _lebarKolom = 150.0;
  static const _pageSize = 15;

  int _halaman = 1;

  @override
  void didUpdateWidget(covariant _TabelLaporan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hasil, widget.hasil)) _halaman = 1;
  }

  int _totalHalaman(int total) {
    if (total <= 0) return 1;
    return ((total - 1) ~/ _pageSize) + 1;
  }

  bool _isHitungKolom(String label) {
    final l = label.trim().toLowerCase();
    return l.startsWith('jml') || l.startsWith('jumlah');
  }

  String _fmtNum(num? v, bool hitung) {
    if (v == null) return '';
    final neg = v < 0;
    final abs = v.abs();
    final formatter = hitung ? NumberFormat.decimalPattern('id_ID') : NumberFormat('#,##0.00', 'id_ID');
    final s = formatter.format(abs);
    return neg ? '($s)' : s;
  }

  String _fmtSel(dynamic v, String tipe, String label) {
    if (v == null) return '';
    if (tipe == 'num') return _fmtNum(v as num, _isHitungKolom(label));
    return v.toString();
  }

  Color _warnaBiruGelap(BuildContext context) =>
      AppColors.gelap(context) ? AppColors.darkTextPrimary : AppColors.sidebarBg;

  @override
  Widget build(BuildContext context) {
    final kolom = ((widget.hasil['kolom'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final baris = ((widget.hasil['baris'] as List?) ?? []).map((e) => List<dynamic>.from(e as List)).toList();
    final catatan = widget.hasil['catatan'] as String?;
    final grup = (widget.hasil['grup'] as num?)?.toInt() ?? -1;
    final grandTotal = widget.hasil['grandTotal'] == true;
    final judul = widget.hasil['judul'] as String?;

    if (kolom.isEmpty) {
      return AppSectionCard(
        child: Center(
          child: Text(
            'Tidak ada kolom pada laporan ini.',
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }
    if (baris.isEmpty) {
      return AppSectionCard(
        child: Center(
          child: Text(
            'Tidak ada data untuk filter yang dipilih.',
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }

    final numIdx = <int>[for (var i = 0; i < kolom.length; i++) if (kolom[i]['t'] == 'num') i];
    final semuaBaris = <AppTableRowData>[];

    List<AppTableCell> selKosong({String? labelAwal, TextStyle? styleAwal}) {
      return List.generate(kolom.length, (i) {
        return AppTableCell.text(
          i == 0 ? (labelAwal ?? '') : '',
          width: _lebarKolom,
          maxLines: 2,
          style: i == 0 ? styleAwal : null,
        );
      });
    }

    AppTableRowData barisData(List<dynamic> r) {
      return AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          final tipe = kolom[i]['t'] as String? ?? 'text';
          final label = kolom[i]['l'] as String? ?? '';
          final isNum = tipe == 'num';
          return AppTableCell.text(
            i < r.length ? _fmtSel(r[i], tipe, label) : '',
            width: _lebarKolom,
            align: isNum ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textPrimaryOf(context),
              fontFamily: isNum ? 'monospace' : null,
            ),
          );
        }),
      );
    }

    void tambahBarisPita(String teks) {
      semuaBaris.add(AppTableRowData(
        cells: selKosong(
          labelAwal: teks,
          styleAwal: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: _warnaBiruGelap(context),
          ),
        ),
      ));
    }

    void tambahBarisSubtotal(String key, Map<int, double> sums) {
      semuaBaris.add(AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == grup) {
            teks = 'Subtotal $key';
          } else if (sums.containsKey(i)) {
            teks = _fmtNum(sums[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          final isNum = kolom[i]['t'] == 'num';
          return AppTableCell.text(
            teks,
            width: _lebarKolom,
            align: isNum ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
            ),
          );
        }),
      ));
    }

    if (grup >= 0 && grup < kolom.length) {
      String? kunciSaatIni;
      final jumlahSaatIni = <int, double>{};
      for (final r in baris) {
        final kunci = r[grup]?.toString() ?? '';
        if (kunciSaatIni == null) {
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        } else if (kunci != kunciSaatIni) {
          tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
          jumlahSaatIni.clear();
          tambahBarisPita(kunci);
          kunciSaatIni = kunci;
        }
        for (final i in numIdx) {
          jumlahSaatIni[i] = (jumlahSaatIni[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
        final rSalinan = List<dynamic>.from(r);
        rSalinan[grup] = null;
        semuaBaris.add(barisData(rSalinan));
      }
      if (kunciSaatIni != null) tambahBarisSubtotal(kunciSaatIni, jumlahSaatIni);
    } else {
      for (final r in baris) {
        semuaBaris.add(barisData(r));
      }
    }

    if (grandTotal && numIdx.isNotEmpty) {
      final total = <int, double>{};
      for (final r in baris) {
        for (final i in numIdx) {
          total[i] = (total[i] ?? 0) + ((r[i] as num?)?.toDouble() ?? 0);
        }
      }
      semuaBaris.add(AppTableRowData(
        cells: List.generate(kolom.length, (i) {
          String teks = '';
          if (i == 0) {
            teks = 'TOTAL';
          } else if (total.containsKey(i)) {
            teks = _fmtNum(total[i], _isHitungKolom(kolom[i]['l'] as String? ?? ''));
          }
          final isNum = kolom[i]['t'] == 'num';
          return AppTableCell.text(
            teks,
            width: _lebarKolom,
            align: isNum ? TextAlign.right : TextAlign.left,
            maxLines: 2,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: _warnaBiruGelap(context),
            ),
          );
        }),
      ));
    }

    final totalHalaman = _totalHalaman(semuaBaris.length);
    if (_halaman > totalHalaman) _halaman = totalHalaman;
    final mulai = (_halaman - 1) * _pageSize;
    final sampai = (mulai + _pageSize).clamp(0, semuaBaris.length) as int;
    final rows = mulai >= semuaBaris.length ? <AppTableRowData>[] : semuaBaris.sublist(mulai, sampai);
    final minWidth = (_lebarKolom * kolom.length) < 760 ? 760.0 : _lebarKolom * kolom.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (judul != null || (catatan != null && catatan.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (judul != null)
                    Text(
                      judul,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  if (catatan != null && catatan.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        catatan,
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        AppDataTable(
          minWidth: minWidth,
          emptyText: 'Tidak ada data untuk halaman ini.',
          columns: kolom
              .map((k) => AppTableColumn(
                    k['l'] as String? ?? '',
                    width: _lebarKolom,
                    align: k['t'] == 'num' ? TextAlign.right : TextAlign.left,
                  ))
              .toList(),
          rows: rows,
          pagination: AppTablePagination(
            halaman: _halaman,
            totalHalaman: totalHalaman,
            totalData: baris.length,
            labelData: 'baris',
            onSebelumnya: _halaman > 1
                ? () => setStateIfMounted(() => _halaman--)
                : null,
            onBerikutnya: _halaman < totalHalaman
                ? () => setStateIfMounted(() => _halaman++)
                : null,
          ),
        ),
      ],
    );
  }
}
