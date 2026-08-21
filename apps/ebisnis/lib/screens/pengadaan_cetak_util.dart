import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

/// Cetak satu dokumen Pengadaan, dengan PRATINJAU lebih dulu.
///
/// Alurnya: server merender PDF memakai templat JasperReports yang SAMA dengan
/// versi ZKoss, lalu mengirim isinya (base64) beserta URL-nya. Isi berkas dipakai
/// untuk membuka pratinjau bawaan `printing` -- pengguna melihat dokumennya,
/// baru memutuskan mencetak. Bila isinya tidak ikut terkirim (dokumen sangat
/// besar), URL-nya dibuka di peramban sebagai jalan mundur.
///
/// [tahap] salah satu dari: pr, po, bast, tagihan, dpc.
Future<void> cetakDokumenPengadaan(
  BuildContext context, {
  required String tahap,
  required int id,
  String? kode,
}) async {
  final pesan = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Menyiapkan dokumen...'),
      ]),
    ),
  );
  Map<String, dynamic>? r;
  String? galat;
  try {
    r = await ApiClient.instance
        .aksi('pengadaan_cetak', {'tahap': tahap, 'id': id});
  } catch (e) {
    galat = '$e';
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (galat != null) {
    pesan.showSnackBar(SnackBar(content: Text('Gagal mencetak: $galat')));
    return;
  }
  final hasil = r ?? const <String, dynamic>{};
  if (hasil['status'] != '00' && hasil['status'] != 'success') {
    pesan.showSnackBar(SnackBar(
        content: Text('${hasil['description'] ?? 'Dokumen gagal dicetak.'}')));
    return;
  }

  final b64 = '${hasil['fileBase64'] ?? ''}';
  final nama = '${hasil['kode'] ?? kode ?? 'dokumen'}';
  if (b64.isNotEmpty) {
    final bytes = base64Decode(b64);
    // Printing.layoutPdf() LANGSUNG membuka dialog printer sistem -- pengguna
    // tidak sempat melihat dokumennya. Tampilkan pratinjau dulu; tombol cetak
    // ada di dalam pratinjau, jadi mencetak tetap satu klik dari sini.
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PratinjauDokumen(bytes: bytes, nama: nama),
    ));
    return;
  }

  // Jalan mundur: dokumen terlalu besar untuk ikut dikirim -- buka lewat URL.
  final url = '${hasil['url'] ?? ''}';
  if (url.isEmpty) {
    pesan.showSnackBar(
        const SnackBar(content: Text('Dokumen tercetak tetapi tidak dapat dibuka.')));
    return;
  }
  final asal = Uri.parse(ApiClient.baseUrl).origin;
  final uri = Uri.parse(url.startsWith('http') ? url : '$asal$url');
  final terbuka = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!terbuka && context.mounted) {
    pesan.showSnackBar(SnackBar(content: Text('Tidak bisa membuka $uri')));
  }
}

/// Halaman pratinjau dokumen Pengadaan.
///
/// Memakai [PdfPreview] bawaan paket `printing`: dokumen dirender di layar
/// lebih dulu, dan tombol cetak/bagikan tersedia di bilah atasnya. Pemilihan
/// ukuran kertas & orientasi DIMATIKAN karena templat JasperReports di server
/// sudah menentukannya -- mengubahnya di sini hanya akan membuat hasil cetak
/// berbeda dengan versi ZKoss.
class _PratinjauDokumen extends StatelessWidget {
  final Uint8List bytes;
  final String nama;

  const _PratinjauDokumen({required this.bytes, required this.nama});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pratinjau $nama')),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: '$nama.pdf',
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        initialPageFormat: PdfPageFormat.a4,
      ),
    );
  }
}
