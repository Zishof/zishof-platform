import 'package:ebisnis/widgets/pemilih_akun.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pemilih akun: susunan POHON, dan hanya akun DAUN yang boleh dipilih.
///
/// Akun induk seperti `100.000 ASET LANCAR` atau `111.000 KAS` tidak pernah menampung
/// transaksi. Sebelumnya dialognya berupa daftar datar dan semuanya dapat dipilih, sehingga
/// jurnal bisa mendarat di akun yang salah tanpa ketahuan sampai laporannya dibaca.
void main() {
  // Potongan bagan akun sungguhan: dua tingkat induk, tiga daun.
  final daftar = <Map<String, dynamic>>[
    {'id': 1, 'kode': '100.000', 'nama': 'ASET LANCAR', 'parentId': null, 'leaf': false},
    {'id': 2, 'kode': '110.000', 'nama': 'KAS DAN GIRO BANK', 'parentId': 1, 'leaf': false},
    {'id': 3, 'kode': '111.000', 'nama': 'KAS', 'parentId': 2, 'leaf': false},
    {'id': 4, 'kode': '111.100', 'nama': 'KAS BESAR', 'parentId': 3, 'leaf': true},
    {'id': 5, 'kode': '111.200', 'nama': 'KAS KECIL', 'parentId': 3, 'leaf': true},
    {'id': 6, 'kode': '411.000', 'nama': 'PENJUALAN', 'parentId': null, 'leaf': true},
  ];

  Future<void> buka(WidgetTester tester, {int? terpilih}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PemilihAkunField(
          label: 'Akun',
          daftar: daftar,
          nilai: terpilih,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
  }

  testWidgets('semua tingkat tampil sebagai pohon, induk maupun daun', (tester) async {
    await buka(tester);
    for (final nama in [
      'ASET LANCAR',
      'KAS DAN GIRO BANK',
      'KAS',
      'KAS BESAR',
      'KAS KECIL',
      'PENJUALAN',
    ]) {
      expect(find.text(nama), findsOneWidget, reason: nama);
    }
  });

  testWidgets('hanya akun daun yang dapat ditekan', (tester) async {
    await buka(tester);
    // Induk: ListTile-nya dinonaktifkan, jadi tidak ada onTap sama sekali.
    final induk = tester.widget<ListTile>(
        find.ancestor(of: find.text('KAS'), matching: find.byType(ListTile)).first);
    expect(induk.enabled, isFalse, reason: 'akun induk tidak boleh dapat dipilih');
    expect(induk.onTap, isNull);

    final daun = tester.widget<ListTile>(
        find.ancestor(of: find.text('KAS BESAR'), matching: find.byType(ListTile)).first);
    expect(daun.enabled, isTrue, reason: 'akun daun harus dapat dipilih');
    expect(daun.onTap, isNotNull);
  });

  testWidgets('jumlah yang disebut adalah jumlah DAUN, bukan seluruh akun', (tester) async {
    await buka(tester);
    // Tiga daun dari enam akun; menyebut "6 akun" akan menyesatkan karena separuhnya
    // tidak dapat dipilih.
    expect(find.textContaining('3 akun dapat dipilih'), findsOneWidget);
  });

  testWidgets('pencarian menyaring, dan induk hasilnya ikut tampil sebagai konteks',
      (tester) async {
    await buka(tester);
    await tester.enterText(find.byType(TextField), 'kas kecil');
    await tester.pumpAndSettle();

    expect(find.text('KAS KECIL'), findsOneWidget);
    // Jalur induknya tetap terlihat supaya hasilnya tidak melayang tanpa susunan.
    expect(find.text('KAS'), findsOneWidget);
    expect(find.text('ASET LANCAR'), findsOneWidget);
    // Yang tidak berkaitan tersaring.
    expect(find.text('PENJUALAN'), findsNothing);
    expect(find.text('KAS BESAR'), findsNothing);
  });

  testWidgets('pencarian kode juga bekerja', (tester) async {
    await buka(tester);
    await tester.enterText(find.byType(TextField), '411');
    await tester.pumpAndSettle();
    expect(find.text('PENJUALAN'), findsOneWidget);
    expect(find.text('KAS BESAR'), findsNothing);
  });

  testWidgets('menekan Enter mengambil DAUN teratas, bukan induk teratas', (tester) async {
    int? dipilih;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PemilihAkunField(
          label: 'Akun',
          daftar: daftar,
          nilai: null,
          onChanged: (v) => dipilih = v,
        ),
      ),
    ));
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kas');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    // "KAS", "KAS DAN GIRO BANK" ada di atas, tetapi keduanya induk.
    expect(dipilih, 4, reason: 'harus jatuh ke KAS BESAR, daun pertama');
  });
}
