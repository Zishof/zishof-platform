import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';
import 'server_config.dart';
import 'package:flutter/foundation.dart';
import 'kompresi_gambar.dart';

/// Unggahan lampiran untuk satu tahap SOP.
///
/// Server memang memisahkan jalur ini dari aksi JSON `sop_proses`: lampiran
/// dikirim lebih dulu ke servlet `DoUpload` (multipart), barulah `sop_proses`
/// dipanggil. Itu persis urutan yang dipakai versi ZKoss, dan `SopService`
/// membacanya kembali lewat `LampiranLain.ambil(disposisiAlurSopId, key)`.
///
/// `DoUpload` menerima token POS sebagai FIELD form (`token`), bukan header
/// `Authorization` -- lihat `DoUpload.handleUserProfileUpload` yang memanggil
/// `ApiUtil.currentUser(token)`. Karena itu kelas ini tidak memakai
/// [ApiClient.aksi], melainkan membangun permintaannya sendiri.
class UnggahLampiranSop {
  UnggahLampiranSop._();

  /// Nama kelas entitas lampiran di server -- sama dengan yang dibaca
  /// `SopService` saat menampilkan kembali dokumen tahap.
  static const String _kelasLampiran = 'ais.database.model.file.LampiranLain';

  static String get _urlDoUpload =>
      '${ServerConfig.instance.baseUrlTanpaEndpoint}DoUpload';

  /// Mengunggah satu berkas sebagai lampiran dengan jenis [kunci] (nilai `key`
  /// dari `dokumenDefinisi`/`parameterDefinisi`).
  ///
  /// [ref] adalah acuan pemilik lampiran. Untuk tahap yang sedang berjalan itu
  /// `disposisiAlurSopId`. Untuk pengajuan BARU yang belum tersimpan, itu
  /// `refSementara` -- id placeholder NEGATIF dari `sop_mulai_info`, yang
  /// dipetakan ulang ke id tahap awal yang sebenarnya oleh `sop_ajukan`. Pola
  /// ini sama persis dengan `ref = -Common.randLong()` di versi ZKoss.
  ///
  /// Mengembalikan null bila sukses, atau pesan galat yang layak ditampilkan.
  static Future<String?> unggah({
    required String ref,
    required String kunci,
    required String namaBerkas,
    required List<int> isi,
  }) async {
    final token = ApiClient.instance.token;
    if (token == null || token.isEmpty) {
      return 'Sesi sudah berakhir. Masuk ulang lalu coba lagi.';
    }

    // Lampiran SOP boleh berupa apa saja (foto bukti, PDF surat). Yang berupa
    // GAMBAR dikecilkan ke bawah 500 KB di sini -- satu tempat, sehingga
    // seluruh pemanggil ikut terlindungi tanpa harus mengingatnya. Yang bukan
    // gambar dilewatkan apa adanya.
    // Pagar 5 MB diperiksa SEBELUM blok maaf di bawah: blok itu sengaja
    // memaafkan kompresi yang gagal dan mengirim berkas aslinya, dan tanpa
    // pemeriksaan terpisah ia akan ikut memaafkan berkas yang justru harus
    // ditolak -- lalu mengirimkannya mentah.
    final Uint8List bytesAsal =
        isi is Uint8List ? isi : Uint8List.fromList(isi);
    if (tampaknyaGambar(bytesAsal)) {
      try {
        tolakBilaGambarTerlaluBesar(bytesAsal);
      } on FormatException catch (e) {
        return e.message;
      }
    }

    List<int> muatan = isi;
    try {
      // Ambang DOKUMEN (2 MB): berkas pengajuan SOP berupa surat, kuitansi, dan
      // bukti -- dibaca isinya, bukan sekadar dilihat sepintas seperti katalog.
      muatan = await compute(siapkanLampiranDokumenCampuran, bytesAsal);
    } catch (_) {
      // Kompresi gagal (mis. gambar rusak) -- kirim aslinya. Menggagalkan
      // unggahan karena kompresi gagal akan menghalangi pekerjaan yang sah;
      // batas ukurannya ditegakkan server.
      muatan = isi;
    }

    try {
      final permintaan =
          http.MultipartRequest('POST', Uri.parse(_urlDoUpload))
            ..fields['token'] = token
            ..fields['clazz'] = _kelasLampiran
            ..fields['id'] = ref
            ..fields['jenis'] = kunci
            ..fields['nama'] = namaBerkas
            ..files.add(http.MultipartFile.fromBytes('file', muatan,
                filename: namaBerkas));

      final balasan = await http.Response.fromStream(
          await permintaan.send().timeout(const Duration(seconds: 60)));

      if (balasan.statusCode < 200 || balasan.statusCode >= 300) {
        return 'Server menolak unggahan (HTTP ${balasan.statusCode}).';
      }
      // DoUpload membalas {"status":"Sukses"} / {"status":"Gagal"}; balasan
      // non-JSON diperlakukan sebagai kegagalan agar tidak terlihat berhasil
      // padahal berkasnya tidak tersimpan.
      try {
        final isiBalasan = jsonDecode(balasan.body);
        if (isiBalasan is Map && '${isiBalasan['status']}'.toLowerCase() == 'sukses') {
          return null;
        }
        return 'Berkas tidak tersimpan di server.';
      } catch (_) {
        return 'Balasan server tidak dikenali saat mengunggah berkas.';
      }
    } catch (e) {
      return 'Gagal mengunggah berkas: $e';
    }
  }
}
