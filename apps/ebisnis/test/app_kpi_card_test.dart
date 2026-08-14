import 'package:ebisnis/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('seluruh area kartu KPI dapat diklik', (tester) async {
    var jumlahKlik = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 260,
          child: AppKpiCard(
            icon: Icons.payments_outlined,
            warna: Colors.green,
            nilai: 'Rp 32.000',
            label: 'Tunai',
            tooltip: 'Saring pembayaran Tunai',
            onTap: () => jumlahKlik++,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Rp 32.000'));
    await tester.pump();

    expect(jumlahKlik, 1);
  });
}
