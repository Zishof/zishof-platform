import 'dart:io';

import 'package:ebisnis/widgets/proses_simpan_master.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kontrak hasil simpan form', () {
    test('status success dinormalisasi agar form lama ikut menutup', () {
      final hasil = normalisasiHasilSimpanForm({
        'status': 'success',
        'message': 'Tersimpan.',
        'id': 17,
      });

      expect(hasil['status'], '00');
      expect(hasil['statusAsli'], 'success');
      expect(hasil['message'], 'Tersimpan.');
      expect(hasil['id'], 17);
    });

    test('hasil offline tetap dianggap sukses dan membawa penanda antrean', () {
      final hasil = normalisasiHasilSimpanForm(null, offline: true);

      expect(hasil['status'], '00');
      expect(hasil['offline'], isTrue);
    });

    test('status 00 tidak membuat statusAsli yang tidak perlu', () {
      final hasil = normalisasiHasilSimpanForm({'status': '00'});

      expect(hasil['status'], '00');
      expect(hasil.containsKey('statusAsli'), isFalse);
    });
  });

  test('editor Jurnal Umum menutup dan layar induk memuat ulang setelah simpan',
      () {
    final source =
        File('lib/screens/jurnal_umum_screen.dart').readAsStringSync();

    expect(
        source, contains('ApiClient.statusResponsSukses(hasil[\'status\'])'));
    expect(source, contains('Navigator.of(context).pop(true);'));
    expect(source, contains('if (tersimpan == true) await _muat();'));
  });

  test('semua AppFormSheet memiliki jalur tutup sukses', () {
    const berkasForm = <String>[
      'lib/screens/cara_bayar_screen.dart',
      'lib/screens/jenis_produk_screen.dart',
      'lib/screens/produk_screen.dart',
      'lib/screens/supplier_screen.dart',
      'lib/screens/anggota/tab_data_member.dart',
      'lib/screens/anggota/tab_jenis_member.dart',
      'lib/screens/anggota/tab_mutasi_hutang.dart',
      'lib/screens/anggota/tab_tipe_member.dart',
      'lib/screens/anggota/tab_topup.dart',
      'lib/screens/diskon/tab_aturan_diskon.dart',
      'lib/screens/diskon/tab_pencairan_diskon.dart',
      'lib/screens/inventory_sales/harga_screen.dart',
      'lib/screens/inventory_sales/hutang_supplier_screen.dart',
      'lib/screens/inventory_sales/master_customer_screen.dart',
      'lib/screens/inventory_sales/master_sales_screen.dart',
      'lib/screens/inventory_sales/master_supplier_screen.dart',
    ];

    for (final berkas in berkasForm) {
      final source = File(berkas).readAsStringSync();
      expect(source, contains('AppFormSheet('), reason: berkas);
      expect(
        RegExp(r'Navigator(?:\.of\(context\))?\.pop\(context, true\)|'
                r'Navigator\.of\(context\)\.pop\(true\)|'
                r'Navigator\.pop\(context, true\)')
            .hasMatch(source),
        isTrue,
        reason: '$berkas tidak memiliki jalur penutupan setelah simpan sukses',
      );
    }
  });
}
