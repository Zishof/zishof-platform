import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

/// Cetak satu dokumen Pengadaan, SELALU lewat pratinjau di dalam aplikasi.
///
/// Server merender PDF memakai templat JasperReports yang sama dengan versi ZKoss,
/// lalu mengirim isinya (base64) beserta URL-nya.
///
/// Dokumen ditampilkan pada jendela pratinjau [PdfPreview] -- pengguna melihat
/// halamannya lebih dulu, memperbesar, mengganti ukuran kertas, baru menekan cetak.
/// Sengaja TIDAK memanggil `Printing.layoutPdf` secara langsung: di Windows itu
/// melompat ke dialog "Print Setup" bawaan sistem tanpa pengguna sempat melihat
/// dokumennya.
///
/// [tahap] salah satu dari: pr, po, bast, tagihan, dpc, pajak.
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
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PratinjauCetakDialog(judul: nama, isi: bytes),
    );
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

/// Menampilkan pratinjau PDF pada jendela yang SAMA dengan cetak Pengadaan.
///
/// Dipakai juga oleh modul "Pengajuan Anda" (Workflow / Proses SOP), yang aksi
/// cetaknya (`sop_cetak`) hanya mengembalikan URL sehingga isinya diunduh dulu.
/// Dijadikan satu di sini supaya seluruh modul memakai pratinjau yang sama --
/// bukan dua jendela cetak yang berbeda rasa.
Future<void> tampilkanPratinjauPdf(BuildContext context,
    {required String judul, required Uint8List isi}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PratinjauCetakDialog(judul: judul, isi: isi),
  );
}

/// Jendela pratinjau dokumen. Tombol cetak ada DI DALAM pratinjau, jadi dialog
/// printer sistem baru muncul setelah pengguna benar-benar menekannya.
class _PratinjauCetakDialog extends StatelessWidget {
  final String judul;
  final Uint8List isi;
  const _PratinjauCetakDialog({required this.judul, required this.isi});

  @override
  Widget build(BuildContext context) {
    final layar = MediaQuery.of(context).size;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: layar.width * 0.9,
        height: layar.height * 0.9,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Pratinjau $judul',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: PdfPreview(
              build: (_) async => isi,
              pdfFileName: '$judul.pdf',
              canChangePageFormat: true,
              canChangeOrientation: true,
              canDebug: false,
              allowSharing: true,
              allowPrinting: true,
              loadingWidget: const Center(child: CircularProgressIndicator()),
              onPrinted: (_) {
                if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              },
            ),
          ),
        ]),
      ),
    );
  }
}
