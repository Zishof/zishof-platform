import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../models.dart';
import '../parse_util.dart';
import '../services/simple_xlsx.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../widgets/safe_state.dart';

final _bulkRp =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _bulkTanggal = DateFormat('dd/MM/yyyy');

class KulakanBulkEntryScreen extends StatefulWidget {
  const KulakanBulkEntryScreen({super.key});

  @override
  State<KulakanBulkEntryScreen> createState() => _KulakanBulkEntryScreenState();
}

class _BulkRow {
  final kode = TextEditingController();
  final nama = TextEditingController();
  final qty = TextEditingController(text: '1');
  final hargaBeli = TextEditingController();
  final diskon = TextEditingController(text: '0');
  final ppn = TextEditingController(text: '0');
  final batch = TextEditingController();
  final expired = TextEditingController();
  final hargaJual = TextEditingController();
  int? produkId;
  String? namaMaster;
  String? pesan;
  bool mencari = false;
  bool produkBaru = true;
  int? kategoriId;
  String kategoriNama = '';

  _BulkRow();

  _BulkRow.fromValues(List<String> values) {
    final cols = _normalisasiKolom(values);
    kode.text = cols[0];
    nama.text = cols[1];
    qty.text = cols[2];
    hargaBeli.text = cols[3];
    diskon.text = cols[4].isEmpty ? '0' : cols[4];
    ppn.text = cols[5].isEmpty ? '0' : cols[5];
    batch.text = cols[6];
    expired.text = cols[7];
    hargaJual.text = cols[8];
    kategoriNama = cols[9];
  }

  static List<String> _normalisasiKolom(List<String> values) {
    final cols = List<String>.generate(
      11,
      (index) => index < values.length ? values[index].trim() : '',
      growable: false,
    );

    // Beberapa hasil copy/upload dari Excel menghilangkan cell kosong di tengah
    // baris. Akibatnya harga_jual (kolom I) bisa bergeser ke diskon (kolom E).
    // Jika pola itu terdeteksi, pindahkan nilainya kembali ke harga_jual.
    final hargaBeli = parseDesimalAtau(cols[3]);
    final diskon = parseDesimalAtau(cols[4]);
    final hargaJualKosong = cols[8].isEmpty;
    final diskonTerlihatSepertiHargaJual =
        diskon > 0 && hargaBeli > 0 && diskon >= hargaBeli;
    if (hargaJualKosong && diskonTerlihatSepertiHargaJual) {
      cols[8] = cols[4];
      cols[4] = '0';
      if (cols[5].isEmpty) cols[5] = '0';
    }

    return cols;
  }

  void dispose() {
    kode.dispose();
    nama.dispose();
    qty.dispose();
    hargaBeli.dispose();
    diskon.dispose();
    ppn.dispose();
    batch.dispose();
    expired.dispose();
    hargaJual.dispose();
  }

  double get qtyNilai => parseDesimalAtau(qty.text);
  double get hargaBeliNilai => parseDesimalAtau(hargaBeli.text);
  double get diskonNilai => parseDesimalAtau(diskon.text);
  double get ppnNilai => parseDesimalAtau(ppn.text);
  double get hargaJualNilai => parseDesimalAtau(hargaJual.text);
  double get subtotal => qtyNilai * hargaBeliNilai;
  double get totalNetto => subtotal - diskonNilai + ppnNilai;
  double get hppUnit => qtyNilai <= 0 ? 0 : totalNetto / qtyNilai;
  String get kodeBersih => kode.text.trim();
  String get namaBersih => nama.text.trim();
  String get namaEfektif =>
      namaMaster?.trim().isNotEmpty == true ? namaMaster!.trim() : namaBersih;
}

class _BulkValidation {
  final List<String> errors;
  final List<String> warnings;

  const _BulkValidation(this.errors, this.warnings);

  bool get canPost => errors.isEmpty;
}

class _KulakanBulkEntryScreenState extends State<KulakanBulkEntryScreen> {
  final _faktur = TextEditingController();
  final _totalManual = TextEditingController();
  final _keterangan = TextEditingController();
  final _paste = TextEditingController();
  DateTime _tanggalFaktur = DateTime.now();
  Map<String, dynamic>? _supplier;
  final List<_BulkRow> _rows = [_BulkRow()];
  bool _posting = false;
  bool _mengimporExcel = false;
  bool _memuatKategori = false;
  List<Kategori> _kategori = [];
  String? _error;

  @override
  void dispose() {
    _faktur.dispose();
    _totalManual.dispose();
    _keterangan.dispose();
    _paste.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _muatKategori();
  }

  Future<void> _muatKategori() async {
    setStateIfMounted(() => _memuatKategori = true);
    try {
      final hasil = await ApiClient.instance.aksi('jenis_produk_list', {
        'page': 1,
        'page_size': 500,
        'termasuk_nonaktif': true,
      });
      var kategori = _parseKategoriResponse(hasil);
      if (kategori.isEmpty) {
        final katalog = await ApiClient.instance
            .aksi('katalog', {'page': 1, 'page_size': 1});
        kategori = _parseKategoriResponse(katalog);
      }
      if (!mounted) return;
      setStateIfMounted(() {
        _kategori = kategori;
        for (final row in _rows) {
          _resolveKategoriDariNama(row);
        }
      });
    } catch (_) {
      // Kategori bersifat pelengkap untuk produk baru; form tetap bisa dipakai.
    } finally {
      if (mounted) setStateIfMounted(() => _memuatKategori = false);
    }
  }

  List<Kategori> _parseKategoriResponse(Map<String, dynamic> hasil) {
    final sumber = hasil['data'] ??
        hasil['kategori'] ??
        hasil['categories'] ??
        hasil['jenis_produk'] ??
        hasil['jenisProduk'] ??
        hasil['items'] ??
        hasil['rows'];
    final data = sumber is List ? sumber : const [];
    final unik = <int, Kategori>{};
    for (final item in data) {
      final kategori = _parseKategoriItem(item);
      if (kategori != null) unik[kategori.id] = kategori;
    }
    final daftar = unik.values.toList()
      ..sort((a, b) => a.nama.toLowerCase().compareTo(b.nama.toLowerCase()));
    return daftar;
  }

  Kategori? _parseKategoriItem(dynamic item) {
    if (item is! Map) return null;
    final map = Map<String, dynamic>.from(item);
    final id = map['id'] ??
        map['kategoriId'] ??
        map['kategori_id'] ??
        map['jenisProdukId'] ??
        map['jenis_produk_id'];
    final idNilai = id is num ? id.toInt() : int.tryParse('$id');
    final nama =
        '${map['nama'] ?? map['jenisProdukNama'] ?? map['jenis_produk_nama'] ?? map['kategoriNama'] ?? map['kategori_nama'] ?? map['label'] ?? ''}'
            .trim();
    if (idNilai == null || nama.isEmpty) return null;
    return Kategori(id: idNilai, nama: nama);
  }

  double? get _totalFaktur => parseDesimal(_totalManual.text);
  double get _totalBaris => _rows.fold(0, (sum, row) => sum + row.totalNetto);
  int get _produkBaru => _activeRows.where((row) => row.produkBaru).length;
  int get _produkLama => _activeRows.where((row) => !row.produkBaru).length;
  List<_BulkRow> get _activeRows => _rows
      .where((row) => row.kodeBersih.isNotEmpty || row.namaBersih.isNotEmpty)
      .toList();

  void _setKategoriDariProduk(_BulkRow row, Map<String, dynamic> produk) {
    final id = produk['kategoriId'] ??
        produk['kategori_id'] ??
        produk['jenisProdukId'] ??
        produk['jenis_produk_id'];
    row.kategoriId = id is num ? id.toInt() : int.tryParse('$id');
    row.kategoriNama =
        '${produk['kategoriNama'] ?? produk['kategori_nama'] ?? produk['jenisProdukNama'] ?? produk['jenis_produk_nama'] ?? ''}'
            .trim();
  }

  void _resolveKategoriDariNama(_BulkRow row) {
    if (row.kategoriId != null || row.kategoriNama.trim().isEmpty) return;
    final raw = row.kategoriNama.trim().toLowerCase();
    for (final kategori in _kategori) {
      if (kategori.nama.toLowerCase() == raw || '${kategori.id}' == raw) {
        row.kategoriId = kategori.id;
        row.kategoriNama = kategori.nama;
        return;
      }
    }
  }

  String _labelKategori(_BulkRow row) {
    if (row.kategoriNama.trim().isNotEmpty) return row.kategoriNama.trim();
    if (row.kategoriId != null) {
      for (final kategori in _kategori) {
        if (kategori.id == row.kategoriId) return kategori.nama;
      }
    }
    return 'Tanpa Jenis Produk';
  }

  Future<void> _pilihSupplier() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BulkSupplierSheet(),
    );
    if (dipilih != null) setStateIfMounted(() => _supplier = dipilih);
  }

  Future<void> _pilihTanggal() async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggalFaktur,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (hasil != null) setStateIfMounted(() => _tanggalFaktur = hasil);
  }

  Future<void> _pilihExpired(_BulkRow row) async {
    final initial = _parseTanggal(row.expired.text) ??
        DateTime.now().add(const Duration(days: 365));
    final hasil = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (hasil != null) {
      setStateIfMounted(
          () => row.expired.text = DateFormat('yyyy-MM-dd').format(hasil));
    }
  }

  void _tambahBaris() {
    setStateIfMounted(() => _rows.add(_BulkRow()));
  }

  void _hapusBaris(_BulkRow row) {
    if (_rows.length == 1) {
      setStateIfMounted(() {
        row.kode.clear();
        row.nama.clear();
        row.qty.text = '1';
        row.hargaBeli.clear();
        row.diskon.text = '0';
        row.ppn.text = '0';
        row.batch.clear();
        row.expired.clear();
        row.hargaJual.clear();
        row.produkId = null;
        row.namaMaster = null;
        row.produkBaru = true;
        row.kategoriId = null;
        row.kategoriNama = '';
        row.pesan = null;
      });
      return;
    }
    setStateIfMounted(() => _rows.remove(row));
    row.dispose();
  }

  void _resetDraft({bool tampilkanInfo = true}) {
    setStateIfMounted(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..add(_BulkRow());
      _paste.clear();
      _error = null;
    });
    if (tampilkanInfo && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft bulk entry sudah direset.')));
    }
  }

  Future<bool> _konfirmasiResetDraft() async {
    if (_activeRows.isEmpty) {
      _resetDraft();
      return true;
    }
    final lanjut = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reset Draft?'),
            content: const Text(
                'Semua baris draft yang belum diposting akan dihapus dari layar ini.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal')),
              FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Reset')),
            ],
          ),
        ) ??
        false;
    if (lanjut) _resetDraft();
    return lanjut;
  }

  Future<bool?> _pilihModeUploadExcel() async {
    if (_activeRows.isEmpty) return false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Excel ke Draft'),
        content: const Text(
            'Pilih cara memasukkan data Excel ke draft yang sedang terbuka.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Batal')),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(false),
            icon: const Icon(Icons.playlist_add_outlined, size: 18),
            label: const Text('Tambah ke Draft'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.refresh_outlined, size: 18),
            label: const Text('Ganti Draft'),
          ),
        ],
      ),
    );
  }

  void _pasteBaris() {
    final teks = _paste.text.trim();
    if (teks.isEmpty) return;
    final parsed = teks
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.split(line.contains('\t') ? '\t' : RegExp(r'[;,]')))
        .map((cols) => cols.map((col) => col.trim()).toList())
        .toList();
    if (parsed.isEmpty) return;
    setStateIfMounted(() {
      if (_rows.length == 1 &&
          _rows.first.kodeBersih.isEmpty &&
          _rows.first.namaBersih.isEmpty) {
        _rows.removeAt(0).dispose();
      }
      _rows.addAll(parsed.map(_BulkRow.fromValues));
      _paste.clear();
      _error = null;
    });
  }

  Future<void> _cariProduk(_BulkRow row) async {
    final kode = row.kodeBersih;
    if (kode.isEmpty) return;
    setStateIfMounted(() {
      row.mencari = true;
      row.pesan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (!mounted) return;
      setStateIfMounted(() {
        row.produkId = (hasil['produkId'] as num?)?.toInt();
        row.namaMaster = '${hasil['nama'] ?? ''}'.trim();
        if (row.nama.text.trim().isEmpty) row.nama.text = row.namaMaster ?? '';
        if (row.hargaBeli.text.trim().isEmpty) {
          final hargaBeli = (hasil['hargaBeli'] as num?)?.toDouble();
          if (hargaBeli != null && hargaBeli > 0) {
            row.hargaBeli.text = hargaBeli.toStringAsFixed(0);
          }
        }
        if (row.hargaJual.text.trim().isEmpty) {
          final hargaJual = (hasil['hargaJual'] as num?)?.toDouble();
          if (hargaJual != null && hargaJual > 0) {
            row.hargaJual.text = hargaJual.toStringAsFixed(0);
          }
        }
        _setKategoriDariProduk(row, hasil);
        row.produkBaru = row.produkId == null;
        row.pesan = row.produkBaru
            ? 'Produk belum ada, akan dibuat saat posting.'
            : 'Cocok: ${row.namaMaster}';
      });
    } catch (_) {
      if (!mounted) return;
      setStateIfMounted(() {
        row.produkId = null;
        row.namaMaster = null;
        row.produkBaru = true;
        _resolveKategoriDariNama(row);
        row.pesan = 'Produk belum ditemukan, akan dibuat baru saat posting.';
      });
    } finally {
      if (mounted) setStateIfMounted(() => row.mencari = false);
    }
  }

  Future<void> _pilihProdukDariNama(_BulkRow row, String kode) async {
    final nilai = kode.trim();
    if (nilai.isEmpty) return;
    row.kode.text = nilai;
    row.nama.clear();
    await _cariProduk(row);
  }

  Future<void> _cekSemuaProduk() async {
    for (final row in _rows.where((row) => row.kodeBersih.isNotEmpty)) {
      await _cariProduk(row);
    }
  }

  DateTime? _parseTanggal(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    for (final format in [
      DateFormat('yyyy-MM-dd'),
      DateFormat('dd/MM/yyyy'),
      DateFormat('dd-MM-yyyy'),
    ]) {
      try {
        return format.parseStrict(value);
      } catch (_) {}
    }
    return DateTime.tryParse(value);
  }

  List<String> _masalahBaris(_BulkRow row, int index) {
    final masalah = <String>[];
    if (row.kodeBersih.isEmpty && row.namaBersih.isEmpty) return masalah;
    final idx = index + 1;
    if (row.kodeBersih.isEmpty) {
      masalah.add('Baris $idx: kode/barcode wajib diisi.');
    }
    if (row.namaEfektif.isEmpty) {
      masalah.add('Baris $idx: nama produk wajib diisi.');
    }
    if (row.qtyNilai <= 0) {
      masalah.add('Baris $idx: qty harus lebih dari 0.');
    }
    if (row.hargaBeliNilai <= 0) {
      masalah.add('Baris $idx: harga beli harus lebih dari 0.');
    }
    if (row.totalNetto <= 0) {
      masalah.add('Baris $idx: total netto tidak boleh 0/negatif.');
    }
    if (row.produkBaru && row.hargaJualNilai <= 0) {
      masalah.add('Baris $idx: produk baru wajib memiliki harga jual awal.');
    }
    if (row.expired.text.trim().isNotEmpty &&
        _parseTanggal(row.expired.text) == null) {
      masalah.add('Baris $idx: format expired tidak dikenali.');
    }
    return masalah;
  }

  List<String> _warningBaris(_BulkRow row, int index) {
    final warnings = <String>[];
    if (row.kodeBersih.isEmpty && row.namaBersih.isEmpty) return warnings;
    final idx = index + 1;
    if (!row.produkBaru &&
        row.namaBersih.isNotEmpty &&
        row.namaMaster != null &&
        row.namaBersih.toLowerCase() != row.namaMaster!.toLowerCase()) {
      warnings.add(
          'Baris $idx: kode cocok ke "${row.namaMaster}", tetapi nama input "${row.namaBersih}".');
    }
    final duplikat = _rows.where((r) =>
        r != row &&
        r.kodeBersih.isNotEmpty &&
        r.kodeBersih.toLowerCase() == row.kodeBersih.toLowerCase());
    if (row.kodeBersih.isNotEmpty && duplikat.isNotEmpty) {
      final namaSet = <String>{
        row.namaEfektif.toLowerCase(),
        ...duplikat.map((r) => r.namaEfektif.toLowerCase()),
      }..remove('');
      final idSet = <int>{
        if (row.produkId != null) row.produkId!,
        ...duplikat.map((r) => r.produkId).whereType<int>(),
      };
      if (namaSet.length > 1 || idSet.length > 1) {
        warnings
            .add('Baris $idx: kode/barcode sama dipakai untuk item berbeda.');
      } else {
        warnings.add('Baris $idx: kode/barcode muncul lebih dari sekali.');
      }
    }
    return warnings;
  }

  _BulkValidation _validasi() {
    final errors = <String>[];
    final warnings = <String>[];
    if (_faktur.text.trim().isEmpty) {
      errors.add('Nomor faktur wajib diisi.');
    }
    if (_supplier == null) {
      errors.add('Supplier wajib dipilih untuk jejak pembelian dan hutang.');
    }
    if (_activeRows.isEmpty) {
      errors.add('Minimal satu baris barang harus diisi.');
    }

    final kodeMap = <String, List<_BulkRow>>{};
    for (var i = 0; i < _activeRows.length; i++) {
      final row = _activeRows[i];
      final idx = i + 1;
      if (row.kodeBersih.isEmpty) {
        errors.add('Baris $idx: kode/barcode wajib diisi.');
      }
      if (row.namaEfektif.isEmpty) {
        errors.add('Baris $idx: nama produk wajib diisi.');
      }
      if (row.qtyNilai <= 0) errors.add('Baris $idx: qty harus lebih dari 0.');
      if (row.hargaBeliNilai <= 0) {
        errors.add('Baris $idx: harga beli harus lebih dari 0.');
      }
      if (row.totalNetto <= 0) {
        errors.add('Baris $idx: total netto tidak boleh 0/negatif.');
      }
      if (row.produkBaru && row.hargaJualNilai <= 0) {
        errors.add('Baris $idx: produk baru wajib memiliki harga jual awal.');
      }
      if (row.expired.text.trim().isNotEmpty &&
          _parseTanggal(row.expired.text) == null) {
        errors.add(
            'Baris $idx: format expired tidak dikenali. Gunakan yyyy-MM-dd atau dd/MM/yyyy.');
      }
      if (!row.produkBaru &&
          row.namaBersih.isNotEmpty &&
          row.namaMaster != null &&
          row.namaBersih.toLowerCase() != row.namaMaster!.toLowerCase()) {
        warnings.add(
            'Baris $idx: kode cocok ke "${row.namaMaster}", tetapi nama input "${row.namaBersih}". Pastikan kode/barcode tidak salah.');
      }
      kodeMap.putIfAbsent(row.kodeBersih.toLowerCase(), () => []).add(row);
    }

    for (final entry in kodeMap.entries) {
      if (entry.value.length <= 1) continue;
      final names = entry.value
          .map((row) => row.namaEfektif.toLowerCase())
          .where((name) => name.isNotEmpty)
          .toSet();
      final ids =
          entry.value.map((row) => row.produkId).whereType<int>().toSet();
      if (names.length > 1 || ids.length > 1) {
        errors.add(
            'Kode/barcode "${entry.value.first.kodeBersih}" dipakai untuk item berbeda. Periksa ulang sebelum posting.');
      } else {
        warnings.add(
            'Kode/barcode "${entry.value.first.kodeBersih}" muncul lebih dari sekali. Jika barang sama, sebaiknya gabungkan qty dalam satu baris.');
      }
    }

    final total = _totalFaktur;
    if (total != null && total > 0) {
      final selisih = (_totalBaris - total).abs();
      if (selisih > 1) {
        warnings.add(
            'Total baris berbeda dari total faktur sebesar ${_bulkRp.format(selisih)}. Pastikan diskon/PPN/biaya sudah benar.');
      }
    }
    return _BulkValidation(errors, warnings);
  }

  Future<bool> _konfirmasiPosting(_BulkValidation validasi) async {
    final total = _totalFaktur;
    final adaWarning = validasi.warnings.isNotEmpty;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  adaWarning
                      ? Icons.warning_amber_outlined
                      : Icons.cloud_done_outlined,
                  color: adaWarning ? AppColors.warning : AppColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(adaWarning
                      ? 'Perhatian: Ada Warning Entry'
                      : 'Posting Penerimaan?'),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Faktur: ${_faktur.text.trim()}'),
                  Text('Supplier: ${_supplier?['nama'] ?? '-'}'),
                  Text('Item: ${_activeRows.length} baris'),
                  Text('Produk lama: $_produkLama, produk baru: $_produkBaru'),
                  Text('Total baris: ${_bulkRp.format(_totalBaris)}'),
                  if (total != null)
                    Text('Total faktur: ${_bulkRp.format(total)}'),
                  if (adaWarning) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.warning),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Periksa sebelum posting',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Jika kode/barcode salah tetapi tetap diposting, stok dan HPP akan masuk ke produk yang terdeteksi oleh kode tersebut. Koreksi setelah posting harus lewat retur/koreksi stok.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          const SizedBox(height: 8),
                          ...validasi.warnings.take(6).map(
                                (warning) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '- $warning',
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ),
                          if (validasi.warnings.length > 6)
                            Text(
                              '- ${validasi.warnings.length - 6} warning lain',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Setelah posting, stok bertambah dan faktur tersimpan di server.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(adaWarning ? 'Periksa Lagi' : 'Batal'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: Icon(adaWarning
                    ? Icons.warning_amber_outlined
                    : Icons.cloud_done_outlined),
                label: Text(adaWarning ? 'Tetap Posting' : 'Posting'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _postingFaktur() async {
    final validasi = _validasi();
    if (!validasi.canPost) {
      setStateIfMounted(() => _error = validasi.errors.join('\n'));
      return;
    }
    if (!await _konfirmasiPosting(validasi)) return;
    setStateIfMounted(() {
      _posting = true;
      _error = null;
    });
    try {
      final items = <Map<String, dynamic>>[];
      for (final row in _activeRows) {
        var produkId = row.produkId;
        if (produkId == null) {
          final hasil = await ApiClient.instance.aksi('produk_simpan', {
            'kode': row.kodeBersih,
            'nama': row.namaBersih,
            'barcode': row.kodeBersih,
            'harga_beli': row.hppUnit,
            'harga_jual': row.hargaJualNilai,
            'stok': 0,
            'keterangan':
                'Dibuat dari Bulk Entry Kulakan faktur ${_faktur.text.trim()}',
            'kategori_id': row.kategoriId,
            'jenis_produk_id': row.kategoriId,
            'kebijakan_retur_id': null,
            'izinkan_jual_minus_stok': false,
            'aktif': true,
            'jenis_item': 'JUAL',
            'bahan_baku': const [],
            'ekstra_pilihan': const [],
          });
          produkId = (hasil['id'] as num?)?.toInt();
          if (produkId == null) {
            throw 'Produk baru ${row.namaBersih} gagal mendapat ID dari server.';
          }
        }
        final expired = _parseTanggal(row.expired.text);
        items.add({
          'produk_id': produkId,
          'qty': row.qtyNilai,
          'harga_beli_satuan': row.hppUnit,
          if (row.batch.text.trim().isNotEmpty)
            'nomor_batch': row.batch.text.trim(),
          if (expired != null)
            'tanggal_expired': DateFormat('yyyy-MM-dd').format(expired),
        });
      }
      await ApiClient.instance.aksi('kulakan_faktur_simpan', {
        'nomor_faktur': _faktur.text.trim(),
        'tanggal_faktur': _tanggalFaktur.toIso8601String(),
        'supplier_id': _supplier!['id'],
        if (_totalFaktur != null) 'total_faktur_manual': _totalFaktur,
        'keterangan': _keterangan.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Bulk entry faktur tersimpan (${items.length} item).')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _posting = false);
    }
  }

  Future<void> _downloadTemplateExcel() async {
    try {
      final bytes = buildSimpleXlsx(
        sheetName: 'Template Bulk Kulakan',
        headers: const [
          'kode_barcode [WAJIB]',
          'nama_produk [WAJIB utk barang baru]',
          'qty [WAJIB]',
          'harga_beli [WAJIB]',
          'diskon [OPSIONAL]',
          'ppn [OPSIONAL]',
          'batch [OPSIONAL]',
          'expired [OPSIONAL yyyy-MM-dd]',
          'harga_jual [WAJIB utk barang baru]',
          'jenis_produk [OPSIONAL utk barang baru]',
          'catatan',
        ],
        rows: const [
          [
            '8999999999999',
            'Contoh Produk Baru',
            12,
            7500,
            0,
            0,
            'B2401',
            '2027-12-31',
            10000,
            'AKSESORIS',
            'Contoh barang baru: nama dan harga jual wajib diisi.'
          ],
          [
            'BRG001',
            '',
            6,
            8200,
            500,
            0,
            '',
            '',
            '',
            '',
            'Contoh barang lama: cukup kode/barcode, lalu klik Cek Produk Existing.'
          ],
          [
            'PANDUAN',
            'Jangan ubah urutan kolom. Kolom bertanda WAJIB harus diisi.',
            '',
            '',
            'Isi 0 jika tidak ada diskon.',
            'Isi 0 jika tidak ada PPN.',
            'Opsional untuk non-batch.',
            'Format yyyy-MM-dd atau dd/MM/yyyy.',
            'Wajib hanya untuk produk baru.',
            'Isi nama jenis produk atau ID jenis produk, opsional.',
            'Hapus baris panduan sebelum paste/import ke aplikasi.'
          ],
        ],
      );
      final fileName =
          'Template_Bulk_Kulakan_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan Template Bulk Kulakan',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      if (path != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Template Excel berhasil dibuat.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Template Excel gagal dibuat: $e')));
      }
    }
  }

  Future<void> _uploadTemplateExcel() async {
    setStateIfMounted(() {
      _mengimporExcel = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pilih Format Bulk Kulakan',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final bytes = file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw 'File Excel tidak dapat dibaca. Pilih file kembali.';
      }
      final sheetRows = readSimpleXlsx(bytes);
      if (sheetRows.length <= 1) {
        throw 'Template Excel belum berisi baris barang.';
      }
      final parsed = <_BulkRow>[];
      for (final row in sheetRows.skip(1)) {
        final cols = List<String>.generate(
            11, (index) => index < row.length ? row[index].trim() : '',
            growable: false);
        final kode = cols[0].trim();
        final nama = cols[1].trim();
        if (kode.isEmpty && nama.isEmpty) continue;
        if (kode.toUpperCase() == 'PANDUAN') continue;
        parsed.add(_BulkRow.fromValues(cols));
      }
      if (parsed.isEmpty) {
        throw 'Tidak ada baris barang yang bisa diproses dari Excel.';
      }
      final gantiDraft = await _pilihModeUploadExcel();
      if (gantiDraft == null) {
        for (final row in parsed) {
          row.dispose();
        }
        return;
      }
      setStateIfMounted(() {
        if (gantiDraft) {
          for (final row in _rows) {
            row.dispose();
          }
          _rows.clear();
        } else if (_rows.length == 1 &&
            _rows.first.kodeBersih.isEmpty &&
            _rows.first.namaBersih.isEmpty) {
          _rows.removeAt(0).dispose();
        }
        _rows.addAll(parsed);
      });
      await _cekProdukUntuk(parsed);
      if (mounted) {
        final mode = gantiDraft ? 'mengganti draft' : 'ditambahkan ke draft';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${parsed.length} baris Excel $mode.')));
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mengimporExcel = false);
    }
  }

  Future<void> _cekProdukUntuk(List<_BulkRow> rows) async {
    for (final row in rows.where((row) => row.kodeBersih.isNotEmpty)) {
      await _cariProduk(row);
    }
  }

  Widget _field(TextEditingController controller,
      {String? hint, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setStateIfMounted(() {}),
      style: const TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _statusRow(_BulkRow row) {
    final color = row.produkBaru ? AppColors.primary : AppColors.success;
    final label = row.produkBaru ? 'Baru' : 'Existing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.latarLembut(color),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ),
        if (row.pesan != null) ...[
          const SizedBox(height: 4),
          Text(row.pesan!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondaryOf(context))),
        ],
      ],
    );
  }

  Widget _kategoriCell(_BulkRow row) {
    if (!row.produkBaru) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borderOf(context)),
          borderRadius: BorderRadius.circular(4),
          color: AppColors.pageBgOf(context),
        ),
        child: Text(
          _labelKategori(row),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondaryOf(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return DropdownButtonFormField<int?>(
      value: row.kategoriId,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        border: OutlineInputBorder(),
      ),
      hint: Text(_memuatKategori ? 'Memuat...' : 'Pilih jenis produk'),
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('Tanpa Jenis Produk'),
        ),
        ..._kategori.map((kategori) => DropdownMenuItem<int?>(
              value: kategori.id,
              child: Text(kategori.nama,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: _memuatKategori
          ? null
          : (value) {
              setStateIfMounted(() {
                row.kategoriId = value;
                row.kategoriNama = value == null
                    ? ''
                    : _kategori
                        .firstWhere((kategori) => kategori.id == value)
                        .nama;
              });
            },
    );
  }

  Widget _headerCell(String label,
      {required double width, TextAlign align = TextAlign.left}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: AppColors.borderOf(context)),
          ),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
      ),
    );
  }

  Widget _bulkTable() {
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1710,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.pageBgOf(context),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    _headerCell('NO', width: 44, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('KODE / BARCODE', width: 170),
                    const SizedBox(width: 8),
                    _headerCell('NAMA PRODUK', width: 202),
                    const SizedBox(width: 8),
                    _headerCell('JENIS PRODUK', width: 160),
                    const SizedBox(width: 8),
                    _headerCell('QTY', width: 72, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('HARGA BELI',
                        width: 112, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('DISKON', width: 92, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('PPN', width: 92, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('HPP UNIT', width: 97, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('BATCH', width: 112),
                    const SizedBox(width: 8),
                    _headerCell('EXPIRED', width: 112),
                    const SizedBox(width: 8),
                    _headerCell('HARGA JUAL',
                        width: 92, align: TextAlign.right),
                    const SizedBox(width: 8),
                    _headerCell('STATUS', width: 147),
                    const SizedBox(width: 52),
                  ]),
                ),
                ..._rows.asMap().entries.map((entry) {
                  final index = entry.key;
                  final row = entry.value;
                  final errors = _masalahBaris(row, index);
                  final warnings = _warningBaris(row, index);
                  final rowColor = row.produkBaru && row.kodeBersih.isNotEmpty
                      ? (AppColors.gelap(context)
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : const Color(0xFFEAF2FF))
                      : errors.isNotEmpty
                          ? AppColors.latarLembut(AppColors.danger)
                          : warnings.isNotEmpty
                              ? AppColors.latarLembut(AppColors.warning)
                              : AppColors.cardBgOf(context);
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: rowColor,
                      border: Border(
                          top: BorderSide(color: AppColors.borderOf(context))),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 44,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text('${index + 1}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: errors.isNotEmpty
                                        ? AppColors.danger
                                        : warnings.isNotEmpty
                                            ? AppColors.warning
                                            : AppColors.textSecondaryOf(
                                                context))),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 170,
                          child: Row(children: [
                            Expanded(
                                child:
                                    _field(row.kode, hint: 'scan/ketik kode')),
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Cek produk',
                              onPressed:
                                  row.mencari ? null : () => _cariProduk(row),
                              icon: row.mencari
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.search, size: 18),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 202,
                          child: PencarianProdukBanbox(
                            controller: row.nama,
                            label: 'Nama Produk',
                            icon: Icons.search,
                            onPilih: (kode) => _pilihProdukDariNama(row, kode),
                            decorationBuilder: (context) =>
                                const InputDecoration(
                              hintText: 'cari / ketik nama',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 9),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 160, child: _kategoriCell(row)),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 72,
                            child: _field(row.qty,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true))),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 112,
                            child: _field(row.hargaBeli,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true))),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 92,
                            child: _field(row.diskon,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true))),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 92,
                            child: _field(row.ppn,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true))),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 97,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 9),
                            child: Text(_bulkRp.format(row.hppUnit),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 112,
                            child: _field(row.batch, hint: 'opsional')),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 112,
                          child: TextField(
                            controller: row.expired,
                            onChanged: (_) => setStateIfMounted(() {}),
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              hintText: 'yyyy-MM-dd',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 9),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: 'Pilih tanggal',
                                icon:
                                    const Icon(Icons.event_outlined, size: 16),
                                onPressed: () => _pilihExpired(row),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 92,
                            child: _field(row.hargaJual,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true))),
                        const SizedBox(width: 8),
                        SizedBox(width: 147, child: _statusRow(row)),
                        SizedBox(
                          width: 52,
                          child: IconButton(
                            tooltip: 'Hapus baris',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => _hapusBaris(row),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelValidasi(_BulkValidation validasi) {
    final items = [
      ...validasi.errors.map((e) => (e, AppColors.danger, Icons.error_outline)),
      ...validasi.warnings
          .map((w) => (w, AppColors.warning, Icons.warning_amber_outlined)),
    ];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.latarLembut(AppColors.success),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Icon(Icons.check_circle_outline, color: AppColors.success),
          const SizedBox(width: 8),
          const Expanded(
              child: Text(
                  'Draft siap diposting. Stok baru masuk setelah tombol Posting ditekan.')),
        ]),
      );
    }
    return Column(
      children: items
          .take(8)
          .map((item) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.latarLembut(item.$2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(item.$3, size: 18, color: item.$2),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(item.$1,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimaryOf(context)))),
                    ]),
              ))
          .toList(),
    );
  }

  Widget _chipRingkas(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.cardBgOf(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11, color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryOf(context))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final validasi = _validasi();
    final totalFaktur = _totalFaktur;
    return AppShell(
      menuAktif: MenuEBisnis.kulakan,
      judul: 'Bulk Entry Faktur Kulakan',
      subjudul: 'Draft penerimaan barang massal berdasarkan faktur supplier',
      aksiHeader: OutlinedButton.icon(
        onPressed: _posting ? null : () => Navigator.of(context).pop(false),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Kembali'),
      ),
      actionsAppBar: [
        IconButton(
          tooltip: 'Kembali',
          onPressed: _posting ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.arrow_back),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppFormSection(
            judul: 'Header Faktur',
            deskripsi:
                'Data belum menambah stok sampai user menekan Posting Penerimaan.',
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _faktur,
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Nomor Faktur *'),
                    onChanged: (_) => setStateIfMounted(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pilihTanggal,
                    child: InputDecorator(
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Tanggal Faktur *'),
                      child: Text(_bulkTanggal.format(_tanggalFaktur)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: _pilihSupplier,
                    child: InputDecorator(
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Supplier *',
                          prefixIcon:
                              const Icon(Icons.local_shipping_outlined)),
                      child: Row(children: [
                        Expanded(
                            child: Text(_supplier == null
                                ? '-- Pilih Supplier --'
                                : '${_supplier!['nama']}')),
                        const Icon(Icons.arrow_drop_down),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _totalManual,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Total Faktur',
                        hintText: 'Untuk rekonsiliasi total supplier'),
                    onChanged: (_) => setStateIfMounted(() {}),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _keterangan,
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Keterangan'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppFormSection(
            judul: 'Excel / Paste Draft Faktur',
            deskripsi:
                'Urutan kolom: kode/barcode, nama, qty, harga beli, diskon, ppn, batch, expired, harga jual, kategori. Bisa dipisah TAB, titik koma, atau koma.',
            children: [
              TextField(
                controller: _paste,
                minLines: 3,
                maxLines: 6,
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Tempel baris faktur',
                    hintText:
                        '8999999999999\tNama Barang\t12\t7500\t0\t0\tB2401\t2027-12-31\t10000'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _downloadTemplateExcel,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download Format Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: _mengimporExcel ? null : _uploadTemplateExcel,
                  icon: _mengimporExcel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Upload Excel ke Draft'),
                ),
                OutlinedButton.icon(
                  onPressed: _pasteBaris,
                  icon: const Icon(Icons.content_paste_outlined, size: 18),
                  label: const Text('Tambahkan dari Paste'),
                ),
                OutlinedButton.icon(
                  onPressed: _cekSemuaProduk,
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Cek Produk Existing'),
                ),
                OutlinedButton.icon(
                  onPressed: _tambahBaris,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tambah Baris Kosong'),
                ),
                OutlinedButton.icon(
                  onPressed: _posting ? null : _konfirmasiResetDraft,
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  label: const Text('Reset Draft'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 16),
          _bulkTable(),
          const SizedBox(height: 16),
          AppFormSection(
            judul: 'Review & Posting',
            children: [
              Wrap(spacing: 18, runSpacing: 10, children: [
                _chipRingkas('Baris', '${_activeRows.length}'),
                _chipRingkas('Produk existing', '$_produkLama'),
                _chipRingkas('Produk baru', '$_produkBaru'),
                _chipRingkas('Total baris', _bulkRp.format(_totalBaris)),
                if (totalFaktur != null)
                  _chipRingkas('Total faktur', _bulkRp.format(totalFaktur)),
              ]),
              const SizedBox(height: 12),
              _panelValidasi(validasi),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.latarLembut(AppColors.danger),
                      borderRadius: BorderRadius.circular(8)),
                  child:
                      Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed:
                      _posting || !validasi.canPost ? null : _postingFaktur,
                  icon: _posting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_done_outlined, size: 18),
                  label: const Text('Posting Penerimaan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulkSupplierSheet extends StatefulWidget {
  const _BulkSupplierSheet();

  @override
  State<_BulkSupplierSheet> createState() => _BulkSupplierSheetState();
}

class _BulkSupplierSheetState extends State<_BulkSupplierSheet> {
  final _cari = TextEditingController();
  final _namaBaru = TextEditingController();
  bool _memuat = true;
  bool _menyimpan = false;
  bool _tambahBaru = false;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _muat('');
  }

  @override
  void dispose() {
    _cari.dispose();
    _namaBaru.dispose();
    super.dispose();
  }

  Future<void> _muat(String keyword) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('penyedia_list', {'keyword': keyword});
      setStateIfMounted(() => _daftar =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      setStateIfMounted(() => _daftar = []);
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _simpanBaru() async {
    final nama = _namaBaru.text.trim();
    if (nama.isEmpty) return;
    setStateIfMounted(() => _menyimpan = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('penyedia_simpan', {'nama': nama});
      if (!mounted) return;
      Navigator.of(context).pop({
        'id': hasil['id'],
        'nama': hasil['nama'] ?? nama,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal simpan supplier: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Pilih Supplier',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton.icon(
                onPressed: () =>
                    setStateIfMounted(() => _tambahBaru = !_tambahBaru),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Supplier Baru'),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _cari,
              decoration: const InputDecoration(
                labelText: 'Cari supplier',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: _muat,
            ),
            if (_tambahBaru) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _namaBaru,
                    decoration: const InputDecoration(
                      labelText: 'Nama supplier baru',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _menyimpan ? null : _simpanBaru,
                  child: const Text('Simpan'),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _daftar.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final supplier = _daftar[i];
                        return ListTile(
                          leading: const Icon(Icons.local_shipping_outlined),
                          title: Text('${supplier['nama'] ?? '-'}'),
                          subtitle: supplier['kode'] == null
                              ? null
                              : Text('${supplier['kode']}'),
                          onTap: () => Navigator.of(context).pop(supplier),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
