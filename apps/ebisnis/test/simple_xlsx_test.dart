import 'dart:convert';

import 'package:archive/archive.dart';
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

  test('kolom melampaui Z (AA, AB) dipetakan & terbaca di posisi yang benar', () {
    // Laporan lebar: 28 kolom -> kolom ke-27 dan ke-28 memakai nama AA/AB.
    // Bila penulis kolom dan pembaca tidak sepakat, sel akan tergeser.
    final headers = [for (var i = 0; i < 28; i++) 'H$i'];
    final baris = [for (var i = 0; i < 28; i++) 'v$i'];
    final rows = readSimpleXlsx(buildSimpleXlsx(
        sheetName: 'Lebar', headers: headers, rows: [baris]));
    expect(rows[0].length, 28);
    expect(rows[0][26], 'H26'); // kolom AA
    expect(rows[0][27], 'H27'); // kolom AB
    expect(rows[1][26], 'v26');
    expect(rows[1][27], 'v27');
  });

  test('karakter khusus XML round-trip utuh (kutip, ampersand, kurung siku)', () {
    final rows = readSimpleXlsx(buildSimpleXlsx(
      sheetName: 'X',
      headers: const ['Nama'],
      rows: const [
        ['Pipa 6" & 3\' <best> \'quote\''],
      ],
    ));
    expect(rows[1][0], 'Pipa 6" & 3\' <best> \'quote\'');
  });

  test('sel null di tengah tidak menggeser kolom lain', () {
    final rows = readSimpleXlsx(buildSimpleXlsx(
      sheetName: 'X',
      headers: const ['A', 'B', 'C'],
      rows: const [
        ['x', null, 'z'],
      ],
    ));
    expect(rows[1][0], 'x');
    expect(rows[1][1], ''); // sel kosong dipertahankan posisinya
    expect(rows[1][2], 'z');
  });

  test('baris kosong seluruhnya dilewati pembaca', () {
    final rows = readSimpleXlsx(buildSimpleXlsx(
      sheetName: 'X',
      headers: const ['A', 'B'],
      rows: const [
        [null, null],
        ['ada', 'isi'],
      ],
    ));
    // header + 1 baris berisi; baris semua-null tidak muncul.
    expect(rows.length, 2);
    expect(rows[1], ['ada', 'isi']);
  });

  test('nama sheet dengan karakter ilegal/terlalu panjang tidak merusak file', () {
    // Excel menolak nama sheet mengandung []/\\*?: atau > 31 karakter.
    final bytes = buildSimpleXlsx(
      sheetName: r'Lap/2026:[Q1]*?\panjang-sekali-melebihi-tiga-puluh-satu-karakter',
      headers: const ['A'],
      rows: const [
        ['satu'],
      ],
    );
    // File tetap valid & terbaca (sanitasi tidak merusak isi).
    final rows = readSimpleXlsx(bytes);
    expect(rows[0], ['A']);
    expect(rows[1], ['satu']);
  });

  test('angka ditulis sebagai angka (bisa dijumlahkan Excel), bukan teks', () {
    final bytes = buildSimpleXlsx(
      sheetName: 'X',
      headers: const ['Total'],
      rows: const [
        [15000],
      ],
    );
    // Sel angka memakai <v> tanpa t="inlineStr"; teks memakai inlineStr.
    final xml = utf8.decode(
        ZipDecoder().decodeBytes(bytes).firstWhere(
              (e) => e.name == 'xl/worksheets/sheet1.xml',
            ).content as List<int>);
    expect(xml.contains('<v>15000</v>'), isTrue);
    // header teks memakai inlineStr
    expect(xml.contains('t="inlineStr"'), isTrue);
  });
}
