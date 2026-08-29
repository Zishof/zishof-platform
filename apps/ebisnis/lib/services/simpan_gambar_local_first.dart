import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_db/core_db.dart';

import '../api_client.dart';
import 'master_offline.dart';

/// Hasil penyimpanan media dengan jaminan local-first.
///
/// [tertunda] berarti berkas sudah aman di outbox SQLite, tetapi server belum
/// mengakuinya. Timer [MasterOffline] akan mencoba ulang secara periodik.
class HasilSimpanGambar {
  final Map<String, dynamic> respons;
  final bool tertunda;
  final int idAntrean;

  const HasilSimpanGambar(this.respons,
      {required this.tertunda, required this.idAntrean});
}

/// Salinan media yang masih menunggu penerimaan server.
class GambarLokalTertunda {
  final int idAntrean;
  final String aksi;
  final String kunci;
  final String namaFile;
  final Uint8List bytes;
  final String status;

  const GambarLokalTertunda({
    required this.idAntrean,
    required this.aksi,
    required this.kunci,
    required this.namaFile,
    required this.bytes,
    required this.status,
  });
}

/// Pulihkan preview media dari SQLite agar tetap terlihat setelah form dibuka
/// ulang, termasuk ketika server sedang lama, belum mendukung aksi, atau baru
/// saja menolak payload. Baris rusak dilewati tanpa menggagalkan form.
Future<List<GambarLokalTertunda>> muatGambarLokalTertunda({
  required String aksi,
  required String awalanKunci,
  String fieldBase64 = 'file_base64',
}) async {
  final baris = await CoreDb.instance.outboxMasterAktif(
    aksi: aksi,
    awalanKunci: awalanKunci,
  );
  final hasil = <GambarLokalTertunda>[];
  for (final antrean in baris) {
    try {
      final payload = jsonDecode('${antrean['payload_json'] ?? '{}'}')
          as Map<String, dynamic>;
      final encoded = '${payload[fieldBase64] ?? ''}'.trim();
      if (encoded.isEmpty) continue;
      hasil.add(GambarLokalTertunda(
        idAntrean: (antrean['id'] as num).toInt(),
        aksi: '${antrean['aksi'] ?? aksi}',
        kunci: '${antrean['kunci'] ?? ''}',
        namaFile: '${payload['nama_file'] ?? 'foto.jpg'}',
        bytes: base64Decode(encoded),
        status: '${antrean['status'] ?? 'PENDING'}',
      ));
    } catch (_) {
      // Payload diagnostik lama/rusak tidak boleh memblokir form.
    }
  }
  return hasil;
}

/// Batalkan media lokal yang belum pernah diterima server.
Future<void> hapusGambarLokalTertunda(int idAntrean) =>
    CoreDb.instance.outboxMasterHapus(idAntrean);

/// Kontrak tunggal untuk SEMUA upload gambar.
///
/// Berkas selalu ditulis ke outbox lebih dahulu. Gangguan jaringan, HTTP 5xx,
/// respons HTML/non-JSON, dan timeout tidak boleh menghilangkan foto yang sudah
/// dipilih pengguna. Penolakan bisnis eksplisit tetap dilempar agar datanya
/// dapat diperbaiki, sementara payload lokal tetap tersedia untuk diagnosis.
Future<HasilSimpanGambar> simpanGambarLocalFirst({
  required String aksi,
  required Map<String, dynamic> body,
  required String kunci,
  Duration batasTunggu = const Duration(seconds: 6),
}) async {
  final idAntrean = await MasterOffline.antreLokal(
    aksi,
    body,
    kunci: kunci,
  );
  try {
    final respons = await MasterOffline.kirimSatuAntrean(
      idAntrean,
      aksi,
      body,
      kunci: kunci,
    ).timeout(batasTunggu);
    return HasilSimpanGambar(respons, tertunda: false, idAntrean: idAntrean);
  } on TimeoutException {
    return HasilSimpanGambar(
      <String, dynamic>{'status': 'success', 'offline': true},
      tertunda: true,
      idAntrean: idAntrean,
    );
  } on ApiException catch (error) {
    if (!MasterOffline.dapatDicobaUlang(error)) rethrow;
    return HasilSimpanGambar(
      <String, dynamic>{'status': 'success', 'offline': true},
      tertunda: true,
      idAntrean: idAntrean,
    );
  }
}
