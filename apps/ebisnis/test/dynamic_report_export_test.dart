import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/services/dynamic_report.dart';

/// Regresi untuk mesin ekspor laporan dinamis — fungsi yang menyusun ISI setiap
/// unduhan PDF/Excel/Word (termasuk "Rincian Produk" yang diminta An Nahl).
/// Sebelumnya tanpa test; bug di sini merusak seluruh laporan yang bisa diunduh.
DynamicReportData _data() => DynamicReportData(
      title: 'Rincian Produk Terjual',
      subtitle: 'uji',
      columns: const [
        DynamicReportColumn('nota', 'Nota'),
        DynamicReportColumn('produk', 'Produk'),
        DynamicReportColumn('qty', 'Qty', numeric: true),
        DynamicReportColumn('total', 'Total', numeric: true),
      ],
      rows: [
        {'nota': 'A-1', 'produk': 'Kopi', 'qty': 2, 'total': 6000},
        {'nota': 'A-2', 'produk': 'Roti', 'qty': 3, 'total': 9000},
        {'nota': 'A-3', 'produk': 'Kopi', 'qty': 1, 'total': 3000},
      ],
    );

void main() {
  group('formatValue', () {
    final data = _data();
    final model = DynamicReportModel.fromData(data);
    const kolomAngka = DynamicReportColumn('x', 'X', numeric: true);
    const kolomTeks = DynamicReportColumn('y', 'Y');

    test('null selalu jadi tanda strip', () {
      expect(DynamicReportDesigner.formatValue(null, kolomAngka, model), '-');
      expect(DynamicReportDesigner.formatValue(null, kolomTeks, model), '-');
    });

    test('kolom teks diteruskan apa adanya', () {
      expect(DynamicReportDesigner.formatValue('Kopi', kolomTeks, model), 'Kopi');
    });

    test('kolom angka tapi nilai bukan num diteruskan apa adanya (tidak crash)', () {
      expect(DynamicReportDesigner.formatValue('n/a', kolomAngka, model), 'n/a');
    });

    test('angka positif diformat dengan pemisah ribuan id_ID', () {
      expect(DynamicReportDesigner.formatValue(1000, kolomAngka, model), '1.000');
      expect(
          DynamicReportDesigner.formatValue(1234567, kolomAngka, model), '1.234.567');
    });

    test('angka minus: default pakai tanda minus', () {
      expect(DynamicReportDesigner.formatValue(-500, kolomAngka, model), '-500');
    });

    test('angka minus: mode kurung membungkus, bukan tanda minus', () {
      final m = DynamicReportModel.fromData(data)..parenthesesNegative = true;
      expect(DynamicReportDesigner.formatValue(-500, kolomAngka, m), '(500)');
    });
  });

  group('selectedColumns', () {
    test('menghormati kolom yang dipilih model, mempertahankan urutan', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)
        ..selectedColumns.remove('qty');
      final kol = DynamicReportDesigner.selectedColumns(data, model);
      expect(kol.map((c) => c.key), ['nota', 'produk', 'total']);
    });
  });

  group('filteredRows', () {
    test('tanpa filter mengembalikan semua baris', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data);
      expect(DynamicReportDesigner.filteredRows(data, model).length, 3);
    });

    test('filter mencari di seluruh nilai, case-insensitive', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)..filter = 'kopi';
      final rows = DynamicReportDesigner.filteredRows(data, model);
      expect(rows.length, 2);
      expect(rows.every((r) => r['produk'] == 'Kopi'), isTrue);
    });

    test('groupBy mengurutkan berdasarkan kolom itu', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)..groupBy = 'produk';
      final rows = DynamicReportDesigner.filteredRows(data, model);
      expect(rows.map((r) => r['produk']), ['Kopi', 'Kopi', 'Roti']);
    });

    test('filter tidak mengubah data sumber', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)..filter = 'kopi';
      DynamicReportDesigner.filteredRows(data, model);
      expect(data.rows.length, 3);
    });
  });

  group('totals', () {
    test('hanya menjumlahkan kolom angka yang dipilih', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data);
      final rows = DynamicReportDesigner.filteredRows(data, model);
      final t = DynamicReportDesigner.totals(data, model, rows);
      expect(t['qty'], 6);
      expect(t['total'], 18000);
      expect(t.containsKey('produk'), isFalse);
      expect(t.containsKey('nota'), isFalse);
    });

    test('total mengikuti hasil penyaringan, bukan seluruh sumber', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)..filter = 'kopi';
      final rows = DynamicReportDesigner.filteredRows(data, model);
      final t = DynamicReportDesigner.totals(data, model, rows);
      expect(t['qty'], 3); // 2 + 1
      expect(t['total'], 9000); // 6000 + 3000
    });

    test('kolom yang dilepas dari pilihan tidak ikut ditotal', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data)
        ..selectedColumns.remove('qty');
      final rows = DynamicReportDesigner.filteredRows(data, model);
      final t = DynamicReportDesigner.totals(data, model, rows);
      expect(t.containsKey('qty'), isFalse);
      expect(t['total'], 18000);
    });
  });

  group('chartSeries', () {
    test('memakai kolom angka pertama sebagai nilai dan kolom TEKS PERTAMA'
        ' (nota) sebagai label', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data);
      final rows = DynamicReportDesigner.filteredRows(data, model);
      final s = DynamicReportDesigner.chartSeries(data, model, rows);
      // Kolom teks pertama adalah 'nota' (urutan kolom: nota, produk, ...),
      // jadi label = nota dan nilai = qty; tiga nota berbeda -> tiga seri.
      expect(s.length, 3);
      final peta = {for (final e in s) e.key: e.value};
      expect(peta['A-1'], 2);
      expect(peta['A-2'], 3);
      expect(peta['A-3'], 1);
    });

    test('label sama benar-benar digabung (bukan baris terpisah)', () {
      // Bila kolom teks pertama punya nilai berulang, seri harus menyatu.
      final data = DynamicReportData(
        title: 't', subtitle: 's',
        columns: const [
          DynamicReportColumn('produk', 'Produk'),
          DynamicReportColumn('qty', 'Qty', numeric: true),
        ],
        rows: [
          {'produk': 'Kopi', 'qty': 2},
          {'produk': 'Roti', 'qty': 3},
          {'produk': 'Kopi', 'qty': 1},
        ],
      );
      final model = DynamicReportModel.fromData(data);
      final rows = DynamicReportDesigner.filteredRows(data, model);
      final s = DynamicReportDesigner.chartSeries(data, model, rows);
      expect(s.length, 2);
      final peta = {for (final e in s) e.key: e.value};
      expect(peta['Kopi'], 3); // 2 + 1 digabung
      expect(peta['Roti'], 3);
      // diurut menurun berdasarkan nilai
      expect(s.first.value >= s.last.value, isTrue);
    });

    test('daftar baris kosong menghasilkan seri kosong, bukan galat', () {
      final data = _data();
      final model = DynamicReportModel.fromData(data);
      expect(DynamicReportDesigner.chartSeries(data, model, const []), isEmpty);
    });
  });
}
