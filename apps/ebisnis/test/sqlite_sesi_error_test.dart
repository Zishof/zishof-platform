import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const galat =
      "SqfliteFfiException(sqlite_error: 21, SqliteException(21): while preparing statement, bad parameter or other API misuse) SELECT * FROM sesi_kas_lokal WHERE status = 'BUKA'";
  test('SQLite sesi kas tidak diklasifikasikan sebagai login kedaluwarsa', () {
    final info = AppErrorInfo.dari(galat, aktivitas: 'menyimpan pembayaran');
    expect(info.judul, 'Penyimpanan lokal belum dapat diakses');
    expect(info.teknis, contains(galat));
    expect(info.solusi.join(' '), contains('Jangan hapus'));
    expect(info.solusi.join(' '), isNot(contains('masukkan akun')));
  });
  test('nama kolom password dan nomor 401 tidak mengubah klasifikasi SQLite',
      () {
    expect(
        AppErrorInfo.dari(
                'DatabaseException SELECT password FROM sesi WHERE id=401')
            .judul,
        'Penyimpanan lokal belum dapat diakses');
  });
  test('401 autentikasi tetap terpisah dari database', () {
    expect(AppErrorInfo.dari('HTTP 401 Unauthorized').judul,
        'Sesi masuk telah berakhir');
  });
  test('error misuse tidak boleh masuk jalur penggantian file korup', () {
    for (final e in [
      galat,
      'SqliteException(21): misuse',
      'SQLITE_MISUSE',
      'sqlite_error: 21,'
    ]) {
      expect(CoreDb.kesalahanPemakaianSqlite(e), isTrue);
    }
    expect(
        CoreDb.kesalahanPemakaianSqlite(
            'SqliteException(11): database disk image is malformed'),
        isFalse);
    expect(CoreDb.kesalahanPemakaianSqlite('sqlite_error: 210,'), isFalse);
  });
}
