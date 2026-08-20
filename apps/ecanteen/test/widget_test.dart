import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishof/main.dart';

void main() {
  testWidgets('Aplikasi terpasang sebagai MaterialApp tanpa galat',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ECanteenApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
