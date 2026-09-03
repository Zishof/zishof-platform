import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog kesalahan baku aplikasi.
///
/// Menyamakan perilaku alert di seluruh produk eCampus (ZKoss, JSP, dan mobile):
///
/// * **Yang tampil tanpa diklik apa pun adalah informasi yang BERMAKNA** — apa yang
///   gagal, penyebabnya, dan langkah yang dapat dicoba pengguna. Bukan sapaan, bukan
///   kalimat generik "terjadi kesalahan", dan bukan pesan exception mentah.
/// * **Rincian teknis disembunyikan di balik "Detail"** dan baru muncul saat ditekan —
///   selengkap mungkin: waktu, kode rujukan, konteks, tipe error, penyebab terdalam,
///   dan stack trace penuh. Disertai tombol Salin agar pengguna tinggal menempelkannya
///   ke pesan untuk pengembang.
///
/// Sisi ZKoss memakai `MyMessageboxConfig` dan sisi JSP memakai `pesan-formal.js`
/// dengan bentuk yang sama; kelas ini adalah padanannya untuk Flutter.
///
/// Berada di `core_ui` supaya seluruh aplikasi pada monorepo ini (ebisnis, ecanteen)
/// memakai bentuk dialog kesalahan yang sama. Aplikasi yang belum bergantung pada
/// `core_ui` cukup menambahkannya pada `pubspec.yaml`.
///
/// Contoh pemakaian:
///
/// ```dart
/// try {
///   await simpanTagihan();
/// } catch (e, s) {
///   await DialogKesalahan.tampilkan(
///     context,
///     ringkasan: 'Tagihan belum dapat disimpan karena nominalnya melebihi sisa '
///         'tunggakan mahasiswa ini.',
///     langkah: const <String>[
///       'Periksa kembali nominal yang diisikan.',
///       'Muat ulang daftar tagihan lalu coba simpan sekali lagi.',
///     ],
///     konteks: 'penyimpanan tagihan mahasiswa',
///     error: e,
///     stackTrace: s,
///   );
/// }
/// ```
class DialogKesalahan {
  const DialogKesalahan._();

  /// Kode rujukan singkat untuk satu kejadian, dicetak di muka DAN di dalam detail
  /// sehingga laporan pengguna dapat dicocokkan dengan catatan di sisi server.
  static String buatKodeRujukan() {
    final String basis =
        DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'APP-$basis';
  }

  /// Tampilkan dialog kesalahan.
  ///
  /// [ringkasan] wajib diisi dengan kalimat yang benar-benar menjelaskan masalahnya
  /// dalam bahasa pengguna — inilah satu-satunya hal yang dibaca sebagian besar orang.
  static Future<void> tampilkan(
    BuildContext context, {
    required String ringkasan,
    String judul = 'Terjadi Kesalahan',
    List<String> langkah = const <String>[],
    String? konteks,
    Object? error,
    StackTrace? stackTrace,
    String? kodeRujukan,
    String? detailTambahan,
  }) {
    final String kode = kodeRujukan ?? buatKodeRujukan();
    final String detail = susunDetail(
      ringkasan: ringkasan,
      judul: judul,
      langkah: langkah,
      konteks: konteks,
      error: error,
      stackTrace: stackTrace,
      kodeRujukan: kode,
      detailTambahan: detailTambahan,
    );
    return showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => _IsiDialogKesalahan(
        judul: judul,
        ringkasan: ringkasan,
        langkah: langkah,
        kodeRujukan: kode,
        detail: detail,
      ),
    );
  }

  /// Susun teks teknis yang dibuka lewat tombol "Detail" dan disalin pengguna.
  ///
  /// Ringkasan teknis (tipe & pesan error, termasuk penyebab TERDALAM) ditulis
  /// SEBELUM stack trace: keduanya hal pertama yang dicari pengembang dan mudah
  /// terlewat pada stack trace yang panjang.
  static String susunDetail({
    required String ringkasan,
    required String judul,
    List<String> langkah = const <String>[],
    String? konteks,
    Object? error,
    StackTrace? stackTrace,
    String? kodeRujukan,
    String? detailTambahan,
  }) {
    final StringBuffer b = StringBuffer();
    b.writeln('Waktu         : ${DateTime.now()}');
    b.writeln('Kode Rujukan  : ${kodeRujukan ?? '-'}');
    b.writeln('Judul         : $judul');
    if (konteks != null && konteks.trim().isNotEmpty) {
      b.writeln('Proses        : ${konteks.trim()}');
    }
    b.writeln();
    b.writeln('Pesan yang Ditampilkan:');
    b.writeln(ringkasan);
    b.writeln();
    if (langkah.isNotEmpty) {
      b.writeln('Langkah yang Disarankan:');
      for (int i = 0; i < langkah.length; i++) {
        b.writeln('  ${i + 1}. ${langkah[i]}');
      }
      b.writeln();
    }
    if (detailTambahan != null && detailTambahan.trim().isNotEmpty) {
      b.writeln('Keterangan Tambahan:');
      b.writeln(detailTambahan.trim());
      b.writeln();
    }
    if (error != null) {
      final Object akar = akarPenyebab(error);
      b.writeln('Ringkasan Teknis:');
      b.writeln('- Tipe error utama       : ${error.runtimeType}');
      b.writeln('- Pesan error utama      : $error');
      if (!identical(akar, error)) {
        b.writeln('- Tipe penyebab terdalam : ${akar.runtimeType}');
        b.writeln('- Pesan penyebab terdalam: $akar');
      }
      b.writeln();
    }
    b.writeln('Stack Trace:');
    b.writeln(stackTrace == null
        ? 'Tidak ada stack trace yang dikirim ke dialog ini.'
        : stackTrace.toString());
    return sensor(b.toString());
  }

  /// Penyebab terdalam pada rantai [Error]/[Exception] yang membungkus penyebab lain.
  ///
  /// Dart tidak punya `getCause()` baku, jadi ditelusuri lewat properti `cause` bila
  /// objeknya menyediakannya (pola yang lazim pada exception khusus aplikasi).
  /// Dijaga dari rantai melingkar.
  static Object akarPenyebab(Object error) {
    Object hasil = error;
    int batas = 0;
    while (batas < 50) {
      Object? berikut;
      try {
        final dynamic dinamis = hasil;
        berikut = dinamis.cause as Object?;
      } catch (_) {
        berikut = null;
      }
      if (berikut == null || identical(berikut, hasil)) {
        break;
      }
      hasil = berikut;
      batas++;
    }
    return hasil;
  }

  /// Hapus kredensial dari teks teknis sebelum ditampilkan atau disalin.
  ///
  /// Teks ini akan disalin pengguna dan dikirim lewat kanal yang tidak terkendali
  /// (WhatsApp, e-mail), sementara pesan galat jaringan/basis data kerap membawa URL
  /// koneksi berikut sandinya. Penyensoran dilakukan di sini, bukan diserahkan pada
  /// kebijaksanaan pengguna.
  static String sensor(String teks) {
    if (teks.isEmpty) {
      return teks;
    }
    String hasil = teks;
    try {
      // Authorization: Bearer <token> -- nilainya mengandung spasi, jadi disikat
      // sampai akhir baris. HARUS didahulukan sebelum aturan kata kunci di bawah,
      // yang hanya akan memakan kata "Bearer" dan justru meninggalkan tokennya.
      hasil = hasil.replaceAllMapped(
        RegExp(r'(authorization)(\s*[=:]\s*).*', caseSensitive: false),
        (Match m) => '${m[1]}${m[2]}***disensor***',
      );
      hasil = hasil.replaceAllMapped(
        RegExp(r'\bbearer\s+[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false),
        (Match m) => 'Bearer ***disensor***',
      );
      // Kutip pembuka ditangkap terpisah: tanpa itu nilai yang diapit tanda kutip
      // justru LOLOS, karena kutip termasuk karakter penghenti.
      hasil = hasil.replaceAllMapped(
        RegExp(
          '(password|passwd|pwd|secret|token|api[_-]?key)'
          '(\\s*[=:]\\s*)(["\']?)[^\\s,;&\'"<>)\\]}]+',
          caseSensitive: false,
        ),
        (Match m) => '${m[1]}${m[2]}${m[3]}***disensor***',
      );
      // skema://pengguna:sandi@host
      hasil = hasil.replaceAllMapped(
        RegExp(r'([a-z0-9+.-]+://[^/:@\s]+):([^@\s/]+)@', caseSensitive: false),
        (Match m) => '${m[1]}:***disensor***@',
      );
    } catch (_) {
      // Bila regex gagal, lebih baik kembalikan teks apa adanya daripada
      // kehilangan seluruh detail teknis.
      return teks;
    }
    return hasil;
  }
}

/// Isi dialog. Dipisah menjadi widget tersendiri agar buka-tutup bagian "Detail"
/// punya state sendiri tanpa memaksa pemanggil menjadi stateful.
class _IsiDialogKesalahan extends StatefulWidget {
  const _IsiDialogKesalahan({
    required this.judul,
    required this.ringkasan,
    required this.langkah,
    required this.kodeRujukan,
    required this.detail,
  });

  final String judul;
  final String ringkasan;
  final List<String> langkah;
  final String kodeRujukan;
  final String detail;

  @override
  State<_IsiDialogKesalahan> createState() => _IsiDialogKesalahanState();
}

class _IsiDialogKesalahanState extends State<_IsiDialogKesalahan> {
  bool _detailTerbuka = false;
  bool _tersalin = false;

  Future<void> _salin() async {
    await Clipboard.setData(ClipboardData(text: widget.detail));
    if (!mounted) {
      return;
    }
    setState(() => _tersalin = true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData tema = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: tema.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.judul)),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ---- RINGKASAN: terbaca tanpa menekan apa pun ----
              Text(widget.ringkasan, style: const TextStyle(height: 1.45)),
              if (widget.langkah.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                const Text('Yang dapat Anda lakukan:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                for (int i = 0; i < widget.langkah.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${i + 1}. ${widget.langkah[i]}',
                        style: const TextStyle(height: 1.4)),
                  ),
              ],
              const SizedBox(height: 12),
              Text('Kode rujukan: ${widget.kodeRujukan}',
                  style: TextStyle(
                      fontSize: 12, color: tema.textTheme.bodySmall?.color)),

              // ---- DETAIL: hanya muncul bila diminta ----
              const Divider(height: 24),
              InkWell(
                onTap: () => setState(() => _detailTerbuka = !_detailTerbuka),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        _detailTerbuka ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Detail (informasi teknis)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
              if (_detailTerbuka) ...<Widget>[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    // Warna literal, bukan token skema warna: token seperti
                    // surfaceContainerHighest berganti nama antar versi Flutter dan
                    // akan menggagalkan kompilasi pada versi yang lebih lama.
                    color: const Color(0xFFF4F6F8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // SelectableText, bukan Text: bila papan klip diblokir sistem,
                  // pengguna tetap dapat menyorot dan menyalin manual.
                  child: SelectableText(
                    widget.detail,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, height: 1.4),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _salin,
                    icon: Icon(_tersalin ? Icons.check : Icons.copy, size: 18),
                    label: Text(_tersalin ? 'Tersalin' : 'Salin Detail'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
