import 'package:ebisnis/services/master_offline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page dan page_size diterjemahkan ke LIMIT/OFFSET SQLite', () {
    expect(
      MasterOffline.paginasiLokalUntukTest(
          <String, dynamic>{'page': 2, 'page_size': 15}),
      <String, int>{'limit': 15, 'offset': 15},
    );
  });

  test('limit dan offset eksplisit didukung', () {
    expect(
      MasterOffline.paginasiLokalUntukTest(
          <String, dynamic>{'limit': '20', 'offset': '40'}),
      <String, int>{'limit': 20, 'offset': 40},
    );
  });

  test('request tanpa paginasi tetap menerima dataset lengkap', () {
    expect(
      MasterOffline.paginasiLokalUntukTest(
          <String, dynamic>{'keyword': 'kopi'}),
      isNull,
    );
  });
}
