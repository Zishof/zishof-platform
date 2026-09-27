import 'dart:async';
import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseGangguan extends Fake implements Database {
  final sesi = Completer<List<Map<String, Object?>>>();
  int ditutup = 0;
  int hitung = 0;
  @override
  bool get isOpen => ditutup == 0;
  @override
  Future<void> close() async {
    ditutup++;
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    if (table == 'sesi_kas_lokal') return sesi.future;
    hitung++;
    if (hitung == 1) {
      throw StateError(
          'SqliteException(21): bad parameter or other API misuse (code 21)');
    }
    return [
      {'n': 2}
    ];
  }
}

void main() {
  test('error penghitung tidak menutup koneksi checkout yang masih berjalan',
      () async {
    final database = DatabaseGangguan();
    final core = CoreDb.untukPengujian(database);
    final checkout = core.sesiKasAktif();
    await expectLater(core.jumlahTransaksiPending(), throwsStateError);
    expect(database.ditutup, 0);
    expect(database.hitung, 1, reason: 'Tidak retry tersembunyi saat error');
    database.sesi.complete([
      {'kode': 'UAT-KAS', 'status': 'BUKA'}
    ]);
    expect((await checkout)?['kode'], 'UAT-KAS');
    expect(await core.jumlahTransaksiPending(), 2);
    expect(database.ditutup, 0);
  });
}
