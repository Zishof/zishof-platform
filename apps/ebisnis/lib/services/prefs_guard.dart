import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Perbaikan mandiri utk `shared_preferences.json` yang korup -- gap-closure
/// "app tidak bisa dibuka lagi stlh mati listrik, satu-satunya cara adalah
/// hapus folder AppData".
///
/// Akar masalah: `shared_preferences_windows` menulis file ini LANGSUNG ke
/// lokasi asli (`writeAsStringSync`), BUKAN pola tulis-ke-temp-lalu-rename --
/// listrik mati di tengah proses tulis meninggalkan JSON setengah-jadi.
/// `SharedPreferences.getInstance()` sendiri TIDAK punya try/catch di
/// sekitar `json.decode()`-nya, jadi file korup bikin exception lolos TAK
/// TERTANGANI di titik pertama manapun yang memanggilnya -- yang karena
/// dipanggil tanpa `await` dari `initState()` (`ServerConfig.muat()` dkk),
/// jadi unhandled Future error yang cuma ditelan zone handler, dan flag
/// loading (`_memeriksa`/`_memuat`) tidak pernah sempat di-set `false` --
/// app macet SELAMANYA di spinner, tanpa pesan error, tanpa jejak log.
///
/// HARUS dipanggil di [main] SEBELUM kode lain manapun menyentuh
/// `SharedPreferences` (langsung ATAU tak langsung lewat servis spt
/// `ServerConfig`/`AppThemeController`) -- kalau filenya korup, dicadangkan
/// (BUKAN dihapus, spy masih bisa diperiksa manual kalau perlu) supaya baca
/// berikutnya oleh `SharedPreferences.getInstance()` mulai dari kosong
/// (otomatis dibuat ulang saat nanti ada yg ditulis), bukan melempar
/// exception yang menggantung.
class PrefsGuard {
  PrefsGuard._();

  static Future<void> perbaikiJikaKorup() async {
    File? file;
    try {
      final dir = await getApplicationSupportDirectory();
      file = File(p.join(dir.path, 'shared_preferences.json'));
      if (!await file.exists()) return;
      final isi = await file.readAsString();
      if (isi.trim().isEmpty) return;
      final data = jsonDecode(isi);
      if (data is! Map) {
        throw const FormatException('Isi shared_preferences.json bukan objek JSON.');
      }
    } catch (e) {
      if (file != null) await _cadangkanKorup(file, alasan: e.toString());
    }
  }

  static Future<void> _cadangkanKorup(File file, {required String alasan}) async {
    try {
      if (!await file.exists()) return;
      final cadangan = File(
          '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      await file.rename(cadangan.path);
      if (kDebugMode) {
        debugPrint(
            'PrefsGuard: ${file.path} korup ($alasan) -- dicadangkan ke ${cadangan.path}.');
      }
    } catch (_) {
      // Upaya terbaik (mis. rename gagal krn terkunci proses lain) --
      // SharedPreferences.getInstance() berikutnya akan melempar apa
      // adanya spt sebelum fitur perbaikan ini ada.
    }
  }
}
