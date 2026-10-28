import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../widgets/aksi_baris_menu.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');

enum PresetPergerakanStok {
  hariIni('Hari Ini'),
  kemarin('Kemarin'),
  tujuhHari('7 Hari Terakhir'),
  tigaPuluhHari('30 Hari Terakhir'),
  bulanIni('Bulan Ini'),
  bulanLalu('Bulan Lalu'),
  kustom('Kustom');

  final String label;
  const PresetPergerakanStok(this.label);
}

class TabPergerakanStok extends StatefulWidget {
  const TabPergerakanStok({super.key});

  @override
  State<TabPergerakanStok> createState() => _TabPergerakanStokState();
}

class _TabPergerakanStokState extends State<TabPergerakanStok> {
  PresetPergerakanStok _preset = PresetPergerakanStok.bulanIni;
  late DateTime _tglMulai;
  late DateTime _tglSampai;

  final TextEditingController _cariController = TextEditingController();
  bool _memuat = false;
  String? _pesanError;
  List<Map<String, dynamic>> _data = [];
  Map<String, dynamic>? _ringkasanTotal;

  @override
  void initState() {
    super.initState();
    _terapkanPreset(PresetPergerakanStok.bulanIni, panggilMuat: false);
    _muatData();
  }

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  void _terapkanPreset(PresetPergerakanStok preset, {bool panggilMuat = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _preset = preset;

    switch (preset) {
      case PresetPergerakanStok.hariIni:
        _tglMulai = today;
        _tglSampai = today;
        break;
      case PresetPergerakanStok.kemarin:
        final kem = today.subtract(const Duration(days: 1));
        _tglMulai = kem;
        _tglSampai = kem;
        break;
      case PresetPergerakanStok.tujuhHari:
        _tglMulai = today.subtract(const Duration(days: 6));
        _tglSampai = today;
        break;
      case PresetPergerakanStok.tigaPuluhHari:
        _tglMulai = today.subtract(const Duration(days: 29));
        _tglSampai = today;
        break;
      case PresetPergerakanStok.bulanIni:
        _tglMulai = DateTime(now.year, now.month, 1);
        _tglSampai = today;
        break;
      case PresetPergerakanStok.bulanLalu:
        final firstDayThisMonth = DateTime(now.year, now.month, 1);
        final lastDayPrevMonth = firstDayThisMonth.subtract(const Duration(days: 1));
        _tglMulai = DateTime(lastDayPrevMonth.year, lastDayPrevMonth.month, 1);
        _tglSampai = lastDayPrevMonth;
        break;
      case PresetPergerakanStok.kustom:
        break;
    }

    if (panggilMuat) {
      _muatData();
    }
  }

  String _formatTglParam(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
  String _formatTglTampilan(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);

  Future<void> _pilihRentangKustom() async {
    final hasil = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _tglMulai, end: _tglSampai),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (hasil != null) {
      setStateIfMounted(() {
        _preset = PresetPergerakanStok.kustom;
        _tglMulai = hasil.start;
        _tglSampai = hasil.end;
      });
      _muatData();
    }
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_rekap', {
        'dari': _formatTglParam(_tglMulai),
        'sampai': _formatTglParam(_tglSampai),
        'q': _cariController.text.trim(),
        'limit': 300,
      });

      if (!mounted) return;

      final List list = (res['data'] as List?) ?? [];
      final ringkasan = (res['ringkasan'] as Map?)?.cast<String, dynamic>();

      setStateIfMounted(() {
        _data = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _ringkasanTotal = ringkasan;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = 'Gagal memuat pergerakan stok: $e';
      });
    }
  }

  Future<void> _eksporExcel() async {
    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
        'dari': _formatTglParam(_tglMulai),
        'sampai': _formatTglParam(_tglSampai),
        'q': _cariController.text.trim(),
      });

      final b64 = res['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan file.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (res['namaFile'] as String?) ??
          'Pergerakan_Stok_${_formatTglParam(_tglMulai)}_${_formatTglParam(_tglSampai)}.xlsx';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Rekap Pergerakan Stok',
        fileName: namaFile,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File Excel berhasil disimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor Excel: $e')),
      );
    }
  }

  void _bukaDetailProduk(Map<String, dynamic> item) {
    final idProduk = (item['id'] as num?)?.toInt() ?? 0;
    if (idProduk <= 0) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => DialogDetailPergerakanStok(
        idProduk: idProduk,
        namaProduk: (item['nama'] as String?) ?? 'Produk',
        kodeProduk: (item['kode'] as String?) ?? '',
        kategori: (item['kategori'] as String?) ?? '-',
        tglMulai: _tglMulai,
        tglSampai: _tglSampai,
      ),
    );
  }

  Widget _buildSummaryMini(String title, num val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$title: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          Text(
            _formatAngka.format(val),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar
        Card(
          margin: const EdgeInsets.all(12),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Preset Dropdown
                DropdownButton<PresetPergerakanStok>(
                  value: _preset,
                  underline: const SizedBox(),
                  borderRadius: BorderRadius.circular(8),
                  items: PresetPergerakanStok.values.map((p) {
                    return DropdownMenuItem(
                      value: p,
                      child: Text(
                        p.label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    if (val == PresetPergerakanStok.kustom) {
                      _pilihRentangKustom();
                    } else {
                      setStateIfMounted(() {
                        _terapkanPreset(val);
                      });
                    }
                  },
                ),

                // Indikator tanggal
                InkWell(
                  onTap: _pilihRentangKustom,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.date_range, size: 16, color: Colors.blueGrey),
                        const SizedBox(width: 6),
                        Text(
                          '${_formatTglTampilan(_tglMulai)} - ${_formatTglTampilan(_tglSampai)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),

                // Pencarian
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    controller: _cariController,
                    decoration: InputDecoration(
                      hintText: 'Cari produk / kode...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) => _muatData(),
                  ),
                ),

                // Tombol Cari
                ElevatedButton.icon(
                  onPressed: _memuat ? null : _muatData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Cari / Muat'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                // Tombol Unduh Excel
                OutlinedButton.icon(
                  onPressed: _memuat ? null : _eksporExcel,
                  icon: const Icon(Icons.file_download, size: 16, color: Colors.green),
                  label: const Text('Unduh Excel', style: TextStyle(color: Colors.green)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),

                if (_ringkasanTotal != null) ...[
                  _buildSummaryMini('Masuk', (_ringkasanTotal!['masuk'] as num?) ?? 0, Colors.green),
                  _buildSummaryMini('Retur', (_ringkasanTotal!['retur'] as num?) ?? 0, Colors.blue),
                  _buildSummaryMini('Penjualan', (_ringkasanTotal!['penjualan'] as num?) ?? 0, Colors.orange),
                  _buildSummaryMini('Keluar', (_ringkasanTotal!['keluar'] as num?) ?? 0, Colors.red),
                ],
              ],
            ),
          ),
        ),

        // Konten Tabel / Loading / Error
        Expanded(
          child: _memuat
              ? const Center(child: CircularProgressIndicator())
              : _pesanError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 40),
                          const SizedBox(height: 8),
                          Text(_pesanError!),
                          const SizedBox(height: 8),
                          ElevatedButton(onPressed: _muatData, child: const Text('Coba Lagi')),
                        ],
                      ),
                    )
                  : _data.isEmpty
                      ? const Center(child: Text('Tidak ada pergerakan stok pada periode ini.'))
                      : Card(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                                  ),
                                  columnSpacing: 20,
                                  columns: const [
                                    DataColumn(label: Text('Grup', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Produk', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(numeric: true, label: Text('Awal', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(numeric: true, label: Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                    DataColumn(numeric: true, label: Text('Pengembalian', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                    DataColumn(numeric: true, label: Text('Penjualan', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))),
                                    DataColumn(numeric: true, label: Text('Keluar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                                    DataColumn(numeric: true, label: Text('Sisa', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _data.map((item) {
                                    final awal = (item['awal'] as num?)?.toDouble() ?? 0;
                                    final masuk = (item['masuk'] as num?)?.toDouble() ?? 0;
                                    final retur = (item['retur'] as num?)?.toDouble() ?? 0;
                                    final penjualan = (item['penjualan'] as num?)?.toDouble() ?? 0;
                                    final keluar = (item['keluar'] as num?)?.toDouble() ?? 0;
                                    final sisa = (item['sisa'] as num?)?.toDouble() ?? 0;

                                    return DataRow(
                                      onSelectChanged: (_) => _bukaDetailProduk(item),
                                      cells: [
                                        DataCell(Text((item['kategori'] as String?) ?? '-')),
                                        DataCell(
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                (item['nama'] as String?) ?? '-',
                                                style: const TextStyle(fontWeight: FontWeight.w600),
                                              ),
                                              if ((item['kode'] as String?)?.isNotEmpty == true)
                                                Text(
                                                  '${item['kode']}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                            ],
                                          ),
                                        ),
                                        DataCell(Text(_formatAngka.format(awal))),
                                        DataCell(Text(
                                          _formatAngka.format(masuk),
                                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(retur),
                                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(penjualan),
                                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(Text(
                                          _formatAngka.format(keluar),
                                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                        )),
                                        DataCell(
                                          Text(
                                            _formatAngka.format(sisa),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        DataCell(
                                          IconButton(
                                            icon: const Icon(Icons.visibility, size: 18, color: Colors.blue),
                                            tooltip: 'Lihat Buku Besar',
                                            onPressed: () => _bukaDetailProduk(item),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class DialogDetailPergerakanStok extends StatefulWidget {
  final int idProduk;
  final String namaProduk;
  final String kodeProduk;
  final String kategori;
  final DateTime tglMulai;
  final DateTime tglSampai;

  const DialogDetailPergerakanStok({
    super.key,
    required this.idProduk,
    required this.namaProduk,
    required this.kodeProduk,
    required this.kategori,
    required this.tglMulai,
    required this.tglSampai,
  });

  @override
  State<DialogDetailPergerakanStok> createState() => _DialogDetailPergerakanStokState();
}

class _DialogDetailPergerakanStokState extends State<DialogDetailPergerakanStok> {
  bool _memuat = true;
  String? _pesanError;
  Map<String, dynamic>? _ringkasan;
  List<Map<String, dynamic>> _mutasi = [];

  @override
  void initState() {
    super.initState();
    _muatDetail();
  }

  String _formatTglParam(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);
  String _formatTglTampilan(DateTime dt) => DateFormat('dd/MM/yyyy').format(dt);

  Future<void> _muatDetail() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_detail', {
        'id': widget.idProduk,
        'dari': _formatTglParam(widget.tglMulai),
        'sampai': _formatTglParam(widget.tglSampai),
      });

      if (!mounted) return;

      final ringkasanData = (res['ringkasan'] as Map?)?.cast<String, dynamic>();
      final List mutasiList = (res['mutasi'] as List?) ?? [];

      setStateIfMounted(() {
        _ringkasan = ringkasanData;
        _mutasi = mutasiList.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = 'Gagal memuat detail pergerakan: $e';
      });
    }
  }

  Future<void> _eksporExcelProduk() async {
    try {
      final res = await ApiClient.instance.aksi('stok_pergerakan_ekspor_excel', {
        'id': widget.idProduk,
        'dari': _formatTglParam(widget.tglMulai),
        'sampai': _formatTglParam(widget.tglSampai),
      });

      final b64 = res['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan file.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (res['namaFile'] as String?) ??
          'Buku_Besar_${widget.namaProduk}_${_formatTglParam(widget.tglMulai)}.xlsx';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Buku Besar Produk',
        fileName: namaFile,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Buku besar disimpan: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengekspor: $e')),
      );
    }
  }

  Widget _buildSummaryCard(String title, num val, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _formatAngka.format(val),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  /// Saldo pembuka ditampilkan sebagai baris agar cocok dengan format buku besar Al-Bahjah.
  DataRow _barisSaldoAwal(double saldo) => DataRow(cells: [
        const DataCell(Text('1')),
        DataCell(Text('${_formatTglTampilan(widget.tglMulai)} 00:00')),
        const DataCell(Text('SA-001')),
        const DataCell(Text('100')),
        const DataCell(Text('-')),
        const DataCell(Text('Saldo awal')),
        const DataCell(Text('-')),
        const DataCell(Text('-')),
        const DataCell(Text('-')),
        DataCell(Text(_formatAngka.format(saldo),
            style: const TextStyle(fontWeight: FontWeight.bold))),
      ]);

  @override
  Widget build(BuildContext context) {
    final awal = (_ringkasan?['awal'] as num?)?.toDouble() ?? 0;
    final masuk = (_ringkasan?['masuk'] as num?)?.toDouble() ?? 0;
    final retur = (_ringkasan?['retur'] as num?)?.toDouble() ?? 0;
    final penjualan = (_ringkasan?['penjualan'] as num?)?.toDouble() ?? 0;
    final keluar = (_ringkasan?['keluar'] as num?)?.toDouble() ?? 0;
    final sisa = (_ringkasan?['sisa'] as num?)?.toDouble() ?? 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 950, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.namaProduk,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kode: ${widget.kodeProduk.isNotEmpty ? widget.kodeProduk : '-'} | Grup: ${widget.kategori} | Periode: ${_formatTglTampilan(widget.tglMulai)} - ${_formatTglTampilan(widget.tglSampai)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  AksiBarisMenu(tooltip: 'Aksi rincian mutasi', aksi: [
                    AksiBaris(
                      ikon: Icons.file_download_outlined,
                      label: 'Unduh Excel',
                      onTap: _eksporExcelProduk,
                    ),
                    AksiBaris(
                      ikon: Icons.close,
                      label: 'Tutup rincian',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 16),

              // 6 Summary Cards
              Row(
                children: [
                  _buildSummaryCard('Awal', awal, Colors.blueGrey),
                  _buildSummaryCard('Masuk', masuk, Colors.green),
                  _buildSummaryCard('Pengembalian', retur, Colors.blue),
                  _buildSummaryCard('Penjualan', penjualan, Colors.orange),
                  _buildSummaryCard('Keluar', keluar, Colors.red),
                  _buildSummaryCard('Sisa', sisa, Colors.indigo),
                ],
              ),
              const SizedBox(height: 16),

              // Tabel Rincian Buku Besar Mutasi
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _pesanError != null
                        ? Center(child: Text(_pesanError!, style: const TextStyle(color: Colors.red)))
                        : _ringkasan == null
                            ? const Center(child: Text('Belum ada catatan mutasi transaksi pada rentang ini.'))
                            : Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                                        columnSpacing: 24,
                                        columns: const [
                                          DataColumn(label: Text('No', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Tanggal & jam', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('No Faktur', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('kode mutasi', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('ID Pelanggan', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(label: Text('Nama Pelanggan', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(numeric: true, label: Text('Saldo sebelum', style: TextStyle(fontWeight: FontWeight.bold))),
                                          DataColumn(numeric: true, label: Text('Masuk', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                                          DataColumn(numeric: true, label: Text('Keluar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                                          DataColumn(numeric: true, label: Text('Saldo', style: TextStyle(fontWeight: FontWeight.bold))),
                                        ],
                                        rows: [
                                          _barisSaldoAwal(awal),
                                          ..._mutasi.asMap().entries.map((entry) {
                                          final idx = entry.key + 2;
                                          final m = entry.value;
                                          final tAwal = (m['awal'] as num?)?.toDouble() ?? 0;
                                          final tMasuk = (m['masuk'] as num?)?.toDouble() ?? 0;
                                          final tKeluar = (m['keluar'] as num?)?.toDouble() ?? 0;
                                          final tSisa = (m['sisa'] as num?)?.toDouble() ?? 0;
                                          final tipe = (m['tipe'] as String?) ?? '';
                                          final ref = (m['referensi'] as String?) ?? '';
                                          final kodeMutasi = (m['kodeMutasi'] as String?) ?? '000';
                                          final idPel = (m['idPelanggan'] as String?) ?? '';
                                          final namaPel = (m['namaPelanggan'] as String?) ?? '';

                                          Color badgeColor = Colors.grey.shade700;
                                          if (tipe.contains('Penjualan')) {
                                            badgeColor = Colors.orange.shade800;
                                          } else if (tipe.contains('Pembelian')) {
                                            badgeColor = Colors.green.shade800;
                                          } else if (tipe.contains('Retur')) {
                                            badgeColor = Colors.blue.shade800;
                                          } else if (tipe.contains('Opname') ||
                                              tipe.contains('Penyesuaian')) {
                                            badgeColor = Colors.purple.shade800;
                                          }

                                          return DataRow(
                                            cells: [
                                              DataCell(Text('$idx')),
                                              DataCell(Text((m['tanggal'] as String?) ?? '-')),
                                              DataCell(Text(ref.isEmpty ? '-' : ref)),
                                              DataCell(Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: badgeColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  kodeMutasi,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: badgeColor,
                                                  ),
                                                ),
                                              )),
                                              DataCell(Text(idPel.isEmpty ? '-' : idPel)),
                                              DataCell(Text(namaPel.isNotEmpty ? namaPel : (tipe.isNotEmpty ? tipe : '-'))),
                                              DataCell(Text(_formatAngka.format(tAwal))),
                                              DataCell(Text(
                                                tMasuk > 0 ? '+${_formatAngka.format(tMasuk)}' : '-',
                                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                              )),
                                              DataCell(Text(
                                                tKeluar > 0 ? '-${_formatAngka.format(tKeluar)}' : '-',
                                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                              )),
                                              DataCell(Text(
                                                _formatAngka.format(tSisa),
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              )),
                                            ],
                                          );
                                        }),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
              ),
              const SizedBox(height: 12),

            ],
          ),
        ),
      ),
    );
  }
}
