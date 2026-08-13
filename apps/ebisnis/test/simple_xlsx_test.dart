import 'package:ebisnis/services/simple_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('XLSX topup dapat dibuat dan dibaca kembali', () {
    final bytes = buildSimpleXlsx(
      sheetName: 'Topup',
      headers: const ['KODE_MEMBER', 'NAMA_MEMBER', 'NOMINAL', 'KETERANGAN'],
      rows: const [
        ['A-001', 'Anggota & Satu', 25000, 'Setoran <tunai>'],
        ['A-002', 'Anggota Dua', 10000.5, ''],
      ],
    );

    final rows = readSimpleXlsx(bytes);
    expect(rows[0], ['KODE_MEMBER', 'NAMA_MEMBER', 'NOMINAL', 'KETERANGAN']);
    expect(rows[1], ['A-001', 'Anggota & Satu', '25000', 'Setoran <tunai>']);
    expect(rows[2][0], 'A-002');
    expect(rows[2][2], '10000.5');
  });
}
