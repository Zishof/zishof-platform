import 'package:ebisnis/screens/struk_screen.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const struk = StrukScreen(
    kode: 'TEST-VOUCHER', waktu: '21-09-2026 08:00:00',
    item: [{'nama': 'Produk Uji', 'qty': 1, 'harga': 15500}],
    total: 15500, metode: 'Voucher Pejuang',
    uangDiterima: 15500, kembalian: 0, modeCetakUlang: true,
  );

  test('saldo server nol sah; saldo hilang/rusak tidak menjadi nol', () {
    expect(StrukScreen.saldoDariSumber({'saldo': 0}), 0);
    expect(StrukScreen.saldoDariSumber({'sisaSaldo': '84500'}), 84500);
    expect(StrukScreen.saldoDariSumber({}), isNull);
    expect(StrukScreen.saldoDariSumber({'saldo': 'tidak tersedia'}), isNull);
    expect(StrukScreen.saldoDariSumber({'saldo': double.nan}), isNull);
    expect(StrukScreen.saldoDariSumber({'saldo': double.infinity}), isNull);
  });

  test('koreksi total mempertahankan saldo dan saldo server mengganti snapshot', () {
    final bersaldo = struk.salin(saldo: 84500);
    expect(bersaldo.salin(total: 15000).saldo, 84500);
    expect(bersaldo.salin(saldo: 0).saldo, 0);
    expect(struk.salin(total: 15000).saldo, isNull);
  });

  testWidgets('preview voucher menampilkan saldo server tanpa label tunai', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Sesi.instance.tokoAlamat = 'Alamat Uji';
    Sesi.instance.tokoTelp = '000';
    await tester.pumpWidget(MaterialApp(home: struk.salin(saldo: 84500)));
    await tester.pumpAndSettle();
    expect(find.text('Saldo :'), findsOneWidget);
    expect(find.text('84.500,-'), findsOneWidget);
    expect(find.text('Voucher Pejuang'), findsOneWidget);
    expect(find.text('Dibayar :'), findsOneWidget);
    expect(find.text('Tunai :'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
