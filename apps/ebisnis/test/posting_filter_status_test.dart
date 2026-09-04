import 'package:ebisnis/widgets/filter_status_posting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = <String, dynamic>{
    'rincian': [
      {
        'id': 1,
        'sudahDiposting': false,
        'siap': true,
        'statusPosting': 'BELUM_DIPOSTING_SIAP',
      },
      {
        'id': 2,
        'sudahDiposting': false,
        'siap': false,
        'statusPosting': 'BELUM_DIPOSTING_TERTAHAN',
      },
    ],
    'rincianSudahDiposting': [
      {
        'id': 3,
        'sudahDiposting': true,
        'siap': false,
        'statusPosting': 'SUDAH_DIPOSTING',
      },
    ],
  };

  test('semua, telah, dan belum diposting tersaring tanpa kehilangan baris',
      () {
    final semua = rincianPostingSemua(data);
    expect(semua.map((e) => e['id']), [1, 2, 3]);
    expect(
        filterRincianPosting(semua, FilterStatusPosting.semua), hasLength(3));
    expect(
      filterRincianPosting(semua, FilterStatusPosting.sudah)
          .map((e) => e['id']),
      [3],
    );
    expect(
      filterRincianPosting(semua, FilterStatusPosting.belum)
          .map((e) => e['id']),
      [1, 2],
    );
  });

  testWidgets('kontrol menampilkan tiga filter beserta jumlah record',
      (tester) async {
    FilterStatusPosting? terpilih;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FilterStatusPostingBar(
          nilai: FilterStatusPosting.semua,
          jumlahSemua: 203,
          jumlahSudah: 103,
          jumlahBelum: 100,
          onChanged: (nilai) => terpilih = nilai,
        ),
      ),
    ));

    expect(find.text('Semua (203)'), findsOneWidget);
    expect(find.text('Telah Diposting (103)'), findsOneWidget);
    expect(find.text('Belum Diposting (100)'), findsOneWidget);
    await tester.tap(find.text('Belum Diposting (100)'));
    await tester.pump();
    expect(terpilih, FilterStatusPosting.belum);
  });
}
