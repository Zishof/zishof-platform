import 'package:ebisnis/features/apotik/core/apotik_breakpoints.dart';
import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_context_bar.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_state_views.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_status_pill.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _bungkus(Widget child, {Size ukuran = const Size(1400, 800)}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true, extensions: const [
      ApotikDesignTokens.light,
    ]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: Scaffold(body: SizedBox(width: ukuran.width, child: child)),
    ),
  );
}

void main() {
  group('ApotikBreakpoints', () {
    test('memetakan lebar ke kelas layout sesuai spesifikasi', () {
      expect(ApotikBreakpoints.dariLebar(599), ApotikLayout.compactMobile);
      expect(ApotikBreakpoints.dariLebar(600), ApotikLayout.tablet);
      expect(ApotikBreakpoints.dariLebar(899), ApotikLayout.tablet);
      expect(ApotikBreakpoints.dariLebar(900), ApotikLayout.desktopCompact);
      expect(ApotikBreakpoints.dariLebar(1279), ApotikLayout.desktopCompact);
      expect(ApotikBreakpoints.dariLebar(1280), ApotikLayout.desktopStandard);
      expect(ApotikBreakpoints.dariLebar(1599), ApotikLayout.desktopStandard);
      expect(ApotikBreakpoints.dariLebar(1600), ApotikLayout.desktopWide);
    });

    test('POS tiga area hanya mulai desktop standard (1280 ke atas)', () {
      expect(ApotikBreakpoints.dariLebar(1279).bolehTigaArea, isFalse);
      expect(ApotikBreakpoints.dariLebar(1280).bolehTigaArea, isTrue);
      expect(ApotikBreakpoints.dariLebar(1600).bolehTigaArea, isTrue);
    });

    test('kolom sekunder disembunyikan sampai desktop compact', () {
      expect(ApotikBreakpoints.dariLebar(400).sembunyikanKolomSekunder, isTrue);
      expect(
          ApotikBreakpoints.dariLebar(1000).sembunyikanKolomSekunder, isTrue);
      expect(
          ApotikBreakpoints.dariLebar(1400).sembunyikanKolomSekunder, isFalse);
    });

    test('target sentuh minimum memenuhi pedoman 44-48 dp', () {
      expect(ApotikBreakpoints.targetSentuhMinimum, greaterThanOrEqualTo(44));
    });
  });

  group('ApotikDesignTokens', () {
    test('memakai teal farmasi, bukan biru POS umum', () {
      expect(ApotikDesignTokens.light.primary, const Color(0xFF0F766E));
    });

    test('lerp menghasilkan token valid antar tema', () {
      final hasil = ApotikDesignTokens.light.lerp(ApotikDesignTokens.dark, 0.5);
      expect(hasil.primary, isNot(ApotikDesignTokens.light.primary));
    });

    testWidgets('of() jatuh ke light bila ekstensi belum dipasang',
        (tester) async {
      late ApotikDesignTokens terbaca;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(builder: (context) {
          terbaca = ApotikDesignTokens.of(context);
          return const SizedBox();
        }),
      ));
      expect(terbaca.primary, ApotikDesignTokens.light.primary);
    });
  });

  group('ApotikStatusPill - status tidak boleh bergantung warna saja', () {
    testWidgets('selalu memuat ikon DAN teks', (tester) async {
      await tester.pumpWidget(_bungkus(Row(children: [
        ApotikStatusPill.layak(),
        ApotikStatusPill.kedaluwarsa(),
        ApotikStatusPill.lasa(),
        ApotikStatusPill.terkendali(),
      ])));
      expect(find.text('Layak'), findsOneWidget);
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      expect(find.text('LASA'), findsOneWidget);
      expect(find.text('Terkendali'), findsOneWidget);
      expect(find.byType(Icon), findsAtLeastNWidgets(4));
    });

    testWidgets('near-expiry menuliskan jumlah harinya', (tester) async {
      await tester.pumpWidget(_bungkus(ApotikStatusPill.nearExpiry(56)));
      expect(find.textContaining('56 hari'), findsOneWidget);
    });

    testWidgets('penjelasan menjadi label semantik (aksesibilitas)',
        (tester) async {
      await tester.pumpWidget(_bungkus(ApotikStatusPill.kedaluwarsa()));
      expect(find.bySemanticsLabel('Kedaluwarsa. Tidak dapat dipilih'),
          findsOneWidget);
    });
  });

  group('MedicationCard', () {
    final obat = <String, dynamic>{
      'id': 1,
      'kode': 'OBT-001',
      'nama': 'Amoxicillin 500 mg',
      'kandungan': 'Amoxicillin trihydrate',
      'satuan': 'tablet',
      'stok': 42,
      'hargaJual': 2500,
      'lasa': true,
      'terkendali': false,
    };

    testWidgets('menampilkan nama, harga, stok, dan badge LASA',
        (tester) async {
      await tester.pumpWidget(_bungkus(MedicationCard(item: obat)));
      expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
      expect(find.text('Rp 2.500'), findsOneWidget);
      expect(find.textContaining('stok 42 tablet'), findsOneWidget);
      expect(find.text('LASA'), findsOneWidget);
    });

    testWidgets('LASA ditebalkan sebagai pembeda selain warna', (tester) async {
      await tester.pumpWidget(_bungkus(MedicationCard(item: obat)));
      final teks = tester.widget<Text>(find.text('Amoxicillin 500 mg'));
      expect(teks.style?.fontWeight, FontWeight.w800);
    });

    testWidgets('stok habis tidak dapat ditap (pagar sebelum keranjang)',
        (tester) async {
      var ditap = false;
      await tester.pumpWidget(_bungkus(MedicationCard(
          item: <String, dynamic>{...obat, 'stok': 0},
          onTap: () => ditap = true)));
      await tester.tap(find.byType(MedicationCard));
      await tester.pump();
      expect(ditap, isFalse);
      expect(find.text('Stok habis'), findsOneWidget);
    });

    testWidgets('item terkunci menampilkan alasannya dan menolak tap',
        (tester) async {
      var ditap = false;
      await tester.pumpWidget(_bungkus(MedicationCard(
        item: obat,
        alasanTerkunci: 'Baris racikan - belum didukung kasir',
        onTap: () => ditap = true,
      )));
      await tester.tap(find.byType(MedicationCard));
      await tester.pump();
      expect(ditap, isFalse);
      expect(find.textContaining('Baris racikan'), findsOneWidget);
    });

    testWidgets('TIDAK mengarang field yang tak dikirim server',
        (tester) async {
      await tester.pumpWidget(_bungkus(MedicationCard(item: obat)));
      expect(find.textContaining('High-alert'), findsNothing);
      expect(find.textContaining('Cold-chain'), findsNothing);
    });
  });

  group('State views', () {
    testWidgets('empty state selalu memberi petunjuk langkah berikutnya',
        (tester) async {
      await tester.pumpWidget(_bungkus(const ApotikEmptyState(
          judul: 'Belum ada resep',
          petunjuk: 'Resep baru akan muncul di sini.')));
      expect(find.text('Belum ada resep'), findsOneWidget);
      expect(find.text('Resep baru akan muncul di sini.'), findsOneWidget);
    });

    testWidgets('error state menampilkan pesan server apa adanya + coba lagi',
        (tester) async {
      var dicoba = false;
      await tester.pumpWidget(_bungkus(ApotikErrorState(
          pesan: 'Stok batch tidak mencukupi.',
          onCobaLagi: () => dicoba = true)));
      expect(find.text('Stok batch tidak mencukupi.'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      expect(dicoba, isTrue);
    });

    testWidgets('permission denied tidak menawarkan jalan pintas',
        (tester) async {
      await tester.pumpWidget(
          _bungkus(const ApotikPermissionDeniedState(namaMenu: 'Laporan')));
      expect(
          find.textContaining('Tidak memiliki akses Laporan'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ApotikContextBar', () {
    testWidgets('menampilkan konteks kerja dan menyembunyikan ruas kosong',
        (tester) async {
      await tester.pumpWidget(_bungkus(const ApotikContextBar(ruas: [
        ApotikKonteksRuas(
            ikon: Icons.store, label: 'Outlet', nilai: 'Apotek Pusat'),
        ApotikKonteksRuas(ikon: Icons.schedule, label: 'Shift', nilai: ''),
      ])));
      expect(find.text('Apotek Pusat'), findsOneWidget);
      expect(find.text('Shift '), findsNothing);
    });
  });
}
