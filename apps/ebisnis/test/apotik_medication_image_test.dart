import 'dart:convert';
import 'dart:typed_data';

import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bungkus(Map<String, dynamic> item, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    themeMode: mode,
    theme: ThemeData(
      useMaterial3: true,
      extensions: const [ApotikDesignTokens.light],
    ),
    darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
      extensions: const [ApotikDesignTokens.dark],
    ),
    home: Scaffold(body: Center(child: MedicationImage(item: item))),
  );
}

void main() {
  testWidgets('tanpa URL memakai fallback stabil dan semantics jujur',
      (tester) async {
    await tester.pumpWidget(_bungkus({
      'nama': 'Amoxicillin 500 mg',
      'bentukSediaan': 'Kapsul',
    }));

    expect(find.byKey(const ValueKey('medication-image')), findsOneWidget);
    expect(find.bySemanticsLabel('Belum ada foto kemasan Amoxicillin 500 mg'),
        findsOneWidget);
    final kotak =
        tester.getSize(find.byKey(const ValueKey('medication-image')));
    expect(kotak, const Size(72, 88));
  });

  testWidgets('fotoUrls pertama diprioritaskan dibanding gambarUrl',
      (tester) async {
    await tester.pumpWidget(_bungkus({
      'nama': 'Paracetamol',
      'fotoUrls': const [
        'https://example.invalid/utama.png',
        'https://example.invalid/kedua.png'
      ],
      'gambarUrl': 'https://example.invalid/lama.png',
    }));

    final image = tester.widget<Image>(
        find.byKey(const ValueKey('medication-thumbnail-image')));
    final provider = (image.image as ResizeImage).imageProvider as NetworkImage;
    expect(provider.url, 'https://example.invalid/utama.png');
  });

  testWidgets('bytes lokal menang atas foto server tanpa request network',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    await tester.pumpWidget(_bungkus({
      'nama': 'Cetirizine',
      'localBytes': bytes,
      'fotoUrls': const ['https://example.invalid/tidak-dipakai.png'],
    }));

    expect(find.byKey(const ValueKey('medication-image-local-bytes')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('medication-image-network')), findsNothing);
  });

  testWidgets('fotoUrls malformed tetap fail-safe ke gambarUrl',
      (tester) async {
    await tester.pumpWidget(_bungkus({
      'nama': 'Omeprazole',
      'fotoUrls': 'bukan-list',
      'gambarUrl': 'https://example.invalid/fallback.png',
    }));
    final image = tester.widget<Image>(
        find.byKey(const ValueKey('medication-thumbnail-image')));
    final provider = (image.image as ResizeImage).imageProvider as NetworkImage;
    expect(provider.url, 'https://example.invalid/fallback.png');
  });

  testWidgets('fallback tetap terbaca pada tema gelap', (tester) async {
    await tester.pumpWidget(_bungkus(
      {'nama': 'Salep Demo', 'bentukSediaan': 'Salep'},
      mode: ThemeMode.dark,
    ));
    expect(find.byKey(const ValueKey('medication-image')), findsOneWidget);
    expect(find.byIcon(Icons.healing_outlined), findsOneWidget);
  });
}
