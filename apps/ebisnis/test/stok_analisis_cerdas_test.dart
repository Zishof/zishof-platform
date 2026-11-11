import 'package:ebisnis/screens/pergerakan_stok_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Analisis cerdas pergerakan stok', () {
    test('data mutasi kosong tidak disimpulkan sebagai stok normal', () {
      final hasil = StokAnalisisCerdasLokal.susunAnalisisProdukDariData(
        namaProduk: 'Produk Uji',
        kodeProduk: 'UJI-01',
        kategori: 'Uji',
        tglMulai: DateTime(2026, 11, 1),
        tglSampai: DateTime(2026, 11, 11),
        ringkasan: const {},
        mutasi: const [],
      );

      expect(hasil['dataMemadai'], isFalse);
      expect(hasil['judulDiagnosis'], contains('Belum Cukup'));
      expect(hasil['penjelasanUtama'], contains('belum dapat dipastikan'));
      expect(hasil['penjelasanUtama'], isNot(contains('Seluruh keluar-masuk')));
    });

    test('ringkasan periode lengkap dapat dianalisis tanpa kronologi tambahan',
        () {
      final hasil = StokAnalisisCerdasLokal.susunAnalisisProdukDariData(
        namaProduk: 'Produk Uji',
        kodeProduk: 'UJI-01',
        kategori: 'Uji',
        tglMulai: DateTime(2026, 11, 1),
        tglSampai: DateTime(2026, 11, 11),
        ringkasan: const {
          'awal': 10,
          'masuk': 4,
          'retur': 0,
          'penjualan': 3,
          'keluar': 0,
          'opnameMasuk': 0,
          'opnameKeluar': 0,
          'sisa': 11,
        },
        mutasi: const [],
      );

      expect(hasil['dataMemadai'], isTrue);
      expect(hasil['penjelasanUtama'], contains('Sisa Akhir: 11'));
    });

    testWidgets(
        'hasil ledger yang sudah dimuat langsung tampil tanpa meminta layanan analisis lagi',
        (tester) async {
      const hasil = {
        'dataMemadai': true,
        'judulDiagnosis': 'Ringkasan produk uji',
        'penjelasanUtama': 'Ringkasan periode yang sudah tersedia.',
        'kronologiPoin': <String>[],
        'langkahSolusi': <String>['Periksa jumlah fisik barang.'],
        'teksAnalisisWa': 'Ringkasan siap disalin.',
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DialogAnalisisCerdasStok(
            idProduk: 1,
            namaProduk: 'Produk Uji',
            kodeProduk: 'UJI-01',
            tglMulai: DateTime(2026, 11, 1),
            tglSampai: DateTime(2026, 11, 11),
            hasilAnalisisAwal: hasil,
            gunakanHasilAwalSaja: true,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Ringkasan produk uji'), findsOneWidget);
      expect(
          find.text('Ringkasan periode yang sudah tersedia.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
