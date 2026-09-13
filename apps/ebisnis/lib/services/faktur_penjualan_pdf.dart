import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Satu baris barang pada faktur penjualan A4.
class FakturPenjualanItem {
  const FakturPenjualanItem({
    required this.kode,
    required this.nama,
    required this.satuan,
    required this.qty,
    required this.harga,
    required this.diskon,
  });

  final String kode;
  final String nama;
  final String satuan;
  final double qty;
  final double harga;
  final double diskon;

  double get total => (qty * harga) - diskon;
}

/// Data siap-cetak. Factory menerima nama field server maupun snapshot lokal,
/// sehingga ekspor tetap dapat dibuat ketika transaksi masih berada di SQLite.
class FakturPenjualanData {
  const FakturPenjualanData({
    required this.toko,
    required this.alamat,
    required this.telepon,
    required this.pelanggan,
    required this.nomor,
    required this.tanggal,
    required this.metodePembayaran,
    required this.kasir,
    required this.referensi,
    required this.keterangan,
    required this.subtotal,
    required this.diskon,
    required this.ppn,
    required this.pajakPersen,
    required this.biayaLain,
    required this.total,
    required this.lunas,
    required this.items,
  });

  final String toko;
  final String alamat;
  final String telepon;
  final String pelanggan;
  final String nomor;
  final String tanggal;
  final String metodePembayaran;
  final String kasir;
  final String referensi;
  final String keterangan;
  final double subtotal;
  final double diskon;
  final double ppn;
  final double pajakPersen;
  final double biayaLain;
  final double total;
  final bool lunas;
  final List<FakturPenjualanItem> items;

  factory FakturPenjualanData.dariSumber({
    required Map<String, dynamic> detail,
    required Map<String, dynamic> ringkasan,
    required List<Map<String, dynamic>> items,
    required String toko,
    required String alamat,
    required String telepon,
    required String metodePembayaran,
  }) {
    final sumber = [detail, ringkasan];
    final baris = items.map((item) {
      return FakturPenjualanItem(
        kode: _teksDari([
          item
        ], const [
          'kode',
          'kodeProduk',
          'kodeBarang',
          'barcode',
        ], fallback: '-'),
        nama: _teksDari([
          item
        ], const [
          'nama',
          'namaProduk',
          'namaBarang',
          'produk',
        ], fallback: '-'),
        satuan: _teksDari([
          item
        ], const [
          'satuan',
          'namaSatuan',
          'satuanNama',
          'uom',
        ], fallback: '-'),
        qty: _angkaDari([item], const ['qty', 'jumlah', 'kuantitas']),
        harga: _angkaDari(
            [item], const ['harga', 'hargaJual', 'hargaSatuan', 'price']),
        diskon:
            _angkaDari([item], const ['diskon', 'nilaiDiskon', 'diskonNilai']),
      );
    }).toList();
    final subtotal =
        baris.fold<double>(0, (sum, item) => sum + item.qty * item.harga);
    final diskonBaris = baris.fold<double>(0, (sum, item) => sum + item.diskon);
    final diskonHeader = _angkaOpsionalDari(
        sumber, const ['totalDiskon', 'diskonTotal', 'diskon', 'nilaiDiskon']);
    // Ringkasan legacy selalu mengirim totalDiskon=0 ketika field itu belum
    // didukung server. Jangan sampai nilai default tersebut menghapus diskon
    // nyata yang sudah tersimpan pada baris barang.
    final diskon =
        diskonHeader != null && diskonHeader > 0 ? diskonHeader : diskonBaris;
    final ppn = _angkaDari(sumber, const ['pajak', 'totalPajak', 'ppn']);
    final totalSumber = _angkaOpsionalDari(sumber, const [
      'totalBiaya',
      'grandTotal',
      'totalBayar',
      'totalPenjualan',
      'total',
      'nilai',
    ]);
    final totalHitung = subtotal - diskon + ppn;
    final total = totalSumber ?? totalHitung;
    final selisih = total - totalHitung;
    final dasarPajak = subtotal - diskon;
    final persenEksplisit = _angkaOpsionalDari(
        sumber, const ['pajakPersen', 'persenPajak', 'ppnPersen']);
    final pajakPersen = persenEksplisit != null && persenEksplisit > 0
        ? persenEksplisit
        : (ppn > 0 && dasarPajak > 0 ? (ppn / dasarPajak) * 100 : 0.0);
    final status = _teksDari(
            sumber, const ['statusPembayaran', 'statusBayar', 'status'],
            fallback: '')
        .toLowerCase();
    final belumLunas = status.contains('belum') ||
        status.contains('hutang') ||
        status.contains('piutang') ||
        status.contains('unpaid');

    return FakturPenjualanData(
      toko: toko.trim().isEmpty ? 'Nama Toko' : toko.trim(),
      alamat: alamat.trim().isEmpty ? '-' : alamat.trim(),
      telepon: telepon.trim(),
      pelanggan: _teksDari(
          sumber,
          const [
            'pembeli',
            'namaPembeli',
            'pelanggan',
            'namaPelanggan',
            'memberNama',
            'nama_member',
          ],
          fallback: 'Umum'),
      nomor: _teksDari(
          sumber,
          const [
            'kode',
            'nomorNota',
            'nomorTransaksi',
            'kodeTransaksi',
            'kodeUnik',
          ],
          fallback: '-'),
      tanggal: _formatTanggal(_nilaiDari(sumber, const [
        'waktu',
        'tanggal',
        'tanggalTransaksi',
        'createdAt',
      ])),
      metodePembayaran:
          metodePembayaran.trim().isEmpty ? '-' : metodePembayaran.trim(),
      kasir: _teksDari(sumber,
          const ['kasirNama', 'kasir', 'namaKasir', 'operator', 'petugas'],
          fallback: '-'),
      referensi: _teksDari(
          sumber, const ['poNo', 'nomorPo', 'nomorReferensi', 'referensi'],
          fallback: ''),
      keterangan: _teksDari(
          sumber, const ['keterangan', 'catatan', 'note', 'notes'],
          fallback: ''),
      subtotal: subtotal,
      diskon: diskon,
      ppn: ppn,
      pajakPersen: pajakPersen,
      biayaLain: selisih.abs() < 0.5 ? 0 : selisih,
      total: total,
      lunas: !belumLunas,
      items: baris,
    );
  }
}

dynamic _nilaiDari(List<Map<String, dynamic>> sumber, List<String> kunci) {
  for (final map in sumber) {
    for (final key in kunci) {
      final nilai = map[key];
      if (nilai != null && '$nilai'.trim().isNotEmpty && '$nilai' != 'null') {
        return nilai;
      }
    }
  }
  return null;
}

String _teksDari(List<Map<String, dynamic>> sumber, List<String> kunci,
    {required String fallback}) {
  final nilai = _nilaiDari(sumber, kunci);
  return nilai == null ? fallback : '$nilai'.trim();
}

double? _angkaOpsionalDari(
    List<Map<String, dynamic>> sumber, List<String> kunci) {
  final nilai = _nilaiDari(sumber, kunci);
  if (nilai is num) return nilai.toDouble();
  if (nilai is String) {
    return double.tryParse(
        nilai.replaceAll(RegExp(r'[^0-9,.-]'), '').replaceAll(',', '.'));
  }
  return null;
}

double _angkaDari(List<Map<String, dynamic>> sumber, List<String> kunci) =>
    _angkaOpsionalDari(sumber, kunci) ?? 0;

String _formatTanggal(dynamic nilai) {
  final raw = '${nilai ?? ''}'.trim();
  final parsed = nilai is DateTime ? nilai : DateTime.tryParse(raw);
  if (parsed == null) return raw.isEmpty || raw == 'null' ? '-' : raw;
  const bulan = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des'
  ];
  final jam = '${parsed.hour}'.padLeft(2, '0');
  final menit = '${parsed.minute}'.padLeft(2, '0');
  return '${parsed.day} ${bulan[parsed.month - 1]} ${parsed.year} $jam:$menit';
}

String namaFileFakturPenjualan(String nomor) {
  final aman = nomor
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'Faktur-Penjualan-${aman.isEmpty ? 'transaksi' : aman}.pdf';
}

/// Terbilang rupiah untuk nominal bulat pada faktur.
String terbilangRupiah(num nilai) {
  final angka = nilai.round().abs();
  if (angka == 0) return 'Nol rupiah';
  final hasil = _terbilang(angka).trim();
  return '${hasil[0].toUpperCase()}${hasil.substring(1)} rupiah';
}

String _terbilang(int nilai) {
  const satuan = [
    '',
    'satu',
    'dua',
    'tiga',
    'empat',
    'lima',
    'enam',
    'tujuh',
    'delapan',
    'sembilan',
    'sepuluh',
    'sebelas'
  ];
  if (nilai < 12) return satuan[nilai];
  if (nilai < 20) return '${_terbilang(nilai - 10)} belas';
  if (nilai < 100) {
    return '${_terbilang(nilai ~/ 10)} puluh ${_terbilang(nilai % 10)}';
  }
  if (nilai < 200) return 'seratus ${_terbilang(nilai - 100)}';
  if (nilai < 1000) {
    return '${_terbilang(nilai ~/ 100)} ratus ${_terbilang(nilai % 100)}';
  }
  if (nilai < 2000) return 'seribu ${_terbilang(nilai - 1000)}';
  if (nilai < 1000000) {
    return '${_terbilang(nilai ~/ 1000)} ribu ${_terbilang(nilai % 1000)}';
  }
  if (nilai < 1000000000) {
    return '${_terbilang(nilai ~/ 1000000)} juta ${_terbilang(nilai % 1000000)}';
  }
  if (nilai < 1000000000000) {
    return '${_terbilang(nilai ~/ 1000000000)} miliar ${_terbilang(nilai % 1000000000)}';
  }
  return '${_terbilang(nilai ~/ 1000000000000)} triliun ${_terbilang(nilai % 1000000000000)}';
}

pw.Document buatDokumenFakturPenjualan(FakturPenjualanData data) {
  final uang = NumberFormat.decimalPattern('id_ID');
  String nilaiUang(double nilai) => uang.format(nilai.round());
  String qty(double nilai) => nilai == nilai.roundToDouble()
      ? nilai.round().toString()
      : nilai
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
  final biru = PdfColor.fromInt(0xff173563);
  final abu = PdfColor.fromInt(0xffe5e7eb);
  final doc = pw.Document();

  pw.Widget info(String label, String nilai) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
              width: 82,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 8))),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 8)),
          pw.Expanded(
              child: pw.Text(nilai, style: const pw.TextStyle(fontSize: 8))),
        ],
      );

  pw.Widget totalBaris(String label, double nilai, {bool utama = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
          color: utama ? biru : PdfColors.white,
          border: pw.Border.all(color: utama ? biru : abu, width: 0.5),
        ),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Text(label,
                style: pw.TextStyle(
                    color: utama ? PdfColors.white : PdfColors.black,
                    fontSize: 8,
                    fontWeight:
                        utama ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
          pw.Text(nilaiUang(nilai),
              style: pw.TextStyle(
                  color: utama ? PdfColors.white : PdfColors.black,
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.portrait,
    margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
    footer: (context) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Dokumen dibuat dari Back Office',
            style: const pw.TextStyle(fontSize: 7)),
        pw.Text('Halaman ${context.pageNumber} dari ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7)),
      ],
    ),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(data.toko,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Text(data.alamat, style: const pw.TextStyle(fontSize: 8)),
              if (data.telepon.isNotEmpty)
                pw.Text('Telp. ${data.telepon}',
                    style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
        pw.Text('FAKTUR PENJUALAN',
            style: pw.TextStyle(
                fontSize: 17, fontWeight: pw.FontWeight.bold, color: biru)),
      ]),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: abu)),
            child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('KEPADA',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(data.pelanggan,
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ]),
          ),
        ),
        pw.SizedBox(width: 18),
        pw.SizedBox(
          width: 235,
          child: pw.Column(children: [
            info('Tanggal', data.tanggal),
            info('Nomor', data.nomor),
            info('Pembayaran', data.metodePembayaran),
            info('Kasir', data.kasir),
            if (data.referensi.isNotEmpty) info('Referensi', data.referensi),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
        headerDecoration: pw.BoxDecoration(color: biru),
        headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        columnWidths: {
          0: const pw.FixedColumnWidth(60),
          1: const pw.FlexColumnWidth(2.4),
          2: const pw.FixedColumnWidth(38),
          3: const pw.FixedColumnWidth(38),
          4: const pw.FixedColumnWidth(62),
          5: const pw.FixedColumnWidth(55),
          6: const pw.FixedColumnWidth(70),
        },
        cellAlignments: {
          2: pw.Alignment.center,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
        },
        headers: const [
          'Kode',
          'Nama Barang',
          'Kts.',
          'Sat.',
          '@Harga',
          'Diskon',
          'Total Harga'
        ],
        data: data.items
            .map((item) => [
                  item.kode,
                  item.nama,
                  qty(item.qty),
                  item.satuan,
                  nilaiUang(item.harga),
                  nilaiUang(item.diskon),
                  nilaiUang(item.total),
                ])
            .toList(),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: abu)),
        child: pw.Text('Terbilang: ${terbilangRupiah(data.total)}',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ),
      pw.SizedBox(height: 8),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Keterangan',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Container(
                  width: double.infinity,
                  height: 52,
                  padding: const pw.EdgeInsets.all(6),
                  decoration:
                      pw.BoxDecoration(border: pw.Border.all(color: abu)),
                  child: pw.Text(
                      data.keterangan.isEmpty ? '-' : data.keterangan,
                      style: const pw.TextStyle(fontSize: 8)),
                ),
              ]),
        ),
        pw.SizedBox(width: 20),
        pw.SizedBox(
          width: 220,
          child: pw.Column(children: [
            totalBaris('Sub Total', data.subtotal),
            totalBaris('Diskon', data.diskon),
            totalBaris(
                'PPN (${data.pajakPersen == data.pajakPersen.roundToDouble() ? data.pajakPersen.round() : data.pajakPersen.toStringAsFixed(2)}%)',
                data.ppn),
            totalBaris('Biaya Lain-lain', data.biayaLain),
            totalBaris('TOTAL', data.total, utama: true),
          ]),
        ),
      ]),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pw.Expanded(
          child: pw.Column(children: [
            pw.Text('Disiapkan Oleh', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 35),
            pw.Container(
                width: 110,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
          ]),
        ),
        pw.Expanded(
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: -0.12,
              child: pw.Container(
                padding:
                    const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                      color:
                          data.lunas ? PdfColors.green700 : PdfColors.orange700,
                      width: 2),
                ),
                child: pw.Text(data.lunas ? 'LUNAS' : 'BELUM LUNAS',
                    style: pw.TextStyle(
                      color:
                          data.lunas ? PdfColors.green700 : PdfColors.orange700,
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    )),
              ),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Column(children: [
            pw.Text('Disetujui Oleh', style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 35),
            pw.Container(
                width: 110,
                decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(width: 0.5)))),
          ]),
        ),
      ]),
    ],
  ));
  return doc;
}

/// Menyimpan berkas langsung, bukan mengandalkan printer virtual Windows.
/// Mengembalikan path jika pengguna memilih lokasi, atau null bila dibatalkan.
Future<String?> simpanFakturPenjualanPdf(FakturPenjualanData data) async {
  final namaFile = namaFileFakturPenjualan(data.nomor);
  final bytes =
      Uint8List.fromList(await buatDokumenFakturPenjualan(data).save());
  const dirUji = String.fromEnvironment('POS_TEST_PDF_DIR');
  if (dirUji.isNotEmpty) {
    final file = File('$dirUji${Platform.pathSeparator}$namaFile');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Simpan Faktur Penjualan PDF',
    fileName: namaFile,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
  if (path == null) return null;
  // Desktop hanya mengembalikan path; pada mobile bytes bisa sudah ditulis.
  // Penulisan ulang idempoten memastikan hasil benar di kedua platform.
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
