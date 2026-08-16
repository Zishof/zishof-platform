import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'simple_xlsx.dart';

class DynamicReportColumn {
  final String key;
  final String label;
  final bool numeric;

  const DynamicReportColumn(this.key, this.label, {this.numeric = false});
}

class DynamicReportData {
  final String title;
  final String subtitle;
  final List<DynamicReportColumn> columns;
  final List<Map<String, dynamic>> rows;

  const DynamicReportData({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
  });
}

class DynamicReportModel {
  String title;
  String company;
  String subtitle;
  Set<String> selectedColumns;
  String filter;
  String groupBy;
  String paper;
  bool landscape;
  double marginMm;
  double fontSize;
  int decimals;
  bool parenthesesNegative;
  bool showHeader;
  bool showFooter;
  bool showPrintDate;
  bool showPageNumber;
  bool showTotals;
  bool showAnalysis;
  bool showChart;

  DynamicReportModel.fromData(DynamicReportData data)
      : title = data.title,
        company = 'Unit Usaha Al Bahjah',
        subtitle = data.subtitle,
        selectedColumns = data.columns.map((e) => e.key).toSet(),
        filter = '',
        groupBy = '',
        paper = 'A4',
        landscape = true,
        marginMm = 10,
        fontSize = 8.5,
        decimals = 0,
        parenthesesNegative = false,
        showHeader = true,
        showFooter = true,
        showPrintDate = true,
        showPageNumber = true,
        showTotals = true,
        showAnalysis = true,
        showChart = false;
}

class DynamicReportDesigner {
  DynamicReportDesigner._();

  static List<DynamicReportColumn> selectedColumns(
          DynamicReportData data, DynamicReportModel model) =>
      data.columns.where((c) => model.selectedColumns.contains(c.key)).toList();

  static List<Map<String, dynamic>> filteredRows(
      DynamicReportData data, DynamicReportModel model) {
    final query = model.filter.trim().toLowerCase();
    final rows = query.isEmpty
        ? List<Map<String, dynamic>>.from(data.rows)
        : data.rows
            .where((row) => row.values
                .any((value) => '$value'.toLowerCase().contains(query)))
            .toList();
    if (model.groupBy.isNotEmpty) {
      rows.sort((a, b) =>
          '${a[model.groupBy] ?? ''}'.compareTo('${b[model.groupBy] ?? ''}'));
    }
    return rows;
  }

  static String formatValue(
      dynamic value, DynamicReportColumn column, DynamicReportModel model) {
    if (value == null) return '-';
    if (!column.numeric || value is! num) return '$value';
    final number = value.toDouble();
    final absText = NumberFormat.currency(
      locale: 'id_ID',
      symbol: '',
      decimalDigits: model.decimals,
    ).format(number.abs()).trim();
    if (number >= 0) return absText;
    return model.parenthesesNegative ? '($absText)' : '-$absText';
  }

  static Map<String, num> totals(DynamicReportData data,
      DynamicReportModel model, List<Map<String, dynamic>> rows) {
    final out = <String, num>{};
    for (final column in selectedColumns(data, model).where((c) => c.numeric)) {
      out[column.key] = rows.fold<double>(
          0, (sum, row) => sum + ((row[column.key] as num?)?.toDouble() ?? 0));
    }
    return out;
  }

  static List<MapEntry<String, double>> chartSeries(DynamicReportData data,
      DynamicReportModel model, List<Map<String, dynamic>> rows) {
    final columns = selectedColumns(data, model);
    DynamicReportColumn? valueColumn;
    DynamicReportColumn? labelColumn;
    for (final column in columns) {
      if (valueColumn == null && column.numeric) valueColumn = column;
      if (labelColumn == null && !column.numeric) labelColumn = column;
    }
    if (valueColumn == null || rows.isEmpty) return const [];
    final grouped = <String, double>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final label = labelColumn == null
          ? 'Data ${index + 1}'
          : '${row[labelColumn.key] ?? '-'}';
      grouped[label] = (grouped[label] ?? 0) +
          ((row[valueColumn.key] as num?)?.toDouble() ?? 0).abs();
    }
    final series = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return series.take(8).toList();
  }

  static Future<DynamicReportModel?> show(
    BuildContext context, {
    required DynamicReportData data,
    DynamicReportModel? initial,
    int initialTab = 0,
  }) async {
    return showDialog<DynamicReportModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DynamicReportDialog(
        data: data,
        model: initial ?? DynamicReportModel.fromData(data),
        initialTab: initialTab,
      ),
    );
  }

  static PdfPageFormat _pageFormat(DynamicReportModel model) {
    PdfPageFormat base;
    switch (model.paper) {
      case 'A3':
        base = PdfPageFormat.a3;
        break;
      case 'Letter':
        base = PdfPageFormat.letter;
        break;
      default:
        base = PdfPageFormat.a4;
    }
    return model.landscape ? base.landscape : base.portrait;
  }

  static Future<void> exportPdf(
      DynamicReportData data, DynamicReportModel model, String fileName) async {
    final columns = selectedColumns(data, model);
    final rows = filteredRows(data, model);
    final total = totals(data, model, rows);
    final chart = chartSeries(data, model, rows);
    final margin = model.marginMm * PdfPageFormat.mm;
    final document = pw.Document();
    document.addPage(pw.MultiPage(
      pageFormat: _pageFormat(model),
      margin: pw.EdgeInsets.all(margin),
      header: model.showHeader
          ? (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(model.company,
                      style: pw.TextStyle(
                          fontSize: model.fontSize + 2,
                          fontWeight: pw.FontWeight.bold)),
                  pw.Text(model.title,
                      style: pw.TextStyle(
                          fontSize: model.fontSize + 4,
                          fontWeight: pw.FontWeight.bold)),
                  if (model.subtitle.trim().isNotEmpty)
                    pw.Text(model.subtitle,
                        style: pw.TextStyle(fontSize: model.fontSize)),
                  pw.SizedBox(height: 7),
                ],
              )
          : null,
      footer: model.showFooter
          ? (context) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  if (model.showPrintDate)
                    pw.Text(
                        'Dicetak ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                        style: pw.TextStyle(fontSize: model.fontSize - 1)),
                  if (model.showPageNumber)
                    pw.Text(
                        'Halaman ${context.pageNumber} / ${context.pagesCount}',
                        style: pw.TextStyle(fontSize: model.fontSize - 1)),
                ],
              )
          : null,
      build: (_) => [
        pw.TableHelper.fromTextArray(
          headers: columns.map((c) => c.label).toList(),
          data: [
            ...rows.map((row) =>
                columns.map((c) => formatValue(row[c.key], c, model)).toList()),
            if (model.showTotals)
              columns
                  .map((c) => c == columns.first
                      ? 'TOTAL'
                      : c.numeric
                          ? formatValue(total[c.key] ?? 0, c, model)
                          : '')
                  .toList(),
          ],
          headerStyle: pw.TextStyle(
              fontSize: model.fontSize, fontWeight: pw.FontWeight.bold),
          cellStyle: pw.TextStyle(fontSize: model.fontSize),
        ),
        if (model.showAnalysis) ...[
          pw.SizedBox(height: 8),
          pw.Text(
              'Analisa: ${rows.length} baris ditampilkan dari ${data.rows.length} baris sumber.',
              style: pw.TextStyle(fontSize: model.fontSize)),
        ],
        if (model.showChart && chart.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text('Grafik ringkas',
              style: pw.TextStyle(
                  fontSize: model.fontSize + 1,
                  fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          ...chart.map((item) {
            final maxValue = chart.first.value == 0 ? 1 : chart.first.value;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 3),
              child: pw.Row(children: [
                pw.SizedBox(
                    width: 90,
                    child: pw.Text(item.key,
                        maxLines: 1,
                        style: pw.TextStyle(fontSize: model.fontSize - 1))),
                pw.Container(
                    height: 7,
                    width: 180 * (item.value / maxValue),
                    color: PdfColors.green700),
                pw.SizedBox(width: 5),
                pw.Text(NumberFormat('#,##0.##', 'id_ID').format(item.value),
                    style: pw.TextStyle(fontSize: model.fontSize - 1)),
              ]),
            );
          }),
        ],
      ],
    ));
    await Printing.layoutPdf(onLayout: (_) => document.save(), name: fileName);
  }

  static Future<void> exportExcel(BuildContext context, DynamicReportData data,
      DynamicReportModel model, String fileName) async {
    final columns = selectedColumns(data, model);
    final rows = filteredRows(data, model);
    final total = totals(data, model, rows);
    final bytes = buildSimpleXlsx(
      sheetName: 'Laporan',
      headers: columns.map((c) => c.label).toList(),
      rows: [
        ...rows
            .map((row) => columns.map((c) => '${row[c.key] ?? ''}').toList()),
        if (model.showTotals)
          columns
              .map((c) => c == columns.first
                  ? 'TOTAL'
                  : c.numeric
                      ? '${total[c.key] ?? 0}'
                      : '')
              .toList(),
      ],
    );
    await _saveBytes(context, fileName.replaceAll(RegExp(r'\.[^.]+$'), '.xlsx'),
        bytes, 'Excel', const ['xlsx']);
  }

  static Future<void> exportWord(BuildContext context, DynamicReportData data,
      DynamicReportModel model, String fileName) async {
    final columns = selectedColumns(data, model);
    final rows = filteredRows(data, model);
    final total = totals(data, model, rows);
    final chart = chartSeries(data, model, rows);
    String esc(dynamic value) => const HtmlEscape().convert('$value');
    final html = StringBuffer()
      ..write(
          '<html><head><meta charset="utf-8"><style>body{font-family:Arial;font-size:${model.fontSize + 2}pt}table{border-collapse:collapse;width:100%}th,td{border:1px solid #555;padding:4px}th{background:#eee}.num{text-align:right}</style></head><body>')
      ..write(model.showHeader
          ? '<h3>${esc(model.company)}</h3><h1>${esc(model.title)}</h1><p>${esc(model.subtitle)}</p>'
          : '')
      ..write('<table><thead><tr>');
    for (final c in columns) {
      html.write('<th>${esc(c.label)}</th>');
    }
    html.write('</tr></thead><tbody>');
    for (final row in rows) {
      html.write('<tr>');
      for (final c in columns) {
        html.write(
            '<td class="${c.numeric ? 'num' : ''}">${esc(formatValue(row[c.key], c, model))}</td>');
      }
      html.write('</tr>');
    }
    if (model.showTotals) {
      html.write('<tr><th>TOTAL</th>');
      for (var i = 1; i < columns.length; i++) {
        final c = columns[i];
        html.write(
            '<th class="${c.numeric ? 'num' : ''}">${c.numeric ? esc(formatValue(total[c.key] ?? 0, c, model)) : ''}</th>');
      }
      html.write('</tr>');
    }
    html.write('</tbody></table>');
    if (model.showChart && chart.isNotEmpty) {
      final maxValue = chart.first.value == 0 ? 1 : chart.first.value;
      html.write('<h3>Grafik ringkas</h3>');
      for (final item in chart) {
        final width = (item.value / maxValue * 100).round();
        html.write('<div style="margin:4px 0">${esc(item.key)} '
            '<span style="display:inline-block;background:#176b45;height:10px;width:$width%"></span> '
            '${esc(NumberFormat('#,##0.##', 'id_ID').format(item.value))}</div>');
      }
    }
    if (model.showFooter && model.showPrintDate) {
      html.write(
          '<p>Dicetak ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}</p>');
    }
    html.write('</body></html>');
    await _saveBytes(context, fileName.replaceAll(RegExp(r'\.[^.]+$'), '.doc'),
        utf8.encode(html.toString()), 'Word', const ['doc']);
  }

  static Future<void> _saveBytes(BuildContext context, String fileName,
      List<int> bytes, String label, List<String> extensions) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Simpan $label',
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (path == null) return;
    if (!path.startsWith('content://')) await File(path).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label disimpan: $path')));
    }
  }
}

class _DynamicReportDialog extends StatefulWidget {
  final DynamicReportData data;
  final DynamicReportModel model;
  final int initialTab;

  const _DynamicReportDialog(
      {required this.data, required this.model, required this.initialTab});

  @override
  State<_DynamicReportDialog> createState() => _DynamicReportDialogState();
}

class _DynamicReportDialogState extends State<_DynamicReportDialog> {
  late final DynamicReportModel model = widget.model;

  @override
  Widget build(BuildContext context) {
    final columns = DynamicReportDesigner.selectedColumns(widget.data, model);
    final rows = DynamicReportDesigner.filteredRows(widget.data, model);
    return DefaultTabController(
      length: 8,
      initialIndex: widget.initialTab.clamp(0, 7),
      child: AlertDialog(
        insetPadding: const EdgeInsets.all(12),
        contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
        title: const Text('Preview & Pengaturan Model Laporan'),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width * .94,
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(children: [
            const TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Preview'),
                Tab(text: 'Kolom Data'),
                Tab(text: 'Penyaringan'),
                Tab(text: 'Grup'),
                Tab(text: 'Header & Footer'),
                Tab(text: 'Halaman'),
                Tab(text: 'Huruf & Angka'),
                Tab(text: 'Analisa & Grafik'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                _preview(columns, rows),
                _columns(),
                _filter(),
                _group(),
                _headerFooter(),
                _page(),
                _fontNumber(),
                _analysis(),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton.icon(
            onPressed: model.selectedColumns.isEmpty
                ? null
                : () => Navigator.pop(context, model),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Simpan Model'),
          ),
        ],
      ),
    );
  }

  Widget _preview(
      List<DynamicReportColumn> columns, List<Map<String, dynamic>> rows) {
    final totals = DynamicReportDesigner.totals(widget.data, model, rows);
    final chart = DynamicReportDesigner.chartSeries(widget.data, model, rows);
    return Container(
      color: const Color(0xFF30343B),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(model.marginMm.clamp(4, 30)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (model.showHeader) ...[
                    Text(model.company, textAlign: TextAlign.center),
                    Text(model.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: model.fontSize + 7,
                            fontWeight: FontWeight.bold)),
                    Text(model.subtitle, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: columns
                              .map((c) => DataColumn(label: Text(c.label)))
                              .toList(),
                          rows: [
                            ...rows.take(100).map((row) => DataRow(
                                cells: columns
                                    .map((c) => DataCell(Text(
                                        DynamicReportDesigner.formatValue(
                                            row[c.key], c, model))))
                                    .toList())),
                            if (model.showTotals)
                              DataRow(
                                  cells: columns
                                      .map((c) => DataCell(Text(
                                            c == columns.first
                                                ? 'TOTAL'
                                                : c.numeric
                                                    ? DynamicReportDesigner
                                                        .formatValue(
                                                            totals[c.key] ?? 0,
                                                            c,
                                                            model)
                                                    : '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          )))
                                      .toList()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (model.showChart && chart.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Grafik ringkas',
                        style: TextStyle(
                            fontSize: model.fontSize + 2,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 120,
                      child: LayoutBuilder(builder: (context, constraints) {
                        final maxValue =
                            chart.first.value == 0 ? 1 : chart.first.value;
                        return Column(
                          children: chart
                              .map((item) => Expanded(
                                    child: Row(children: [
                                      SizedBox(
                                          width: 110,
                                          child: Text(item.key,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 10))),
                                      Container(
                                        height: 8,
                                        width: (constraints.maxWidth - 200) *
                                            (item.value / maxValue),
                                        color: const Color(0xFF176B45),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              NumberFormat('#,##0.##', 'id_ID')
                                                  .format(item.value),
                                              style: const TextStyle(
                                                  fontSize: 10))),
                                    ]),
                                  ))
                              .toList(),
                        );
                      }),
                    ),
                  ],
                  if (model.showFooter)
                    Text(
                        'Preview ${rows.length} baris · ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 10)),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _columns() => ListView(
        padding: const EdgeInsets.all(12),
        children: widget.data.columns
            .map((c) => CheckboxListTile(
                  value: model.selectedColumns.contains(c.key),
                  title: Text(c.label),
                  subtitle: Text(c.numeric
                      ? 'Kolom angka · memiliki total'
                      : 'Kolom teks'),
                  onChanged: (v) => setState(() => v == true
                      ? model.selectedColumns.add(c.key)
                      : model.selectedColumns.remove(c.key)),
                ))
            .toList(),
      );

  Widget _filter() => Padding(
        padding: const EdgeInsets.all(18),
        child: TextFormField(
          initialValue: model.filter,
          decoration: const InputDecoration(
              labelText: 'Cari/penyaringan seluruh data',
              prefixIcon: Icon(Icons.filter_alt_outlined),
              helperText:
                  'Hanya baris yang mengandung teks ini yang ditampilkan dan diekspor.'),
          onChanged: (v) => setState(() => model.filter = v),
        ),
      );

  Widget _group() => Padding(
        padding: const EdgeInsets.all(18),
        child: DropdownButtonFormField<String>(
          value: model.groupBy,
          decoration: const InputDecoration(
              labelText: 'Kelompokkan / urutkan berdasarkan'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Tanpa grup')),
            ...widget.data.columns.map(
                (c) => DropdownMenuItem(value: c.key, child: Text(c.label)))
          ],
          onChanged: (v) => setState(() => model.groupBy = v ?? ''),
        ),
      );

  Widget _headerFooter() =>
      ListView(padding: const EdgeInsets.all(18), children: [
        SwitchListTile(
            value: model.showHeader,
            title: const Text('Tampilkan header laporan'),
            onChanged: (v) => setState(() => model.showHeader = v)),
        TextFormField(
            initialValue: model.company,
            decoration: const InputDecoration(labelText: 'Nama perusahaan'),
            onChanged: (v) => model.company = v),
        const SizedBox(height: 8),
        TextFormField(
            initialValue: model.title,
            decoration: const InputDecoration(labelText: 'Judul laporan'),
            onChanged: (v) => model.title = v),
        const SizedBox(height: 8),
        TextFormField(
            initialValue: model.subtitle,
            decoration:
                const InputDecoration(labelText: 'Subjudul / parameter'),
            onChanged: (v) => model.subtitle = v),
        SwitchListTile(
            value: model.showFooter,
            title: const Text('Tampilkan footer laporan'),
            onChanged: (v) => setState(() => model.showFooter = v)),
        CheckboxListTile(
            value: model.showPrintDate,
            title: const Text('Tanggal cetak'),
            onChanged: (v) => setState(() => model.showPrintDate = v == true)),
        CheckboxListTile(
            value: model.showPageNumber,
            title: const Text('Nomor halaman'),
            onChanged: (v) => setState(() => model.showPageNumber = v == true)),
      ]);

  Widget _page() => ListView(padding: const EdgeInsets.all(18), children: [
        DropdownButtonFormField<String>(
            value: model.paper,
            decoration: const InputDecoration(labelText: 'Ukuran kertas'),
            items: const [
              DropdownMenuItem(value: 'A4', child: Text('A4')),
              DropdownMenuItem(value: 'A3', child: Text('A3')),
              DropdownMenuItem(value: 'Letter', child: Text('Letter'))
            ],
            onChanged: (v) => setState(() => model.paper = v ?? 'A4')),
        SwitchListTile(
            value: model.landscape,
            title: const Text('Orientasi mendatar'),
            subtitle: Text(model.landscape ? 'Landscape' : 'Portrait'),
            onChanged: (v) => setState(() => model.landscape = v)),
        Text('Margin: ${model.marginMm.toStringAsFixed(0)} mm'),
        Slider(
            value: model.marginMm,
            min: 4,
            max: 30,
            divisions: 26,
            onChanged: (v) => setState(() => model.marginMm = v)),
      ]);

  Widget _fontNumber() =>
      ListView(padding: const EdgeInsets.all(18), children: [
        Text('Ukuran huruf: ${model.fontSize.toStringAsFixed(1)} pt'),
        Slider(
            value: model.fontSize,
            min: 6,
            max: 14,
            divisions: 16,
            onChanged: (v) => setState(() => model.fontSize = v)),
        DropdownButtonFormField<int>(
            value: model.decimals,
            decoration:
                const InputDecoration(labelText: 'Angka di belakang koma'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Tanpa desimal')),
              DropdownMenuItem(value: 1, child: Text('1 angka')),
              DropdownMenuItem(value: 2, child: Text('2 angka'))
            ],
            onChanged: (v) => setState(() => model.decimals = v ?? 0)),
        SwitchListTile(
            value: model.parenthesesNegative,
            title: const Text('Angka minus dalam kurung'),
            subtitle: const Text('(500) sebagai pengganti -500'),
            onChanged: (v) => setState(() => model.parenthesesNegative = v)),
      ]);

  Widget _analysis() => ListView(padding: const EdgeInsets.all(18), children: [
        SwitchListTile(
            value: model.showTotals,
            title: const Text('Tampilkan total per kolom angka'),
            onChanged: (v) => setState(() => model.showTotals = v)),
        SwitchListTile(
            value: model.showAnalysis,
            title: const Text('Sertakan ringkasan analisa'),
            onChanged: (v) => setState(() => model.showAnalysis = v)),
        SwitchListTile(
            value: model.showChart,
            title: const Text('Sertakan grafik dalam model laporan'),
            subtitle: const Text('Grafik mengikuti data setelah penyaringan.'),
            onChanged: (v) => setState(() => model.showChart = v)),
      ]);
}
