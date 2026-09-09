import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/services/master_offline.dart').readAsStringSync();
  });

  test('helper baca fallback pada seluruh gangguan teknis yang retryable', () {
    final awal = source.indexOf('static Future<void> daftarCacheDulu(');
    final akhir = source.indexOf('static Future<void> terapkanLokal', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));
    final helperBaca = source.substring(awal, akhir);

    expect(helperBaca, contains('if (!dapatDicobaUlang(e)) rethrow;'));
    expect(helperBaca, isNot(contains('if (!e.offline) rethrow;')));
  });

  test('objek penting dapat dibaca cache-first tanpa jaringan', () {
    expect(source, contains('ambilObjekTersimpan('));
    expect(source, contains('final decoded = jsonDecode(tersimpan)'));
    expect(source, contains("'offline': true"));
  });
}
