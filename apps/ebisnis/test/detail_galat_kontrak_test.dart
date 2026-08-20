import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak sumber: setiap AppFormSheet yang menampilkan pesan kegagalan wajib
/// ikut meneruskan `errorDetail`.
///
/// Kontrak API memisahkan `message` (kalimat untuk pengguna) dari `teknis`
/// (jejak untuk admin). Form yang hanya memasang `errorText` membuang lapis
/// kedua, dan ketika server menyamarkan alasan penolakan -- seperti seluruh
/// status "91" sebelum SVN r77848 -- pengguna kehilangan satu-satunya petunjuk
/// penyebabnya. Test ini menjaga agar form baru tidak mengulangi pola itu.
void main() {
  test('setiap AppFormSheet dengan errorText juga meneruskan errorDetail', () {
    final berkas = Directory('lib/screens')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(berkas, isNotEmpty, reason: 'lib/screens tidak terbaca');

    final pelanggaran = <String>[];
    for (final f in berkas) {
      final baris = f.readAsLinesSync();
      for (var i = 0; i < baris.length; i++) {
        if (!baris[i].contains('AppFormSheet(')) continue;
        // Jendela cukup untuk menjangkau daftar argumen sebelum `children:`.
        final akhir = (i + 60).clamp(0, baris.length);
        final jendela = baris.sublist(i, akhir).join('\n');
        final potongan = jendela.contains('children:')
            ? jendela.substring(0, jendela.indexOf('children:'))
            : jendela;
        if (potongan.contains('errorText:') &&
            !potongan.contains('errorDetail:')) {
          pelanggaran.add('${f.path}:${i + 1}');
        }
      }
    }

    expect(pelanggaran, isEmpty,
        reason: 'AppFormSheet berikut memasang errorText tanpa errorDetail, '
            'sehingga jejak teknis kegagalan tidak dapat dilihat pengguna:\n'
            '${pelanggaran.join('\n')}');
  });
}
