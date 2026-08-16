import 'dart:io';
import 'dart:math' as math;

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
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

final _rpAnalisis =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _tanggalAnalisis = DateFormat('yyyy-MM-dd');

class RiwayatPenjualanAnalisisScreen extends StatefulWidget {
  const RiwayatPenjualanAnalisisScreen({super.key});

  @override
  State<RiwayatPenjualanAnalisisScreen> createState() =>
      _RiwayatPenjualanAnalisisScreenState();
}

class _RiwayatPenjualanAnalisisScreenState
    extends State<RiwayatPenjualanAnalisisScreen> {
  DateTime _mulai = DateTime.now().subtract(const Duration(days: 29));
  DateTime _sampai = DateTime.now();
  bool _memuat = true;
  String? _error;
  Map<String, dynamic>? _hasil;
  int _bagian = 0;

  Map<String, dynamic> get _kpi =>
      Map<String, dynamic>.from((_hasil?['kpi'] as Map?) ?? const {});
  Map<String, dynamic> get _pembanding =>
      Map<String, dynamic>.from((_hasil?['pembanding'] as Map?) ?? const {});
  Map<String, dynamic> get _retur =>
      Map<String, dynamic>.from((_hasil?['retur'] as Map?) ?? const {});
  Map<String, dynamic> get _laba =>
      Map<String, dynamic>.from((_hasil?['labaKotor'] as Map?) ?? const {});
  Map<String, dynamic> get _labaRingkasan =>
      Map<String, dynamic>.from((_laba['ringkasan'] as Map?) ?? const {});
  Map<String, dynamic> get _labaPembanding => Map<String, dynamic>.from(
      (_hasil?['labaKotorPembanding'] as Map?) ?? const {});

  List<Map<String, dynamic>> _daftar(String kunci) =>
      ((_hasil?[kunci] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  List<Map<String, dynamic>> _daftarLaba(String kunci) =>
      ((_laba[kunci] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('laporan_riwayat_penjualan_analitik', {
        'tglMulai': _tanggalAnalisis.format(_mulai),
        'tglSampai': _tanggalAnalisis.format(_sampai),
      });
      setStateIfMounted(() => _hasil = hasil);
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'memuat analisis riwayat penjualan');
      }
    } finally {
      setStateIfMounted(() => _memuat = false);
    }
  }

  void _preset(int hari) {
    final sekarang = DateTime.now();
    setState(() {
      _sampai = sekarang;
      _mulai = sekarang.subtract(Duration(days: hari - 1));
    });
    _muat();
  }

  double _angka(Map<String, dynamic> sumber, String kunci) =>
      (sumber[kunci] as num?)?.toDouble() ?? 0;

  double _pertumbuhan(String kunci) {
    final kini = _angka(_kpi, kunci);
    final lalu = _angka(_pembanding, kunci);
    if (lalu == 0) return kini > 0 ? 100 : 0;
    return ((kini - lalu) / lalu) * 100;
  }

  String _persen(double nilai) =>
      '${nilai >= 0 ? '+' : ''}${nilai.toStringAsFixed(1)}%';

  List<_InsightPenjualan> get _insight {
    final hasil = <_InsightPenjualan>[];
    final omzet = _angka(_kpi, 'omzet');
    final transaksi = _angka(_kpi, 'transaksi');
    final tumbuh = _pertumbuhan('omzet');
    final invalid = _angka(_kpi, 'tidakValid');
    final metode = _daftar('metode');
    final jam = _daftar('jam');
    final produk = _daftar('produk');
    final member = _angka(_kpi, 'transaksiMember');
    final diskon = _angka(_kpi, 'diskon');
    final cashback = _angka(_kpi, 'cashback');
    final nilaiTidakValid = _angka(_kpi, 'nilaiTidakValid');
    final nilaiRetur = _angka(_retur, 'nilai');
    final transaksiRetur = _angka(_retur, 'transaksi');
    final hari = _daftar('hari');
    final keranjang = _daftar('keranjang');

    if (invalid > 0) {
      hasil.add(_InsightPenjualan(
        warna: AppColors.danger,
        ikon: Icons.warning_amber_rounded,
        judul: 'Prioritas tinggi: $invalid transaksi tidak konsisten',
        alasan:
            'Total pada master berbeda dari jumlah rincian. Angka laporan dan pertanggungjawaban kas berisiko tidak sama.',
        tindakan:
            'Aktifkan filter “Transaksi tidak valid” pada Riwayat Penjualan, periksa selisih, lalu koreksi hanya dengan otorisasi supervisor.',
      ));
      if (nilaiTidakValid > 0) {
        hasil.add(_InsightPenjualan(
          warna: AppColors.danger,
          ikon: Icons.price_check_outlined,
          judul: 'Eksposur selisih data ${_rpAnalisis.format(nilaiTidakValid)}',
          alasan:
              'Nilai ini adalah akumulasi selisih absolut antara total master dan jumlah rincian transaksi yang tidak konsisten.',
          tindakan:
              'Dahulukan transaksi dengan selisih terbesar, cocokkan dengan struk dan log sinkronisasi, lalu dokumentasikan koreksi supervisor.',
        ));
      }
    }
    hasil.add(_InsightPenjualan(
      warna: tumbuh >= 0 ? AppColors.success : AppColors.danger,
      ikon: tumbuh >= 0 ? Icons.trending_up : Icons.trending_down,
      judul:
          '${tumbuh >= 0 ? 'Pertumbuhan' : 'Penurunan'} omzet ${_persen(tumbuh)}',
      alasan:
          'Omzet ${_rpAnalisis.format(omzet)} dibandingkan periode sebelumnya dengan jumlah hari yang sama.',
      tindakan: tumbuh >= 0
          ? 'Pertahankan produk, jam layanan, dan metode pembayaran yang memberi kontribusi terbesar; pastikan stok produk unggulan aman.'
          : 'Telusuri tren harian dan produk yang turun, periksa ketersediaan stok, harga, jadwal layanan, serta efektivitas promosi.',
    ));
    if (metode.isNotEmpty && omzet > 0) {
      final teratas = metode.first;
      final porsi = _angka(teratas, 'omzet') / omzet * 100;
      if (porsi >= 70) {
        hasil.add(_InsightPenjualan(
          warna: AppColors.warning,
          ikon: Icons.account_balance_wallet_outlined,
          judul:
              'Penerimaan terkonsentrasi pada ${teratas['nama']} (${porsi.toStringAsFixed(0)}%)',
          alasan:
              'Ketergantungan tinggi pada satu metode dapat menghambat transaksi saat kanal tersebut bermasalah.',
          tindakan:
              'Pastikan kanal cadangan aktif, petunjuk pembayaran jelas, dan rekonsiliasi metode utama dilakukan setiap pergantian kasir.',
        ));
      }
    }
    if (jam.isNotEmpty) {
      final puncak = [...jam]..sort(
          (a, b) => _angka(b, 'transaksi').compareTo(_angka(a, 'transaksi')));
      final terbaik = puncak.first;
      hasil.add(_InsightPenjualan(
        warna: AppColors.primary,
        ikon: Icons.schedule,
        judul:
            'Jam ramai: ${('${terbaik['jam']}').padLeft(2, '0')}.00–${((terbaik['jam'] as num).toInt() + 1).toString().padLeft(2, '0')}.00',
        alasan:
            '${terbaik['transaksi']} transaksi tercatat pada rentang jam ini.',
        tindakan:
            'Siapkan kasir, uang kembalian, perangkat pembayaran, dan pengisian rak sebelum jam ramai dimulai.',
      ));
    }
    if (produk.isNotEmpty && omzet > 0) {
      final porsi = _angka(produk.first, 'omzet') / omzet * 100;
      final omzetLimaTeratas = produk
          .take(5)
          .fold<double>(0, (jumlah, e) => jumlah + _angka(e, 'omzet'));
      final porsiLima = omzetLimaTeratas / omzet * 100;
      hasil.add(_InsightPenjualan(
        warna: AppColors.teal,
        ikon: Icons.inventory_2_outlined,
        judul: 'Produk utama: ${produk.first['nama']}',
        alasan:
            'Menyumbang ${_rpAnalisis.format(produk.first['omzet'] ?? 0)} atau ${porsi.toStringAsFixed(1)}% omzet periode.',
        tindakan: porsi >= 30
            ? 'Jaga stok pengaman dan siapkan produk alternatif karena ketergantungan omzet pada satu produk cukup tinggi.'
            : 'Pertahankan ketersediaannya dan gunakan sebagai pasangan promosi untuk membantu produk dengan perputaran lebih lambat.',
      ));
      if (porsiLima >= 70) {
        hasil.add(_InsightPenjualan(
          warna: AppColors.warning,
          ikon: Icons.donut_large_outlined,
          judul:
              'Konsentrasi produk tinggi: 5 produk menyumbang ${porsiLima.toStringAsFixed(1)}%',
          alasan:
              'Omzet sangat bergantung pada sedikit produk sehingga kekosongan stok dapat langsung menekan penjualan.',
          tindakan:
              'Tetapkan stok pengaman untuk lima produk tersebut dan siapkan produk pengganti yang margin serta kegunaannya sebanding.',
        ));
      }
    }
    if (transaksi > 0 && member / transaksi < .3) {
      hasil.add(_InsightPenjualan(
        warna: AppColors.warning,
        ikon: Icons.people_outline,
        judul:
            'Identifikasi member baru ${(member / transaksi * 100).toStringAsFixed(0)}%',
        alasan:
            'Sebagian besar transaksi belum terhubung ke member sehingga analisis perilaku dan retensi pelanggan terbatas.',
        tindakan:
            'Tawarkan pendaftaran member secara wajar dan pastikan nomor telepon unik agar riwayat pelanggan dapat dianalisis dengan benar.',
      ));
    }
    if (nilaiRetur > 0 && omzet > 0) {
      final rasio = nilaiRetur / omzet * 100;
      hasil.add(_InsightPenjualan(
        warna: rasio >= 3 ? AppColors.danger : AppColors.warning,
        ikon: Icons.assignment_return_outlined,
        judul:
            'Retur ${_rpAnalisis.format(nilaiRetur)} (${rasio.toStringAsFixed(2)}% omzet)',
        alasan:
            '${transaksiRetur.toInt()} transaksi memiliki retur pada periode terpilih. Rasio yang meningkat dapat menunjukkan masalah kualitas, salah ambil, atau informasi produk.',
        tindakan:
            'Kelompokkan alasan retur, periksa produk yang berulang, lalu tindak lanjuti ke pemasok, penataan rak, atau pengarahan kasir sesuai penyebabnya.',
      ));
    }
    if ((diskon + cashback) > 0 && omzet > 0) {
      final rasioPromo = (diskon + cashback) / (omzet + diskon) * 100;
      hasil.add(_InsightPenjualan(
        warna: rasioPromo >= 15 ? AppColors.warning : AppColors.teal,
        ikon: Icons.local_offer_outlined,
        judul:
            'Biaya promo ${_rpAnalisis.format(diskon + cashback)} (${rasioPromo.toStringAsFixed(1)}% nilai sebelum diskon)',
        alasan:
            'Terdiri dari diskon ${_rpAnalisis.format(diskon)} dan cashback ${_rpAnalisis.format(cashback)}.',
        tindakan:
            'Bandingkan pertumbuhan transaksi dan nilai keranjang dengan biaya promo. Pertahankan promo hanya bila kenaikan penjualan atau retensi menutup biaya tersebut.',
      ));
    }
    if (hari.length >= 2) {
      final urut = [...hari]
        ..sort((a, b) => _angka(b, 'omzet').compareTo(_angka(a, 'omzet')));
      hasil.add(_InsightPenjualan(
        warna: AppColors.primary,
        ikon: Icons.calendar_month_outlined,
        judul:
            'Hari terkuat ${urut.first['nama']}; hari terlemah ${urut.last['nama']}',
        alasan:
            'Omzet hari terkuat ${_rpAnalisis.format(urut.first['omzet'] ?? 0)}, sedangkan hari terlemah ${_rpAnalisis.format(urut.last['omzet'] ?? 0)}.',
        tindakan:
            'Atur jadwal petugas dan pengisian stok mengikuti hari terkuat; uji bundling atau aktivasi pelanggan pada hari terlemah.',
      ));
    }
    if (keranjang.isNotEmpty && transaksi > 0) {
      final rendah = keranjang
          .where((e) => '${e['rentang']}'.startsWith('<'))
          .fold<double>(0, (jumlah, e) => jumlah + _angka(e, 'transaksi'));
      if (rendah / transaksi >= .5) {
        hasil.add(_InsightPenjualan(
          warna: AppColors.warning,
          ikon: Icons.shopping_basket_outlined,
          judul:
              '${(rendah / transaksi * 100).toStringAsFixed(0)}% transaksi bernilai di bawah Rp25 ribu',
          alasan:
              'Mayoritas keranjang bernilai kecil sehingga peluang menaikkan nilai per kunjungan masih besar.',
          tindakan:
              'Uji rekomendasi produk pelengkap dan paket hemat yang relevan; jangan memaksa pembelian atau mengorbankan margin.',
        ));
      }
    }
    return hasil;
  }

  Map<String, double> get _skorRadar {
    final tren = _daftar('tren');
    final nilaiHarian = tren.map((e) => _angka(e, 'omzet')).toList();
    final rata = nilaiHarian.isEmpty
        ? 0.0
        : nilaiHarian.reduce((a, b) => a + b) / nilaiHarian.length;
    final variasi = rata == 0 || nilaiHarian.isEmpty
        ? 1.0
        : math.sqrt(nilaiHarian
                    .map((v) => math.pow(v - rata, 2).toDouble())
                    .reduce((a, b) => a + b) /
                nilaiHarian.length) /
            rata;
    final trx = _angka(_kpi, 'transaksi');
    final invalid = _angka(_kpi, 'tidakValid');
    final member = _angka(_kpi, 'transaksiMember');
    final metode = _daftar('metode');
    final omzet = _angka(_kpi, 'omzet');
    final porsiMetode = metode.isEmpty || omzet == 0
        ? 1.0
        : _angka(metode.first, 'omzet') / omzet;
    return {
      'Pertumbuhan': (50 + _pertumbuhan('omzet')).clamp(0, 100).toDouble(),
      'Konsistensi': (100 - variasi * 100).clamp(0, 100).toDouble(),
      'Nilai Keranjang':
          (50 + _pertumbuhan('rataRata')).clamp(0, 100).toDouble(),
      'Diversifikasi':
          ((1 - porsiMetode) * 100 + metode.length * 8).clamp(0, 100),
      'Integritas':
          trx == 0 ? 100 : ((trx - invalid) / trx * 100).clamp(0, 100),
      'Data Member': trx == 0 ? 0 : (member / trx * 100).clamp(0, 100),
    }.map((k, v) => MapEntry(k, v.toDouble()));
  }

  String _namaBerkas(String judul) => judul
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _eksporPopupExcel(
      String judul, List<String> header, List<List<Object?>> baris) async {
    final bytes =
        buildSimpleXlsx(sheetName: judul, headers: header, rows: baris);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan $judul',
      fileName:
          '${_namaBerkas(judul)}-${DateFormat('yyyyMMdd-HHmmss').format(DateTime.now())}.xlsx',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      bytes: bytes,
    );
    if (path != null) await File(path).writeAsBytes(bytes);
  }

  Future<void> _eksporPopupPdf(
      String judul, List<String> header, List<List<Object?>> baris) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(judul,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(
            '${Sesi.instance.tokoNama} · ${_tanggalAnalisis.format(_mulai)} s/d ${_tanggalAnalisis.format(_sampai)}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: header,
          data: baris.map((e) => e.map((v) => '$v').toList()).toList(),
          headerStyle:
              pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
        ),
      ],
    ));
    await Printing.layoutPdf(
        onLayout: (_) => doc.save(), name: '${_namaBerkas(judul)}.pdf');
  }

  Future<void> _bukaDrilldown(
      String judul, List<String> header, List<List<Object?>> baris) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(judul),
        content: SizedBox(
          width: math.min(MediaQuery.sizeOf(context).width * .88, 1100),
          height: math.min(MediaQuery.sizeOf(context).height * .65, 620),
          child: baris.isEmpty
              ? const Center(child: Text('Belum ada data pada periode ini.'))
              : Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: header
                            .map((e) => DataColumn(label: Text(e)))
                            .toList(),
                        rows: baris
                            .map((r) => DataRow(
                                cells: List.generate(
                                    header.length,
                                    (i) => DataCell(Text(
                                        i < r.length ? '${r[i] ?? ''}' : '')))))
                            .toList(),
                      ),
                    ),
                  ),
                ),
        ),
        actions: [
          OutlinedButton.icon(
              onPressed: () => _eksporPopupExcel(judul, header, baris),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Download Excel')),
          OutlinedButton.icon(
              onPressed: () => _eksporPopupPdf(judul, header, baris),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Download PDF')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _cetakPdf() async {
    if (_hasil == null) return;
    try {
      final doc = pw.Document();
      final insight = _insight;
      pw.Widget tabel(
              String judul, List<String> header, List<List<String>> baris) =>
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(height: 10),
            pw.Text(judul,
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              headers: header,
              data: baris,
              headerStyle:
                  pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
            ),
          ]);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text('Analisis Cerdas Riwayat Penjualan',
              style:
                  pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(
              'Toko: ${Sesi.instance.tokoNama} · Periode: ${_tanggalAnalisis.format(_mulai)} s/d ${_tanggalAnalisis.format(_sampai)} · Dicetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8.5)),
          tabel('Ringkasan KPI', [
            'Ukuran',
            'Periode ini',
            'Periode lalu'
          ], [
            [
              'Omzet',
              _rpAnalisis.format(_kpi['omzet'] ?? 0),
              _rpAnalisis.format(_pembanding['omzet'] ?? 0)
            ],
            [
              'Transaksi',
              '${_kpi['transaksi'] ?? 0}',
              '${_pembanding['transaksi'] ?? 0}'
            ],
            [
              'Rata-rata transaksi',
              _rpAnalisis.format(_kpi['rataRata'] ?? 0),
              _rpAnalisis.format(_pembanding['rataRata'] ?? 0)
            ],
            [
              'Barang terjual',
              '${_kpi['qty'] ?? 0}',
              '${_pembanding['qty'] ?? 0}'
            ],
            ['Transaksi tidak valid', '${_kpi['tidakValid'] ?? 0}', '-'],
            [
              'Nilai selisih transaksi',
              _rpAnalisis.format(_kpi['nilaiTidakValid'] ?? 0),
              '-'
            ],
            ['Diskon', _rpAnalisis.format(_kpi['diskon'] ?? 0), '-'],
            ['Cashback', _rpAnalisis.format(_kpi['cashback'] ?? 0), '-'],
            ['Nilai retur', _rpAnalisis.format(_retur['nilai'] ?? 0), '-'],
          ]),
          tabel('Analisis dan Rekomendasi', ['Prioritas', 'Temuan', 'Tindakan'],
              insight.map((e) => [e.judul, e.alasan, e.tindakan]).toList()),
          tabel(
              'Tren Harian',
              ['Tanggal', 'Transaksi', 'Omzet', 'Rata-rata'],
              _daftar('tren')
                  .map((e) => [
                        '${e['tanggal']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['rataRata'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Metode Pembayaran',
              ['Metode', 'Transaksi', 'Omzet'],
              _daftar('metode')
                  .map((e) => [
                        '${e['nama']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Jam Transaksi',
              ['Jam', 'Transaksi', 'Omzet'],
              _daftar('jam')
                  .map((e) => [
                        '${e['jam']}:00',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Pola Hari dalam Minggu',
              ['Hari', 'Transaksi', 'Omzet', 'Rata-rata'],
              _daftar('hari')
                  .map((e) => [
                        '${e['nama']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['rataRata'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Distribusi Nilai Keranjang',
              ['Rentang', 'Transaksi', 'Omzet'],
              _daftar('keranjang')
                  .map((e) => [
                        '${e['rentang']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Kinerja Kasir',
              ['Kasir', 'Transaksi', 'Omzet', 'Rata-rata'],
              _daftar('kasir')
                  .map((e) => [
                        '${e['nama']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['rataRata'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Produk Terlaris',
              ['Produk', 'Qty', 'Transaksi', 'Omzet'],
              _daftar('produk')
                  .map((e) => [
                        '${e['nama']}',
                        '${e['qty']}',
                        '${e['transaksi']}',
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          tabel(
              'Radar Kesehatan Penjualan',
              ['Dimensi', 'Skor (0-100)'],
              _skorRadar.entries
                  .map((e) => [e.key, e.value.toStringAsFixed(1)])
                  .toList()),
          tabel('Ringkasan Laba Kotor', [
            'Ukuran',
            'Periode ini',
            'Periode lalu'
          ], [
            [
              'Penjualan',
              _rpAnalisis.format(_labaRingkasan['omzet'] ?? 0),
              _rpAnalisis.format(_labaPembanding['omzet'] ?? 0)
            ],
            [
              'Harga pokok penjualan',
              _rpAnalisis.format(_labaRingkasan['hpp'] ?? 0),
              _rpAnalisis.format(_labaPembanding['hpp'] ?? 0)
            ],
            [
              'Laba kotor',
              _rpAnalisis.format(_labaRingkasan['labaKotor'] ?? 0),
              _rpAnalisis.format(_labaPembanding['labaKotor'] ?? 0)
            ],
            [
              'Margin laba kotor',
              '${_angka(_labaRingkasan, 'marginPersen').toStringAsFixed(2)}%',
              '${_angka(_labaPembanding, 'marginPersen').toStringAsFixed(2)}%'
            ],
            [
              'Produk margin negatif',
              '${_labaRingkasan['produkMarginNegatif'] ?? 0}',
              '${_labaPembanding['produkMarginNegatif'] ?? 0}'
            ],
            [
              'Produk tanpa HPP',
              '${_labaRingkasan['produkTanpaHpp'] ?? 0}',
              '${_labaPembanding['produkTanpaHpp'] ?? 0}'
            ],
          ]),
          tabel(
              'Tren Laba Kotor Harian',
              ['Tanggal', 'Penjualan', 'HPP', 'Laba kotor', 'Margin'],
              _daftarLaba('tren')
                  .map((e) => [
                        '${e['tanggal']}',
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['hpp'] ?? 0),
                        _rpAnalisis.format(e['labaKotor'] ?? 0),
                        '${((e['marginPersen'] as num?) ?? 0).toStringAsFixed(2)}%'
                      ])
                  .toList()),
          tabel(
              'Laba Kotor per Produk',
              ['Produk', 'Qty', 'Penjualan', 'HPP', 'Laba', 'Margin'],
              _daftarLaba('produk')
                  .map((e) => [
                        '${e['nama']}',
                        '${e['qty']}',
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['hpp'] ?? 0),
                        _rpAnalisis.format(e['labaKotor'] ?? 0),
                        '${((e['marginPersen'] as num?) ?? 0).toStringAsFixed(2)}%'
                      ])
                  .toList()),
          tabel(
              'Candlestick Laba Transaksi Harian',
              ['Tanggal', 'Open', 'High', 'Low', 'Close', 'Transaksi'],
              _daftarLaba('candle')
                  .map((e) => [
                        '${e['tanggal']}',
                        _rpAnalisis.format(e['open'] ?? 0),
                        _rpAnalisis.format(e['high'] ?? 0),
                        _rpAnalisis.format(e['low'] ?? 0),
                        _rpAnalisis.format(e['close'] ?? 0),
                        '${e['transaksi']}'
                      ])
                  .toList()),
          tabel(
              'Radar Kesehatan Laba Kotor',
              ['Dimensi', 'Skor (0-100)'],
              _skorRadarLaba.entries
                  .map((e) => [e.key, e.value.toStringAsFixed(1)])
                  .toList()),
          pw.SizedBox(height: 8),
          pw.Text(
              'Catatan: rekomendasi dibuat dengan aturan statistik yang dapat dijelaskan dan tetap memerlukan pertimbangan penanggung jawab toko.',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ));
      await Printing.layoutPdf(
          onLayout: (_) => doc.save(),
          name:
              'Analisis-Penjualan-${_tanggalAnalisis.format(_mulai)}-${_tanggalAnalisis.format(_sampai)}.pdf');
    } catch (e) {
      if (mounted) {
        await tampilkanKesalahan(context, e,
            aktivitas: 'mencetak analisis PDF');
      }
    }
  }

  Widget _kartuGrafik(
          {required String judul,
          required Widget child,
          List<String> header = const <String>[],
          List<List<Object?>> baris = const <List<Object?>>[]}) =>
      Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _bukaDrilldown(judul, header, baris),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(judul,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700))),
                const Icon(Icons.open_in_new, size: 16),
              ]),
              const SizedBox(height: 14),
              child,
            ]),
          ),
        ),
      );

  Widget _filter() => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final hari in const [7, 30, 90])
            ActionChip(
                label: Text('$hari hari'), onPressed: () => _preset(hari)),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_tanggalAnalisis.format(_mulai)),
            onPressed: () async {
              final v = await showDatePicker(
                  context: context,
                  initialDate: _mulai,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (v != null) setState(() => _mulai = v);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_available, size: 18),
            label: Text(_tanggalAnalisis.format(_sampai)),
            onPressed: () async {
              final v = await showDatePicker(
                  context: context,
                  initialDate: _sampai,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (v != null) setState(() => _sampai = v);
            },
          ),
          FilledButton.icon(
              onPressed: _muat,
              icon: const Icon(Icons.analytics_outlined, size: 18),
              label: const Text('Analisis')),
          OutlinedButton.icon(
              onPressed: _hasil == null ? null : _cetakPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Cetak PDF')),
        ],
      );

  Widget _kpiCards() {
    final data = [
      (
        Icons.payments_outlined,
        AppColors.success,
        _rpAnalisis.format(_kpi['omzet'] ?? 0),
        'Omzet · ${_persen(_pertumbuhan('omzet'))}'
      ),
      (
        Icons.receipt_long_outlined,
        AppColors.primary,
        '${_kpi['transaksi'] ?? 0}',
        'Transaksi · ${_persen(_pertumbuhan('transaksi'))}'
      ),
      (
        Icons.shopping_basket_outlined,
        AppColors.teal,
        _rpAnalisis.format(_kpi['rataRata'] ?? 0),
        'Rata-rata transaksi'
      ),
      (
        Icons.inventory_2_outlined,
        AppColors.warning,
        NumberFormat('#,##0.##', 'id_ID').format(_kpi['qty'] ?? 0),
        'Barang terjual'
      ),
      (
        Icons.rule_outlined,
        AppColors.danger,
        '${_kpi['tidakValid'] ?? 0}',
        'Transaksi tidak valid'
      ),
      (
        Icons.assignment_return_outlined,
        AppColors.warning,
        _rpAnalisis.format(_retur['nilai'] ?? 0),
        'Nilai retur · ${_retur['transaksi'] ?? 0} transaksi'
      ),
      (
        Icons.local_offer_outlined,
        Colors.purple,
        _rpAnalisis.format(_angka(_kpi, 'diskon') + _angka(_kpi, 'cashback')),
        'Diskon + cashback'
      ),
      (
        Icons.price_check_outlined,
        AppColors.danger,
        _rpAnalisis.format(_kpi['nilaiTidakValid'] ?? 0),
        'Eksposur selisih data'
      ),
    ];
    return LayoutBuilder(builder: (_, batas) {
      final kolom = batas.maxWidth >= 1200
          ? 4
          : batas.maxWidth >= 760
              ? 3
              : batas.maxWidth >= 480
                  ? 2
                  : 1;
      final lebar = (batas.maxWidth - (kolom - 1) * 8) / kolom;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(data.length, (i) {
          return SizedBox(
            width: lebar,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _bukaDrilldown(
                data[i].$4,
                const ['Ukuran', 'Periode ini', 'Periode sebelumnya'],
                [
                  [data[i].$4, data[i].$3, i < 4 ? 'Lihat pembanding' : '-']
                ],
              ),
              child: AppKpiCard(
                  icon: data[i].$1,
                  warna: data[i].$2,
                  nilai: data[i].$3,
                  label: data[i].$4),
            ),
          );
        }),
      );
    });
  }

  Widget _ringkasan() => Column(children: [
        _kpiCards(),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, c) {
          final cards = [
            _kartuGrafik(
                judul: 'Tren Omzet Harian',
                child: _TrendMiniChart(data: _daftar('tren')),
                header: const ['Tanggal', 'Transaksi', 'Omzet', 'Rata-rata'],
                baris: _daftar('tren')
                    .map((e) => <Object?>[
                          e['tanggal'],
                          e['transaksi'],
                          _rpAnalisis.format(e['omzet'] ?? 0),
                          _rpAnalisis.format(e['rataRata'] ?? 0)
                        ])
                    .toList()),
            _kartuGrafik(
                judul: 'Radar Kesehatan Penjualan',
                child: _RadarPenjualan(data: _skorRadar),
                header: const ['Dimensi', 'Skor'],
                baris: _skorRadar.entries
                    .map((e) => <Object?>[e.key, e.value.toStringAsFixed(1)])
                    .toList()),
          ];
          return c.maxWidth >= 900
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1])
                ])
              : Column(
                  children: [cards[0], const SizedBox(height: 12), cards[1]]);
        }),
        const SizedBox(height: 12),
        _kartuGrafik(
            judul: 'Analisis Cerdas & Rekomendasi Tindakan',
            child: Column(
                children:
                    _insight.map((e) => _InsightCard(insight: e)).toList()),
            header: const ['Temuan', 'Alasan', 'Tindakan'],
            baris: _insight
                .map((e) => <Object?>[e.judul, e.alasan, e.tindakan])
                .toList()),
      ]);

  Widget _produkPembayaran() => LayoutBuilder(builder: (_, c) {
        final cards = [
          _kartuGrafik(
              judul: 'Produk Terlaris berdasarkan Omzet',
              child: _BarRanking(
                  data: _daftar('produk'),
                  labelKey: 'nama',
                  valueKey: 'omzet',
                  format: _rpAnalisis.format,
                  warna: AppColors.teal),
              header: const ['Produk', 'Qty', 'Transaksi', 'Omzet'],
              baris: _daftar('produk')
                  .map((e) => <Object?>[
                        e['nama'],
                        e['qty'],
                        e['transaksi'],
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          _kartuGrafik(
              judul: 'Komposisi Metode Pembayaran',
              child: _DonutKomposisi(data: _daftar('metode')),
              header: const ['Metode', 'Transaksi', 'Omzet'],
              baris: _daftar('metode')
                  .map((e) => <Object?>[
                        e['nama'],
                        e['transaksi'],
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
        ];
        return c.maxWidth >= 900
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1])
              ])
            : Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]]);
      });

  Widget _operasional() => LayoutBuilder(builder: (_, c) {
        final cards = [
          _kartuGrafik(
              judul: 'Distribusi Transaksi per Jam',
              child: _BarRanking(
                  data: _daftar('jam'),
                  labelKey: 'jam',
                  valueKey: 'transaksi',
                  format: (v) => '${v.toInt()} transaksi',
                  labelFormat: (v) => '${v.toString().padLeft(2, '0')}.00',
                  warna: AppColors.primary),
              header: const ['Jam', 'Transaksi', 'Omzet'],
              baris: _daftar('jam')
                  .map((e) => <Object?>[
                        '${e['jam']}:00',
                        e['transaksi'],
                        _rpAnalisis.format(e['omzet'] ?? 0)
                      ])
                  .toList()),
          _kartuGrafik(
              judul: 'Kinerja Kasir berdasarkan Omzet',
              child: _BarRanking(
                  data: _daftar('kasir'),
                  labelKey: 'nama',
                  valueKey: 'omzet',
                  format: _rpAnalisis.format,
                  warna: AppColors.warning),
              header: const ['Kasir', 'Transaksi', 'Omzet', 'Rata-rata'],
              baris: _daftar('kasir')
                  .map((e) => <Object?>[
                        e['nama'],
                        e['transaksi'],
                        _rpAnalisis.format(e['omzet'] ?? 0),
                        _rpAnalisis.format(e['rataRata'] ?? 0)
                      ])
                  .toList()),
        ];
        return c.maxWidth >= 900
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1])
              ])
            : Column(
                children: [cards[0], const SizedBox(height: 12), cards[1]]);
      });

  Widget _risikoDanPeluang() => Column(children: [
        LayoutBuilder(builder: (_, c) {
          final cards = [
            _kartuGrafik(
                judul: 'Pola Omzet per Hari dalam Minggu',
                child: _BarRanking(
                    data: _daftar('hari'),
                    labelKey: 'nama',
                    valueKey: 'omzet',
                    format: _rpAnalisis.format,
                    warna: AppColors.primary),
                header: const ['Hari', 'Transaksi', 'Omzet', 'Rata-rata'],
                baris: _daftar('hari')
                    .map((e) => <Object?>[
                          e['nama'],
                          e['transaksi'],
                          _rpAnalisis.format(e['omzet'] ?? 0),
                          _rpAnalisis.format(e['rataRata'] ?? 0)
                        ])
                    .toList()),
            _kartuGrafik(
                judul: 'Distribusi Nilai Keranjang',
                child: _BarRanking(
                    data: _daftar('keranjang'),
                    labelKey: 'rentang',
                    valueKey: 'transaksi',
                    format: (v) => '${v.toInt()} transaksi',
                    warna: Colors.purple),
                header: const ['Rentang', 'Transaksi', 'Omzet'],
                baris: _daftar('keranjang')
                    .map((e) => <Object?>[
                          e['rentang'],
                          e['transaksi'],
                          _rpAnalisis.format(e['omzet'] ?? 0)
                        ])
                    .toList()),
          ];
          return c.maxWidth >= 900
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1])
                ])
              : Column(
                  children: [cards[0], const SizedBox(height: 12), cards[1]]);
        }),
        const SizedBox(height: 12),
        _kartuGrafik(
          judul: 'Rekap Risiko, Promo, dan Retur',
          child: _RekapRisikoPromo(
              kpi: _kpi, retur: _retur, omzet: _angka(_kpi, 'omzet')),
          header: const ['Ukuran', 'Nilai'],
          baris: [
            ['Transaksi tidak valid', _kpi['tidakValid'] ?? 0],
            [
              'Eksposur selisih',
              _rpAnalisis.format(_kpi['nilaiTidakValid'] ?? 0)
            ],
            ['Diskon', _rpAnalisis.format(_kpi['diskon'] ?? 0)],
            ['Cashback', _rpAnalisis.format(_kpi['cashback'] ?? 0)],
            ['Retur', _rpAnalisis.format(_retur['nilai'] ?? 0)],
          ],
        ),
      ]);

  Map<String, double> get _skorRadarLaba {
    final margin = _angka(_labaRingkasan, 'marginPersen');
    final labaKini = _angka(_labaRingkasan, 'labaKotor');
    final labaLalu = _angka(_labaPembanding, 'labaKotor');
    final tumbuh = labaLalu == 0
        ? (labaKini > 0 ? 100.0 : 0.0)
        : (labaKini - labaLalu) / labaLalu * 100;
    final produk = _daftarLaba('produk');
    final negatif = _angka(_labaRingkasan, 'produkMarginNegatif');
    final tanpaHpp = _angka(_labaRingkasan, 'produkTanpaHpp');
    final promo = _angka(_kpi, 'diskon') + _angka(_kpi, 'cashback');
    final omzet = _angka(_labaRingkasan, 'omzet');
    return {
      'Margin': (margin / 40 * 100).clamp(0, 100),
      'Pertumbuhan': (50 + tumbuh).clamp(0, 100),
      'Produk Positif': produk.isEmpty
          ? 0
          : ((produk.length - negatif) / produk.length * 100).clamp(0, 100),
      'Kelengkapan HPP': produk.isEmpty
          ? 0
          : ((produk.length - tanpaHpp) / produk.length * 100).clamp(0, 100),
      'Efisiensi Promo':
          omzet == 0 ? 100 : (100 - promo / omzet * 100).clamp(0, 100),
    }.map((k, v) => MapEntry(k, v.toDouble()));
  }

  Widget _analisisLabaKotor() {
    final laba = _angka(_labaRingkasan, 'labaKotor');
    final hpp = _angka(_labaRingkasan, 'hpp');
    final omzet = _angka(_labaRingkasan, 'omzet');
    final margin = _angka(_labaRingkasan, 'marginPersen');
    final labaLalu = _angka(_labaPembanding, 'labaKotor');
    final tumbuh = labaLalu == 0
        ? (laba > 0 ? 100.0 : 0.0)
        : (laba - labaLalu) / labaLalu * 100;
    final kpi = <(IconData, Color, String, String)>[
      (
        Icons.trending_up,
        AppColors.success,
        _rpAnalisis.format(laba),
        'Laba kotor · ${_persen(tumbuh)}'
      ),
      (
        Icons.inventory_2_outlined,
        AppColors.warning,
        _rpAnalisis.format(hpp),
        'Harga pokok penjualan'
      ),
      (
        Icons.percent,
        AppColors.primary,
        '${margin.toStringAsFixed(2)}%',
        'Margin laba kotor'
      ),
      (
        Icons.money_off_outlined,
        AppColors.danger,
        '${_labaRingkasan['produkMarginNegatif'] ?? 0}',
        'Produk margin negatif'
      ),
      (
        Icons.help_outline,
        Colors.purple,
        '${_labaRingkasan['produkTanpaHpp'] ?? 0}',
        'Produk tanpa HPP'
      ),
      (
        Icons.shopping_cart_outlined,
        AppColors.teal,
        _rpAnalisis.format(omzet),
        'Penjualan dasar laba'
      ),
    ];
    final ringkasanRows = <List<Object?>>[
      ['Penjualan', _rpAnalisis.format(omzet)],
      ['HPP', _rpAnalisis.format(hpp)],
      ['Laba kotor', _rpAnalisis.format(laba)],
      ['Margin', '${margin.toStringAsFixed(2)}%'],
      ['Pertumbuhan laba', _persen(tumbuh)],
      ['Produk margin negatif', _labaRingkasan['produkMarginNegatif'] ?? 0],
      ['Produk tanpa HPP', _labaRingkasan['produkTanpaHpp'] ?? 0],
      ['Qty tanpa HPP', _labaRingkasan['qtyTanpaHpp'] ?? 0],
    ];
    return Column(children: [
      LayoutBuilder(builder: (_, batas) {
        final kolom = batas.maxWidth >= 1100
            ? 3
            : batas.maxWidth >= 650
                ? 2
                : 1;
        final lebar = (batas.maxWidth - (kolom - 1) * 8) / kolom;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kpi
              .map((e) => SizedBox(
                    width: lebar,
                    child: InkWell(
                      onTap: () => _bukaDrilldown(
                          e.$4, const ['Ukuran', 'Nilai'], ringkasanRows),
                      child: AppKpiCard(
                          icon: e.$1, warna: e.$2, nilai: e.$3, label: e.$4),
                    ),
                  ))
              .toList(),
        );
      }),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (_, batas) {
        final lebar =
            batas.maxWidth >= 900 ? (batas.maxWidth - 12) / 2 : batas.maxWidth;
        final tren = _daftarLaba('tren');
        final candle = _daftarLaba('candle');
        final produk = _daftarLaba('produk');
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: lebar,
              child: _kartuGrafik(
                judul: 'Tren Penjualan, HPP & Laba Kotor',
                child: _TrendLabaChart(data: tren),
                header: const ['Tanggal', 'Penjualan', 'HPP', 'Laba', 'Margin'],
                baris: tren
                    .map((e) => <Object?>[
                          e['tanggal'],
                          _rpAnalisis.format(e['omzet'] ?? 0),
                          _rpAnalisis.format(e['hpp'] ?? 0),
                          _rpAnalisis.format(e['labaKotor'] ?? 0),
                          '${((e['marginPersen'] as num?) ?? 0).toStringAsFixed(2)}%'
                        ])
                    .toList(),
              )),
          SizedBox(
              width: lebar,
              child: _kartuGrafik(
                judul: 'Radar Kesehatan Laba Kotor',
                child: _RadarPenjualan(data: _skorRadarLaba),
                header: const ['Dimensi', 'Skor'],
                baris: _skorRadarLaba.entries
                    .map((e) => <Object?>[e.key, e.value.toStringAsFixed(1)])
                    .toList(),
              )),
          SizedBox(
              width: lebar,
              child: _kartuGrafik(
                judul: 'Candlestick Laba per Transaksi Harian',
                child: _CandleLabaChart(data: candle),
                header: const [
                  'Tanggal',
                  'Open',
                  'High',
                  'Low',
                  'Close',
                  'Transaksi'
                ],
                baris: candle
                    .map((e) => <Object?>[
                          e['tanggal'],
                          _rpAnalisis.format(e['open'] ?? 0),
                          _rpAnalisis.format(e['high'] ?? 0),
                          _rpAnalisis.format(e['low'] ?? 0),
                          _rpAnalisis.format(e['close'] ?? 0),
                          e['transaksi']
                        ])
                    .toList(),
              )),
          SizedBox(
              width: lebar,
              child: _kartuGrafik(
                judul: 'Produk Penyumbang Laba Kotor',
                child: _BarRanking(
                    data: produk,
                    labelKey: 'nama',
                    valueKey: 'labaKotor',
                    format: _rpAnalisis.format,
                    warna: AppColors.success),
                header: const [
                  'Produk',
                  'Qty',
                  'Penjualan',
                  'HPP',
                  'Laba',
                  'Margin'
                ],
                baris: produk
                    .map((e) => <Object?>[
                          e['nama'],
                          e['qty'],
                          _rpAnalisis.format(e['omzet'] ?? 0),
                          _rpAnalisis.format(e['hpp'] ?? 0),
                          _rpAnalisis.format(e['labaKotor'] ?? 0),
                          '${((e['marginPersen'] as num?) ?? 0).toStringAsFixed(2)}%'
                        ])
                    .toList(),
              )),
        ]);
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.riwayatPenjualan,
      judul: 'Analisis Riwayat Penjualan',
      subjudul: 'Tren, rekap, kualitas data, dan rekomendasi keputusan',
      scrollable: false,
      body: Column(children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Riwayat Transaksi')),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _muat,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _filter(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                        label: const Text('Ringkasan & Tren'),
                        selected: _bagian == 0,
                        onSelected: (_) => setState(() => _bagian = 0)),
                    ChoiceChip(
                        label: const Text('Produk & Pembayaran'),
                        selected: _bagian == 1,
                        onSelected: (_) => setState(() => _bagian = 1)),
                    ChoiceChip(
                        label: const Text('Operasional & Kasir'),
                        selected: _bagian == 2,
                        onSelected: (_) => setState(() => _bagian = 2)),
                    ChoiceChip(
                        label: const Text('Risiko & Peluang'),
                        selected: _bagian == 3,
                        onSelected: (_) => setState(() => _bagian = 3)),
                    ChoiceChip(
                        label: const Text('Analisis Laba Kotor'),
                        selected: _bagian == 4,
                        onSelected: (_) => setState(() => _bagian = 4)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_memuat)
                  const Padding(
                      padding: EdgeInsets.all(60),
                      child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(_error!)))
                else if (_hasil == null)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Belum ada analisis.')))
                else if (_bagian == 0)
                  _ringkasan()
                else if (_bagian == 1)
                  _produkPembayaran()
                else if (_bagian == 2)
                  _operasional()
                else if (_bagian == 3)
                  _risikoDanPeluang()
                else
                  _analisisLabaKotor(),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _InsightPenjualan {
  const _InsightPenjualan(
      {required this.warna,
      required this.ikon,
      required this.judul,
      required this.alasan,
      required this.tindakan});
  final Color warna;
  final IconData ikon;
  final String judul;
  final String alasan;
  final String tindakan;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});
  final _InsightPenjualan insight;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.latarLembut(insight.warna),
            borderRadius: BorderRadius.circular(10)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(insight.ikon, color: insight.warna),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(insight.judul,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: insight.warna)),
                const SizedBox(height: 3),
                Text(insight.alasan, style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 3),
                Text('Tindakan: ${insight.tindakan}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ])),
        ]),
      );
}

class _RekapRisikoPromo extends StatelessWidget {
  const _RekapRisikoPromo(
      {required this.kpi, required this.retur, required this.omzet});

  final Map<String, dynamic> kpi;
  final Map<String, dynamic> retur;
  final double omzet;

  double _n(Map<String, dynamic> sumber, String kunci) =>
      (sumber[kunci] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final transaksi = _n(kpi, 'transaksi');
    final invalid = _n(kpi, 'tidakValid');
    final diskon = _n(kpi, 'diskon');
    final cashback = _n(kpi, 'cashback');
    final nilaiRetur = _n(retur, 'nilai');
    final sebelumDiskon = omzet + diskon;
    final rows = <(String, String, String, Color)>[
      (
        'Kualitas transaksi',
        '${invalid.toInt()} dari ${transaksi.toInt()}',
        transaksi == 0
            ? '100,0% valid'
            : '${((transaksi - invalid) / transaksi * 100).clamp(0, 100).toStringAsFixed(1)}% valid',
        invalid > 0 ? AppColors.danger : AppColors.success
      ),
      (
        'Eksposur selisih data',
        _rpAnalisis.format(_n(kpi, 'nilaiTidakValid')),
        'Perlu rekonsiliasi supervisor',
        _n(kpi, 'nilaiTidakValid') > 0 ? AppColors.danger : AppColors.success
      ),
      (
        'Diskon',
        _rpAnalisis.format(diskon),
        sebelumDiskon == 0
            ? '0,0% nilai sebelum diskon'
            : '${(diskon / sebelumDiskon * 100).toStringAsFixed(1)}% nilai sebelum diskon',
        AppColors.warning
      ),
      (
        'Cashback',
        _rpAnalisis.format(cashback),
        omzet == 0
            ? '0,0% omzet'
            : '${(cashback / omzet * 100).toStringAsFixed(1)}% omzet',
        Colors.purple
      ),
      (
        'Retur penjualan',
        _rpAnalisis.format(nilaiRetur),
        omzet == 0
            ? '${_n(retur, 'transaksi').toInt()} transaksi'
            : '${(nilaiRetur / omzet * 100).toStringAsFixed(2)}% omzet · ${_n(retur, 'transaksi').toInt()} transaksi',
        nilaiRetur > 0 ? AppColors.warning : AppColors.success
      ),
    ];
    return Column(
      children: rows
          .map((r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.latarLembut(r.$4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: r.$4),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(r.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(r.$2,
                      style:
                          TextStyle(color: r.$4, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 16),
                  SizedBox(
                      width: 210,
                      child: Text(r.$3,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12))),
                ]),
              ))
          .toList(),
    );
  }
}

class _BarRanking extends StatelessWidget {
  const _BarRanking(
      {required this.data,
      required this.labelKey,
      required this.valueKey,
      required this.format,
      required this.warna,
      this.labelFormat});
  final List<Map<String, dynamic>> data;
  final String labelKey;
  final String valueKey;
  final String Function(num) format;
  final String Function(dynamic)? labelFormat;
  final Color warna;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 180, child: Center(child: Text('Belum ada data.')));
    }
    final max = data
        .map((e) => (e[valueKey] as num?)?.toDouble() ?? 0)
        .fold<double>(0, math.max);
    return Column(
        children: data.take(10).map((e) {
      final nilai = (e[valueKey] as num?)?.toDouble() ?? 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(labelFormat?.call(e[labelKey]) ?? '${e[labelKey]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text(format(nilai),
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
              value: max <= 0 ? 0 : (nilai / max).clamp(0, 1),
              minHeight: 7,
              color: warna,
              backgroundColor: AppColors.latarLembut(warna),
              borderRadius: BorderRadius.circular(5)),
        ]),
      );
    }).toList());
  }
}

class _TrendMiniChart extends StatelessWidget {
  const _TrendMiniChart({required this.data});
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 220, child: Center(child: Text('Belum ada data tren.')));
    }
    return Column(children: [
      SizedBox(
          height: 190,
          width: double.infinity,
          child: CustomPaint(painter: _TrendPainter(data))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${data.first['tanggal']}', style: const TextStyle(fontSize: 10)),
        Text('${data.last['tanggal']}', style: const TextStyle(fontSize: 10))
      ]),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.data);
  final List<Map<String, dynamic>> data;
  @override
  void paint(Canvas canvas, Size size) {
    final values =
        data.map((e) => (e['omzet'] as num?)?.toDouble() ?? 0).toList();
    final max = values.fold<double>(0, math.max);
    final grid = Paint()..color = AppColors.border;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * i / (values.length - 1);
      final y = max <= 0
          ? size.height
          : size.height - (values[i] / max * (size.height - 12));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _TrendLabaChart extends StatelessWidget {
  const _TrendLabaChart({required this.data});
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 230, child: Center(child: Text('Belum ada data laba.')));
    }
    return Column(children: [
      Wrap(spacing: 14, runSpacing: 4, children: [
        _LegendaGrafik(warna: AppColors.primary, label: 'Penjualan'),
        _LegendaGrafik(warna: AppColors.warning, label: 'HPP'),
        _LegendaGrafik(warna: AppColors.success, label: 'Laba kotor'),
      ]),
      const SizedBox(height: 8),
      SizedBox(
          height: 185,
          width: double.infinity,
          child: CustomPaint(painter: _TrendLabaPainter(data))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${data.first['tanggal']}', style: const TextStyle(fontSize: 10)),
        Text('${data.last['tanggal']}', style: const TextStyle(fontSize: 10)),
      ]),
    ]);
  }
}

class _LegendaGrafik extends StatelessWidget {
  const _LegendaGrafik({required this.warna, required this.label});
  final Color warna;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: warna, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10.5)),
      ]);
}

class _TrendLabaPainter extends CustomPainter {
  _TrendLabaPainter(this.data);
  final List<Map<String, dynamic>> data;

  @override
  void paint(Canvas canvas, Size size) {
    final semua = <double>[];
    for (final e in data) {
      semua.add((e['omzet'] as num?)?.toDouble() ?? 0);
      semua.add((e['hpp'] as num?)?.toDouble() ?? 0);
      semua.add((e['labaKotor'] as num?)?.toDouble() ?? 0);
    }
    final maksimum = semua.isEmpty ? 0.0 : semua.reduce(math.max);
    final minimum = semua.isEmpty ? 0.0 : math.min(0, semua.reduce(math.min));
    final rentang = maksimum - minimum;
    final grid = Paint()..color = AppColors.border;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    void gambar(String key, Color warna) {
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final nilai = (data[i][key] as num?)?.toDouble() ?? 0;
        final x = data.length == 1
            ? size.width / 2
            : size.width * i / (data.length - 1);
        final y = rentang <= 0
            ? size.height
            : size.height - ((nilai - minimum) / rentang * (size.height - 8));
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = warna
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round);
    }

    gambar('omzet', AppColors.primary);
    gambar('hpp', AppColors.warning);
    gambar('labaKotor', AppColors.success);
  }

  @override
  bool shouldRepaint(covariant _TrendLabaPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _CandleLabaChart extends StatelessWidget {
  const _CandleLabaChart({required this.data});
  final List<Map<String, dynamic>> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 230, child: Center(child: Text('Belum ada data candle.')));
    }
    return Column(children: [
      Wrap(spacing: 14, children: [
        _LegendaGrafik(warna: AppColors.success, label: 'Close >= Open'),
        _LegendaGrafik(warna: AppColors.danger, label: 'Close < Open'),
      ]),
      const SizedBox(height: 8),
      SizedBox(
          height: 185,
          width: double.infinity,
          child: CustomPaint(painter: _CandleLabaPainter(data))),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${data.first['tanggal']}', style: const TextStyle(fontSize: 10)),
        Text('${data.last['tanggal']}', style: const TextStyle(fontSize: 10)),
      ]),
    ]);
  }
}

class _CandleLabaPainter extends CustomPainter {
  _CandleLabaPainter(this.data);
  final List<Map<String, dynamic>> data;

  @override
  void paint(Canvas canvas, Size size) {
    final tinggi = data
        .map((e) => (e['high'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, math.max);
    final rendah = data
        .map((e) => (e['low'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, math.min);
    final rentang = tinggi - rendah;
    double y(double nilai) => rentang <= 0
        ? size.height / 2
        : size.height - ((nilai - rendah) / rentang * (size.height - 10)) - 5;
    final grid = Paint()..color = AppColors.border;
    for (var i = 0; i <= 4; i++) {
      final gy = size.height * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
    if (rendah < 0 && tinggi > 0) {
      canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)),
          Paint()..color = Colors.blueGrey.withValues(alpha: .7));
    }
    final slot = size.width / math.max(1, data.length);
    final bodyWidth = math.max(3.0, math.min(14.0, slot * .48));
    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      final open = (e['open'] as num?)?.toDouble() ?? 0;
      final high = (e['high'] as num?)?.toDouble() ?? 0;
      final low = (e['low'] as num?)?.toDouble() ?? 0;
      final close = (e['close'] as num?)?.toDouble() ?? 0;
      final warna = close >= open ? AppColors.success : AppColors.danger;
      final x = slot * i + slot / 2;
      canvas.drawLine(
          Offset(x, y(high)),
          Offset(x, y(low)),
          Paint()
            ..color = warna
            ..strokeWidth = 1.4);
      final atas = math.min(y(open), y(close));
      final bawah = math.max(y(open), y(close));
      canvas.drawRect(
          Rect.fromLTWH(
              x - bodyWidth / 2, atas, bodyWidth, math.max(2.0, bawah - atas)),
          Paint()..color = warna);
    }
  }

  @override
  bool shouldRepaint(covariant _CandleLabaPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _DonutKomposisi extends StatelessWidget {
  const _DonutKomposisi({required this.data});
  final List<Map<String, dynamic>> data;
  static final warna = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.teal,
    AppColors.danger,
    Colors.purple,
    Colors.blueGrey
  ];
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox(
          height: 220,
          child: Center(child: Text('Belum ada data pembayaran.')));
    }
    final total = data.fold<double>(
        0, (s, e) => s + ((e['omzet'] as num?)?.toDouble() ?? 0));
    return Row(children: [
      SizedBox(
          width: 170,
          height: 170,
          child: CustomPaint(painter: _DonutPainter(data))),
      const SizedBox(width: 16),
      Expanded(
          child: Column(
              children: List.generate(math.min(data.length, 7), (i) {
        final nilai = (data[i]['omzet'] as num?)?.toDouble() ?? 0;
        return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: warna[i % warna.length], shape: BoxShape.circle)),
              const SizedBox(width: 7),
              Expanded(
                  child: Text('${data[i]['nama']}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5))),
              Text(
                  total == 0
                      ? '0%'
                      : '${(nilai / total * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700))
            ]));
      }))),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.data);
  final List<Map<String, dynamic>> data;
  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<double>(
        0, (s, e) => s + ((e['omzet'] as num?)?.toDouble() ?? 0));
    final rect = Offset.zero & size;
    var awal = -math.pi / 2;
    for (var i = 0; i < data.length; i++) {
      final nilai = (data[i]['omzet'] as num?)?.toDouble() ?? 0;
      final sweep = total == 0 ? 0.0 : nilai / total * math.pi * 2;
      canvas.drawArc(
          rect.deflate(18),
          awal,
          sweep,
          false,
          Paint()
            ..color = _DonutKomposisi.warna[i % _DonutKomposisi.warna.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 24);
      awal += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.data != data;
}

class _RadarPenjualan extends StatelessWidget {
  const _RadarPenjualan({required this.data});
  final Map<String, double> data;
  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
            height: 230,
            width: double.infinity,
            child: CustomPaint(painter: _RadarPainter(data))),
        Wrap(
            spacing: 10,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: data.entries
                .map((e) => Text('${e.key}: ${e.value.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 10.5)))
                .toList()),
      ]);
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.data);
  final Map<String, double> data;
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .38;
    final count = data.length;
    Offset titik(int i, double skala) {
      final sudut = -math.pi / 2 + math.pi * 2 * i / count;
      return center + Offset(math.cos(sudut), math.sin(sudut)) * radius * skala;
    }

    for (var level = 1; level <= 5; level++) {
      final p = Path();
      for (var i = 0; i < count; i++) {
        final t = titik(i, level / 5);
        if (i == 0) {
          p.moveTo(t.dx, t.dy);
        } else {
          p.lineTo(t.dx, t.dy);
        }
      }
      p.close();
      canvas.drawPath(
          p,
          Paint()
            ..color = AppColors.border
            ..style = PaintingStyle.stroke);
    }
    for (var i = 0; i < count; i++) {
      canvas.drawLine(center, titik(i, 1), Paint()..color = AppColors.border);
    }
    final isi = Path();
    final values = data.values.toList();
    for (var i = 0; i < count; i++) {
      final t = titik(i, values[i].clamp(0, 100) / 100);
      if (i == 0) {
        isi.moveTo(t.dx, t.dy);
      } else {
        isi.lineTo(t.dx, t.dy);
      }
    }
    isi.close();
    canvas.drawPath(
        isi,
        Paint()
          ..color = AppColors.primary.withValues(alpha: .18)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        isi,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.data != data;
}
