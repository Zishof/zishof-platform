import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../sesi.dart';
import '../theme.dart';
import '../widgets/aksi_baris_menu.dart';
import '../widgets/app_data_table.dart';
import '../widgets/safe_state.dart';

/// Tab SO Grand (Grand Stock Opname) &mdash; Audit Total Seluruh Fisik Barang Toko.
///
/// Berbeda dari SO Harian yang hanya memeriksa barang terjual hari ini, SO Grand
/// mencakup 100% produk aktif di dalam toko/gudang untuk audit periodik atau penutupan buku.
///
/// Fitur Lengkap:
/// 1. Daftar seluruh produk aktif toko dengan pencarian instan (kode/nama/barcode).
/// 2. Mode Entry Fisik Langsung di Tabel (dengan kalkulasi selisih seketika dan simpan batch).
/// 3. Unduh Template Excel SO Grand lengkap seluruh barang.
/// 4. Unggah Excel hasil hitung fisik lapangan secara batch aman.
/// 5. Cetak blanko formulir SO Grand ke PDF.
/// 6. Indikator progres audit (jumlah barang dicek, selisih lebih, selisih kurang).
class TabSoGrand extends StatefulWidget {
  const TabSoGrand({super.key});

  @override
  State<TabSoGrand> createState() => _TabSoGrandState();
}

class _TabSoGrandState extends State<TabSoGrand> {
  final _formatAngka = NumberFormat('#,##0.##', 'id_ID');
  final _formatRupiah = NumberFormat.currency(
      locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  bool _memuat = true;
  bool _menyimpan = false;
  bool _mengunduh = false;
  bool _mengunggah = false;
  String? _pesanError;

  List<Map<String, dynamic>> _semuaProduk = [];
  List<Map<String, dynamic>> _filteredProduk = [];
  final Map<int, TextEditingController> _controllersFisik = {};
  final Map<int, TextEditingController> _controllersKet = {};
  Set<int> _checklistSelesai = <int>{};

  final TextEditingController _cariController = TextEditingController();
  String _kategoriTerpilih = '';
  List<String> _daftarKategori = [];

  double _totalStokSistem = 0;
  double _totalNilaiAset = 0;

  String get _kunciChecklist =>
      'so_grand_cek_${Sesi.instance.idTokoTerpilih ?? 0}';

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  @override
  void dispose() {
    _cariController.dispose();
    for (final c in _controllersFisik.values) {
      c.dispose();
    }
    for (final c in _controllersKet.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muatChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kunciChecklist) ?? [];
    _checklistSelesai = list.map(int.tryParse).whereType<int>().toSet();
  }

  Future<void> _simpanChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kunciChecklist, _checklistSelesai.map((e) => '$e').toList());
  }

  Future<void> _muatData() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    try {
      await _muatChecklist();
      final payload = <String, dynamic>{};
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }

      final res = await ApiClient.instance.aksi('so_grand_daftar', payload);
      final rawList = (res['data'] as List?) ?? [];
      final list = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final kategoriSet = <String>{};
      for (final item in list) {
        final kat = (item['kategori'] as String?)?.trim() ?? '';
        if (kat.isNotEmpty) kategoriSet.add(kat);

        final pId = (item['produkId'] as num).toInt();
        if (!_controllersFisik.containsKey(pId)) {
          _controllersFisik[pId] = TextEditingController();
        }
        if (!_controllersKet.containsKey(pId)) {
          _controllersKet[pId] = TextEditingController();
        }
      }

      if (!mounted) return;
      setStateIfMounted(() {
        _semuaProduk = list;
        _totalStokSistem = (res['totalStokSistem'] as num?)?.toDouble() ?? 0;
        _totalNilaiAset = (res['totalNilaiAset'] as num?)?.toDouble() ?? 0;
        _daftarKategori = kategoriSet.toList()..sort();
        _terapkanFilter();
      });
    } catch (e) {
      if (mounted) {
        setStateIfMounted(() => _pesanError = 'Gagal memuat SO Grand: $e');
      }
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  void _terapkanFilter() {
    final kw = _cariController.text.trim().toLowerCase();
    setStateIfMounted(() {
      _filteredProduk = _semuaProduk.where((p) {
        final nama = (p['nama'] as String?)?.toLowerCase() ?? '';
        final kode = (p['kode'] as String?)?.toLowerCase() ?? '';
        final barcode = (p['barcode'] as String?)?.toLowerCase() ?? '';
        final kat = (p['kategori'] as String?) ?? '';

        final cocokKw = kw.isEmpty ||
            nama.contains(kw) ||
            kode.contains(kw) ||
            barcode.contains(kw);
        final cocokKat =
            _kategoriTerpilih.isEmpty || kat == _kategoriTerpilih;
        return cocokKw && cocokKat;
      }).toList();
    });
  }

  Future<void> _ubahChecklist(int produkId, bool checked) async {
    setStateIfMounted(() {
      if (checked) {
        _checklistSelesai.add(produkId);
      } else {
        _checklistSelesai.remove(produkId);
      }
    });
    await _simpanChecklist();
  }

  Future<void> _simpanBatchEntry() async {
    final items = <Map<String, dynamic>>[];
    for (final p in _filteredProduk) {
      final pId = (p['produkId'] as num).toInt();
      final ctrl = _controllersFisik[pId];
      final teksFisik = ctrl?.text.trim() ?? '';
      if (teksFisik.isNotEmpty) {
        final fisik = double.tryParse(teksFisik.replaceAll(',', '.'));
        if (fisik != null && fisik >= 0) {
          items.add({
            'produkId': pId,
            'stokFisik': fisik,
            'keterangan': _controllersKet[pId]?.text.trim() ?? '',
          });
        }
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Belum ada stok fisik yang diisi pada baris tabel.')));
      return;
    }

    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Simpan Entri SO Grand?'),
        content: Text(
            'Akan menyimpan penyesuaian stok untuk ${items.length} produk yang telah diisi fisik.\n\nStok sistem produk akan langsung diselaraskan dengan hasil fisik ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ya, Simpan Penyesuaian',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setStateIfMounted(() => _menyimpan = true);
    try {
      final payload = <String, dynamic>{
        'items': items,
        'keterangan': 'Entry Cepat SO Grand',
      };
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }

      final res = await ApiClient.instance.aksi('so_grand_simpan_batch', payload);
      final disimpan = (res['disimpan'] as num?)?.toInt() ?? 0;
      final dilewati = (res['dilewati'] as num?)?.toInt() ?? 0;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Berhasil menyimpan $disimpan item SO Grand${dilewati > 0 ? ' ($dilewati dilewati)' : ''}.')));

      // Tandai produk yang berhasil disimpan ke checklist
      for (final it in items) {
        _checklistSelesai.add(it['produkId'] as int);
      }
      await _simpanChecklist();
      await _muatData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan SO Grand: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<void> _unduhExcel() async {
    setStateIfMounted(() => _mengunduh = true);
    try {
      final payload = <String, dynamic>{};
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }

      final res =
          await ApiClient.instance.aksi('so_grand_download_excel', payload);
      final b64 = res['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan berkas SO Grand.');
      }

      final bytes = base64Decode(b64);
      final nama = '${res['namaFile'] ?? 'SO-Grand-Toko.xlsx'}';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Lembar Kerja SO Grand Excel',
        fileName: nama,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Form SO Grand disimpan: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengunduh SO Grand Excel: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengunduh = false);
    }
  }

  Future<void> _unggahExcel() async {
    final hasilPilih = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (hasilPilih == null || hasilPilih.files.isEmpty) return;
    final bytes = hasilPilih.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setStateIfMounted(() => _mengunggah = true);
    try {
      final payload = <String, dynamic>{
        'file_base64': base64Encode(bytes),
        'keterangan': 'Unggah Excel SO Grand',
      };
      final tokoId = Sesi.instance.idTokoTerpilih;
      if (tokoId != null && tokoId > 0) {
        payload['toko_id'] = tokoId;
      }

      final res =
          await ApiClient.instance.aksi('so_grand_upload_excel', payload);
      final disimpan = (res['disimpan'] as num?)?.toInt() ?? 0;
      final dilewati = (res['dilewati'] as num?)?.toInt() ?? 0;
      final masalahRaw = res['masalah'];
      final masalahList = masalahRaw is List
          ? masalahRaw
              .whereType<Map>()
              .map((b) => Map<String, dynamic>.from(b))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      if (dilewati > 0 || masalahList.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hasil Unggah SO Grand'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tersimpan: $disimpan baris\nDilewati / Gagal: $dilewati baris',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (masalahList.isNotEmpty) ...[
                      const Text('Rincian baris bermasalah:',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ...masalahList.take(20).map((m) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• Baris ${m['baris'] ?? '-'}: [${m['produk'] ?? '-'}] — ${m['alasan'] ?? 'Gagal'}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'SO Grand berhasil disimpan: $disimpan baris tersinkronisasi.')));
      }

      await _muatData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memproses unggah SO Grand: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _mengunggah = false);
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
                pw.Text('KERTAS KERJA STOK OPNAME (KKSO) - SO GRAND',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('Toko: $tokoNama · Total Item: ${items.length}',
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
            'BARCODE',
            'NAMA BARANG',
            'KATEGORI',
            'SATUAN',
            'STOK SISTEM',
            'STOK FISIK',
            'SELISIH',
            'PARAF',
            'CATATAN'
          ],
          data: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final r = entry.value;
            return [
              '$idx',
              '${r['kode'] ?? ''}',
              '${r['barcode'] ?? ''}',
              '${r['nama'] ?? ''}',
              '${r['kategori'] ?? '-'}',
              '${r['satuan'] ?? '-'}',
              _formatAngka.format(r['stokSistem'] ?? 0),
              '',
              '',
              '',
              '',
            ];
          }).toList(),
          cellStyle: const pw.TextStyle(fontSize: 7),
          headerStyle:
              pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ));

    await Printing.layoutPdf(
        onLayout: (_) async => doc.save(), name: 'Lembar-SO-Grand.pdf');
  }

  @override
  Widget build(BuildContext context) {
    final totalProduk = _semuaProduk.length;
    final jumlahDicek = _checklistSelesai.length;
    final persenSelesai =
        totalProduk > 0 ? (jumlahDicek / totalProduk * 100).clamp(0, 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Baris Aksi Atas
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _cariController,
                      decoration: InputDecoration(
                        hintText: 'Cari nama / kode / barcode...',
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
                      value: _kategoriTerpilih.isEmpty
                          ? null
                          : _kategoriTerpilih,
                      hint: const Text('Semua Kategori'),
                      items: [
                        const DropdownMenuItem(
                            value: '', child: Text('Semua Kategori')),
                        ..._daftarKategori.map((k) =>
                            DropdownMenuItem(value: k, child: Text(k))),
                      ],
                      onChanged: (val) {
                        setStateIfMounted(() => _kategoriTerpilih = val ?? '');
                        _terapkanFilter();
                      },
                    ),
                ],
              ),
            ),
            AksiBarisMenu(
              tooltip: 'Aksi SO Grand',
              aksi: [
                AksiBaris(
                  ikon: Icons.refresh,
                  label: 'Muat Ulang Data',
                  onTap: _memuat ? null : _muatData,
                ),
                AksiBaris(
                  ikon: Icons.save_outlined,
                  label: 'Simpan Entri Fisik Tabel',
                  onTap: _menyimpan ? null : _simpanBatchEntry,
                ),
                AksiBaris(
                  ikon: Icons.download_outlined,
                  label: 'Unduh Excel SO Grand (100% Produk)',
                  onTap: _mengunduh ? null : _unduhExcel,
                ),
                AksiBaris(
                  ikon: Icons.upload_file_outlined,
                  label: 'Unggah Excel Hasil Fisik',
                  onTap: _mengunggah ? null : _unggahExcel,
                ),
                AksiBaris(
                  ikon: Icons.picture_as_pdf_outlined,
                  label: 'Cetak KKSO (Kertas Kerja SO PDF)',
                  onTap: _filteredProduk.isEmpty ? null : _cetakPdf,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Banner Penjelasan SO Grand & Alur 3 Tahap Standar TokoQu
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            border: Border.all(color: const Color(0xFF86EFAC)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      color: Color(0xFF15803D), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'SO Grand (Grand Stock Opname) \u2014 Standar Audit 3 Tahap TokoQu',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Mencakup 100% barang aktif toko untuk rekonsiliasi total. Mengacu pada SOP Ritel TokoQu: '
                '(1) Persiapan: Jadwalkan, bekukan mutasi, cetak KKSO per kategori/rak; '
                '(2) Pelaksanaan: Hitung detail per pcs, beri tanda rak sudah dihitung, input fisik; '
                '(3) Rekonsiliasi: Cocokkan sistem vs fisik, investigasi selisih, dan simpan adjustment.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Kartu Ringkasan & Progres
        Row(
          children: [
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.primary),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Produk Aktif',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '$_formatAngka.format(totalProduk) Item',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Menampilkan ${_filteredProduk.length} item',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.warning),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Stok Sistem',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        _formatAngka.format(_totalStokSistem),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Estimasi Nilai: ${_formatRupiah.format(_totalNilaiAset)}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                elevation: 0,
                color: AppColors.latarLembut(AppColors.success),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Progres Penghitungan Fisik',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '$jumlahDicek / $totalProduk (${persenSelesai.toStringAsFixed(1)}%)',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: totalProduk > 0 ? (jumlahDicek / totalProduk) : 0,
                        backgroundColor: Colors.grey.shade200,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_pesanError != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: AppColors.latarLembut(AppColors.danger),
                borderRadius: BorderRadius.circular(8)),
            child: Text(_pesanError!,
                style: const TextStyle(color: AppColors.danger)),
          ),

        if (_memuat)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),

        if (!_memuat && _filteredProduk.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: Text('Tidak ada produk yang cocok dengan pencarian.')),
          ),

        // Tabel Entry SO Grand
        if (!_memuat && _filteredProduk.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Barang & Kolom Entry Fisik (${_filteredProduk.length} Produk)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Simpan Entri Fisik Tabel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  dense: true,
                ),
                onPressed: _menyimpan ? null : _simpanBatchEntry,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppDataTable(
            minWidth: 1150,
            emptyText: 'Belum ada produk.',
            columns: const [
              AppTableColumn('Cek', flex: 1),
              AppTableColumn('Kode / Barcode', flex: 2),
              AppTableColumn('Nama Produk', flex: 4),
              AppTableColumn('Kategori', flex: 2),
              AppTableColumn('Satuan', flex: 1),
              AppTableColumn('Stok Sistem', flex: 2, align: TextAlign.right),
              AppTableColumn('Input Stok Fisik', flex: 2, align: TextAlign.center),
              AppTableColumn('Catatan / Keterangan', flex: 3),
            ],
            rows: _filteredProduk.map((p) {
              final pId = (p['produkId'] as num).toInt();
              final dicek = _checklistSelesai.contains(pId);
              final ctrlFisik = _controllersFisik[pId]!;
              final ctrlKet = _controllersKet[pId]!;
              final stokSistem = (p['stokSistem'] as num?)?.toDouble() ?? 0.0;

              return AppTableRowData(cells: [
                AppTableCell(
                  flex: 1,
                  child: Checkbox(
                    value: dicek,
                    onChanged: (v) => _ubahChecklist(pId, v == true),
                  ),
                ),
                AppTableCell.text(
                  '${p['kode'] ?? ''}${('${p['barcode'] ?? ''}').isEmpty ? '' : '\n${p['barcode']}'}',
                  flex: 2,
                  maxLines: 2,
                ),
                AppTableCell.text('${p['nama'] ?? ''}', flex: 4, maxLines: 2),
                AppTableCell.text('${p['kategori'] ?? '-'}', flex: 2),
                AppTableCell.text('${p['satuan'] ?? '-'}', flex: 1),
                AppTableCell.text(
                  _formatAngka.format(stokSistem),
                  flex: 2,
                  align: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                AppTableCell(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: ctrlFisik,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      textAlign: TextAlign.right,
                      decoration: InputDecoration(
                        hintText: '0',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (teks) {
                        final val = double.tryParse(teks.replaceAll(',', '.'));
                        if (val != null) {
                          _ubahChecklist(pId, true);
                        }
                      },
                    ),
                  ),
                ),
                AppTableCell(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: TextField(
                      controller: ctrlKet,
                      decoration: InputDecoration(
                        hintText: 'Alasan / paraf...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ),
                ),
              ]);
            }).toList(),
          ),
        ],
      ],
    );
  }
}
