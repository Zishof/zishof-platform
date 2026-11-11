import 'package:ebisnis/widgets/app_components.dart';
import 'package:ebisnis/widgets/rincian_intip_dialog.dart';
import 'package:ebisnis/services/dynamic_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paging bawaan [AppDataTable]. Sebelum ini 44 dari 73 tabel merender seluruh
/// barisnya sekaligus; pada tab tanpa area gulir sendiri, barisnya bahkan tidak
/// dapat dicapai sama sekali.
///
/// Yang dikunci di sini terutama BATAS-BATASNYA: tabel yang mengurus pagingnya
/// sendiri tidak boleh dipotong dua kali, dan halaman yang sedang dibuka tidak
/// boleh menjadi kosong ketika daftarnya menyusut.
void main() {
  List<AppTableRowData> baris(int n) => List.generate(
        n,
        (i) => AppTableRowData(cells: [AppTableCell.text('Baris ${i + 1}')]),
      );

  List<DataRow> barisMaterial(int n) => List.generate(
        n,
        (i) => DataRow(cells: [DataCell(Text('Rincian ${i + 1}'))]),
      );

  const kolom = [AppTableColumn('Nama')];

  Future<void> pasang(WidgetTester t, Widget w) async {
    // Layar uji bawaan 800x600 memotong bilah halaman ke luar viewport,
    // sehingga ketukan pada tombol halaman berikutnya meleset tanpa gagal --
    // ujinya lalu tampak salah padahal widgetnya benar.
    t.view.physicalSize = const Size(1400, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 1000, child: w)),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('lebih dari 15 baris dipotong per halaman', (t) async {
    await pasang(t, AppDataTable(columns: kolom, rows: baris(20)));
    expect(find.text('Baris 1'), findsOneWidget);
    expect(find.text('Baris 15'), findsOneWidget);
    expect(find.text('Baris 16'), findsNothing);
    expect(find.text('20 data'), findsOneWidget);
    expect(find.text('Halaman 1 / 2'), findsOneWidget);
  });

  testWidgets('tabel Material juga membatasi render menjadi 15 baris',
      (t) async {
    await pasang(
      t,
      AppPagedDataTable(
        columns: const [DataColumn(label: Text('Nama'))],
        rows: barisMaterial(35),
      ),
    );
    expect(find.text('Rincian 1'), findsOneWidget);
    expect(find.text('Rincian 15'), findsOneWidget);
    expect(find.text('Rincian 16'), findsNothing);
    expect(find.text('35 data'), findsOneWidget);
    expect(find.text('Halaman 1 / 3'), findsOneWidget);
  });

  testWidgets('halaman tabel Material berganti tepat 15 baris', (t) async {
    await pasang(
      t,
      AppPagedDataTable(
        columns: const [DataColumn(label: Text('Nama'))],
        rows: barisMaterial(35),
      ),
    );
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pumpAndSettle();
    expect(find.text('Rincian 16'), findsOneWidget);
    expect(find.text('Rincian 30'), findsOneWidget);
    expect(find.text('Rincian 15'), findsNothing);
    expect(find.text('Halaman 2 / 3'), findsOneWidget);
  });

  testWidgets('popup rincian kartu juga menampilkan 15 baris per halaman',
      (t) async {
    t.view.physicalSize = const Size(1400, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => tampilkanRincianKlikDialog(
              context,
              judul: 'Rincian kartu',
              kolom: const ['Nama'],
              baris: List.generate(35, (i) => ['Rincian ${i + 1}']),
            ),
            child: const Text('Buka rincian'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('Buka rincian'));
    await t.pumpAndSettle();
    expect(find.text('Rincian 1'), findsOneWidget);
    expect(find.text('Rincian 15'), findsOneWidget);
    expect(find.text('Rincian 16'), findsNothing);
    expect(find.text('Halaman 1 / 3'), findsOneWidget);

    await t.tap(find.byIcon(Icons.chevron_right).last);
    await t.pumpAndSettle();
    expect(find.text('Rincian 16'), findsOneWidget);
    expect(find.text('Rincian 30'), findsOneWidget);
    expect(find.text('Rincian 15'), findsNothing);
    expect(find.text('Halaman 2 / 3'), findsOneWidget);
  });

  testWidgets('pratinjau laporan juga menampilkan 15 baris per halaman',
      (t) async {
    t.view.physicalSize = const Size(1400, 2200);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final data = DynamicReportData(
      title: 'Laporan Uji',
      subtitle: 'Uji paging pratinjau',
      columns: const [DynamicReportColumn('nama', 'Nama')],
      rows: List.generate(35, (i) => {'nama': 'Baris Laporan ${i + 1}'}),
    );
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => DynamicReportDesigner.show(context, data: data),
            child: const Text('Buka pratinjau laporan'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('Buka pratinjau laporan'));
    await t.pumpAndSettle();
    expect(find.text('Baris Laporan 1'), findsOneWidget);
    expect(find.text('Baris Laporan 15'), findsOneWidget);
    expect(find.text('Baris Laporan 16'), findsNothing);
    expect(find.text('Halaman 1 / 3'), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_right).last);
    await t.pumpAndSettle();
    expect(find.text('Baris Laporan 16'), findsOneWidget);
    expect(find.text('Baris Laporan 30'), findsOneWidget);
    expect(find.text('Baris Laporan 15'), findsNothing);
  });

  testWidgets('area tabel terbatas selalu menyediakan scrollbar desktop',
      (t) async {
    await pasang(
      t,
      SizedBox(
        height: 360,
        child: AppDataTable(columns: kolom, rows: baris(20)),
      ),
    );

    final scrollbar = t.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.trackVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
  });

  testWidgets('halaman berikutnya menampilkan sisanya', (t) async {
    await pasang(t, AppDataTable(columns: kolom, rows: baris(20)));
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pumpAndSettle();
    expect(find.text('Baris 16'), findsOneWidget);
    expect(find.text('Baris 20'), findsOneWidget);
    expect(find.text('Baris 1'), findsNothing);
    expect(find.text('Halaman 2 / 2'), findsOneWidget);
  });

  testWidgets('15 baris atau kurang tampil utuh tanpa bilah halaman',
      (t) async {
    await pasang(t, AppDataTable(columns: kolom, rows: baris(15)));
    expect(find.text('Baris 15'), findsOneWidget);
    expect(find.textContaining('Halaman'), findsNothing);
  });

  testWidgets('pagingOtomatis:false menampilkan semuanya', (t) async {
    await pasang(t,
        AppDataTable(columns: kolom, rows: baris(20), pagingOtomatis: false));
    expect(find.text('Baris 20'), findsOneWidget);
    expect(find.textContaining('Halaman'), findsNothing);
  });

  testWidgets('tabel dgn paging sendiri TIDAK dipotong dua kali', (t) async {
    // Barisnya sudah sepotong halaman dari server. Memotongnya lagi di sini
    // akan menyembunyikan sebagian data yang justru baru saja diambil.
    await pasang(
      t,
      AppDataTable(
        columns: kolom,
        rows: baris(20),
        pagination: const AppTablePagination(
            halaman: 3, totalHalaman: 9, totalData: 175, labelData: 'nota'),
      ),
    );
    expect(find.text('Baris 20'), findsOneWidget);
    expect(find.text('175 nota'), findsOneWidget);
    expect(find.text('Halaman 3 / 9'), findsOneWidget);
  });

  testWidgets('daftar menyusut saat di halaman akhir tidak jadi kosong',
      (t) async {
    await pasang(t, AppDataTable(columns: kolom, rows: baris(20)));
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pumpAndSettle();
    expect(find.text('Halaman 2 / 2'), findsOneWidget);

    // Pengguna menyaring, sisa 5 baris -- halaman 2 tidak ada lagi.
    await pasang(t, AppDataTable(columns: kolom, rows: baris(5)));
    expect(find.text('Baris 1'), findsOneWidget,
        reason: 'tabel tidak boleh tampak kosong padahal datanya ada');
  });
}
