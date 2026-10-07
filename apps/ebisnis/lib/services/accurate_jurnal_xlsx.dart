import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

/// Item rincian per baris jurnal untuk format Accurate / Jurnal Umum.
class AccurateJurnalBarisItem {
  final String kodeAkun;
  final String namaAkun;
  final String keterangan;
  final double debet;
  final double kredit;
  final int? akunId;

  const AccurateJurnalBarisItem({
    required this.kodeAkun,
    required this.namaAkun,
    required this.keterangan,
    required this.debet,
    required this.kredit,
    this.akunId,
  });

  Map<String, dynamic> toJson() => {
        'kodeAkun': kodeAkun,
        'namaAkun': namaAkun,
        'keterangan': keterangan,
        'debet': debet,
        'kredit': kredit,
        if (akunId != null) 'akunId': akunId,
      };
}

/// Satu bundel kepala jurnal beserta rincian barisnya.
class AccurateJurnalItem {
  final String noBukti;
  final String tanggal; // yyyy-MM-dd
  final String tipeTransaksi;
  final String keterangan;
  final List<AccurateJurnalBarisItem> rincian;

  const AccurateJurnalItem({
    required this.noBukti,
    required this.tanggal,
    required this.tipeTransaksi,
    required this.keterangan,
    required this.rincian,
  });

  double get totalDebet =>
      rincian.fold(0.0, (acc, item) => acc + item.debet);

  double get totalKredit =>
      rincian.fold(0.0, (acc, item) => acc + item.kredit);

  bool get isSeimbang => (totalDebet - totalKredit).abs() < 0.005;

  Map<String, dynamic> toPayloadSimpan({int? jenisTransaksiId}) => {
        'kode': noBukti,
        'noBukti': noBukti,
        'tanggal': tanggal,
        'keterangan': keterangan.isNotEmpty
            ? keterangan
            : (noBukti.isNotEmpty ? 'Impor Accurate $noBukti' : 'Impor Jurnal'),
        if (jenisTransaksiId != null && jenisTransaksiId > 0)
          'jenisTransaksiId': jenisTransaksiId,
        'baris': rincian
            .map((b) => {
                  'akunId': b.akunId ?? 0,
                  'kodeAkun': b.kodeAkun,
                  'namaAkun': b.namaAkun,
                  'debet': b.debet,
                  'kredit': b.kredit,
                  'keterangan': b.keterangan.isNotEmpty
                      ? b.keterangan
                      : keterangan,
                })
            .toList(),
      };
}

/// Hasil pembacaan (impor) berkas Excel Accurate.
class HasilParseAccurateJurnal {
  final List<AccurateJurnalItem> daftarJurnal;
  final List<String> daftarPeringatan;
  final int totalBarisMentah;
  final double totalDebet;
  final double totalKredit;

  const HasilParseAccurateJurnal({
    required this.daftarJurnal,
    required this.daftarPeringatan,
    required this.totalBarisMentah,
    required this.totalDebet,
    required this.totalKredit,
  });
}

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _xmlUnescape(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

DateTime _excelSerialToDate(double serial) {
  final base = DateTime(1899, 12, 30);
  final days = serial.floor();
  final millis = ((serial - days) * 86400000).round();
  return base.add(Duration(days: days, milliseconds: millis));
}

/// Mengurai daftar string bersama (sharedStrings.xml)
List<String> _parseSharedStrings(String xml) {
  final result = <String>[];
  final siRegex = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true);
  final tRegex = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);
  for (final match in siRegex.allMatches(xml)) {
    final siContent = match.group(1) ?? '';
    final sb = StringBuffer();
    for (final tMatch in tRegex.allMatches(siContent)) {
      sb.write(tMatch.group(1));
    }
    result.add(_xmlUnescape(sb.toString()));
  }
  return result;
}

/// Mengurai berkas Excel (.xlsx) dengan pola Accurate "Histori Buku Besar (Jurnal)".
HasilParseAccurateJurnal parseAccurateJurnalXlsx(
  Uint8List bytes, {
  List<Map<String, dynamic>> daftarAkun = const [],
}) {
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? sstFile;
  ArchiveFile? sheetFile;

  for (final file in archive.files) {
    if (file.name == 'xl/sharedStrings.xml') {
      sstFile = file;
    } else if (file.name == 'xl/worksheets/sheet1.xml') {
      sheetFile = file;
    }
  }

  if (sheetFile == null) {
    throw const FormatException('Berkas Excel tidak memuat lembar kerja (sheet1.xml).');
  }

  final sharedStrings = sstFile != null
      ? _parseSharedStrings(utf8.decode(sstFile.content as List<int>, allowMalformed: true))
      : <String>[];

  final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);

  final rAttrRegex = RegExp(r'r="([A-Z]+)(\d+)"');
  final tAttrRegex = RegExp(r't="([^"]+)"');
  final vRegex = RegExp(r'<v>(.*?)</v>');
  final isTRegex = RegExp(r'<is><t[^>]*>(.*?)</t></is>');

  final rowsRegex = RegExp(r'<row\s+[^>]*?r="(\d+)"[^>]*?>(.*?)</row>', dotAll: true);
  final cTagRegex = RegExp(r'<c\s+([^>]+?)(?:/>|>(.*?)</c>)', dotAll: true);

  // Buat index akun untuk pencarian instan berdasarkan kode akun & nama
  final mapAkunKode = <String, Map<String, dynamic>>{};
  final mapAkunNama = <String, Map<String, dynamic>>{};
  for (final a in daftarAkun) {
    final k = '${a['kode'] ?? ''}'.trim().toLowerCase();
    final n = '${a['nama'] ?? ''}'.trim().toLowerCase();
    if (k.isNotEmpty) mapAkunKode[k] = a;
    if (n.isNotEmpty) mapAkunNama[n] = a;
  }

  final peringatan = <String>[];
  var totalBaris = 0;
  var totalDebet = 0.0;
  var totalKredit = 0.0;

  String currentTanggal = '';
  // Baris-baris transaksi dikelompokkan berdasarkan identitas jurnal:
  // key: noBukti (jika ada) atau tanggal + '_' + keterangan
  final grupJurnal = <String, List<_RawRow>>{};
  final urutanGrup = <String>[];

  for (final rMatch in rowsRegex.allMatches(sheetXml)) {
    final rowNum = int.tryParse(rMatch.group(1) ?? '') ?? 0;
    if (rowNum < 5) continue; // Row 1-4 header toko dan periode

    final rowXml = rMatch.group(2) ?? '';
    final cells = <String, String>{};

    for (final cMatch in cTagRegex.allMatches(rowXml)) {
      final attrs = cMatch.group(1) ?? '';
      final body = cMatch.group(2);

      final rM = rAttrRegex.firstMatch(attrs);
      if (rM == null) continue;
      final col = rM.group(1)!;

      if (body == null || body.isEmpty) {
        cells[col] = '';
        continue;
      }

      final tM = tAttrRegex.firstMatch(attrs);
      final t = tM?.group(1);

      String val = '';
      if (t == 's') {
        final vM = vRegex.firstMatch(body);
        if (vM != null) {
          final idx = int.tryParse(vM.group(1) ?? '');
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            val = sharedStrings[idx];
          }
        }
      } else if (t == 'inlineStr') {
        final isM = isTRegex.firstMatch(body);
        if (isM != null) val = isM.group(1) ?? '';
      } else {
        final vM = vRegex.firstMatch(body);
        if (vM != null) val = vM.group(1) ?? '';
      }
      cells[col] = val.trim();
    }

    final colB = cells['B'] ?? '';
    final colE = cells['E'] ?? '';
    final colG = cells['G'] ?? '';
    final colI = cells['I'] ?? '';
    final colK = cells['K'] ?? '';
    final colM = double.tryParse(cells['M'] ?? '') ?? 0.0;
    final colO = double.tryParse(cells['O'] ?? '') ?? 0.0;

    // Lewati baris judul kolom yang berulang
    if (colB == 'Tipe Transaksi Jurnal' || (colB.isEmpty && colE.isEmpty && colG.isEmpty)) {
      continue;
    }

    // Baris pemisah tanggal (Col B terisi tanggal, Col E dan Col G kosong)
    if (colE.isEmpty && colG.isEmpty && colB.isNotEmpty) {
      final serial = double.tryParse(colB);
      if (serial != null && serial > 30000 && serial < 80000) {
        final d = _excelSerialToDate(serial);
        currentTanggal =
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      } else {
        // Coba cocokkan format yyyy-MM-dd atau dd/MM/yyyy
        final tglPola = RegExp(r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})');
        final matchIso = tglPola.firstMatch(colB);
        if (matchIso != null) {
          final y = matchIso.group(1)!;
          final m = matchIso.group(2)!.padLeft(2, '0');
          final d = matchIso.group(3)!.padLeft(2, '0');
          currentTanggal = '$y-$m-$d';
        } else {
          final matchId = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(colB);
          if (matchId != null) {
            final d = matchId.group(1)!.padLeft(2, '0');
            final m = matchId.group(2)!.padLeft(2, '0');
            final y = matchId.group(3)!;
            currentTanggal = '$y-$m-$d';
          } else {
            currentTanggal = colB;
          }
        }
      }
      continue;
    }

    // Baris data transaksi
    if (colG.isNotEmpty || colM > 0 || colO > 0) {
      totalBaris++;
      totalDebet += colM;
      totalKredit += colO;

      final keyGrup = colE.isNotEmpty
          ? '${currentTanggal}_$colE'
          : '${currentTanggal}_$colK';

      if (!grupJurnal.containsKey(keyGrup)) {
        grupJurnal[keyGrup] = [];
        urutanGrup.add(keyGrup);
      }

      grupJurnal[keyGrup]!.add(_RawRow(
        tanggal: currentTanggal,
        tipe: colB,
        noBukti: colE,
        kodeAkun: colG,
        namaAkun: colI,
        keterangan: colK,
        debet: colM,
        kredit: colO,
      ));
    }
  }

  final daftarJurnal = <AccurateJurnalItem>[];

  for (final key in urutanGrup) {
    final rows = grupJurnal[key]!;
    if (rows.isEmpty) continue;

    final noBukti = rows.first.noBukti;
    final tanggal = rows.first.tanggal;
    final tipe = rows.first.tipe.isNotEmpty ? rows.first.tipe : 'Jurnal Umum';
    // Ambil keterangan dari baris pertama yang tidak kosong
    final keterangan = rows
        .map((r) => r.keterangan)
        .firstWhere((k) => k.trim().isNotEmpty, orElse: () => '');

    final barisList = <AccurateJurnalBarisItem>[];
    for (final r in rows) {
      // Cari akunId
      int? akunId;
      final kClean = r.kodeAkun.trim().toLowerCase();
      final nClean = r.namaAkun.trim().toLowerCase();
      if (kClean.isNotEmpty && mapAkunKode.containsKey(kClean)) {
        akunId = (mapAkunKode[kClean]!['id'] as num?)?.toInt();
      } else if (nClean.isNotEmpty && mapAkunNama.containsKey(nClean)) {
        akunId = (mapAkunNama[nClean]!['id'] as num?)?.toInt();
      }

      if (akunId == null && r.kodeAkun.isNotEmpty) {
        final pesan =
            'Akun "${r.kodeAkun}" (${r.namaAkun}) pada bukti "$noBukti" belum terdaftar di sistem.';
        if (!peringatan.contains(pesan)) peringatan.add(pesan);
      }

      barisList.add(AccurateJurnalBarisItem(
        kodeAkun: r.kodeAkun,
        namaAkun: r.namaAkun,
        keterangan: r.keterangan,
        debet: r.debet,
        kredit: r.kredit,
        akunId: akunId,
      ));
    }

    final item = AccurateJurnalItem(
      noBukti: noBukti,
      tanggal: tanggal,
      tipeTransaksi: tipe,
      keterangan: keterangan,
      rincian: barisList,
    );

    if (!item.isSeimbang) {
      peringatan.add(
          'Jurnal "$noBukti" tidak seimbang: Debet ${item.totalDebet} vs Kredit ${item.totalKredit}.');
    }

    daftarJurnal.add(item);
  }

  return HasilParseAccurateJurnal(
    daftarJurnal: daftarJurnal,
    daftarPeringatan: peringatan,
    totalBarisMentah: totalBaris,
    totalDebet: totalDebet,
    totalKredit: totalKredit,
  );
}

class _RawRow {
  final String tanggal;
  final String tipe;
  final String noBukti;
  final String kodeAkun;
  final String namaAkun;
  final String keterangan;
  final double debet;
  final double kredit;

  _RawRow({
    required this.tanggal,
    required this.tipe,
    required this.noBukti,
    required this.kodeAkun,
    required this.namaAkun,
    required this.keterangan,
    required this.debet,
    required this.kredit,
  });
}

/// Menghasilkan file Excel (.xlsx) dengan format Accurate "Histori Buku Besar (Jurnal)".
Uint8List buildAccurateJurnalXlsx({
  required String namaToko,
  required DateTime mulai,
  required DateTime sampai,
  required List<Map<String, dynamic>> daftarJurnal,
}) {
  const namaBulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  String formatTgl(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${namaBulan[d.month - 1]} ${d.year}';
  final periodeTeks = 'Dari ${formatTgl(mulai)} s/d ${formatTgl(sampai)}';

  final sheetXml = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<cols>')
    ..write('<col min="1" max="1" width="5" customWidth="1"/>')
    ..write('<col min="2" max="2" width="22" customWidth="1"/>') // Tipe Transaksi / Tanggal
    ..write('<col min="3" max="3" width="5" customWidth="1"/>')
    ..write('<col min="4" max="4" width="5" customWidth="1"/>')
    ..write('<col min="5" max="5" width="24" customWidth="1"/>') // No Bukti
    ..write('<col min="6" max="6" width="5" customWidth="1"/>')
    ..write('<col min="7" max="7" width="16" customWidth="1"/>') // Kode Akun
    ..write('<col min="8" max="8" width="5" customWidth="1"/>')
    ..write('<col min="9" max="9" width="30" customWidth="1"/>') // Nama Perkiraan
    ..write('<col min="10" max="10" width="5" customWidth="1"/>')
    ..write('<col min="11" max="11" width="35" customWidth="1"/>') // Keterangan
    ..write('<col min="12" max="12" width="5" customWidth="1"/>')
    ..write('<col min="13" max="13" width="18" customWidth="1"/>') // Debit
    ..write('<col min="14" max="14" width="5" customWidth="1"/>')
    ..write('<col min="15" max="15" width="18" customWidth="1"/>') // Kredit
    ..write('</cols>')
    ..write('<sheetData>');

  // Row 1: Nama Toko
  sheetXml.write(
      '<row r="1"><c r="B1" t="inlineStr" s="1"><is><t>${_xmlEscape(namaToko)}</t></is></c></row>');
  // Row 2: Judul Laporan
  sheetXml.write(
      '<row r="2"><c r="B2" t="inlineStr" s="1"><is><t>Histori Buku Besar (Jurnal)</t></is></c></row>');
  // Row 3: Periode
  sheetXml.write(
      '<row r="3"><c r="B3" t="inlineStr"><is><t>${_xmlEscape(periodeTeks)}</t></is></c></row>');
  // Row 4: Cabang
  sheetXml.write(
      '<row r="4"><c r="B4" t="inlineStr"><is><t>Cabang : ${_xmlEscape(namaToko)}</t></is></c></row>');
  // Row 5: Header Kolom
  sheetXml.write(
      '<row r="5">'
      '<c r="B5" t="inlineStr" s="1"><is><t>Tipe Transaksi Jurnal</t></is></c>'
      '<c r="E5" t="inlineStr" s="1"><is><t>No Bukti #</t></is></c>'
      '<c r="G5" t="inlineStr" s="1"><is><t>Kode #</t></is></c>'
      '<c r="I5" t="inlineStr" s="1"><is><t>Nama Perkiraan</t></is></c>'
      '<c r="K5" t="inlineStr" s="1"><is><t>Keterangan Jurnal</t></is></c>'
      '<c r="M5" t="inlineStr" s="1"><is><t>Debit</t></is></c>'
      '<c r="O5" t="inlineStr" s="1"><is><t>Kredit</t></is></c>'
      '</row>');

  var currentRow = 6;
  String lastDate = '';

  for (final j in daftarJurnal) {
    final tanggal = '${j['tanggal'] ?? ''}';
    final kode = '${j['kode'] ?? ''}';
    final ketJurnal = '${j['keterangan'] ?? ''}';
    final jenis = '${j['jenisTransaksi'] ?? 'Jurnal Umum'}';

    // Jika tanggal berbeda, tulis baris pemisah tanggal
    if (tanggal.isNotEmpty && tanggal != lastDate) {
      sheetXml.write(
          '<row r="$currentRow"><c r="B$currentRow" t="inlineStr" s="1"><is><t>${_xmlEscape(tanggal)}</t></is></c></row>');
      currentRow++;
      lastDate = tanggal;
    }

    final barisList = (j['baris'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (barisList.isEmpty) {
      // Jika rincian baris kosong, tulis minimal 1 baris kepala
      final d = (j['totalDebet'] as num?)?.toDouble() ?? 0.0;
      final k = (j['totalKredit'] as num?)?.toDouble() ?? 0.0;
      sheetXml.write(
          '<row r="$currentRow">'
          '<c r="B$currentRow" t="inlineStr"><is><t>${_xmlEscape(jenis)}</t></is></c>'
          '<c r="E$currentRow" t="inlineStr"><is><t>${_xmlEscape(kode)}</t></is></c>'
          '<c r="K$currentRow" t="inlineStr"><is><t>${_xmlEscape(ketJurnal)}</t></is></c>'
          '<c r="M$currentRow"><v>$d</v></c>'
          '<c r="O$currentRow"><v>$k</v></c>'
          '</row>');
      currentRow++;
    } else {
      for (final b in barisList) {
        final kodeAkun = '${b['kodeAkun'] ?? ''}';
        final namaAkun = '${b['namaAkun'] ?? ''}';
        final ketBaris = '${b['keterangan'] ?? ''}'.trim().isNotEmpty
            ? '${b['keterangan']}'
            : ketJurnal;
        final d = (b['debet'] as num?)?.toDouble() ?? 0.0;
        final k = (b['kredit'] as num?)?.toDouble() ?? 0.0;

        sheetXml.write(
            '<row r="$currentRow">'
            '<c r="B$currentRow" t="inlineStr"><is><t>${_xmlEscape(jenis)}</t></is></c>'
            '<c r="E$currentRow" t="inlineStr"><is><t>${_xmlEscape(kode)}</t></is></c>'
            '<c r="G$currentRow" t="inlineStr"><is><t>${_xmlEscape(kodeAkun)}</t></is></c>'
            '<c r="I$currentRow" t="inlineStr"><is><t>${_xmlEscape(namaAkun)}</t></is></c>'
            '<c r="K$currentRow" t="inlineStr"><is><t>${_xmlEscape(ketBaris)}</t></is></c>'
            '<c r="M$currentRow"><v>$d</v></c>'
            '<c r="O$currentRow"><v>$k</v></c>'
            '</row>');
        currentRow++;
      }
    }
  }

  sheetXml.write('</sheetData></worksheet>');

  return _kemasXlsx(
    sheetName: 'Histori Buku Besar (Jurnal)',
    sheetXmlContent: sheetXml.toString(),
  );
}

/// Menghasilkan file Excel (.xlsx) dengan Format Standar Tabel.
Uint8List buildStandarJurnalXlsx({
  required String namaToko,
  required DateTime mulai,
  required DateTime sampai,
  required List<Map<String, dynamic>> daftarJurnal,
}) {
  final sheetXml = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<cols>')
    ..write('<col min="1" max="1" width="18" customWidth="1"/>') // No Bukti
    ..write('<col min="2" max="2" width="14" customWidth="1"/>') // Tanggal
    ..write('<col min="3" max="3" width="18" customWidth="1"/>') // Jenis
    ..write('<col min="4" max="4" width="30" customWidth="1"/>') // Keterangan
    ..write('<col min="5" max="5" width="16" customWidth="1"/>') // Kode Akun
    ..write('<col min="6" max="6" width="26" customWidth="1"/>') // Nama Akun
    ..write('<col min="7" max="7" width="16" customWidth="1"/>') // Debet
    ..write('<col min="8" max="8" width="16" customWidth="1"/>') // Kredit
    ..write('<col min="9" max="9" width="14" customWidth="1"/>') // Status
    ..write('</cols>')
    ..write('<sheetData>');

  // Header Row 1
  sheetXml.write(
      '<row r="1">'
      '<c r="A1" t="inlineStr" s="1"><is><t>No Bukti</t></is></c>'
      '<c r="B1" t="inlineStr" s="1"><is><t>Tanggal</t></is></c>'
      '<c r="C1" t="inlineStr" s="1"><is><t>Jenis Transaksi</t></is></c>'
      '<c r="D1" t="inlineStr" s="1"><is><t>Keterangan Jurnal</t></is></c>'
      '<c r="E1" t="inlineStr" s="1"><is><t>Kode Akun</t></is></c>'
      '<c r="F1" t="inlineStr" s="1"><is><t>Nama Akun</t></is></c>'
      '<c r="G1" t="inlineStr" s="1"><is><t>Debet</t></is></c>'
      '<c r="H1" t="inlineStr" s="1"><is><t>Kredit</t></is></c>'
      '<c r="I1" t="inlineStr" s="1"><is><t>Status</t></is></c>'
      '</row>');

  var r = 2;
  for (final j in daftarJurnal) {
    final kode = '${j['kode'] ?? ''}';
    final tanggal = '${j['tanggal'] ?? ''}';
    final jenis = '${j['jenisTransaksi'] ?? 'Jurnal Umum'}';
    final ketJurnal = '${j['keterangan'] ?? ''}';
    final status = j['terposting'] == true ? 'Terposting' : 'Draf';
    final barisList = (j['baris'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (barisList.isEmpty) {
      final d = (j['totalDebet'] as num?)?.toDouble() ?? 0.0;
      final k = (j['totalKredit'] as num?)?.toDouble() ?? 0.0;
      sheetXml.write(
          '<row r="$r">'
          '<c r="A$r" t="inlineStr"><is><t>${_xmlEscape(kode)}</t></is></c>'
          '<c r="B$r" t="inlineStr"><is><t>${_xmlEscape(tanggal)}</t></is></c>'
          '<c r="C$r" t="inlineStr"><is><t>${_xmlEscape(jenis)}</t></is></c>'
          '<c r="D$r" t="inlineStr"><is><t>${_xmlEscape(ketJurnal)}</t></is></c>'
          '<c r="E$r" t="inlineStr"><is><t>-</t></is></c>'
          '<c r="F$r" t="inlineStr"><is><t>-</t></is></c>'
          '<c r="G$r"><v>$d</v></c>'
          '<c r="H$r"><v>$k</v></c>'
          '<c r="I$r" t="inlineStr"><is><t>${_xmlEscape(status)}</t></is></c>'
          '</row>');
      r++;
    } else {
      for (final b in barisList) {
        final kodeAkun = '${b['kodeAkun'] ?? ''}';
        final namaAkun = '${b['namaAkun'] ?? ''}';
        final ketBaris = '${b['keterangan'] ?? ''}'.trim().isNotEmpty
            ? '${b['keterangan']}'
            : ketJurnal;
        final d = (b['debet'] as num?)?.toDouble() ?? 0.0;
        final k = (b['kredit'] as num?)?.toDouble() ?? 0.0;

        sheetXml.write(
            '<row r="$r">'
            '<c r="A$r" t="inlineStr"><is><t>${_xmlEscape(kode)}</t></is></c>'
            '<c r="B$r" t="inlineStr"><is><t>${_xmlEscape(tanggal)}</t></is></c>'
            '<c r="C$r" t="inlineStr"><is><t>${_xmlEscape(jenis)}</t></is></c>'
            '<c r="D$r" t="inlineStr"><is><t>${_xmlEscape(ketBaris)}</t></is></c>'
            '<c r="E$r" t="inlineStr"><is><t>${_xmlEscape(kodeAkun)}</t></is></c>'
            '<c r="F$r" t="inlineStr"><is><t>${_xmlEscape(namaAkun)}</t></is></c>'
            '<c r="G$r"><v>$d</v></c>'
            '<c r="H$r"><v>$k</v></c>'
            '<c r="I$r" t="inlineStr"><is><t>${_xmlEscape(status)}</t></is></c>'
            '</row>');
        r++;
      }
    }
  }

  sheetXml.write('</sheetData></worksheet>');

  return _kemasXlsx(
    sheetName: 'Jurnal Umum',
    sheetXmlContent: sheetXml.toString(),
  );
}

Uint8List _kemasXlsx({
  required String sheetName,
  required String sheetXmlContent,
}) {
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

  final cleanedSheetName =
      sheetName.replaceAll(RegExp(r"[\\/*?:\[\]]"), ' ').trim();
  final safeSheetName = _xmlEscape(cleanedSheetName.isEmpty
      ? 'Sheet1'
      : cleanedSheetName.substring(0, cleanedSheetName.length.clamp(1, 31)));

  final workbookXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="$safeSheetName" sheetId="1" r:id="rId1"/></sheets>'
      '</workbook>';

  const workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>';

  const stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="2">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '</cellXfs>'
      '</styleSheet>';

  final archive = Archive()
    ..addFile(
        ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypes)))
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRels)))
    ..addFile(ArchiveFile.bytes('xl/workbook.xml', utf8.encode(workbookXml)))
    ..addFile(ArchiveFile.bytes(
        'xl/_rels/workbook.xml.rels', utf8.encode(workbookRels)))
    ..addFile(ArchiveFile.bytes('xl/styles.xml', utf8.encode(stylesXml)))
    ..addFile(ArchiveFile.bytes(
        'xl/worksheets/sheet1.xml', utf8.encode(sheetXmlContent)));

  return ZipEncoder().encodeBytes(archive);
}
