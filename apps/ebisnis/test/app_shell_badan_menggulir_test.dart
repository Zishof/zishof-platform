import 'dart:io';

import 'package:ebisnis/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Penjaga tata letak: badan layar yang MENGGULIR SENDIRI tidak boleh dibungkus
/// lagi oleh penggulir milik [AppShell].
///
/// `AppShell.scrollable` bernilai **true** secara bawaan, dan pada mode itu badannya
/// dimasukkan ke dalam `SingleChildScrollView`. Bila badannya sendiri berupa
/// `ListView`/`CustomScrollView`/`GridView`, penggulir itu memberinya tinggi TAK
/// TERBATAS — Flutter melempar galat tata letak dan seluruh badan layar tidak
/// tergambar sama sekali. Gejalanya tidak terlihat seperti galat: layarnya cuma
/// **kosong**, lengkap dengan judul dan tombolnya, sehingga mudah disangka data
/// yang belum ada.
///
/// Itulah yang terjadi pada layar Draft Jurnal.
void main() {
  test('layar dengan badan menggulir wajib memakai scrollable: false', () {
    final dir = Directory('lib/screens');
    final pelanggar = <String>[];

    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (!src.contains('AppShell(')) continue;
      // Hanya `body:` milik AppShell yang berarti di sini; penggulir di dalam
      // dialog atau widget lain tidak terpengaruh.
      final badanMenggulir = RegExp(r'body: (ListView|CustomScrollView|GridView)')
          .hasMatch(src);
      if (badanMenggulir && !src.contains('scrollable: false')) {
        pelanggar.add(f.path.replaceAll(r'\', '/').split('lib/').last);
      }
    }

    expect(pelanggar, isEmpty,
        reason: 'badan menggulir di dalam AppShell yang juga menggulir membuat '
            'layarnya kosong sama sekali: ${pelanggar.join(', ')}');
  });

  testWidgets('ListView di dalam AppShell yang menggulir melempar galat tata letak',
      (tester) async {
    // Bukan sekadar penalaran: dijalankan sungguhan supaya alasan layar Draft
    // Jurnal tampak kosong tercatat sebagai perilaku yang teramati.
    // Lebar desktop: itulah cabang tata letak yang dipakai tangkapan layarnya.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        menuAktif: MenuEBisnis.draftJurnal,
        judul: 'Uji',
        body: ListView(children: const [Text('isi')]),
      ),
    ));
    final galatPertama = tester.takeException();
    expect(galatPertama, isNotNull,
        reason: 'badan menggulir di dalam penggulir harus melempar galat');

    // RenderFlex/viewport dapat melaporkan lebih dari satu exception turunan
    // untuk akar masalah yang sama. Bersihkan semuanya agar test penjaga ini
    // tidak meninggalkan exception yang dianggap gagal oleh test berikutnya.
    while (tester.takeException() != null) {}
  });

  testWidgets('dengan scrollable: false, isinya tergambar normal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        menuAktif: MenuEBisnis.draftJurnal,
        judul: 'Uji',
        scrollable: false,
        body: ListView(children: const [Text('isi')]),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('isi'), findsOneWidget);
  });
}
