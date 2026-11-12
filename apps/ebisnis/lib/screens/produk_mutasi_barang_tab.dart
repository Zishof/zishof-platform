import 'dart:convert';
import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../sesi.dart';
import '../services/simple_xlsx.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/rincian_intip_dialog.dart';
import 'pergerakan_stok_tab.dart';
import '../services/simpan_berkas_helper.dart';

final _mutasiRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _mutasiAngka = NumberFormat('#,##0.##', 'id_ID');
final _mutasiTanggal = DateFormat('yyyy-MM-dd');

class ProdukMutasiBarangTab extends StatefulWidget {
  final bool modePerTanggalLengkap;
  const ProdukMutasiBarangTab({
    super.key,
    this.modePerTanggalLengkap = false,
  });

  @override
  State<ProdukMutasiBarangTab> createState() => _ProdukMutasiBarangTabState();
}

class _ProdukMutasiBarangTabState extends State<ProdukMutasiBarangTab>
    with JejakGalat {
  int get _pageSize => 15;
  late DateTime _dari;
  late DateTime _sampai;
  int _halaman = 1;
  int _total = 0;
  bool _memuat = true;
  bool _mengekspor = false;
  String? _error;
  String _keyword = '';
  DateTime? _waktuCacheMutasiPerTanggal;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic> _summary = {};
  Map<String, Map<String, dynamic>> _summaryPerTanggalMap = {};

  /// Diff emisi "lokal dulu" -- menggerakkan animasi kilau baris yang
  /// baru/berubah di server.
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dari = DateTime(now.year, now.month, 1);
    _sampai = now;
    _muat();
  }

  Map<String, dynamic> _payload({int? page, int? pageSize}) => {
        'dari': _mutasiTanggal.format(_dari),
        'sampai': _mutasiTanggal.format(_sampai),
        'page': page ?? _halaman,
        'page_size': pageSize ?? _pageSize,
        if (widget.modePerTanggalLengkap) 'per_tanggal': true,
        if (_keyword.trim().isNotEmpty) 'keyword': _keyword.trim(),
      };

  /// Kunci salinan harian memuat cakupan pengguna, tenant, toko, tanggal,
  /// filter, dan halaman agar cache lintas konteks tidak tercampur.
  String get _cacheKeyMutasiPerTanggal =>
      'master:mutasi_per_tanggal:${Sesi.instance.tenantId ?? 'umum'}:'
      '${Sesi.instance.userId.trim().toLowerCase()}:'
      '${Sesi.instance.idTokoTerpilih ?? 'semua'}:'
      '${_mutasiTanggal.format(_dari)}:${_mutasiTanggal.format(_sampai)}:'
      '${_keyword.trim().toLowerCase().isEmpty ? '-' : _keyword.trim().toLowerCase()}:'
      '$_halaman:$_pageSize';

  /// Memastikan kelompok dan subtotal hanya ditampilkan bila server memberi
  /// tanggal setiap baris serta ringkasan lengkap untuk setiap tanggal.
  Map<String, dynamic> _validasiHasilMutasiPerTanggal(
      Map<String, dynamic> hasil) {
    final data = ((hasil['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (data.any((row) => '${row['tanggal'] ?? ''}'.trim().isEmpty)) {
      throw const FormatException('Baris mutasi tanpa tanggal tidak sah.');
    }
    final tanggalRingkasan = {
      for (final item in ((hasil['summaryPerTanggal'] as List?) ?? const [])
          .whereType<Map>())
        '${item['tanggal'] ?? ''}'.trim(),
    };
    if (data
        .any((row) => !tanggalRingkasan.contains('${row['tanggal']}'.trim()))) {
      throw const FormatException('Subtotal harian belum tersedia lengkap.');
    }
    return {
      ...hasil,
      'data': data,
      'total': (hasil['total'] as num?)?.toInt() ?? data.length,
      'summary': (hasil['summary'] as Map?)?.cast<String, dynamic>() ?? {},
    };
  }

  void _terapkanHasilMutasiPerTanggal(
    Map<String, dynamic> hasil, {
    required bool dariCache,
    DateTime? disimpanPada,
  }) {
    _data = (hasil['data'] as List).cast<Map<String, dynamic>>();
    _total = (hasil['total'] as num?)?.toInt() ?? _data.length;
    _summary = (hasil['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    _terapkanSummaryPerTanggal(hasil);
    _waktuCacheMutasiPerTanggal = dariCache ? disimpanPada : null;
    _memuat = false;
  }

  String _formatLabelTanggalGrup(String tglIso) {
    try {
      final dt = DateTime.parse(tglIso);
      return DateFormat('dd/MM/yyyy (EEEE, dd MMMM yyyy)', 'id_ID').format(dt);
    } catch (_) {
      return tglIso.isEmpty ? '-' : tglIso;
    }
  }

  void _terapkanSummaryPerTanggal(Map<String, dynamic> hasil) {
    final map = <String, Map<String, dynamic>>{};
    final rawList = hasil['summaryPerTanggal'];
    if (rawList is List) {
      for (final item in rawList.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final tgl = '${m['tanggal'] ?? ''}'.trim();
        if (tgl.isNotEmpty) {
          map[tgl] = m;
        }
      }
    }
    _summaryPerTanggalMap = map;
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
      if (widget.modePerTanggalLengkap) {
        _waktuCacheMutasiPerTanggal = null;
      }
    });
    try {
      if (widget.modePerTanggalLengkap) {
        // Jangan mengganti rincian harian dengan ringkasan periode. Respons
        // ringkasan tidak memiliki tanggal transaksi per baris; menambahkan
        // tanggal akhir akan menghasilkan pengelompokan dan subtotal palsu.
        Map<String, dynamic>? cacheLokal;
        try {
          final tersimpan = await CoreDb.instance
              .ambilCacheReferensi(_cacheKeyMutasiPerTanggal);
          if (tersimpan != null) {
            final mentah = jsonDecode(tersimpan) as Map<String, dynamic>;
            final waktu = DateTime.tryParse('${mentah['_cacheWaktu'] ?? ''}');
            cacheLokal = _validasiHasilMutasiPerTanggal(mentah);
            if (!mounted) return;
            setStateIfMounted(() => _terapkanHasilMutasiPerTanggal(
                  cacheLokal!,
                  dariCache: true,
                  disimpanPada: waktu,
                ));
            await Future<void>.delayed(Duration.zero);
          }
        } catch (_) {
          cacheLokal = null; // cache rusak/tidak cocok: lanjut minta server.
        }
        try {
          final hasilServer = await ApiClient.instance
              .aksi('produk_mutasi_per_tanggal', _payload());
          final hasil = _validasiHasilMutasiPerTanggal(hasilServer);
          try {
            await CoreDb.instance.simpanCacheReferensi(
              _cacheKeyMutasiPerTanggal,
              jsonEncode({
                ...hasil,
                '_cacheWaktu': DateTime.now().toIso8601String(),
              }),
            );
          } catch (_) {
            // Kegagalan menulis cache tidak boleh menyembunyikan hasil server
            // yang sudah valid; layar tetap menampilkan data terbaru.
          }
          if (!mounted) return;
          setStateIfMounted(() => _terapkanHasilMutasiPerTanggal(
                hasil,
                dariCache: false,
              ));
        } on ApiException catch (e) {
          if (cacheLokal != null && e.offline) return;
          rethrow;
        }
        return;
      }

      // Baca LOKAL DULU (MasterOffline.daftarCacheDulu): tabel tampil seketika
      // dari cache, hasil server menyusul + diff utk kilau baris. Cache
      // dipisah per toko dan rentang tanggal karena seluruh kolom saldo/nilai baris
      // hanya sahih untuk toko dan periode itu.
      await MasterOffline.daftarCacheDulu(
        'produk_mutasi_ringkasan',
        _payload(),
        'master:mutasi_barang:${Sesi.instance.idTokoTerpilih ?? "semua"}:${_mutasiTanggal.format(_dari)}_${_mutasiTanggal.format(_sampai)}',
        // Baris ringkasan mutasi tidak ber-'id'; satu-satunya kolom identitas
        // yang dikirim server adalah kode barang (unik per produk). Baris yang
        // kebetulan tanpa kode tetap aman: MasterOffline memperlakukannya
        // sebagai "baris tanpa kunci" (tidak digandakan di cache), hanya saja
        // tidak ikut berkilau.
        kolomKunci: 'kode',
        onData: (hasil) {
          if (!mounted) return;
          setStateIfMounted(() {
            _data = _diff.terapkan(hasil);
            _total = _diff.total ?? _data.length;
            // Baris TOTAL memakai summary server -- hanya ada pada emisi
            // server, jadi nilai terakhir dipertahankan saat emisi lokal.
            if (_diff.dariServer) {
              _summary =
                  (hasil['summary'] as Map?)?.cast<String, dynamic>() ?? {};
            }
            _memuat = false;
          });
        },
      );
    } catch (e) {
      setStateIfMounted(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _pilihTanggal(bool mulai) async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: mulai ? _dari : _sampai,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (hasil == null) return;
    setStateIfMounted(() {
      if (mulai) {
        _dari = hasil;
        if (_sampai.isBefore(_dari)) _sampai = _dari;
      } else {
        _sampai = hasil;
        if (_dari.isAfter(_sampai)) _dari = _sampai;
      }
      _halaman = 1;
    });
    await _muat();
  }

  Future<List<Map<String, dynamic>>> _ambilSemua() async {
    final semua = <Map<String, dynamic>>[];
    var page = 1;
    final namaAksi = widget.modePerTanggalLengkap
        ? 'produk_mutasi_per_tanggal'
        : 'produk_mutasi_ringkasan';
    while (true) {
      Map<String, dynamic> hasil;
      try {
        hasil = await ApiClient.instance
            .aksi(namaAksi, _payload(page: page, pageSize: 500));
      } catch (_) {
        // Ekspor harus mempertahankan tingkat rincian yang sama dengan layar.
        // Ringkasan agregat bukan pengganti yang sah untuk ekspor per tanggal.
        rethrow;
      }
      final bagian = ((hasil['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (widget.modePerTanggalLengkap &&
          bagian.any((row) => '${row['tanggal'] ?? ''}'.trim().isEmpty)) {
        throw const FormatException(
          'Ekspor dihentikan karena ada baris mutasi tanpa tanggal.',
        );
      }
      semua.addAll(bagian);
      final total = (hasil['total'] as num?)?.toInt() ?? semua.length;
      if (bagian.isEmpty || semua.length >= total) break;
      page++;
    }
    return semua;
  }

  static const _headersRingkasan = [
    'Kategori Barang',
    'Kode Barang',
    'UPC/Barcode',
    'Nama Barang & Jasa',
    'Saldo Awal',
    'Nilai Awal',
    'Masuk',
    'Nilai Masuk',
    'Keluar',
    'Nilai Keluar',
    'Retur',
    'Nilai Retur',
    'Koreksi SO (Ajusmen)',
    'Nilai Ajusmen',
    'Saldo Akhir',
    'Nilai Akhir',
  ];

  static const _headersPerTanggal = [
    'Tanggal',
    'Kategori Barang',
    'Kode Barang',
    'UPC/Barcode',
    'Nama Barang & Jasa',
    'Saldo Awal',
    'Nilai Awal',
    'Masuk',
    'Nilai Masuk',
    'Keluar',
    'Nilai Keluar',
    'Retur',
    'Nilai Retur',
    'Koreksi SO (Ajusmen)',
    'Nilai Ajusmen',
    'Saldo Akhir',
    'Nilai Akhir',
  ];

  List<String> get _headers =>
      widget.modePerTanggalLengkap ? _headersPerTanggal : _headersRingkasan;

  List<dynamic> _baris(Map<String, dynamic> r) => [
        if (widget.modePerTanggalLengkap) r['tanggal'] ?? '',
        r['kategori'] ?? '',
        r['kode'] ?? '',
        r['barcode'] ?? '',
        r['nama'] ?? '',
        r['saldoAwal'] ?? 0,
        r['nilaiAwal'] ?? 0,
        r['masuk'] ?? 0,
        r['nilaiMasuk'] ?? 0,
        r['keluar'] ?? 0,
        r['nilaiKeluar'] ?? 0,
        r['retur'] ?? 0,
        r['nilaiRetur'] ?? 0,
        r['penyesuaian'] ?? 0,
        r['nilaiPenyesuaian'] ?? 0,
        r['saldoAkhir'] ?? 0,
        r['nilaiAkhir'] ?? 0,
      ];

  List<dynamic> _barisSubtotalTanggal(String tgl, Map<String, dynamic> st) => [
        'SUBTOTAL ($tgl)',
        '',
        '',
        '',
        '${st['jumlahProduk'] ?? 0} Produk',
        st['saldoAwal'] ?? 0,
        st['nilaiAwal'] ?? 0,
        st['masuk'] ?? 0,
        st['nilaiMasuk'] ?? 0,
        st['keluar'] ?? 0,
        st['nilaiKeluar'] ?? 0,
        st['retur'] ?? 0,
        st['nilaiRetur'] ?? 0,
        st['penyesuaian'] ?? 0,
        st['nilaiPenyesuaian'] ?? 0,
        st['saldoAkhir'] ?? 0,
        st['nilaiAkhir'] ?? 0,
      ];

  List<dynamic> _barisTotal() => [
        'TOTAL KESELURUHAN',
        if (widget.modePerTanggalLengkap) '',
        '',
        '',
        '',
        _summary['saldoAwal'] ?? 0,
        _summary['nilaiAwal'] ?? 0,
        _summary['masuk'] ?? 0,
        _summary['nilaiMasuk'] ?? 0,
        _summary['keluar'] ?? 0,
        _summary['nilaiKeluar'] ?? 0,
        _summary['retur'] ?? 0,
        _summary['nilaiRetur'] ?? 0,
        _summary['penyesuaian'] ?? 0,
        _summary['nilaiPenyesuaian'] ?? 0,
        _summary['saldoAkhir'] ?? 0,
        _summary['nilaiAkhir'] ?? 0,
      ];

  List<List<dynamic>> _susunBarisEkspor(List<Map<String, dynamic>> semua) {
    if (!widget.modePerTanggalLengkap) {
      return [...semua.map(_baris), _barisTotal()];
    }
    final hasil = <List<dynamic>>[];
    String? tglAktif;
    for (var i = 0; i < semua.length; i++) {
      final r = semua[i];
      final tgl = '${r['tanggal'] ?? _mutasiTanggal.format(_sampai)}'.trim();
      if (tglAktif != tgl) {
        tglAktif = tgl;
      }
      hasil.add(_baris(r));
      final nextTgl = (i + 1 < semua.length)
          ? '${semua[i + 1]['tanggal'] ?? _mutasiTanggal.format(_sampai)}'
              .trim()
          : null;
      if (nextTgl != tgl) {
        final st = _summaryPerTanggalMap[tgl] ?? const <String, dynamic>{};
        hasil.add(_barisSubtotalTanggal(tgl, st));
      }
    }
    hasil.add(_barisTotal());
    return hasil;
  }

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      final bytes = buildSimpleXlsx(
        sheetName: widget.modePerTanggalLengkap
            ? 'Mutasi per Tanggal'
            : 'Mutasi Barang',
        headers: _headers,
        rows: _susunBarisEkspor(semua),
      );
      final prefix = widget.modePerTanggalLengkap
          ? 'Mutasi_Barang_per_Tanggal'
          : 'Mutasi_Barang';
      final nama =
          '${prefix}_${_mutasiTanggal.format(_dari)}_sd_${_mutasiTanggal.format(_sampai)}.xlsx';
      final path = await SimpanBerkasHelper.simpanBytes(
        dialogTitle: 'Simpan Ringkasan Mutasi Barang',
        fileName: nama,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null) await File(path).writeAsBytes(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat Excel: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  Future<void> _cetakPdf() async {
    setStateIfMounted(() => _mengekspor = true);
    try {
      final semua = await _ambilSemua();
      final startNumIdx = widget.modePerTanggalLengkap ? 5 : 4;
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a3.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (_) => pw.Column(children: [
          pw.Text(
              widget.modePerTanggalLengkap
                  ? 'Mutasi Barang per Tanggal (Dikelompokkan per Tanggal)'
                  : 'Ringkasan Mutasi Gudang',
              style:
                  pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              '${_mutasiTanggal.format(_dari)} s/d ${_mutasiTanggal.format(_sampai)}'),
          pw.SizedBox(height: 10),
        ]),
        build: (_) => [
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: _susunBarisEkspor(semua).map((row) {
              return row.asMap().entries.map((e) {
                if (e.key >= startNumIdx && e.value is num) {
                  final isRupiah = (e.key - startNumIdx).isOdd;
                  return isRupiah
                      ? _mutasiRp.format(e.value)
                      : _mutasiAngka.format(e.value);
                }
                return '${e.value}';
              }).toList();
            }).toList(),
            headerStyle:
                pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue100),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {
              for (var i = 0; i < startNumIdx; i++) i: pw.Alignment.centerLeft,
            },
          ),
        ],
      ));
      await Printing.layoutPdf(
          name:
              'Mutasi_Barang_${_mutasiTanggal.format(_dari)}_${_mutasiTanggal.format(_sampai)}.pdf',
          onLayout: (_) => doc.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuat PDF: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengekspor = false);
    }
  }

  /// Membuka buku besar produk terpilih dalam periode yang sedang ditampilkan.
  Future<void> _bukaRincian(Map<String, dynamic> produk) async {
    final id = (produk['id'] as num?)?.toInt();
    if (id == null || id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Rincian belum tersedia untuk produk ini. Muat ulang data lalu coba lagi.'),
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => DialogDetailPergerakanStok(
        idProduk: id,
        namaProduk: '${produk['nama'] ?? '-'}',
        kodeProduk: '${produk['kode'] ?? ''}',
        kategori: '${produk['kategori'] ?? '-'}',
        tglMulai: _dari,
        tglSampai: _sampai,
      ),
    );
  }

  /// Membuka Menu Cerdas Analisis Otomatis untuk 1 produk (kronologi penyebab stok berubah/loncat siap WA).
  Future<void> _bukaAnalisisCerdasProduk(Map<String, dynamic> produk) async {
    final id = (produk['id'] as num?)?.toInt();
    if (id == null || id <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Analisis belum tersedia untuk produk ini. Muat ulang data lalu coba lagi.'),
      ));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => DialogAnalisisCerdasStok(
        idProduk: id,
        namaProduk: '${produk['nama'] ?? '-'}',
        kodeProduk: '${produk['kode'] ?? ''}',
        tglMulai: _dari,
        tglSampai: _sampai,
      ),
    );
  }

  /// Membuka Menu Cerdas Analisis Otomatis untuk seluruh toko pada periode aktif.
  Future<void> _bukaAnalisisCerdasToko() async {
    await showDialog<void>(
      context: context,
      builder: (_) => DialogAnalisisCerdasStok(
        idProduk: null,
        namaProduk: 'Seluruh Produk Toko',
        kodeProduk: '',
        tglMulai: _dari,
        tglSampai: _sampai,
      ),
    );
  }

  Future<void> _tampilkanRincianKolomTotal(
      String labelKolom, String keyQty, String keyNilai) async {
    await tampilkanRincianKlikDialog(
      context,
      judul:
          'Rincian $labelKolom (${_mutasiTanggal.format(_dari)} s/d ${_mutasiTanggal.format(_sampai)})',
      subjudul: 'Daftar produk pada halaman ini beserta $labelKolom',
      kolom: [
        'Kategori',
        'Kode Barang',
        'Nama Barang & Jasa',
        labelKolom,
        'Nilai (Rp)',
      ],
      baris: _data
          .map((r) => <Object?>[
                r['kategori'] ?? '-',
                r['kode'] ?? '-',
                r['nama'] ?? '-',
                _mutasiAngka.format((r[keyQty] as num?) ?? 0),
                _mutasiRp.format((r[keyNilai] as num?) ?? 0),
              ])
          .toList(),
      barisTotal: [
        'TOTAL KESELURUHAN',
        '',
        '',
        _mutasiAngka.format((_summary[keyQty] as num?) ?? 0),
        _mutasiRp.format((_summary[keyNilai] as num?) ?? 0),
      ],
    );
  }

  AppTableCell _angkaCell(dynamic v,
          {bool rupiah = false, VoidCallback? onTap}) =>
      AppTableCell(
        width: 105,
        align: TextAlign.right,
        child: onTap == null
            ? Text(
                rupiah
                    ? _mutasiRp.format((v as num?) ?? 0)
                    : _mutasiAngka.format((v as num?) ?? 0),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5),
              )
            : InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Text(
                    rupiah
                        ? _mutasiRp.format((v as num?) ?? 0)
                        : _mutasiAngka.format((v as num?) ?? 0),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                      decorationColor:
                          AppColors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
      );

  AppTableRowData _barisDataProduk(Map<String, dynamic> r) => AppTableRowData(
        cells: [
          if (widget.modePerTanggalLengkap)
            AppTableCell(
              width: 105,
              child: Text(
                '${r['tanggal'] ?? '-'}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          AppTableCell(
            width: 130,
            child: KilauBaris(
              kunci: MasterOffline.kunciBaris(r, 'kode'),
              idBaru: _diff.idBaru,
              idBerubah: _diff.idBerubah,
              child: Text('${r['kategori'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          AppTableCell.text('${r['kode'] ?? '-'}', width: 95),
          AppTableCell.text('${r['barcode'] ?? '-'}', width: 110),
          AppTableCell(
            width: 220,
            child: InkWell(
              onTap: () => _bukaRincian(r),
              child: Text(
                '${r['nama'] ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          _angkaCell(r['saldoAwal'], onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiAwal'],
              rupiah: true, onTap: () => _bukaRincian(r)),
          _angkaCell(r['masuk'], onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiMasuk'],
              rupiah: true, onTap: () => _bukaRincian(r)),
          _angkaCell(r['keluar'], onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiKeluar'],
              rupiah: true, onTap: () => _bukaRincian(r)),
          _angkaCell(r['retur'] ?? 0, onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiRetur'] ?? 0,
              rupiah: true, onTap: () => _bukaRincian(r)),
          _angkaCell(r['penyesuaian'] ?? 0, onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiPenyesuaian'] ?? 0,
              rupiah: true, onTap: () => _bukaRincian(r)),
          _angkaCell(r['saldoAkhir'], onTap: () => _bukaRincian(r)),
          _angkaCell(r['nilaiAkhir'],
              rupiah: true, onTap: () => _bukaRincian(r)),
          AppTableCell(
            width: 64,
            align: TextAlign.center,
            child: AksiBarisMenu(aksi: [
              AksiBaris(
                ikon: Icons.auto_awesome_outlined,
                label: 'Analisis cerdas produk (Siap WA)',
                onTap: () => _bukaAnalisisCerdasProduk(r),
              ),
              AksiBaris(
                ikon: Icons.receipt_long_outlined,
                label: 'Lihat rincian mutasi',
                onTap: () => _bukaRincian(r),
              ),
            ]),
          ),
        ],
      );

  AppTableRowData _barisHeaderGrupTanggal(String tgl, int jmlProduk) =>
      AppTableRowData(
        backgroundColor: AppColors.primary.withValues(alpha: 0.10),
        cells: [
          AppTableCell(
            width: 105,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month, size: 15, color: AppColors.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    tgl,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AppTableCell(
            width: 130,
            child: Text(
              'GRUP TANGGAL',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: AppColors.primary,
              ),
            ),
          ),
          const AppTableCell(width: 95, child: SizedBox.shrink()),
          const AppTableCell(width: 110, child: SizedBox.shrink()),
          AppTableCell(
            width: 220,
            child: Text(
              '${_formatLabelTanggalGrup(tgl)} · $jmlProduk Produk',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.primary,
              ),
            ),
          ),
          for (var i = 0; i < 12; i++)
            const AppTableCell(width: 105, child: SizedBox.shrink()),
          const AppTableCell(width: 64, child: SizedBox.shrink()),
        ],
      );

  AppTableRowData _barisSummaryGrupTanggal(
      String tgl, Map<String, dynamic> st) {
    final jml = (st['jumlahProduk'] as num?)?.toInt() ?? 0;
    return AppTableRowData(
      backgroundColor: Colors.amber.withValues(alpha: 0.12),
      cells: [
        AppTableCell(
          width: 105,
          child: Text(
            'SUBTOTAL',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: Colors.brown.shade800,
            ),
          ),
        ),
        AppTableCell(
          width: 130,
          child: Text(
            tgl,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              color: Colors.brown.shade800,
            ),
          ),
        ),
        const AppTableCell(width: 95, child: SizedBox.shrink()),
        const AppTableCell(width: 110, child: SizedBox.shrink()),
        AppTableCell(
          width: 220,
          child: Text(
            'Summary Tanggal $tgl ($jml Produk)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: Colors.brown.shade800,
            ),
          ),
        ),
        _angkaCell(st['saldoAwal'] ?? 0),
        _angkaCell(st['nilaiAwal'] ?? 0, rupiah: true),
        _angkaCell(st['masuk'] ?? 0),
        _angkaCell(st['nilaiMasuk'] ?? 0, rupiah: true),
        _angkaCell(st['keluar'] ?? 0),
        _angkaCell(st['nilaiKeluar'] ?? 0, rupiah: true),
        _angkaCell(st['retur'] ?? 0),
        _angkaCell(st['nilaiRetur'] ?? 0, rupiah: true),
        _angkaCell(st['penyesuaian'] ?? 0),
        _angkaCell(st['nilaiPenyesuaian'] ?? 0, rupiah: true),
        _angkaCell(st['saldoAkhir'] ?? 0),
        _angkaCell(st['nilaiAkhir'] ?? 0, rupiah: true),
        const AppTableCell(width: 64, child: SizedBox.shrink()),
      ],
    );
  }

  List<AppTableRowData> _bangunBarisTabel() {
    if (!widget.modePerTanggalLengkap) {
      return _data.map(_barisDataProduk).toList();
    }
    final hasil = <AppTableRowData>[];
    String? tglAktif;
    for (var i = 0; i < _data.length; i++) {
      final r = _data[i];
      final tgl = '${r['tanggal'] ?? _mutasiTanggal.format(_sampai)}'.trim();
      final st = _summaryPerTanggalMap[tgl] ?? const <String, dynamic>{};
      if (tglAktif != tgl) {
        tglAktif = tgl;
        final jml = (st['jumlahProduk'] as num?)?.toInt() ??
            _data.where((x) => '${x['tanggal'] ?? ''}'.trim() == tgl).length;
        hasil.add(_barisHeaderGrupTanggal(tgl, jml));
      }
      hasil.add(_barisDataProduk(r));
      final nextTgl = (i + 1 < _data.length)
          ? '${_data[i + 1]['tanggal'] ?? _mutasiTanggal.format(_sampai)}'
              .trim()
          : null;
      if (nextTgl != tgl) {
        hasil.add(_barisSummaryGrupTanggal(tgl, st));
      }
    }
    return hasil;
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman = (_total / _pageSize).ceil().clamp(1, 999999);
    final rows = _bangunBarisTabel();
    final totalRow = AppTableRowData(
        backgroundColor: AppColors.primary.withValues(alpha: 0.06),
        cells: [
          if (widget.modePerTanggalLengkap)
            const AppTableCell(
                width: 105,
                child: Text('TOTAL',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          AppTableCell(
              width: 130,
              child: Text(
                  widget.modePerTanggalLengkap ? 'SEMUA TANGGAL' : 'TOTAL',
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          const AppTableCell(width: 95, child: SizedBox.shrink()),
          const AppTableCell(width: 110, child: SizedBox.shrink()),
          const AppTableCell(width: 220, child: SizedBox.shrink()),
          _angkaCell(_summary['saldoAwal'],
              onTap: () => _tampilkanRincianKolomTotal(
                  'Saldo Awal', 'saldoAwal', 'nilaiAwal')),
          _angkaCell(_summary['nilaiAwal'],
              rupiah: true,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Saldo Awal', 'saldoAwal', 'nilaiAwal')),
          _angkaCell(_summary['masuk'],
              onTap: () => _tampilkanRincianKolomTotal(
                  'Barang Masuk', 'masuk', 'nilaiMasuk')),
          _angkaCell(_summary['nilaiMasuk'],
              rupiah: true,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Barang Masuk', 'masuk', 'nilaiMasuk')),
          _angkaCell(_summary['keluar'],
              onTap: () => _tampilkanRincianKolomTotal(
                  'Barang Keluar', 'keluar', 'nilaiKeluar')),
          _angkaCell(_summary['nilaiKeluar'],
              rupiah: true,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Barang Keluar', 'keluar', 'nilaiKeluar')),
          _angkaCell(_summary['retur'] ?? 0,
              onTap: () =>
                  _tampilkanRincianKolomTotal('Retur', 'retur', 'nilaiRetur')),
          _angkaCell(_summary['nilaiRetur'] ?? 0,
              rupiah: true,
              onTap: () =>
                  _tampilkanRincianKolomTotal('Retur', 'retur', 'nilaiRetur')),
          _angkaCell(_summary['penyesuaian'] ?? 0,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Koreksi SO (Ajusmen)', 'penyesuaian', 'nilaiPenyesuaian')),
          _angkaCell(_summary['nilaiPenyesuaian'] ?? 0,
              rupiah: true,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Koreksi SO (Ajusmen)', 'penyesuaian', 'nilaiPenyesuaian')),
          _angkaCell(_summary['saldoAkhir'],
              onTap: () => _tampilkanRincianKolomTotal(
                  'Saldo Akhir', 'saldoAkhir', 'nilaiAkhir')),
          _angkaCell(_summary['nilaiAkhir'],
              rupiah: true,
              onTap: () => _tampilkanRincianKolomTotal(
                  'Saldo Akhir', 'saldoAkhir', 'nilaiAkhir')),
          const AppTableCell(width: 64, child: SizedBox.shrink()),
        ]);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Column(children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: () => _pilihTanggal(true),
              icon: const Icon(Icons.calendar_today_outlined, size: 17),
              label: Text('Dari ${_mutasiTanggal.format(_dari)}')),
          OutlinedButton.icon(
              onPressed: () => _pilihTanggal(false),
              icon: const Icon(Icons.event_outlined, size: 17),
              label: Text('Sampai ${_mutasiTanggal.format(_sampai)}')),
          AksiToolbarMenu(
            tooltip: 'Aksi pergerakan produk',
            aksi: [
              AksiBaris(
                ikon: Icons.auto_awesome,
                label: 'Analisis Cerdas Toko',
                onTap: _bukaAnalisisCerdasToko,
              ),
              AksiBaris(
                ikon: Icons.table_view_outlined,
                label: 'Download Excel',
                onTap: () {
                  if (!_mengekspor) _unduhExcel();
                },
              ),
              AksiBaris(
                ikon: Icons.picture_as_pdf_outlined,
                label: 'Cetak PDF',
                onTap: () {
                  if (!_mengekspor) _cetakPdf();
                },
              ),
              AksiBaris(
                ikon: Icons.refresh,
                label: 'Muat Ulang',
                onTap: _muat,
              ),
            ],
          ),
        ]),
        const SizedBox(height: 10),
        AppSearchField(
          hintText: 'Cari kategori / kode / barcode / nama barang...',
          scanProduk: true,
          debounce: const Duration(milliseconds: 400),
          onChanged: (v) {
            _keyword = v;
            _halaman = 1;
            _muat();
          },
        ),
        if (_mengekspor) const LinearProgressIndicator(),
        if (widget.modePerTanggalLengkap && _waktuCacheMutasiPerTanggal != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Menampilkan salinan tersimpan (${DateFormat('dd/MM/yyyy HH:mm').format(_waktuCacheMutasiPerTanggal!)}); pembaruan terbaru belum tersedia.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.danger, size: 42),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      AppDetailGalatOpsional(detail: detailUntuk(_error)),
                      TextButton(
                          onPressed: _muat, child: const Text('Coba Lagi')),
                    ]))
                  : AppDataTable(
                      minWidth: widget.modePerTanggalLengkap ? 2049 : 1944,
                      horizontalScroll: true,
                      emptyText: 'Belum ada data mutasi barang.',
                      columns: [
                        if (widget.modePerTanggalLengkap)
                          const AppTableColumn('Tanggal', width: 105),
                        const AppTableColumn('Kategori Barang', width: 130),
                        const AppTableColumn('Kode Barang', width: 95),
                        const AppTableColumn('UPC/Barcode', width: 110),
                        const AppTableColumn('Nama Barang & Jasa', width: 220),
                        const AppTableColumn('Saldo Awal',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Awal',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Masuk',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Masuk',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Keluar',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Keluar',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Retur',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Retur',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Ajusmen SO',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Ajusmen',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Saldo Akhir',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Nilai Akhir',
                            width: 105, align: TextAlign.right),
                        const AppTableColumn('Aksi',
                            width: 64, align: TextAlign.center),
                      ],
                      rows: [...rows, if (_data.isNotEmpty) totalRow],
                      pagination: AppTablePagination(
                        halaman: _halaman,
                        totalHalaman: totalHalaman,
                        totalData: _total,
                        labelData: 'produk',
                        onSebelumnya: _halaman > 1
                            ? () {
                                _halaman--;
                                _muat();
                              }
                            : null,
                        onBerikutnya: _halaman < totalHalaman
                            ? () {
                                _halaman++;
                                _muat();
                              }
                            : null,
                      ),
                    ),
        ),
      ]),
    );
  }
}
