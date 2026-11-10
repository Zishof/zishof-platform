import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_data_table.dart';
import '../widgets/safe_state.dart';

/// Tab PKM (Penentuan Kuantitas Maksimum & Rekomendasi Purchase Order)
///
/// Mengacu pada SOP Manajemen Ritel TokoQu (Knowledge Sharing Halaman 10 & Format PKM.xlsx):
/// Rumus Baku:
///   PKM = AVG * (LT + SS) + Minor
///   PO  = PKM - STOK_AKHIR
///
/// Keterangan:
/// - AVG: Average Sales/Day (Rata-rata penjualan harian dari tren 3 bulan terakhir).
/// - LT: Lead Time (Waktu tunggu pengiriman pemasok, default 3 hari).
/// - SS: Safety Stock (Cadangan stok pengaman, default 2 hari).
/// - Minor: Minimum Order (Kelipatan pemesanan terkecil pemasok).
/// - PO: Rekomendasi kuantitas yang wajib diorder agar stok tidak kosong maupun overstock.
class TabPkmKuantitasMaksimum extends StatefulWidget {
  const TabPkmKuantitasMaksimum({super.key});

  @override
  State<TabPkmKuantitasMaksimum> createState() => _TabPkmKuantitasMaksimumState();
}

class _TabPkmKuantitasMaksimumState extends State<TabPkmKuantitasMaksimum> {
  final _formatAngka = NumberFormat('#,##0.##', 'id_ID');
  final _formatRupiah = NumberFormat.currency(
      locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  bool _mengunduh = false;
  String? _pesanError;

  List<Map<String, dynamic>> _semuaProduk = [];
  List<Map<String, dynamic>> _filteredProduk = [];

  final TextEditingController _cariController = TextEditingController();
  final TextEditingController _ltController = TextEditingController(text: '3');
  final TextEditingController _ssController = TextEditingController(text: '2');
  final TextEditingController _minorController = TextEditingController(text: '1');
  final TextEditingController _hariKerjaController = TextEditingController(text: '69');

  String _kategoriTerpilih = '';
  List<String> _daftarKategori = [];
  String _filterStatus = 'SEMUA'; // SEMUA, REORDER, AMAN, KOSONG

  int _totalPerluOrder = 0;
  double _totalEstBiayaPo = 0;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  @override
  void dispose() {
    _cariController.dispose();
    _ltController.dispose();
    _ssController.dispose();
    _minorController.dispose();
    _hariKerjaController.dispose();
    super.dispose();
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final tokoId = Sesi.instance.idTokoTerpilih;
      final payload = {
        'action': 'pkm_daftar',
        if (tokoId != null && tokoId > 0) 'toko_id': tokoId,
        'leadTime': double.tryParse(_ltController.text) ?? 3.0,
        'safetyStock': double.tryParse(_ssController.text) ?? 2.0,
        'minimumOrder': double.tryParse(_minorController.text) ?? 1.0,
        'hariKerja': int.tryParse(_hariKerjaController.text) ?? 69,
      };

      final res = await ApiClient.instance.post('pos', payload);
      if (res['status'] == '00') {
        final list = (res['data'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        final Set<String> katSet = {};
        for (final p in list) {
          final k = (p['kategori'] ?? '').toString().trim();
          if (k.isNotEmpty) katSet.add(k);
        }

        final katList = katSet.toList()..sort();

        setStateIfMounted(() {
          _semuaProduk = list;
          _daftarKategori = katList;
          _totalPerluOrder = (res['totalPerluOrder'] as num?)?.toInt() ?? 0;
          _totalEstBiayaPo = (res['totalEstBiayaPo'] as num?)?.toDouble() ?? 0.0;
          _memuat = false;
        });
        _terapkanFilter();
      } else {
        setStateIfMounted(() {
          _pesanError = res['description']?.toString() ?? 'Gagal memuat data PKM.';
          _memuat = false;
        });
      }
    } catch (e) {
      setStateIfMounted(() {
        _pesanError = 'Gagal terhubung ke server: $e';
        _memuat = false;
      });
    }
  }

  void _terapkanFilter() {
    final query = _cariController.text.trim().toLowerCase();
    final hasil = _semuaProduk.where((p) {
      if (query.isNotEmpty) {
        final nama = (p['nama'] ?? '').toString().toLowerCase();
        final kode = (p['kode'] ?? '').toString().toLowerCase();
        final barcode = (p['barcode'] ?? '').toString().toLowerCase();
        if (!nama.contains(query) && !kode.contains(query) && !barcode.contains(query)) {
          return false;
        }
      }
      if (_kategoriTerpilih.isNotEmpty) {
        final kat = (p['kategori'] ?? '').toString();
        if (kat != _kategoriTerpilih) return false;
      }
      if (_filterStatus != 'SEMUA') {
        final status = (p['statusStok'] ?? '').toString();
        if (_filterStatus == 'REORDER' && (p['rekomendasiPo'] as num? ?? 0) <= 0) return false;
        if (_filterStatus == 'KOSONG' && (p['stokSistem'] as num? ?? 0) > 0) return false;
        if (_filterStatus == 'AMAN' && status != 'AMAN') return false;
      }
      return true;
    }).toList();

    setStateIfMounted(() {
      _filteredProduk = hasil;
    });
  }

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengunduh = true);
    try {
      final tokoId = Sesi.instance.idTokoTerpilih;
      final payload = {
        'action': 'pkm_download_excel',
        if (tokoId != null && tokoId > 0) 'toko_id': tokoId,
        'leadTime': double.tryParse(_ltController.text) ?? 3.0,
        'safetyStock': double.tryParse(_ssController.text) ?? 2.0,
        'minimumOrder': double.tryParse(_minorController.text) ?? 1.0,
        'hariKerja': int.tryParse(_hariKerjaController.text) ?? 69,
      };

      final res = await ApiClient.instance.post('pos', payload);
      if (res['status'] == '00') {
        final base64Str = res['fileBase64'] as String;
        final namaFile = res['namaFile'] as String? ?? 'Format-PKM-TokoQu.xlsx';
        final bytes = base64Decode(base64Str);

        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Lembar Kerja PKM Excel',
          fileName: namaFile,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (result != null) {
          final file = File(result);
          await file.writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Format PKM berhasil disimpan di $result'),
                backgroundColor: Colors.green.shade700,
              ),
            );
          }
        }
      } else {
        throw Exception(res['description'] ?? 'Gagal mengunduh Excel');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal unduh: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setStateIfMounted(() => _mengunduh = false);
    }
  }

  Future<void> _cetakPdf() async {
    final doc = pw.Document();
    final items = _filteredProduk;
    final tokoNama = Sesi.instance.tenantNama.isNotEmpty
        ? Sesi.instance.tenantNama
        : 'Toko Al-Bahjah';

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('ANALISIS PKM & REKOMENDASI PURCHASE ORDER (PO)',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Toko: $tokoNama · Rumus: PKM = AVG*(LT+SS)+Minor | PO = PKM - Stok',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.Text(
                'Tanggal Cetak: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
      build: (ctx) => [
        pw.TableHelper.fromTextArray(
          headers: [
            'NO',
            'KODE',
            'NAMA BARANG',
            'KATEGORI',
            'TOTAL JUAL (3 BLN)',
            'AVG SALES/HARI',
            'STOK TOKO',
            'PKM (MAX)',
            'SARAN PO',
            'EST. BIAYA PO',
            'STATUS',
          ],
          data: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final p = entry.value;
            final po = (p['rekomendasiPo'] as num?)?.toDouble() ?? 0.0;
            final biaya = (p['estimasiBiayaPo'] as num?)?.toDouble() ?? 0.0;
            return [
              idx.toString(),
              (p['kode'] ?? '').toString(),
              (p['nama'] ?? '').toString(),
              (p['kategori'] ?? '').toString(),
              _formatAngka.format(p['totalJual'] ?? 0),
              _formatAngka.format(p['avgSales'] ?? 0),
              _formatAngka.format(p['stokSistem'] ?? 0),
              _formatAngka.format(p['pkm'] ?? 0),
              po > 0 ? _formatAngka.format(po) : '-',
              biaya > 0 ? _formatRupiah.format(biaya) : '-',
              (p['statusStok'] ?? '').toString(),
            ];
          }).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: {
            0: pw.Alignment.center,
            4: pw.Alignment.centerRight,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
            8: pw.Alignment.centerRight,
            9: pw.Alignment.centerRight,
            10: pw.Alignment.center,
          },
        ),
      ],
    ));

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Rekomendasi_PKM_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Baris Parameter & Tombol Aksi
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _cariController,
                      decoration: InputDecoration(
                        hintText: 'Cari produk / barcode...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => _terapkanFilter(),
                    ),
                  ),
                  if (_daftarKategori.isNotEmpty)
                    DropdownButton<String>(
                      value: _kategoriTerpilih.isEmpty ? null : _kategoriTerpilih,
                      hint: const Text('Semua Kategori'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('Semua Kategori')),
                        ..._daftarKategori.map((k) =>
                            DropdownMenuItem(value: k, child: Text(k))),
                      ],
                      onChanged: (val) {
                        setStateIfMounted(() => _kategoriTerpilih = val ?? '');
                        _terapkanFilter();
                      },
                    ),
                  DropdownButton<String>(
                    value: _filterStatus,
                    items: const [
                      DropdownMenuItem(value: 'SEMUA', child: Text('Semua Status')),
                      DropdownMenuItem(value: 'REORDER', child: Text('Wajib Reorder (PO > 0)')),
                      DropdownMenuItem(value: 'KOSONG', child: Text('Stok Kosong (0)')),
                      DropdownMenuItem(value: 'AMAN', child: Text('Stok Aman')),
                    ],
                    onChanged: (val) {
                      setStateIfMounted(() => _filterStatus = val ?? 'SEMUA');
                      _terapkanFilter();
                    },
                  ),
                ],
              ),
            ),
            AksiBarisMenu(
              tooltip: 'Aksi PKM',
              aksi: [
                AksiBaris(
                  ikon: Icons.refresh,
                  label: 'Hitung Ulang PKM',
                  onTap: _memuat ? null : _muatData,
                ),
                AksiBaris(
                  ikon: Icons.download_outlined,
                  label: 'Unduh Excel Format PKM (Resmi)',
                  onTap: _mengunduh ? null : _unduhExcel,
                ),
                AksiBaris(
                  ikon: Icons.picture_as_pdf_outlined,
                  label: 'Cetak Rekomendasi PO (PDF)',
                  onTap: _filteredProduk.isEmpty ? null : _cetakPdf,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Banner Penjelasan Rumus PKM & Knowledge Sharing
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            border: Border.all(color: const Color(0xFF93C5FD)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.calculate_outlined, color: Color(0xFF1D4ED8), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Penentuan Kuantitas Maksimum (PKM) — Standar Manajemen Ritel TokoQu',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Rumus Baku: PKM = AVG × (LT + SS) + Minor  |  PO = PKM − Stok Akhir\n'
                '• AVG: Penjualan harian 3 bulan terakhir (Hari Aktif dikurangi Stock Out)\n'
                '• LT (Lead Time): Waktu tunggu kirim vendor  |  SS: Safety Stock cadangan  |  Minor: Minimal order vendor',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Pengaturan Variabel Cepat (Lead Time, Safety Stock, Minor, Hari Kerja)
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Parameter Kalkulasi:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _ltController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Lead Time (Hari)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _ssController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Safety Stock (Hari)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _minorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minor Order',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _hariKerjaController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Hari Kerja (Bln)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _memuat ? null : _muatData,
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Terapkan & Hitung Ulang'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Ringkasan Kartu
        Row(
          children: [
            Expanded(
              child: _kartuInfo(
                judul: 'Total Produk Dianalisis',
                nilai: _formatAngka.format(_semuaProduk.length),
                sub: 'Item aktif di katalog toko',
                warna: Colors.blue.shade700,
                latar: Colors.blue.shade50,
                ikon: Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kartuInfo(
                judul: 'Produk Perlu Reorder',
                nilai: '$_totalPerluOrder Item',
                sub: 'Stok di bawah batas PKM',
                warna: Colors.orange.shade800,
                latar: Colors.orange.shade50,
                ikon: Icons.warning_amber_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kartuInfo(
                judul: 'Estimasi Kebutuhan Biaya PO',
                nilai: _formatRupiah.format(_totalEstBiayaPo),
                sub: 'Total modal kerja kulakan',
                warna: Colors.green.shade800,
                latar: Colors.green.shade50,
                ikon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tabel Data PKM
        if (_memuat)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_pesanError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                  const SizedBox(height: 12),
                  Text(_pesanError!, style: TextStyle(color: Colors.red.shade700)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _muatData,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            ),
          )
        else
          AppDataTable(
            kolom: const [
              DataColumn(label: Text('KODE / BARCODE')),
              DataColumn(label: Text('NAMA BARANG')),
              DataColumn(label: Text('KATEGORI')),
              DataColumn(label: Text('TOTAL JUAL (3 BLN)', textAlign: TextAlign.right)),
              DataColumn(label: Text('AVG SALES/HARI', textAlign: TextAlign.right)),
              DataColumn(label: Text('STOK TOKO', textAlign: TextAlign.right)),
              DataColumn(label: Text('PKM (MAX)', textAlign: TextAlign.right)),
              DataColumn(label: Text('SARAN PO', textAlign: TextAlign.right)),
              DataColumn(label: Text('EST. BIAYA PO', textAlign: TextAlign.right)),
              DataColumn(label: Text('STATUS')),
            ],
            baris: _filteredProduk.map((p) {
              final po = (p['rekomendasiPo'] as num?)?.toDouble() ?? 0.0;
              final stok = (p['stokSistem'] as num?)?.toDouble() ?? 0.0;
              final pkm = (p['pkm'] as num?)?.toDouble() ?? 0.0;
              final biaya = (p['estimasiBiayaPo'] as num?)?.toDouble() ?? 0.0;

              Color chipBg = Colors.grey.shade100;
              Color chipFg = Colors.grey.shade800;
              String statusLabel = 'AMAN';

              if (stok <= 0) {
                chipBg = Colors.red.shade100;
                chipFg = Colors.red.shade800;
                statusLabel = 'HABIS';
              } else if (po > 0) {
                chipBg = Colors.orange.shade100;
                chipFg = Colors.orange.shade900;
                statusLabel = 'REORDER';
              } else {
                chipBg = Colors.green.shade100;
                chipFg = Colors.green.shade800;
                statusLabel = 'CUKUP';
              }

              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text((p['kode'] ?? '').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if ((p['barcode'] ?? '').toString().isNotEmpty)
                          Text((p['barcode'] ?? '').toString(),
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  DataCell(Text((p['nama'] ?? '-').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text((p['kategori'] ?? '-').toString())),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(_formatAngka.format(p['totalJual'] ?? 0)),
                  )),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(_formatAngka.format(p['avgSales'] ?? 0),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(_formatAngka.format(stok),
                        style: TextStyle(
                            color: stok <= 0 ? Colors.red.shade700 : null,
                            fontWeight: FontWeight.w600)),
                  )),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(_formatAngka.format(pkm),
                        style: const TextStyle(
                            color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                  )),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: po > 0 ? Colors.orange.shade100 : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        po > 0 ? _formatAngka.format(po) : '0',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: po > 0 ? Colors.orange.shade900 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  )),
                  DataCell(Align(
                    alignment: Alignment.centerRight,
                    child: Text(biaya > 0 ? _formatRupiah.format(biaya) : '-'),
                  )),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold, color: chipFg),
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _kartuInfo({
    required String judul,
    required String nilai,
    required String sub,
    required Color warna,
    required Color latar,
    required IconData ikon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: latar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: warna.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ikon, color: warna, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                const SizedBox(height: 2),
                Text(nilai,
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: warna)),
                const SizedBox(height: 2),
                Text(sub, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
