import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

String _columnName(int index) {
  var value = index;
  var result = '';
  while (true) {
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = value ~/ 26 - 1;
    if (value < 0) return result;
  }
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _unxml(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Membuat workbook XLSX sederhana satu sheet. Angka ditulis sebagai angka
/// Excel, sementara nilai lain ditulis sebagai inline string agar file tidak
/// bergantung pada sharedStrings.xml.
Uint8List buildSimpleXlsx({
  required String sheetName,
  required List<String> headers,
  required List<List<Object?>> rows,
}) {
  return buildSimpleXlsxReport(
    sheetName: sheetName,
    rows: [headers, ...rows],
    boldRows: const {1},
  );
}

Uint8List buildSimpleXlsxReport({
  required String sheetName,
  required List<List<Object?>> rows,
  Set<int> boldRows = const {},
  Set<int> darkRows = const {},
  List<double> columnWidths = const [],
}) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');

  if (columnWidths.isNotEmpty) {
    sheet.write('<cols>');
    for (var i = 0; i < columnWidths.length; i++) {
      final width = columnWidths[i].clamp(6, 80).toStringAsFixed(2);
      sheet.write(
          '<col min="${i + 1}" max="${i + 1}" width="$width" customWidth="1"/>');
    }
    sheet.write('</cols>');
  }

  sheet.write('<sheetData>');

  void writeRow(int rowNumber, List<Object?> values) {
    final style = darkRows.contains(rowNumber)
        ? 2
        : boldRows.contains(rowNumber)
            ? 1
            : 0;
    sheet.write('<row r="$rowNumber">');
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) continue;
      final reference = '${_columnName(i)}$rowNumber';
      final styleAttr = style > 0 ? ' s="$style"' : '';
      if (value is num) {
        sheet.write('<c r="$reference"$styleAttr><v>$value</v></c>');
      } else {
        sheet.write(
            '<c r="$reference" t="inlineStr"$styleAttr><is><t xml:space="preserve">${_xml(value.toString())}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }

  for (var i = 0; i < rows.length; i++) {
    writeRow(i + 1, rows[i]);
  }
  sheet.write('</sheetData></worksheet>');

  final cleanedSheetName =
      sheetName.replaceAll(RegExp(r"[\\/*?:\[\]]"), ' ').trim();
  final safeSheetName = _xml(cleanedSheetName.isEmpty
      ? 'Sheet1'
      : cleanedSheetName.substring(0, cleanedSheetName.length.clamp(1, 31)));
  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '</Types>';
  const rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';
  final workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$safeSheetName" sheetId="1" r:id="rId1"/></sheets></workbook>';
  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';
  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0F3B5F"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>'
      '</styleSheet>';

  final archive = Archive()
    ..addFile(
        ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbook)))
    ..addFile(ArchiveFile.bytes(
        'xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)))
    ..addFile(ArchiveFile.bytes('xl/styles.xml', utf8.encode(styles)))
    ..addFile(ArchiveFile.bytes(
        'xl/worksheets/sheet1.xml', utf8.encode(sheet.toString())));
  return ZipEncoder().encodeBytes(archive);
}

/// Membaca sheet pertama dari XLSX umum (shared string maupun inline string).
/// Hasil mempertahankan posisi kolom sehingga header dapat dipetakan aman.
List<List<String>> readSimpleXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? readEntry(String name) {
    for (final entry in archive) {
      if (entry.name == name && entry.isFile) {
        return utf8.decode((entry.content as List<int>), allowMalformed: true);
      }
    }
    return null;
  }

  final shared = <String>[];
  final sharedXml = readEntry('xl/sharedStrings.xml');
  if (sharedXml != null) {
    for (final match in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true)
        .allMatches(sharedXml)) {
      final parts = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(match.group(1)!)
          .map((m) => _unxml(m.group(1)!))
          .join();
      shared.add(parts);
    }
  }
  final worksheet = readEntry('xl/worksheets/sheet1.xml');
  if (worksheet == null) {
    throw const FormatException('Sheet pertama tidak ditemukan.');
  }
  final result = <List<String>>[];
  for (final rowMatch in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true)
      .allMatches(worksheet)) {
    final cells = <int, String>{};
    for (final cell in RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true)
        .allMatches(rowMatch.group(1)!)) {
      final attrs = cell.group(1)!;
      final body = cell.group(2)!;
      final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attrs)?.group(1);
      if (ref == null) continue;
      var column = 0;
      for (final code in ref.codeUnits) {
        column = column * 26 + code - 64;
      }
      column--;
      final type = RegExp(r'\bt="([^"]+)"').firstMatch(attrs)?.group(1);
      String value;
      if (type == 'inlineStr') {
        value = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true)
            .allMatches(body)
            .map((m) => _unxml(m.group(1)!))
            .join();
      } else {
        final raw = RegExp(r'<v\b[^>]*>(.*?)</v>', dotAll: true)
                .firstMatch(body)
                ?.group(1) ??
            '';
        final index = int.tryParse(raw);
        value = type == 's' && index != null && index < shared.length
            ? shared[index]
            : _unxml(raw);
      }
      cells[column] = value.trim();
    }
    if (cells.isEmpty) continue;
    final row =
        List<String>.filled(cells.keys.reduce((a, b) => a > b ? a : b) + 1, '');
    cells.forEach((index, value) => row[index] = value);
    result.add(row);
  }
  return result;
}
