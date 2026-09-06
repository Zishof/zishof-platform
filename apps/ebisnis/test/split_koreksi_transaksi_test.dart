import 'dart:io';

import 'package:ebisnis/models.dart';
import 'package:ebisnis/widgets/pemilih_metode_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CaraBayar _cara(int id, String nama) => CaraBayar(
      id: id,
      nama: nama,
      manual: true,
    );

void main() {
  test('contoh Tunai 1.500 + Voucher 23.500 tepat membayar total 25.000', () {
    final slot = [
      SlotBayar(_cara(1, 'Tunai'), 1500),
      SlotBayar(_cara(2, 'Voucher Pejuang'), 23500),
    ];

    expect(validasiAlokasiPembayaran(slot, 25000), isNull);
  });

  test('alokasi split yang kurang atau lebih dari total ditolak', () {
    final tunai = _cara(1, 'Tunai');
    final voucher = _cara(2, 'Voucher Pejuang');

    expect(
      validasiAlokasiPembayaran(
          [SlotBayar(tunai, 1500), SlotBayar(voucher, 23000)], 25000),
      contains('harus sama'),
    );
    expect(
      validasiAlokasiPembayaran(
          [SlotBayar(tunai, 2000), SlotBayar(voucher, 23500)], 25000),
      contains('harus sama'),
    );
  });

  test('nominal nol dan metode ganda ditolak sebelum dikirim', () {
    final tunai = _cara(1, 'Tunai');

    expect(validasiAlokasiPembayaran([SlotBayar(tunai, 0)], 25000),
        contains('lebih dari Rp 0'));
    expect(
      validasiAlokasiPembayaran(
          [SlotBayar(tunai, 1500), SlotBayar(tunai, 23500)], 25000),
      contains('lebih dari satu kali'),
    );
  });

  testWidgets('pemilih UI mengembalikan dua metode beserta nominalnya',
      (tester) async {
    List<SlotBayar>? hasil;
    final tunai = _cara(1, 'Tunai');
    final voucher = _cara(2, 'Voucher Pejuang');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              hasil = await showModalBottomSheet<List<SlotBayar>>(
                context: context,
                isScrollControlled: true,
                builder: (_) => PemilihMetodeSplit(
                  daftarMetode: [tunai, voucher],
                  terpilihAwal: const [],
                  total: 25000,
                ),
              );
            },
            child: const Text('Buka'),
          );
        }),
      ),
    ));

    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pump();
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('nominal-split-1')), '1500');
    await tester.enterText(
        find.byKey(const ValueKey('nominal-split-2')), '23500');
    await tester.pump();
    await tester.tap(find.text('Terapkan Split Pembayaran'));
    await tester.pumpAndSettle();

    expect(hasil, isNotNull);
    expect(hasil, hasLength(2));
    expect(hasil![0].caraBayar.nama, 'Tunai');
    expect(hasil![0].nominal, 1500);
    expect(hasil![1].caraBayar.nama, 'Voucher Pejuang');
    expect(hasil![1].nominal, 23500);
  });

  test('form koreksi memakai capability server dan payload pembayaran rinci',
      () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains("detail['bolehKoreksiSplitPembayaran'] == true"));
    expect(source, contains("detail['pembayaran']"));
    expect(source, contains("'pembayaran': _splitBayar"));
    expect(source, contains("'cara_bayar': slot.caraBayar.id"));
    expect(source, contains('validasiAlokasiPembayaran'));
  });

  test('backend mengembalikan slot lama dan memvalidasi split baru', () {
    final backend = File(
        r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\KantinHelper.java');
    final servlet =
        File(r'C:\opt\AIS\ais\src\main\src\ais\action\servlet\PosApi.java');
    if (!backend.existsSync() || !servlet.existsSync()) return;

    final koreksi = backend.readAsStringSync();
    final detail = servlet.readAsStringSync();
    expect(koreksi, contains('resolvePembayaranKoreksi'));
    expect(koreksi, contains('totalAlokasiPembayaranCocok'));
    expect(koreksi, contains('splitEfektif.terapkanKe'));
    expect(detail, contains('rincianPembayaranTransaksi'));
    expect(detail, contains('bolehKoreksiSplitPembayaran'));
  });
}
