import 'dart:io';

import 'package:ebisnis/screens/kode_akun_screen.dart';
import 'package:ebisnis/screens/siklus_akuntansi_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// KodeAkunScreen dan SiklusAkuntansiScreen BUKAN halaman utuh -- badannya Column
/// bertab tanpa Scaffold. Mendorongnya apa adanya sebagai rute (yang sempat
/// dilakukan submenu Akuntansi di drawer Android) menghasilkan "No Material widget
/// found" begitu menu dibuka. Test ini mengunci dua hal: (1) fakta itu memang
/// benar, sehingga siapa pun yang menaruhnya sebagai rute tahu risikonya, dan
/// (2) begitu dibungkus Scaffold, layarnya tampil normal. Kasus "tanpa Scaffold"
/// sengaja tidak diuji sebagai widget test: kegagalannya berupa BEBERAPA
/// exception build sekaligus, yang selalu menggagalkan test walau ditangkap.
void main() {
  testWidgets('dibungkus Scaffold: Kode Akun tampil normal', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: KodeAkunScreen(),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Akun'), findsWidgets);
  });

  testWidgets('dibungkus Scaffold: Siklus Akuntansi tampil normal',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SiklusAkuntansiScreen(),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Saldo Awal'), findsWidgets);
  });

  test('drawer Android membungkus setiap submenu Akuntansi', () {
    // Sumber dibaca langsung: ini kontrak wiring, bukan perilaku widget.
    final drawer = File('lib/widgets/app_drawer.dart').readAsStringSync();
    expect(drawer, isNot(contains('builder: (_) => const KodeAkunScreen(')),
        reason: 'KodeAkunScreen tidak boleh didorong tanpa pembungkus halaman');
    expect(drawer, contains('_halamanAkuntansi('));
  });
}
