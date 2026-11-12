import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

/// Dialog Tahap 2 & Tahap 3 Alur Kerja Stok Opname Terpadu:
/// - **Tahap 1 (Entry Fisik / Draft)**: Petugas menginput hasil hitung fisik per Rak / Manual / Scan / Excel
///   tanpa mengubah stok persediaan berjalan.
/// - **Tahap 2 (Proses Stok Opname & Bandingkan Selisih)**: Membandingkan stok sistem dengan hasil hitung
///   fisik, mengizinkan koreksi/edit kuantitas fisik sebelum disetujui, **mewajibkan Cetak Daftar Selisih**
///   sebelum tombol Adjustment aktif, serta mengizinkan **Cetak Berita Acara** baik sebelum maupun sesudah
///   Adjustment. Apabila kuantitas diubah setelah Daftar Selisih dicetak, status cetak selisih otomatis
///   di-reset agar petugas mencetak ulang daftar selisih terbaru.
/// - **Tahap 3 (Setujui Opname / Adjustment Final & Kunci Permanen)**: Menyesuaikan stok persediaan toko &
///   rak, memastikan hasil opname pada Tanggal `T` menjadi **Stok Awal** pada Tanggal `T+1`, serta mengunci
///   dokumen secara permanen sehingga tidak dapat diedit, dihapus, ataupun dibatalkan lagi.
class ProsesStokOpnameDialog extends StatefulWidget {
  final int dokumenId;

  const ProsesStokOpnameDialog({
    super.key,
    required this.dokumenId,
  });

  /// Membuka dialog Proses Stok Opname & Adjustment untuk [dokumenId].
  /// Mengembalikan `true` apabila terjadi perubahan data atau persetujuan adjustment.
  static Future<bool> buka(
    BuildContext context, {
    required int dokumenId,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProsesStokOpnameDialog(dokumenId: dokumenId),
    );
    return res == true;
  }

  @override
  State<ProsesStokOpnameDialog> createState() => _ProsesStokOpnameDialogState();
}

class _ProsesStokOpnameDialogState extends State<ProsesStokOpnameDialog> {
  final _formatAngka = NumberFormat('#,##0.##', 'id_ID');
  final _formatRupiah =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  bool _menyimpanHeader = false;
  bool _mencetakSelisih = false;
  bool _mencetakBa = false;
  bool _menyetujui = false;
  bool _adaPerubahan = false;
  String? _pesanError;

  Map<String, dynamic> _dokumen = {};
  List<Map<String, dynamic>> _items = [];

  final TextEditingController _cariCtrl = TextEditingController();
  final TextEditingController _penghitungCtrl = TextEditingController();
  final TextEditingController _pengawasCtrl = TextEditingController();
  final TextEditingController _ketDokumenCtrl = TextEditingController();

  final Map<int, TextEditingController> _fisikCtrls = {};
  final Map<int, TextEditingController> _ketItemCtrls = {};
  final Set<int> _menyimpanItemIds = <int>{};

  bool _hanyaSelisih = false;

  bool get _terkunciPermanen =>
      _dokumen['terkunciPermanen'] == true ||
      '${_dokumen['status'] ?? ''}'.toUpperCase() == 'DISETUJUI';

  bool get _sudahCetakSelisih => _dokumen['sudahCetakSelisih'] == true;
  bool get _sudahCetakBa => _dokumen['sudahCetakBeritaAcara'] == true;

  @override
  void initState() {
    super.initState();
    _muatDanProsesDokumen(transisiProses: true);
  }

  @override
  void dispose() {
    _cariCtrl.dispose();
    _penghitungCtrl.dispose();
    _pengawasCtrl.dispose();
    _ketDokumenCtrl.dispose();
    for (final c in _fisikCtrls.values) {
      c.dispose();
    }
    for (final c in _ketItemCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _labelJenisSo(String raw) {
    switch (raw.toUpperCase()) {
      case 'SO_GRAND':
        return 'SO Grand per Rak';
      case 'INPUT_MANUAL':
        return 'Input Opname Manual';
      case 'SO_SCAN':
        return 'SO by Scan';
      case 'IMPOR_EXCEL':
        return 'Unggah Excel SO';
      default:
        return raw.isEmpty ? 'Stok Opname' : raw;
    }
  }

  String _formatAngkaInput(num nilai) {
    final d = nilai.toDouble();
    if ((d - d.roundToDouble()).abs() < 0.000001) {
      return d.round().toString();
    }
    return d.toString();
  }

  Future<void> _muatDanProsesDokumen({
    bool transisiProses = false,
    String? tanggalOpnameBaru,
  }) async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final payload = <String, dynamic>{
        'dokumen_id': widget.dokumenId,
        'dokumenId': widget.dokumenId,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (tanggalOpnameBaru != null && tanggalOpnameBaru.isNotEmpty)
          'tanggal_opname': tanggalOpnameBaru,
      };
      final aksi = transisiProses ? 'so_dokumen_proses' : 'so_dokumen_detail';
      Map<String, dynamic> res;
      try {
        res = await ApiClient.instance.aksi(aksi, payload);
      } catch (_) {
        if (transisiProses) {
          res = await ApiClient.instance.aksi('so_dokumen_detail', payload);
        } else {
          rethrow;
        }
      }

      final dok = res['dokumen'] is Map
          ? Map<String, dynamic>.from(res['dokumen'] as Map)
          : <String, dynamic>{};
      final rawItems = (res['items'] as List?) ?? const [];
      final listItems = rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      for (final it in listItems) {
        final itemId = (it['id'] as num?)?.toInt() ?? 0;
        if (itemId <= 0) continue;
        final fisik = (it['stokFisik'] as num?)?.toDouble() ?? 0;
        final ket = '${it['keterangan'] ?? ''}';
        final cFis = _fisikCtrls.putIfAbsent(itemId, () => TextEditingController());
        cFis.text = _formatAngkaInput(fisik);
        final cKet =
            _ketItemCtrls.putIfAbsent(itemId, () => TextEditingController());
        cKet.text = ket;
      }

      if (!mounted) return;
      setStateIfMounted(() {
        _dokumen = dok;
        _items = listItems;
        _penghitungCtrl.text = '${dok['penghitung'] ?? ''}'.trim();
        _pengawasCtrl.text = '${dok['pengawas'] ?? ''}'.trim();
        _ketDokumenCtrl.text = '${dok['keterangan'] ?? ''}'.trim();
        if (transisiProses || tanggalOpnameBaru != null) {
          _adaPerubahan = true;
        }
      });
    } catch (e) {
      if (mounted) {
        setStateIfMounted(() => _pesanError = '$e');
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _memuat = false);
      }
    }
  }

  Future<void> _pilihTanggalOpname() async {
    if (_terkunciPermanen) return;
    final tglRaw = '${_dokumen['tanggalOpname'] ?? ''}'.trim();
    DateTime awal = DateTime.now();
    if (tglRaw.isNotEmpty) {
      try {
        awal = DateFormat('yyyy-MM-dd').parseStrict(tglRaw);
      } catch (_) {}
    }
    final pilihan = await showDatePicker(
      context: context,
      initialDate: awal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Pilih Tanggal Acuan Stok Opname',
    );
    if (pilihan == null || !mounted) return;
    final baru = DateFormat('yyyy-MM-dd').format(pilihan);
    if (baru == tglRaw) return;
    await _muatDanProsesDokumen(transisiProses: true, tanggalOpnameBaru: baru);
  }

  Future<void> _simpanMetadataHeader() async {
    if (_terkunciPermanen || _menyimpanHeader) return;
    setStateIfMounted(() => _menyimpanHeader = true);
    try {
      final res = await ApiClient.instance.aksi('so_dokumen_proses', {
        'dokumen_id': widget.dokumenId,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        'penghitung': _penghitungCtrl.text.trim(),
        'pengawas': _pengawasCtrl.text.trim(),
        'keterangan': _ketDokumenCtrl.text.trim(),
      });
      if (!mounted) return;
      if (res['dokumen'] is Map) {
        setStateIfMounted(() {
          _dokumen = Map<String, dynamic>.from(res['dokumen'] as Map);
          _adaPerubahan = true;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Identitas petugas & catatan dokumen diperbarui.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui dokumen: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpanHeader = false);
    }
  }

  Future<void> _simpanPerubahanItem(Map<String, dynamic> it) async {
    if (_terkunciPermanen) return;
    final itemId = (it['id'] as num?)?.toInt() ?? 0;
    if (itemId <= 0 || _menyimpanItemIds.contains(itemId)) return;

    final teksFisik = _fisikCtrls[itemId]?.text.trim() ?? '';
    final fisikBaru = double.tryParse(teksFisik.replaceAll(',', '.'));
    if (fisikBaru == null || fisikBaru < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kuantitas stok fisik wajib berupa angka >= 0.')),
      );
      return;
    }

    final sebelumnyaSudahCetakSelisih = _sudahCetakSelisih;
    setStateIfMounted(() => _menyimpanItemIds.add(itemId));
    try {
      final res = await ApiClient.instance.aksi('so_dokumen_update_item', {
        'item_id': itemId,
        'stok_fisik': fisikBaru,
        'keterangan': _ketItemCtrls[itemId]?.text.trim() ?? '',
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        it['stokSistem'] =
            (res['stokSistem'] as num?)?.toDouble() ?? it['stokSistem'] ?? 0;
        it['stokFisik'] = (res['stokFisik'] as num?)?.toDouble() ?? fisikBaru;
        it['selisih'] = (res['selisih'] as num?)?.toDouble() ??
            (fisikBaru - ((it['stokSistem'] as num?)?.toDouble() ?? 0));
        it['nilaiSelisih'] =
            (res['nilaiSelisih'] as num?)?.toDouble() ?? it['nilaiSelisih'] ?? 0;
        it['keterangan'] = _ketItemCtrls[itemId]?.text.trim() ?? '';
        if (res['dokumen'] is Map) {
          _dokumen = Map<String, dynamic>.from(res['dokumen'] as Map);
        }
        _adaPerubahan = true;
      });
      final sekarangSudahCetak = _sudahCetakSelisih;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sebelumnyaSudahCetakSelisih && !sekarangSudahCetak
                ? 'Kuantitas berhasil diperbarui. Karena angka berubah, silakan Cetak Daftar Selisih ulang sebelum Adjustment.'
                : 'Kuantitas stok fisik "${it['nama'] ?? ''}" berhasil diperbarui.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengubah kuantitas: $e')),
        );
      }
    } finally {
      if (mounted) {
        setStateIfMounted(() => _menyimpanItemIds.remove(itemId));
      }
    }
  }

  Future<void> _hapusItem(Map<String, dynamic> it) async {
    if (_terkunciPermanen) return;
    final itemId = (it['id'] as num?)?.toInt() ?? 0;
    if (itemId <= 0) return;

    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Baris dari Dokumen SO?'),
        content: Text(
            'Hapus "${it['nama'] ?? '-'}" dari daftar dokumen opname ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (konfirmasi != true || !mounted) return;

    try {
      final res = await ApiClient.instance.aksi('so_dokumen_hapus_item', {
        'item_id': itemId,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        _items.removeWhere((x) => (x['id'] as num?)?.toInt() == itemId);
        if (res['dokumen'] is Map) {
          _dokumen = Map<String, dynamic>.from(res['dokumen'] as Map);
        }
        _adaPerubahan = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus item: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    final kw = _cariCtrl.text.trim().toLowerCase();
    return _items.where((it) {
      if (_hanyaSelisih) {
        final sel = (it['selisih'] as num?)?.toDouble() ?? 0;
        if (sel.abs() < 0.000001) return false;
      }
      if (kw.isEmpty) return true;
      final nama = '${it['nama'] ?? ''}'.toLowerCase();
      final kode = '${it['kode'] ?? ''}'.toLowerCase();
      final barcode = '${it['barcode'] ?? ''}'.toLowerCase();
      final rak = '${it['rakNama'] ?? ''}'.toLowerCase();
      return nama.contains(kw) ||
          kode.contains(kw) ||
          barcode.contains(kw) ||
          rak.contains(kw);
    }).toList();
  }

  /// Tahap 2A: Cetak Daftar Selisih Stok Opname (A4 Portrait) & tandai `sudahCetakSelisih = true`.
  Future<void> _cetakDaftarSelisihPdf() async {
    if (_mencetakSelisih || _items.isEmpty) return;
    setStateIfMounted(() => _mencetakSelisih = true);
    try {
      // Tandai di server terlebih dahulu beserta nama penghitung & pengawas terbaru
      final res = await ApiClient.instance.aksi('so_dokumen_tandai_cetak', {
        'dokumen_id': widget.dokumenId,
        'jenis_cetak': 'SELISIH',
        'penghitung': _penghitungCtrl.text.trim(),
        'pengawas': _pengawasCtrl.text.trim(),
        'keterangan': _ketDokumenCtrl.text.trim(),
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      if (res['dokumen'] is Map && mounted) {
        setStateIfMounted(() {
          _dokumen = Map<String, dynamic>.from(res['dokumen'] as Map);
          _adaPerubahan = true;
        });
      }

      final tokoNama = '${_dokumen['tokoNama'] ?? Sesi.instance.tokoNama}'
              .trim()
              .isNotEmpty
          ? '${_dokumen['tokoNama'] ?? Sesi.instance.tokoNama}'
          : 'Toko Al-Bahjah';
      final kodeDok = '${_dokumen['kode'] ?? '-'}';
      final tglIndo = '${_dokumen['tanggalOpnameIndo'] ?? _dokumen['tanggalOpname'] ?? '-'}';
      final rakLabel = '${_dokumen['rakNama'] ?? 'Semua Rak'}';
      final penghitung = _penghitungCtrl.text.trim().isNotEmpty
          ? _penghitungCtrl.text.trim()
          : '${_dokumen['dibuatOleh'] ?? '________________'}';
      final pengawas = _pengawasCtrl.text.trim().isNotEmpty
          ? _pengawasCtrl.text.trim()
          : '________________';

      final daftarSelisih = _items
          .where((e) => ((e['selisih'] as num?)?.toDouble() ?? 0).abs() >= 0.000001)
          .toList();
      final sumberCetak = daftarSelisih.isNotEmpty ? daftarSelisih : _items;

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DAFTAR PERBANDINGAN & SELISIH STOK OPNAME',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Toko: $tokoNama   |   No. Dokumen: $kodeDok   |   Metode: ${_labelJenisSo('${_dokumen['jenisSo'] ?? ''}')}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Text(
                  'Tanggal Opname: $tglIndo   |   Rak: $rakLabel   |   Total Diperiksa: ${_items.length} Item (${daftarSelisih.length} Item Selisih)',
                  style: pw.TextStyle(
                      fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.Divider(height: 10),
              ],
            ),
          ),
          build: (_) => [
            if (daftarSelisih.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                margin: const pw.EdgeInsets.only(bottom: 8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Text(
                  'Seluruh item (${_items.length} barang) memiliki Stok Fisik SAMA DENGAN Stok Sistem (Selisih = 0). Rincian lengkap ditampilkan di bawah ini:',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            pw.TableHelper.fromTextArray(
              headers: const [
                'NO',
                'KODE / BARCODE',
                'NAMA BARANG',
                'RAK',
                'SAT',
                'SISTEM',
                'FISIK',
                'SELISIH',
                'NILAI SELISIH',
                'KET / CEK ULANG',
              ],
              columnWidths: const {
                0: pw.FixedColumnWidth(20),
                1: pw.FixedColumnWidth(66),
                2: pw.FlexColumnWidth(2.6),
                3: pw.FixedColumnWidth(52),
                4: pw.FixedColumnWidth(26),
                5: pw.FixedColumnWidth(36),
                6: pw.FixedColumnWidth(36),
                7: pw.FixedColumnWidth(38),
                8: pw.FixedColumnWidth(58),
                9: pw.FlexColumnWidth(1.3),
              },
              data: List.generate(sumberCetak.length, (i) {
                final r = sumberCetak[i];
                final sis = (r['stokSistem'] as num?)?.toDouble() ?? 0;
                final fis = (r['stokFisik'] as num?)?.toDouble() ?? 0;
                final sel = (r['selisih'] as num?)?.toDouble() ?? 0;
                final nil = (r['nilaiSelisih'] as num?)?.toDouble() ?? 0;
                final bc = '${r['barcode'] ?? ''}'.trim();
                return [
                  '${i + 1}',
                  '${r['kode'] ?? ''}${bc.isEmpty ? '' : '\n$bc'}',
                  '${r['nama'] ?? ''}',
                  '${r['rakNama'] ?? '-'}',
                  '${r['satuan'] ?? 'PCS'}',
                  _formatAngka.format(sis),
                  _formatAngka.format(fis),
                  '${sel > 0 ? '+' : ''}${_formatAngka.format(sel)}',
                  _formatRupiah.format(nil),
                  '${r['keterangan'] ?? ''}',
                ];
              }),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerStyle:
                  pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Total Selisih Lebih (+): +${_formatAngka.format(_dokumen['totalSelisihPlus'] ?? 0)}   |   '
                  'Total Selisih Kurang (-): ${_formatAngka.format(_dokumen['totalSelisihMinus'] ?? 0)}   |   '
                  'Total Nilai Selisih: ${_formatRupiah.format(_dokumen['totalNilaiSelisih'] ?? 0)}',
                  style: pw.TextStyle(
                      fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                  pw.Text('Petugas Penghitung,',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 36),
                  pw.Text('( $penghitung )',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Column(children: [
                  pw.Text('Pengawas / Verifikator,',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 36),
                  pw.Text('( $pengawas )',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Daftar-Selisih-$kodeDok.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak Daftar Selisih: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mencetakSelisih = false);
    }
  }

  /// Tahap 2B & Tahap 3: Cetak Berita Acara Stok Opname (A4 Portrait).
  /// Diizinkan baik **sebelum** maupun **sesudah** Adjustment disetujui!
  Future<void> _cetakBeritaAcaraPdf() async {
    if (_mencetakBa || _items.isEmpty) return;
    setStateIfMounted(() => _mencetakBa = true);
    try {
      final res = await ApiClient.instance.aksi('so_dokumen_tandai_cetak', {
        'dokumen_id': widget.dokumenId,
        'jenis_cetak': 'BERITA_ACARA',
        'penghitung': _penghitungCtrl.text.trim(),
        'pengawas': _pengawasCtrl.text.trim(),
        'keterangan': _ketDokumenCtrl.text.trim(),
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      if (res['dokumen'] is Map && mounted) {
        setStateIfMounted(() {
          _dokumen = Map<String, dynamic>.from(res['dokumen'] as Map);
          _adaPerubahan = true;
        });
      }

      final tokoNama = '${_dokumen['tokoNama'] ?? Sesi.instance.tokoNama}'
              .trim()
              .isNotEmpty
          ? '${_dokumen['tokoNama'] ?? Sesi.instance.tokoNama}'
          : 'Toko Al-Bahjah';
      final kodeDok = '${_dokumen['kode'] ?? '-'}';
      final nomorBa = '${_dokumen['nomorBeritaAcara'] ?? kodeDok}';
      final tglIndo =
          '${_dokumen['tanggalOpnameIndo'] ?? _dokumen['tanggalOpname'] ?? '-'}';
      final rakLabel = '${_dokumen['rakNama'] ?? 'Semua Rak'}';
      final statusFinal = _terkunciPermanen
          ? 'DISETUJUI / FINAL (TERKUNCI PERMANEN)'
          : 'PRA-ADJUSTMENT (MENUNGGU PERSETUJUAN FINAL)';
      final penghitung = _penghitungCtrl.text.trim().isNotEmpty
          ? _penghitungCtrl.text.trim()
          : '${_dokumen['penghitung'] ?? _dokumen['dibuatOleh'] ?? '________________'}';
      final pengawas = _pengawasCtrl.text.trim().isNotEmpty
          ? _pengawasCtrl.text.trim()
          : '${_dokumen['pengawas'] ?? ''}'.trim().isNotEmpty
              ? '${_dokumen['pengawas']}'
              : '________________';
      final penyetuju = '${_dokumen['disetujuiOleh'] ?? ''}'.trim().isNotEmpty
          ? '${_dokumen['disetujuiOleh']}'
          : '________________';
      final jmlSelisih = _items
          .where((e) => ((e['selisih'] as num?)?.toDouble() ?? 0).abs() >= 0.000001)
          .length;

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(26),
          header: (_) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'BERITA ACARA STOK OPNAME PERSEDIAAN BARANG',
                  style: pw.TextStyle(
                      fontSize: 13, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Nomor Berita Acara: $nomorBa   |   Dokumen: $kodeDok',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Unit / Toko: $tokoNama   |   Status: $statusFinal',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.Divider(height: 12),
              ],
            ),
          ),
          build: (_) => [
            pw.Text(
              'Pada tanggal acuan opname $tglIndo, telah dilaksanakan penghitungan fisik persediaan barang '
              '(${_labelJenisSo('${_dokumen['jenisSo'] ?? ''}')} — Cakupan Rak: $rakLabel) pada $tokoNama '
              'dengan ringkasan hasil pemeriksaan sebagai berikut:',
              style: const pw.TextStyle(fontSize: 8.5),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500),
                color: PdfColors.grey100,
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Barang Diperiksa: ${_items.length} Item',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Item Berselisih: $jmlSelisih Item',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                      'Lebih (+): +${_formatAngka.format(_dokumen['totalSelisihPlus'] ?? 0)}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                      'Kurang (-): ${_formatAngka.format(_dokumen['totalSelisihMinus'] ?? 0)}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(
                      'Nilai Selisih: ${_formatRupiah.format(_dokumen['totalNilaiSelisih'] ?? 0)}',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            if ('${_dokumen['keterangan'] ?? ''}'.trim().isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Catatan Umum: ${_dokumen['keterangan']}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: const [
                'NO',
                'KODE',
                'NAMA BARANG',
                'RAK',
                'SAT',
                'SISTEM',
                'FISIK',
                'SELISIH',
                'NILAI SELISIH',
                'KETERANGAN',
              ],
              columnWidths: const {
                0: pw.FixedColumnWidth(20),
                1: pw.FixedColumnWidth(58),
                2: pw.FlexColumnWidth(2.6),
                3: pw.FixedColumnWidth(52),
                4: pw.FixedColumnWidth(26),
                5: pw.FixedColumnWidth(36),
                6: pw.FixedColumnWidth(36),
                7: pw.FixedColumnWidth(38),
                8: pw.FixedColumnWidth(58),
                9: pw.FlexColumnWidth(1.3),
              },
              data: List.generate(_items.length, (i) {
                final r = _items[i];
                final sis = (r['stokSistem'] as num?)?.toDouble() ?? 0;
                final fis = (r['stokFisik'] as num?)?.toDouble() ?? 0;
                final sel = (r['selisih'] as num?)?.toDouble() ?? 0;
                final nil = (r['nilaiSelisih'] as num?)?.toDouble() ?? 0;
                return [
                  '${i + 1}',
                  '${r['kode'] ?? ''}',
                  '${r['nama'] ?? ''}',
                  '${r['rakNama'] ?? '-'}',
                  '${r['satuan'] ?? 'PCS'}',
                  _formatAngka.format(sis),
                  _formatAngka.format(fis),
                  '${sel > 0 ? '+' : ''}${_formatAngka.format(sel)}',
                  _formatRupiah.format(nil),
                  '${r['keterangan'] ?? ''}',
                ];
              }),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerStyle:
                  pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Demikian Berita Acara Stok Opname ini dibuat dengan sebenarnya untuk dipergunakan sebagai dasar '
              'penyesuaian saldo persediaan barang (Saldo Akhir tanggal $tglIndo menjadi Saldo Awal hari berikutnya).',
              style: const pw.TextStyle(fontSize: 8),
              textAlign: pw.TextAlign.justify,
            ),
            pw.SizedBox(height: 22),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(children: [
                  pw.Text('Petugas Penghitung,',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 38),
                  pw.Text('( $penghitung )',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Column(children: [
                  pw.Text('Pengawas / Kepala Toko,',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 38),
                  pw.Text('( $pengawas )',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ]),
                pw.Column(children: [
                  pw.Text('Menyetujui (Manajemen / Keuangan),',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 38),
                  pw.Text('( $penyetuju )',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Berita-Acara-SO-${nomorBa.replaceAll('/', '-')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak Berita Acara SO: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mencetakBa = false);
    }
  }

  /// Tahap 3: Setujui Opname (Adjustment Stok Final & Kunci Permanen).
  Future<void> _setujuiAdjustment() async {
    if (_terkunciPermanen || _menyetujui) return;

    if (!_sudahCetakSelisih) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.print_outlined, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(child: Text('Wajib Cetak Daftar Selisih Terlebih Dahulu')),
            ],
          ),
          content: const Text(
            'Sesuai prosedur audit Stok Opname, sebelum melakukan Adjustment (Penyesuaian Stok), '
            'Anda WAJIB menekan tombol "1. Cetak Daftar Selisih (PDF)" terlebih dahulu untuk memastikan '
            'seluruh selisih dan koreksi kuantitas telah diperiksa bersama pengawas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Mengerti'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _cetakDaftarSelisihPdf();
              },
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Cetak Daftar Selisih Sekarang'),
            ),
          ],
        ),
      );
      return;
    }

    final tglIndo =
        '${_dokumen['tanggalOpnameIndo'] ?? _dokumen['tanggalOpname'] ?? 'hari ini'}';
    final jmlSelisih = _items
        .where((e) => ((e['selisih'] as num?)?.toDouble() ?? 0).abs() >= 0.000001)
        .length;

    final setuju = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock_clock_outlined, color: AppColors.primary),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Setujui Opname & Adjustment Stok Permanen?')),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dokumen: ${_dokumen['kode'] ?? '-'} · Tanggal Opname: $tglIndo\n'
                'Total Barang: ${_items.length} item ($jmlSelisih item berselisih)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                '• Stok persediaan toko dan stok per Rak akan disesuaikan mengikuti angka Stok Fisik.\n'
                '• Hasil opname pada tanggal acuan ini otomatis menjadi Saldo Stok Awal pada tanggal berikutnya (H+1).\n'
                '• Setelah disetujui, dokumen dan seluruh baris opname ini DIKUNCI PERMANEN (tidak dapat diedit, dihapus, maupun dibatalkan).\n'
                '• Berita Acara Stok Opname tetap dapat dicetak ulang kapan saja setelah disetujui.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Periksa Kembali'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: const Text('Ya, Setujui Adjustment & Kunci Permanen'),
          ),
        ],
      ),
    );
    if (setuju != true || !mounted) return;

    setStateIfMounted(() => _menyetujui = true);
    try {
      final res =
          await ApiClient.instance.aksi('so_dokumen_setujui_adjustment', {
        'dokumen_id': widget.dokumenId,
        'penghitung': _penghitungCtrl.text.trim(),
        'pengawas': _pengawasCtrl.text.trim(),
        'keterangan': _ketDokumenCtrl.text.trim(),
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      if (!mounted) return;
      final dokBaru = res['dokumen'] is Map
          ? Map<String, dynamic>.from(res['dokumen'] as Map)
          : _dokumen;
      final itemsBaru = ((res['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setStateIfMounted(() {
        _dokumen = dokBaru;
        if (itemsBaru.isNotEmpty) _items = itemsBaru;
        _adaPerubahan = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text(
            '${res['description'] ?? 'Adjustment Stok Opname berhasil disetujui & dikunci permanen.'}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyetujui Adjustment: $e')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyetujui = false);
    }
  }

  Widget _buildStepChip(int nomor, String judul, bool aktif, bool selesai) {
    final warna = selesai
        ? AppColors.success
        : (aktif ? AppColors.primary : Colors.grey.shade500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warna.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selesai ? Icons.check_circle : Icons.looks_one_outlined,
            size: 15,
            color: warna,
          ),
          const SizedBox(width: 5),
          Text(
            '$nomor. $judul',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daftarTampil = _filteredItems;
    final jmlSelisih = _items
        .where((e) => ((e['selisih'] as num?)?.toDouble() ?? 0).abs() >= 0.000001)
        .length;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1320, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // HEADER DIALOG
              Row(
                children: [
                  Icon(
                    _terkunciPermanen
                        ? Icons.verified_user
                        : Icons.fact_check_outlined,
                    color: _terkunciPermanen
                        ? AppColors.success
                        : AppColors.primary,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Proses Stok Opname, Berita Acara & Adjustment · ${_dokumen['kode'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Metode: ${_labelJenisSo('${_dokumen['jenisSo'] ?? ''}')}  ·  '
                          'Rak: ${_dokumen['rakNama'] ?? 'Semua Rak'}  ·  '
                          'No. Berita Acara: ${('${_dokumen['nomorBeritaAcara'] ?? ''}').isEmpty ? '(Terbit otomatis saat Cetak BA / Setujui)' : _dokumen['nomorBeritaAcara']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Muat Ulang Perbandingan',
                    onPressed: _memuat
                        ? null
                        : () => _muatDanProsesDokumen(transisiProses: false),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(_adaPerubahan),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // STEPPER ALUR 3 TAHAP
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildStepChip(1, 'Entry Stok Fisik (Draft)', false, true),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  _buildStepChip(
                      2,
                      'Bandingkan, Edit Qty & Cetak Selisih',
                      !_terkunciPermanen,
                      _sudahCetakSelisih || _terkunciPermanen),
                  const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  _buildStepChip(
                      3,
                      'Setujui Adjustment & Kunci Permanen',
                      _sudahCetakSelisih && !_terkunciPermanen,
                      _terkunciPermanen),
                  if (_sudahCetakBa)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '✓ Berita Acara Sudah Dicetak',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.info),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (_terkunciPermanen)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.success),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dokumen ini telah DISETUJUI pada ${_dokumen['disetujuiPada'] ?? '-'} oleh ${_dokumen['disetujuiOleh'] ?? '-'} '
                          'dan TERKUNCI PERMANEN (tidak dapat diedit/dihapus/dibatalkan). Hasil fisik tanggal ${_dokumen['tanggalOpnameIndo'] ?? '-'} '
                          'telah menjadi Saldo Awal hari berikutnya. Anda tetap dapat mencetak Berita Acara & Daftar Selisih kapan saja.',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // METADATA TANGGAL & PETUGAS
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _terkunciPermanen ? null : _pilihTanggalOpname,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                        'Tgl Opname: ${_dokumen['tanggalOpnameIndo'] ?? _dokumen['tanggalOpname'] ?? '-'}'),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: _penghitungCtrl,
                      readOnly: _terkunciPermanen,
                      decoration: const InputDecoration(
                        labelText: 'Petugas Penghitung',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextField(
                      controller: _pengawasCtrl,
                      readOnly: _terkunciPermanen,
                      decoration: const InputDecoration(
                        labelText: 'Pengawas / Kepala Toko',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _ketDokumenCtrl,
                      readOnly: _terkunciPermanen,
                      decoration: const InputDecoration(
                        labelText: 'Catatan Berita Acara',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (!_terkunciPermanen)
                    OutlinedButton.icon(
                      onPressed:
                          _menyimpanHeader ? null : _simpanMetadataHeader,
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: Text(_menyimpanHeader ? 'Menyimpan...' : 'Simpan Info'),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // RINGKASAN ANGKA & FILTER PENCARIAN
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Total: ${_items.length} Item',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                        Text(
                          'Berselisih: $jmlSelisih Item',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: jmlSelisih > 0
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                        Text(
                          'Lebih (+): +${_formatAngka.format(_dokumen['totalSelisihPlus'] ?? 0)}',
                          style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                        Text(
                          'Kurang (-): ${_formatAngka.format(_dokumen['totalSelisihMinus'] ?? 0)}',
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                        Text(
                          'Estimasi Nilai Selisih: ${_formatRupiah.format(_dokumen['totalNilaiSelisih'] ?? 0)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  FilterChip(
                    label: Text('Hanya Selisih ($jmlSelisih)'),
                    selected: _hanyaSelisih,
                    onSelected: (v) => setStateIfMounted(() => _hanyaSelisih = v),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _cariCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Cari kode / nama / rak...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setStateIfMounted(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_pesanError != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.danger),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_pesanError!,
                      style: const TextStyle(color: AppColors.danger)),
                ),

              // TABEL PERBANDINGAN STOK SISTEM VS STOK FISIK
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : daftarTampil.isEmpty
                        ? const Center(
                            child: Text(
                                'Tidak ada rincian barang yang sesuai filter.'))
                        : SingleChildScrollView(
                            child: AppDataTable(
                              minWidth: 1180,
                              emptyText: 'Belum ada item opname.',
                              columns: [
                                const AppTableColumn('Kode / Barcode', flex: 2),
                                const AppTableColumn('Nama Produk', flex: 3),
                                const AppTableColumn('Rak', flex: 2),
                                const AppTableColumn('Sat', flex: 1),
                                const AppTableColumn('Stok Sistem',
                                    flex: 1, align: TextAlign.right),
                                const AppTableColumn('Stok Fisik (Edit)',
                                    flex: 2, align: TextAlign.right),
                                const AppTableColumn('Selisih',
                                    flex: 1, align: TextAlign.right),
                                const AppTableColumn('Nilai Selisih',
                                    flex: 2, align: TextAlign.right),
                                const AppTableColumn('Keterangan', flex: 2),
                                if (!_terkunciPermanen)
                                  const AppTableColumn('Aksi', flex: 2),
                              ],
                              rows: daftarTampil.map((it) {
                                final itemId = (it['id'] as num?)?.toInt() ?? 0;
                                final sis =
                                    (it['stokSistem'] as num?)?.toDouble() ?? 0;
                                final fis =
                                    (it['stokFisik'] as num?)?.toDouble() ?? 0;
                                final sel =
                                    (it['selisih'] as num?)?.toDouble() ?? 0;
                                final nil =
                                    (it['nilaiSelisih'] as num?)?.toDouble() ??
                                        0;
                                final warnaSel = sel.abs() < 0.000001
                                    ? AppColors.textSecondaryOf(context)
                                    : (sel > 0
                                        ? AppColors.success
                                        : AppColors.danger);
                                final cFis = _fisikCtrls.putIfAbsent(
                                    itemId,
                                    () => TextEditingController(
                                        text: _formatAngkaInput(fis)));
                                final cKet = _ketItemCtrls.putIfAbsent(
                                    itemId,
                                    () => TextEditingController(
                                        text: '${it['keterangan'] ?? ''}'));
                                final sedangSimpan =
                                    _menyimpanItemIds.contains(itemId);

                                return AppTableRowData(cells: [
                                  AppTableCell.text(
                                    '${it['kode'] ?? ''}${('${it['barcode'] ?? ''}').isEmpty ? '' : '\n${it['barcode']}'}',
                                    flex: 2,
                                    maxLines: 2,
                                  ),
                                  AppTableCell.text('${it['nama'] ?? ''}',
                                      flex: 3, maxLines: 2),
                                  AppTableCell.text('${it['rakNama'] ?? '-'}',
                                      flex: 2, maxLines: 2),
                                  AppTableCell.text('${it['satuan'] ?? 'PCS'}',
                                      flex: 1),
                                  AppTableCell.text(_formatAngka.format(sis),
                                      flex: 1,
                                      align: TextAlign.right,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  AppTableCell(
                                    flex: 2,
                                    child: _terkunciPermanen
                                        ? Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              _formatAngka.format(fis),
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          )
                                        : SizedBox(
                                            height: 34,
                                            child: TextField(
                                              controller: cFis,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                              textAlign: TextAlign.right,
                                              onSubmitted: (_) =>
                                                  _simpanPerubahanItem(it),
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6),
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                  ),
                                  AppTableCell.text(
                                    '${sel > 0 ? '+' : ''}${_formatAngka.format(sel)}',
                                    flex: 1,
                                    align: TextAlign.right,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: warnaSel),
                                  ),
                                  AppTableCell.text(
                                    _formatRupiah.format(nil),
                                    flex: 2,
                                    align: TextAlign.right,
                                    style: TextStyle(
                                        fontSize: 12, color: warnaSel),
                                  ),
                                  AppTableCell(
                                    flex: 2,
                                    child: _terkunciPermanen
                                        ? Text('${it['keterangan'] ?? '-'}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                const TextStyle(fontSize: 12))
                                        : SizedBox(
                                            height: 34,
                                            child: TextField(
                                              controller: cKet,
                                              onSubmitted: (_) =>
                                                  _simpanPerubahanItem(it),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              decoration: const InputDecoration(
                                                hintText: 'Catatan...',
                                                isDense: true,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 6),
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ),
                                  ),
                                  if (!_terkunciPermanen)
                                    AppTableCell(
                                      flex: 2,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton(
                                            onPressed: sedangSimpan
                                                ? null
                                                : () =>
                                                    _simpanPerubahanItem(it),
                                            child: Text(sedangSimpan
                                                ? '...'
                                                : 'Update'),
                                          ),
                                          IconButton(
                                            tooltip: 'Hapus baris dari draft',
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.danger),
                                            onPressed: sedangSimpan
                                                ? null
                                                : () => _hapusItem(it),
                                          ),
                                        ],
                                      ),
                                    ),
                                ]);
                              }).toList(),
                            ),
                          ),
              ),
              const Divider(height: 18),

              // FOOTER TOMBOL PROSES 3 TAHAP: CETAK SELISIH -> CETAK BA -> SETUJUI ADJUSTMENT
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  Text(
                    !_terkunciPermanen && !_sudahCetakSelisih
                        ? 'Langkah wajib: Tekan "1. Cetak Daftar Selisih" terlebih dahulu sebelum menyetujui Adjustment.'
                        : (_terkunciPermanen
                            ? 'Adjustment selesai & terkunci permanen. Berita Acara dapat dicetak ulang kapan saja.'
                            : 'Daftar Selisih sudah dicetak ✓. Anda dapat mencetak Berita Acara & menyetujui Adjustment sekarang.'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: !_terkunciPermanen && !_sudahCetakSelisih
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: (_items.isEmpty || _mencetakSelisih)
                            ? null
                            : _cetakDaftarSelisihPdf,
                        icon: Icon(
                          _sudahCetakSelisih
                              ? Icons.check_circle
                              : Icons.print_outlined,
                          size: 18,
                          color: _sudahCetakSelisih
                              ? AppColors.success
                              : AppColors.primary,
                        ),
                        label: Text(_mencetakSelisih
                            ? 'Menyiapkan PDF...'
                            : (_sudahCetakSelisih
                                ? '1. Cetak Ulang Daftar Selisih ✓'
                                : '1. Cetak Daftar Selisih (Wajib)')),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_items.isEmpty || _mencetakBa)
                            ? null
                            : _cetakBeritaAcaraPdf,
                        icon: Icon(
                          _sudahCetakBa
                              ? Icons.verified_outlined
                              : Icons.description_outlined,
                          size: 18,
                          color: AppColors.info,
                        ),
                        label: Text(_mencetakBa
                            ? 'Menyiapkan BA...'
                            : '2. Cetak Berita Acara SO (PDF)'),
                      ),
                      if (!_terkunciPermanen)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sudahCetakSelisih
                                ? AppColors.success
                                : Colors.grey.shade600,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: (_items.isEmpty || _menyetujui)
                              ? null
                              : _setujuiAdjustment,
                          icon: const Icon(Icons.task_alt, size: 18),
                          label: Text(_menyetujui
                              ? 'Memproses Adjustment...'
                              : '3. Setujui Opname (Adjustment Stok)'),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog Daftar Dokumen Stok Opname (`DRAFT_ENTRY`, `PROSES_SO`, `DISETUJUI`)
/// untuk seluruh metode (`SO_GRAND`, `INPUT_MANUAL`, `SO_SCAN`, `IMPOR_EXCEL`).
class DaftarDokumenOpnameSheet extends StatefulWidget {
  final String? filterJenisSo;
  final int? filterRakId;

  const DaftarDokumenOpnameSheet({
    super.key,
    this.filterJenisSo,
    this.filterRakId,
  });

  static Future<bool> buka(
    BuildContext context, {
    String? filterJenisSo,
    int? filterRakId,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => DaftarDokumenOpnameSheet(
        filterJenisSo: filterJenisSo,
        filterRakId: filterRakId,
      ),
    );
    return res == true;
  }

  @override
  State<DaftarDokumenOpnameSheet> createState() =>
      _DaftarDokumenOpnameSheetState();
}

class _DaftarDokumenOpnameSheetState extends State<DaftarDokumenOpnameSheet> {
  bool _memuat = true;
  bool _adaPerubahan = false;
  String? _pesanError;
  String _statusFilter = 'SEMUA';
  late String _jenisFilter;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _jenisFilter = widget.filterJenisSo ?? 'SEMUA';
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final res = await ApiClient.instance.aksi('so_dokumen_daftar', {
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (_statusFilter != 'SEMUA') 'status': _statusFilter,
        if (_jenisFilter != 'SEMUA') 'jenis_so': _jenisFilter,
        if (widget.filterRakId != null && widget.filterRakId! > 0)
          'rak_id': widget.filterRakId,
        'limit': 100,
      });
      final list = ((res['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setStateIfMounted(() => _daftar = list);
    } catch (e) {
      if (mounted) setStateIfMounted(() => _pesanError = '$e');
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _hapusDraft(Map<String, dynamic> d) async {
    final id = (d['id'] as num?)?.toInt() ?? 0;
    if (id <= 0) return;
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Draft Dokumen Opname?'),
        content: Text(
            'Hapus draft "${d['kode'] ?? ''}" beserta seluruh item fisik yang belum disetujui?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Hapus Draft', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (konfirmasi != true || !mounted) return;
    try {
      await ApiClient.instance.aksi('so_dokumen_hapus', {
        'dokumen_id': id,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
      });
      _adaPerubahan = true;
      await _muat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menghapus draft: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 740),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.assignment_turned_in_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Daftar Dokumen Stok Opname, Berita Acara & Adjustment',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: _memuat ? null : _muat,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_adaPerubahan),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final st in const [
                    ('SEMUA', 'Semua Status'),
                    ('DRAFT_ENTRY', '1. Entry Fisik (Draft)'),
                    ('PROSES_SO', '2. Proses SO (Bandingkan)'),
                    ('DISETUJUI', '3. Disetujui / Final'),
                  ])
                    ChoiceChip(
                      label: Text(st.$2),
                      selected: _statusFilter == st.$1,
                      onSelected: (_) {
                        setStateIfMounted(() => _statusFilter = st.$1);
                        _muat();
                      },
                    ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _jenisFilter,
                    items: const [
                      DropdownMenuItem(
                          value: 'SEMUA', child: Text('Semua Metode SO')),
                      DropdownMenuItem(
                          value: 'SO_GRAND', child: Text('SO Grand per Rak')),
                      DropdownMenuItem(
                          value: 'INPUT_MANUAL',
                          child: Text('Input Opname Manual')),
                      DropdownMenuItem(
                          value: 'SO_SCAN', child: Text('SO by Scan')),
                      DropdownMenuItem(
                          value: 'IMPOR_EXCEL', child: Text('Unggah Excel')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setStateIfMounted(() => _jenisFilter = v);
                      _muat();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_pesanError != null)
                Text(_pesanError!,
                    style: const TextStyle(color: AppColors.danger)),
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _daftar.isEmpty
                        ? const Center(
                            child: Text(
                                'Belum ada dokumen Stok Opname untuk filter ini.'))
                        : SingleChildScrollView(
                            child: AppDataTable(
                              minWidth: 980,
                              emptyText: 'Belum ada dokumen.',
                              columns: const [
                                AppTableColumn('Kode / BA', flex: 2),
                                AppTableColumn('Tanggal', flex: 1),
                                AppTableColumn('Metode & Rak', flex: 2),
                                AppTableColumn('Item',
                                    flex: 1, align: TextAlign.right),
                                AppTableColumn('Status Tahap', flex: 2),
                                AppTableColumn('Cetak', flex: 2),
                                AppTableColumn('Aksi', flex: 2),
                              ],
                              rows: _daftar.map((d) {
                                final id = (d['id'] as num?)?.toInt() ?? 0;
                                final st =
                                    '${d['status'] ?? 'DRAFT_ENTRY'}'.toUpperCase();
                                final terkunci = d['terkunciPermanen'] == true ||
                                    st == 'DISETUJUI';
                                final cetakSel = d['sudahCetakSelisih'] == true;
                                final cetakBa =
                                    d['sudahCetakBeritaAcara'] == true;
                                final noBa = '${d['nomorBeritaAcara'] ?? ''}';

                                return AppTableRowData(cells: [
                                  AppTableCell.text(
                                    '${d['kode'] ?? '-'}${noBa.isEmpty ? '' : '\nBA: $noBa'}',
                                    flex: 2,
                                    maxLines: 2,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  AppTableCell.text(
                                    '${d['tanggalOpnameIndo'] ?? d['tanggalOpname'] ?? '-'}',
                                    flex: 1,
                                  ),
                                  AppTableCell.text(
                                    '${d['jenisSo'] ?? '-'}\n${d['rakNama'] ?? 'Semua Rak'}',
                                    flex: 2,
                                    maxLines: 2,
                                  ),
                                  AppTableCell.text(
                                    '${d['totalItem'] ?? 0}',
                                    flex: 1,
                                    align: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  AppTableCell(
                                    flex: 2,
                                    child: Text(
                                      terkunci
                                          ? 'Disetujui (Terkunci)'
                                          : (st == 'PROSES_SO'
                                              ? 'Proses SO (Bandingkan)'
                                              : 'Draft Entry Fisik'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: terkunci
                                            ? AppColors.success
                                            : (st == 'PROSES_SO'
                                                ? AppColors.info
                                                : AppColors.warning),
                                      ),
                                    ),
                                  ),
                                  AppTableCell.text(
                                    'Selisih: ${cetakSel ? "Sudah ✓" : "Belum"}\nBA: ${cetakBa ? "Sudah ✓" : "Belum"}',
                                    flex: 2,
                                    maxLines: 2,
                                  ),
                                  AppTableCell(
                                    flex: 2,
                                    child: Wrap(
                                      spacing: 4,
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: terkunci
                                                ? AppColors.info
                                                : AppColors.primary,
                                            foregroundColor: Colors.white,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          onPressed: () async {
                                            final berubah =
                                                await ProsesStokOpnameDialog
                                                    .buka(context,
                                                        dokumenId: id);
                                            if (berubah) {
                                              _adaPerubahan = true;
                                              await _muat();
                                            }
                                          },
                                          child: Text(terkunci
                                              ? 'Lihat / Cetak BA'
                                              : 'Proses & Adjustment'),
                                        ),
                                        if (!terkunci)
                                          IconButton(
                                            tooltip: 'Hapus Draft',
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: AppColors.danger),
                                            onPressed: () => _hapusDraft(d),
                                          ),
                                      ],
                                    ),
                                  ),
                                ]);
                              }).toList(),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
