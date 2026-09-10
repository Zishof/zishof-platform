import 'dart:convert';
import 'dart:io';

import 'package:ebisnis/screens/laporan_detail_screen.dart';
import 'package:ebisnis/services/simple_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empat laporan Omzet dapat diekspor dan XLSX dibuka kembali', () {
    final evidencePath = Platform.environment['UAT_OMZET_EVIDENCE'];
    final outputPath = Platform.environment['UAT_OMZET_XLSX_OUTPUT'];

    final fixtures = evidencePath == null || evidencePath.trim().isEmpty
        ? <String, dynamic>{
            for (final id in const <String>[
              'omzet_transaksi',
              'omzet_tunai_produk',
              'omzet_saldo_produk',
              'omzet_rekapan',
            ])
              id: <String, dynamic>{
                'kolom': <Map<String, dynamic>>[
                  <String, dynamic>{'l': 'Referensi', 't': 'text'},
                  <String, dynamic>{'l': 'Nilai', 't': 'num'},
                ],
                'baris': <List<dynamic>>[
                  <dynamic>['UAT-$id', 375000],
                ],
              },
          }
        : (jsonDecode(File(evidencePath).readAsStringSync())
            as Map<String, dynamic>)['reportData'] as Map<String, dynamic>;

    final result = <Map<String, dynamic>>[];
    final outputDirectory = outputPath == null || outputPath.trim().isEmpty
        ? null
        : (Directory(outputPath)..createSync(recursive: true));

    for (final id in const <String>[
      'omzet_transaksi',
      'omzet_tunai_produk',
      'omzet_saldo_produk',
      'omzet_rekapan',
    ]) {
      final report = Map<String, dynamic>.from(fixtures[id] as Map);
      final columns = ((report['kolom'] as List?) ?? const <dynamic>[])
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final rows = ((report['baris'] as List?) ?? const <dynamic>[])
          .map((value) => List<dynamic>.from(value as List))
          .toList();
      expect(columns, isNotEmpty, reason: '$id harus memiliki kolom');
      expect(rows, isNotEmpty, reason: '$id tidak boleh kosong');

      final bytes = buildLaporanDetailXlsx(columns, rows);
      expect(bytes.take(2).toList(), <int>[0x50, 0x4b],
          reason: '$id harus menjadi paket ZIP/XLSX');
      final reopened = readSimpleXlsx(bytes);
      final expectedHeaders =
          columns.map((column) => '${column['l']}').toList();
      expect(reopened.first, expectedHeaders,
          reason: 'header $id harus utuh setelah dibuka kembali');
      expect(reopened.length, rows.length + 1,
          reason: 'seluruh baris $id harus terbaca kembali');

      File? written;
      if (outputDirectory != null) {
        written =
            File('${outputDirectory.path}${Platform.pathSeparator}$id.xlsx')
              ..writeAsBytesSync(bytes);
      }
      result.add(<String, dynamic>{
        'id': id,
        'rows': rows.length,
        'columns': columns.length,
        'bytes': bytes.length,
        'path': written?.path,
        'passed': true,
      });
    }

    if (outputDirectory != null) {
      File('${outputDirectory.path}${Platform.pathSeparator}uat-xlsx-result.json')
          .writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'passed': result.length == 4,
          'passedCount': result.length,
          'totalCount': 4,
          'reports': result,
        }),
      );
    }
    expect(result, hasLength(4));
  });
}
