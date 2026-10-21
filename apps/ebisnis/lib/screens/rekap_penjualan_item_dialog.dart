import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../app_variant.dart';
import '../services/pengaturan_struk.dart';
import '../services/print_util.dart';
import '../services/rekap_penjualan_item_pdf.dart';
import '../services/simple_xlsx.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../widgets/penanda_data_tersimpan.dart';

final _formatRupiahDialog =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngkaDialog = NumberFormat.decimalPattern('id_ID');

/// Dialog Rekap Penjualan Item / Produk Harian langsung di POS Kasir
/// (Permintaan Mbak Nia TokoQu Cirebon 1).
class RekapPenjualanItemDialog extends StatefulWidget {
  final DateTime? tanggalAwal;

  const RekapPenjualanItemDialog({super.key, this.tanggalAwal});

  static Future<void> tampilkan(BuildContext context,
      {DateTime? tanggal}) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => RekapPenjualanItemDialog(tanggalAwal: tanggal),
    );
  }

  @override
  State<RekapPenjualanItemDialog> createState() =>
      _RekapPenjualanItemDialogState();
}

class _RekapPenjualanItemDialogState extends State<RekapPenjualanItemDialog> {
  late DateTime _tanggal;
  final TextEditingController _cariController = TextEditingController();
  bool _hanyaKasirSaya = false;

  bool _memuat = true;
  bool _sedangCetak = false;
  String? _pesanError;
  bool _dariCache = false;
  DateTime? _cacheDisimpanPada;

  Map<String, dynamic>? _laporan;
  List<Map<String, dynamic>> _daftarItem = [];

  @override
  void initState() {
    super.initState();
    _tanggal = widget.tanggalAwal ?? DateTime.now();
    _muatData();
  }

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  String get _tglFormatted => DateFormat('yyyy-MM-dd').format(_tanggal);
  String get _tglTampilan => DateFormat('dd/MM/yyyy').format(_tanggal);

  Future<void> _muatData() async {
    var adaCache = false;
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      final payload = <String, dynamic>{
        'tanggal': _tglFormatted,
        'keyword': _cariController.text.trim(),
      };
      if (_hanyaKasirSaya) {
        payload['kasir'] = Sesi.instance.userId;
      }

      // Laporan adalah satu amplop agregat. Tampilkan salinan perangkat lebih
      // dahulu; kunci memisahkan varian, tenant, akun, tanggal, kasir, dan kata
      // pencarian agar laporan antar pengguna tidak pernah tercampur.
      final cacheKey = kunciCacheRekapPenjualanItem(payload);
      try {
        final tersimpan = await CoreDb.instance.ambilCacheReferensi(cacheKey);
        if (tersimpan != null) {
          final lokal = jsonDecode(tersimpan) as Map<String, dynamic>;
          adaCache = true;
          final stempel = DateTime.tryParse('${lokal['_disimpanPada'] ?? ''}');
          setStateIfMounted(() {
            _laporan = lokal;
            _daftarItem = ((lokal['data'] as List?) ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _dariCache = true;
            _cacheDisimpanPada = stempel;
            _memuat = false;
          });
        }
      } catch (_) {
        // Kegagalan membaca salinan lokal tidak boleh menghalangi penyegaran.
        adaCache = false;
      }
      if (!adaCache) {
        setStateIfMounted(() {
          _laporan = null;
          _daftarItem = [];
          _dariCache = false;
          _cacheDisimpanPada = null;
        });
      }

      final res =
          await ApiClient.instance.aksi('penjualan_item_harian', payload);

      if (!mounted) return;

      final List rawList = (res['data'] as List?) ?? [];
      setStateIfMounted(() {
        _laporan = res;
        _daftarItem = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _memuat = false;
        _dariCache = false;
        _cacheDisimpanPada = null;
      });
      try {
        await CoreDb.instance.simpanCacheReferensi(
          cacheKey,
          jsonEncode(
              {...res, '_disimpanPada': DateTime.now().toIso8601String()}),
        );
      } catch (_) {
        // Laporan yang sudah berhasil dimuat tetap tampil walau cache gagal.
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.offline && adaCache) {
        setStateIfMounted(() {
          _memuat = false;
          _dariCache = true;
        });
        return;
      }
      setStateIfMounted(() {
        _memuat = false;
        _pesanError = e is ApiException && e.offline
            ? 'Belum ada salinan laporan untuk tanggal ini. Sambungkan ke jaringan lalu muat kembali.'
            : 'Gagal memuat rekap penjualan: $e';
      });
    }
  }

  Future<void> _pilihTanggal() async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (hasil != null && hasil != _tanggal) {
      setStateIfMounted(() {
        _tanggal = hasil;
      });
      _muatData();
    }
  }

  Future<void> _cetakStrukThermal() async {
    if (_laporan == null || _daftarItem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak ada data penjualan untuk dicetak.')),
      );
      return;
    }

    setStateIfMounted(() => _sedangCetak = true);
    try {
      await PengaturanStruk.instance.muat();
      final (dokumen, format) = await buatPdfRekapPenjualanItemThermal(
        _laporan!,
        lebarMm: PengaturanStruk.instance.lebarKertasMm,
      );

      await cetakLangsungKePrinterDefault(
        dokumen: dokumen,
        nama: 'Rekap Penjualan Item $_tglFormatted',
        format: format,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rekap penjualan berhasil dikirim ke printer kasir.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mencetak ke printer: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setStateIfMounted(() => _sedangCetak = false);
    }
  }

  Future<void> _cetakLaporanPdf() async {
    if (_laporan == null || _daftarItem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tidak ada data penjualan untuk dicetak.')),
      );
      return;
    }

    setStateIfMounted(() => _sedangCetak = true);
    try {
      final doc = await buatPdfRekapPenjualanItemA4(_laporan!);
      await cetakPdfDenganDialogOs(
        dokumen: doc,
        nama: 'Laporan_Penjualan_Item_$_tglFormatted.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak dokumen: $e')),
      );
    } finally {
      if (mounted) setStateIfMounted(() => _sedangCetak = false);
    }
  }

  Future<void> _unduhExcel() async {
    try {
      final laporan = _laporan;
      if (laporan == null) {
        throw StateError('Muat laporan terlebih dahulu sebelum mengunduh.');
      }
      final data = ((laporan['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final rows = <List<Object?>>[
        ['Tanggal', laporan['tanggal'] ?? _tglFormatted],
        ['Toko', laporan['tokoNama'] ?? ''],
        ['Kasir', laporan['kasirNama'] ?? ''],
        [],
        [
          'Kode',
          'Produk',
          'Kategori',
          'Satuan',
          'Transaksi',
          'Qty',
          'Harga Rata-rata',
          'Diskon',
          'Total'
        ],
        ...data.map((item) => <Object?>[
              item['kode'] ?? '',
              item['nama'] ?? '',
              item['kategori'] ?? '',
              item['satuan'] ?? '',
              item['jumlahTransaksi'] ?? 0,
              item['qty'] ?? 0,
              item['hargaRata'] ?? 0,
              item['diskon'] ?? 0,
              item['total'] ?? 0,
            ]),
      ];
      final bytes = buildSimpleXlsxReport(
        sheetName: 'Penjualan Item',
        rows: rows,
        boldRows: const {1, 2, 3, 5},
        columnWidths: const [14, 34, 20, 12, 14, 12, 18, 16, 18],
      );
      final namaFile = 'Rekap_Penjualan_Item_$_tglFormatted.xlsx';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Rekap Penjualan Item Excel',
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

  Widget _buildCardRingkasan(String judul, num nilai, Color warna,
      {bool formatRupiah = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: warna.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              judul,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatRupiah
                  ? _formatRupiahDialog.format(nilai)
                  : _formatAngkaDialog.format(nilai),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: warna,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ringkasan =
        (_laporan?['ringkasan'] as Map?)?.cast<String, dynamic>() ?? {};
    final totalItem = (ringkasan['totalItem'] as num?)?.toInt() ?? 0;
    final totalQty = (ringkasan['totalQty'] as num?)?.toDouble() ?? 0;
    final totalPenjualan =
        (ringkasan['totalPenjualan'] as num?)?.toDouble() ?? 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Dialog
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.receipt_long,
                                color: AppColors.primary, size: 24),
                            const SizedBox(width: 8),
                            const Text(
                              'Rekap Penjualan Item / Produk Harian',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pantau seluruh barang yang terjual di kasir dan cetak langsung struk rekap harian.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PenandaDataTersimpan(
                  tampil: _dariCache, diperbaruiPada: _cacheDisimpanPada),

              // Toolbar Filter & Tanggal
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Tombol Hari Ini
                  ChoiceChip(
                    label: const Text('Hari Ini'),
                    selected: DateUtils.isSameDay(_tanggal, DateTime.now()),
                    onSelected: (val) {
                      if (val) {
                        setStateIfMounted(() => _tanggal = DateTime.now());
                        _muatData();
                      }
                    },
                  ),

                  // Tombol Kemarin
                  ChoiceChip(
                    label: const Text('Kemarin'),
                    selected: DateUtils.isSameDay(
                      _tanggal,
                      DateTime.now().subtract(const Duration(days: 1)),
                    ),
                    onSelected: (val) {
                      if (val) {
                        setStateIfMounted(() => _tanggal =
                            DateTime.now().subtract(const Duration(days: 1)));
                        _muatData();
                      }
                    },
                  ),

                  // Tombol Pilih Tanggal
                  OutlinedButton.icon(
                    onPressed: _pilihTanggal,
                    icon: const Icon(Icons.calendar_today, size: 15),
                    label: Text(_tglTampilan),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                  ),

                  // Filter Kasir Saya
                  FilterChip(
                    label: const Text('Hanya Kasir Saya'),
                    selected: _hanyaKasirSaya,
                    onSelected: (val) {
                      setStateIfMounted(() => _hanyaKasirSaya = val);
                      _muatData();
                    },
                  ),

                  // Pencarian Item
                  SizedBox(
                    width: 200,
                    height: 36,
                    child: TextField(
                      controller: _cariController,
                      decoration: InputDecoration(
                        hintText: 'Cari nama / kode...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) => _muatData(),
                    ),
                  ),

                  // Tombol Cari/Segarkan
                  ElevatedButton.icon(
                    onPressed: _memuat ? null : _muatData,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Muat'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 3 Card Ringkasan
              Row(
                children: [
                  _buildCardRingkasan(
                      'TOTAL PENJUALAN', totalPenjualan, Colors.green.shade800,
                      formatRupiah: true),
                  _buildCardRingkasan(
                      'TOTAL QTY TERJUAL', totalQty, Colors.blue.shade800),
                  _buildCardRingkasan(
                      'JUMLAH JENIS PRODUK', totalItem, Colors.indigo.shade800),
                ],
              ),
              const SizedBox(height: 12),

              // Tabel Data
              Expanded(
                child: _memuat
                    ? const Center(child: CircularProgressIndicator())
                    : _pesanError != null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.red, size: 36),
                                const SizedBox(height: 6),
                                Text(_pesanError!),
                                const SizedBox(height: 6),
                                ElevatedButton(
                                    onPressed: _muatData,
                                    child: const Text('Coba Lagi')),
                              ],
                            ),
                          )
                        : _daftarItem.isEmpty
                            ? const Center(
                                child: Text(
                                    'Belum ada transaksi penjualan produk pada tanggal ini.'))
                            : Container(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                                Colors.grey.shade100),
                                        columnSpacing: 18,
                                        columns: const [
                                          DataColumn(
                                              label: Text('No',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Produk',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              label: Text('Kategori',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Qty Terjual',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.green))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Harga Rata-rata',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Diskon',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                          DataColumn(
                                              numeric: true,
                                              label: Text('Total Omzet (Rp)',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.indigo))),
                                        ],
                                        rows: _daftarItem
                                            .asMap()
                                            .entries
                                            .map((entry) {
                                          final idx = entry.key + 1;
                                          final item = entry.value;
                                          final qty = (item['qty'] as num?)
                                                  ?.toDouble() ??
                                              0;
                                          final harga =
                                              (item['hargaRata'] as num?)
                                                      ?.toDouble() ??
                                                  0;
                                          final diskon =
                                              (item['diskon'] as num?)
                                                      ?.toDouble() ??
                                                  0;
                                          final total = (item['total'] as num?)
                                                  ?.toDouble() ??
                                              0;

                                          return DataRow(
                                            cells: [
                                              DataCell(Text('$idx')),
                                              DataCell(
                                                Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      (item['nama']
                                                              as String?) ??
                                                          '-',
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600),
                                                    ),
                                                    if ((item['kode']
                                                                as String?)
                                                            ?.isNotEmpty ==
                                                        true)
                                                      Text(
                                                        'Kode: ${item['kode']}',
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: Colors
                                                                .grey.shade600),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              DataCell(Text((item['kategori']
                                                      as String?) ??
                                                  '-')),
                                              DataCell(Text(
                                                '${_formatAngkaDialog.format(qty)} ${(item['satuan'] as String?) ?? 'Pcs'}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green),
                                              )),
                                              DataCell(Text(_formatRupiahDialog
                                                  .format(harga))),
                                              DataCell(Text(diskon > 0
                                                  ? _formatRupiahDialog
                                                      .format(diskon)
                                                  : '-')),
                                              DataCell(Text(
                                                _formatRupiahDialog
                                                    .format(total),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.indigo),
                                              )),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
              ),
              const SizedBox(height: 14),

              // Baris Tombol Aksi Bawah (Cetak Struk, Print A4, Unduh Excel, Tutup)
              Row(
                children: [
                  // Tombol Cetak Struk POS Thermal (58mm / 80mm)
                  ElevatedButton.icon(
                    onPressed: (_memuat || _sedangCetak || _daftarItem.isEmpty)
                        ? null
                        : _cetakStrukThermal,
                    icon: _sedangCetak
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print, size: 18),
                    label: const Text('Print Struk POS (Kasir)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tombol Cetak Laporan PDF / A4
                  OutlinedButton.icon(
                    onPressed: (_memuat || _sedangCetak || _daftarItem.isEmpty)
                        ? null
                        : _cetakLaporanPdf,
                    icon: const Icon(Icons.picture_as_pdf,
                        size: 18, color: Colors.red),
                    label: const Text('Print PDF / A4',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tombol Unduh Excel
                  OutlinedButton.icon(
                    onPressed:
                        (_memuat || _daftarItem.isEmpty) ? null : _unduhExcel,
                    icon: const Icon(Icons.file_download,
                        size: 18, color: Colors.green),
                    label: const Text('Unduh Excel',
                        style: TextStyle(color: Colors.green)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),

                  const Spacer(),

                  // Tombol Tutup
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
String kunciCacheRekapPenjualanItem(Map<String, dynamic> parameter) {
  final sesi = Sesi.instance;
  final tenant = sesi.tenantId;
  final akun = sesi.userId.trim().toLowerCase();
  if (tenant == null || tenant <= 0 || akun.isEmpty) {
    throw StateError('Konteks toko dan akun wajib aktif untuk membaca rekap.');
  }
  final urut = <String, dynamic>{};
  for (final k in parameter.keys.toList()..sort()) {
    urut[k] = parameter[k];
  }
  final encoded =
      base64Url.encode(utf8.encode(jsonEncode(urut))).replaceAll('=', '');
  return 'laporan:penjualan_item:${AppVariant.storageNamespace}:'
      'tenant-$tenant:user-$akun:$encoded';
}
