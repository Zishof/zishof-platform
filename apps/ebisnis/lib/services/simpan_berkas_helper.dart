import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:path/path.dart' as p;

/// Pembantu terpusat penyimpanan / pengunduhan berkas lintas platform (Windows,
/// macOS, Linux, Android, iOS) yang menjamin pengguna **bebas memilih folder
/// tujuan SEKALIGUS bebas mengubah/mengetik ulang nama berkas (*rename*)**
/// sebelum disimpan.
///
/// ### Mengapa tidak memakai `FilePicker.platform.saveFile` secara mentah di Windows?
/// Implementasi `file_picker` (`file_picker_windows.dart`) memanggil dialog
/// Win32 lawas `GetSaveFileNameW` dengan flag **`OFN_FILEMUSTEXIST`**. Akibatnya,
/// ketika pengguna mengetik nama berkas baru (mengubah nama bawaan), Windows
/// menolak dengan peringatan *"File not found. Check the file name and try again."*
/// sehingga nama berkas tidak bisa di-*rename* saat mengunduh!
///
/// Sebaliknya, `FileSelectorPlatform.instance.getSaveLocation` (`file_selector_windows`)
/// menggunakan COM modern **`IFileSaveDialog`** hanya dengan `FOS_OVERWRITEPROMPT`
/// (TANPA `FOS_FILEMUSTEXIST`), sehingga di Windows Explorer pengguna dapat:
/// 1. Memilih folder mana pun,
/// 2. Langsung menghapus / mengetik ulang nama berkas sesuka hati di kotak *File name*,
/// 3. Tetap mendapat ekstensi otomatis (mis. mengetik `Rekap Kantin Nov` untuk
///    ekspor Excel otomatis menjadi `Rekap Kantin Nov.xlsx`).
class SimpanBerkasHelper {
  SimpanBerkasHelper._();

  static final RegExp _karakterIlegalNamaBerkas =
      RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  /// Membersihkan nama berkas yang disarankan dari karakter terlarang Windows/POSIX
  /// serta memastikan ekstensi default terpasang bila daftar [allowedExtensions] diberikan.
  static String bersihkanNamaSaran(
    String fileName, {
    List<String>? allowedExtensions,
  }) {
    var bersih = fileName.trim().replaceAll(_karakterIlegalNamaBerkas, '_');
    // Hindari spasi/titik menggantung di ujung nama berkas Windows.
    bersih = bersih.replaceAll(RegExp(r'[\s.]+$'), '');
    if (bersih.isEmpty) {
      bersih = 'berkas_unduhan';
    }
    return pastikanEkstensiPath(bersih, allowedExtensions: allowedExtensions);
  }

  /// Menjamin jalur berkas hasil ketikan pengguna tetap memiliki ekstensi yang
  /// valid apabila pengguna mengubah nama berkas tanpa mengetik ulang `.xlsx`/`.pdf`/dst.
  static String pastikanEkstensiPath(
    String targetPath, {
    List<String>? allowedExtensions,
  }) {
    final trimmed = targetPath.trim();
    if (trimmed.isEmpty || trimmed.startsWith('content://')) {
      return trimmed;
    }
    final daftarEkstensi = (allowedExtensions ?? const <String>[])
        .map((e) => e.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (daftarEkstensi.isEmpty) {
      return trimmed;
    }

    final dir = p.dirname(trimmed);
    var base = p.basename(trimmed).trim();
    base = base.replaceAll(RegExp(r'[\s.]+$'), '');
    if (base.isEmpty) {
      base = 'berkas_unduhan';
    }

    final extSekarang =
        p.extension(base).replaceFirst(RegExp(r'^\.+'), '').toLowerCase();
    if (extSekarang.isEmpty || !daftarEkstensi.contains(extSekarang)) {
      base = '$base.${daftarEkstensi.first}';
    }
    return (dir == '.' && !trimmed.contains('/') && !trimmed.contains('\\'))
        ? base
        : p.join(dir, base);
  }

  /// Membuka dialog sistem operasi untuk memilih lokasi & nama berkas simpanan
  /// tanpa menulis isi berkas secara otomatis (cocok untuk pemanggil yang menulis
  /// sendiri setelah path terpilih).
  static Future<String?> pilihLokasiSimpan({
    String? dialogTitle,
    required String fileName,
    List<String>? allowedExtensions,
    Uint8List? bytesMobile,
  }) async {
    final namaSaran = bersihkanNamaSaran(
      fileName,
      allowedExtensions: allowedExtensions,
    );
    final daftarEkstensi = (allowedExtensions ?? const <String>[])
        .map((e) => e.trim().replaceFirst(RegExp(r'^\.+'), '').toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final typeGroups = daftarEkstensi.isEmpty
          ? const <XTypeGroup>[]
          : <XTypeGroup>[
              XTypeGroup(
                label:
                    'Berkas (${daftarEkstensi.map((e) => '*.$e').join(', ')})',
                extensions: daftarEkstensi,
              ),
              const XTypeGroup(label: 'Semua Berkas (*.*)', extensions: []),
            ];

      final lokasi = await FileSelectorPlatform.instance.getSaveLocation(
        acceptedTypeGroups: typeGroups,
        options: SaveDialogOptions(
          suggestedName: namaSaran,
          confirmButtonText: 'Simpan',
        ),
      );
      if (lokasi == null || lokasi.path.trim().isEmpty) {
        return null;
      }
      return pastikanEkstensiPath(
        lokasi.path,
        allowedExtensions: daftarEkstensi,
      );
    }

    // Android / iOS: gunakan SAF / Document Picker bawaan mobile.
    final pathMobile = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: namaSaran,
      bytes: bytesMobile,
      type: daftarEkstensi.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: daftarEkstensi.isEmpty ? null : daftarEkstensi,
    );
    if (pathMobile == null || pathMobile.trim().isEmpty) {
      return null;
    }
    return pastikanEkstensiPath(
      pathMobile,
      allowedExtensions: daftarEkstensi,
    );
  }

  /// Membuka dialog *Save As* (bebas pilih folder & *rename* nama berkas) lalu
  /// langsung menuliskan [bytes] ke berkas tujuan. Mengembalikan path final
  /// berkas yang tersimpan, atau `null` bila pengguna membatalkan dialog.
  static Future<String?> simpanBytes({
    String? dialogTitle,
    required String fileName,
    required List<int> bytes,
    List<String>? allowedExtensions,
  }) async {
    final dataBytes =
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final path = await pilihLokasiSimpan(
      dialogTitle: dialogTitle,
      fileName: fileName,
      allowedExtensions: allowedExtensions,
      bytesMobile: dataBytes,
    );
    if (path == null) return null;
    if (!path.startsWith('content://')) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(dataBytes, flush: true);
    }
    return path;
  }
}
