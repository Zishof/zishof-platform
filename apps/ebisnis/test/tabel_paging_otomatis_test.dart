import 'package:ebisnis/widgets/app_components.dart';
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
    await pasang(
        t,
        AppDataTable(
            columns: kolom, rows: baris(20), pagingOtomatis: false));
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
