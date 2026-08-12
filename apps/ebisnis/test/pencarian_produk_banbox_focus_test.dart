import 'package:ebisnis/widgets/pencarian_produk_banbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('focus node eksternal dan autofocus diterapkan ke input barcode',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PencarianProdukBanbox(
          controller: controller,
          focusNode: focusNode,
          autofocus: true,
          label: 'Barcode',
          icon: Icons.qr_code,
          onPilih: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(focusNode.hasFocus, isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode,
      same(focusNode),
    );
  });
}
