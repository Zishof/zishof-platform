import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/main.dart';

void main() {
  testWidgets('App boots to a MaterialApp without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const EBisnisApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
