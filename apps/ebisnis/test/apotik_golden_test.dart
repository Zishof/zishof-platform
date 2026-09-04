@Tags(['golden'])
library;

import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/dashboard/apotik_priority_card.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_state_views.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_status_pill.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// <h3>Golden komponen apotik (Fase 8).</h3>
///
/// **Apa yang sebenarnya dijaga.** `flutter test` tidak memuat font aplikasi,
/// sehingga teks pada acuan tampil sebagai blok. Golden ini karena itu menjaga
/// **tata letak, jarak, dan warna** — bukan bentuk huruf. Justru itu yang
/// diinginkan: perubahan token warna atau susunan komponen langsung terlihat,
/// tanpa acuan menjadi rapuh terhadap versi font.
///
/// **Batas jujur.** Berkas acuan di `test/goldens/` dibuat di Windows. Render
/// Flutter tidak dijamin identik lintas sistem operasi (antialias tepi dan
/// bayangan berbeda), jadi di mesin/OS lain berkas ini harus dibuat ulang:
///
/// ```
/// flutter test --update-goldens --tags golden
/// ```
///
/// Karena itu semuanya diberi tag `golden` sehingga dapat dikecualikan:
/// `flutter test --exclude-tags golden`. Nilainya tetap nyata: perubahan tak
/// disengaja pada token warna, jarak, atau susunan komponen langsung terlihat
/// sebagai selisih piksel di mesin pengembang.
Widget _bingkai(Widget anak,
    {double lebar = 340,
    ApotikDesignTokens tokens = ApotikDesignTokens.light}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, extensions: [tokens]),
    home: Scaffold(
      backgroundColor: tokens.surfaceMuted,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(width: lebar, child: anak),
        ),
      ),
    ),
  );
}

Map<String, dynamic> _obat({
  bool lasa = false,
  bool highAlert = false,
  bool coldChain = false,
  double stok = 24,
  String golongan = 'BEBAS',
}) {
  return {
    'id': 1,
    'kode': 'OBT-001',
    'nama': 'Amoxicillin 500 mg',
    'kandungan': 'Amoxicillin trihydrate',
    'satuan': 'kapsul',
    'stok': stok,
    'hargaJual': 3500,
    'lasa': lasa,
    'highAlert': highAlert,
    'coldChain': coldChain,
    'golonganObat': golongan,
    'bentukSediaan': 'kapsul',
    'kekuatan': '500 mg',
  };
}

Future<void> _cocok(WidgetTester tester, Widget w, String nama,
    {Size ukuran = const Size(400, 320)}) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(w);
  await tester.pumpAndSettle();
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('goldens/$nama.png'));
}

void main() {
  group('Kartu obat', () {
    testWidgets('biasa', (tester) async {
      await _cocok(
          tester, _bingkai(MedicationCard(item: _obat())), 'kartu_obat_biasa');
    });

    testWidgets('LASA + high-alert + cold-chain', (tester) async {
      await _cocok(
          tester,
          _bingkai(MedicationCard(
              item: _obat(
                  lasa: true,
                  highAlert: true,
                  coldChain: true,
                  golongan: 'KERAS'))),
          'kartu_obat_penanda_lengkap');
    });

    testWidgets('stok habis', (tester) async {
      await _cocok(tester, _bingkai(MedicationCard(item: _obat(stok: 0))),
          'kartu_obat_stok_habis');
    });

    testWidgets('tema gelap', (tester) async {
      await _cocok(
          tester,
          _bingkai(MedicationCard(item: _obat(lasa: true, golongan: 'KERAS')),
              tokens: ApotikDesignTokens.dark),
          'kartu_obat_gelap');
    });
  });

  group('Penanda status', () {
    testWidgets('semua nada', (tester) async {
      await _cocok(
        tester,
        _bingkai(const Wrap(spacing: 6, runSpacing: 6, children: [
          ApotikStatusPill(teks: 'Layak', nada: ApotikStatusNada.sukses),
          ApotikStatusPill(
              teks: 'Segera kedaluwarsa', nada: ApotikStatusNada.peringatan),
          ApotikStatusPill(teks: 'Kedaluwarsa', nada: ApotikStatusNada.bahaya),
          ApotikStatusPill(teks: 'Menunggu', nada: ApotikStatusNada.info),
          ApotikStatusPill(teks: 'Racikan', nada: ApotikStatusNada.klinis),
          ApotikStatusPill(teks: 'Netral', nada: ApotikStatusNada.netral),
        ])),
        'pill_semua_nada',
        ukuran: const Size(400, 220),
      );
    });
  });

  group('Kartu prioritas dashboard', () {
    testWidgets('kritis', (tester) async {
      await _cocok(
        tester,
        _bingkai(const ApotikPriorityCard(
          judul: 'Batch kedaluwarsa',
          angka: 7,
          satuan: 'lot',
          makna: 'Tidak boleh dijual — segera karantina.',
          tujuanLabel: 'Buka monitor kedaluwarsa',
          ikon: Icons.event_busy,
          nada: ApotikPriorityNada.mendesak,
        )),
        'kartu_prioritas_kritis',
      );
    });
  });

  group('Keadaan layar', () {
    testWidgets('kosong', (tester) async {
      await _cocok(
        tester,
        _bingkai(const ApotikEmptyState(
          ikon: Icons.medication_outlined,
          judul: 'Obat tidak ditemukan',
          petunjuk: 'Coba kata kunci lain.',
        )),
        'keadaan_kosong',
      );
    });

    testWidgets('galat', (tester) async {
      await _cocok(
        tester,
        _bingkai(const ApotikErrorState(pesan: 'Server tidak terjangkau.')),
        'keadaan_galat',
      );
    });
  });
}
