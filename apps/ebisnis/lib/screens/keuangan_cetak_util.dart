import 'dart:convert';

import 'package:flutter/material.dart';

import '../api_client.dart';
import 'pengadaan_cetak_util.dart';

/// Cetak satu dokumen grup menu **Keuangan** (uang muka, LPJ, kas besar, dst).
///
/// Memakai jendela pratinjau yang SAMA dengan cetak Pengadaan
/// ([tampilkanPratinjauPdf]) supaya pengguna tidak menemui dua rasa jendela
/// cetak yang berbeda. Berkasnya sendiri dibuat server dari templat Jasper yang
/// sama dengan layar ZK, jadi lembar cetaknya identik dengan cetakan lama.
Future<void> cetakDokumenKeuangan(
  BuildContext context, {
  required String modul,
  required int id,
  String? kode,
}) async {
  final pesan = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Menyiapkan dokumen...'),
      ]),
    ),
  );

  Map<String, dynamic>? r;
  String? galat;
  try {
    r = await ApiClient.instance.aksi('keuangan_cetak', {'modul': modul, 'id': id});
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
    pesan.showSnackBar(
        SnackBar(content: Text('${hasil['description'] ?? 'Dokumen gagal dicetak.'}')));
    return;
  }
  final b64 = '${hasil['fileBase64'] ?? ''}';
  if (b64.isEmpty) {
    pesan.showSnackBar(
        const SnackBar(content: Text('Dokumen tercetak tetapi berkasnya tidak terkirim.')));
    return;
  }
  await tampilkanPratinjauPdf(
    context,
    judul: '${hasil['kode'] ?? kode ?? 'dokumen'}',
    isi: base64Decode(b64),
  );
}
