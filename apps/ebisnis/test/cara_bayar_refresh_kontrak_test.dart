import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak konsistensi metode pembayaran antar perangkat kasir.
///
/// Daftar metode tidak boleh hanya mengandalkan snapshot saat login karena
/// admin dapat mengubah izin member/metode sementara Kasir 2/3 masih terbuka.
/// Picker harus mengambil daftar terbaru dan tetap menjaga split yang seluruh
/// metodenya masih diizinkan.
void main() {
  late String source;

  setUpAll(() {
    source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
  });

  test('picker memuat ulang metode sesuai member sebelum ditampilkan', () {
    final awal = source.indexOf('Future<void> _pilihMetode() async');
    final akhir = source.indexOf('Future<void> _aturDiskonFaktur()', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));

    final method = source.substring(awal, akhir);
    expect(method,
        contains('await _muatCaraBayarUntukMember(_memberTerpilih?.id);'));
    expect(method.indexOf('await _muatCaraBayarUntukMember'),
        lessThan(method.indexOf('showModalBottomSheet')));
  });

  test('snapshot kosong tetap dapat meminta daftar terbaru', () {
    expect(source, contains('onTap: _memuatCaraBayar ? null : _pilihMetode'));
  });

  test('refresh mempertahankan split yang seluruh metodenya masih sah', () {
    expect(source, contains('splitMasihDiizinkan'));
    expect(source, contains('metodeMenurutId.containsKey(slot.caraBayar.id)'));
    expect(source, contains('_splitBayar = splitTersegar'));
  });
}
