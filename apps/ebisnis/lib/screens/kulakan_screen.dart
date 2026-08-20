import 'dart:io';
import 'dart:typed_data';

import 'package:core_hw/core_hw.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../parse_util.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import '../services/diff_daftar_lokal.dart';
import '../services/master_offline.dart';
import '../services/simple_xlsx.dart';
import 'retur_pembelian_screen.dart';
import 'kulakan_bulk_entry_screen.dart';
import '../widgets/jejak_galat.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngka = NumberFormat.decimalPattern('id_ID');
final _formatTanggal = DateFormat('dd/MM/yyyy');

/// Item satu baris produk yang SUDAH ditambahkan ke faktur yang SEDANG disusun --
/// murni state lokal, belum tersimpan ke server sampai "Simpan Faktur" ditekan.
class _ItemFaktur {
  final int produkId;
  final String nama;
  final String kode;
  final double qty;
  final double harga;
  final String? nomorBatch;
  final DateTime? tanggalProduksi;
  final DateTime? tanggalExpired;
  _ItemFaktur(
      {required this.produkId,
      required this.nama,
      required this.kode,
      required this.qty,
      required this.harga,
      this.nomorBatch,
      this.tanggalProduksi,
      this.tanggalExpired});
  double get total => qty * harga;
}

/// Layar Kulakan (gap-closure 2026-08-11: restrukturisasi per-Faktur, permintaan user) --
/// header (Nomor Faktur/Tanggal/Supplier) diisi SEKALI, diikuti banyak baris produk sebelum
/// disimpan sbg satu transaksi (`kulakan_faktur_simpan`). Sekarang 2 tab: "Kulakan" (form+riwayat
/// per-faktur) dan "Retur Pembelian" (barang kembali ke supplier, layar terpisah [ReturPembelianTab]).
class KulakanScreen extends StatefulWidget {
  const KulakanScreen({super.key});
  @override
  State<KulakanScreen> createState() => _KulakanScreenState();
}

class _KulakanScreenState extends State<KulakanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kulakan,
      judul: 'Kulakan',
      subjudul: 'Catat pengadaan/pembelian stok dari supplier',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Kulakan'),
              Tab(text: 'Retur Pembelian'),
            ],
          ),
          Expanded(
            child: TabBarView(controller: _tab, children: const [
              _TabKulakanFaktur(),
              ReturPembelianTab(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _TabKulakanFaktur extends StatefulWidget {
  const _TabKulakanFaktur();
  @override
  State<_TabKulakanFaktur> createState() => _TabKulakanFakturState();
}

class _TabKulakanFakturState extends State<_TabKulakanFaktur> with JejakGalat {
  static const _pageSize = 15;

  // ==== Header faktur (diisi SEKALI, diikuti banyak baris produk) ====
  final _fakturController = TextEditingController();
  final _totalManualController = TextEditingController();
  final _keteranganController = TextEditingController();
  DateTime _tanggalFaktur = DateTime.now();
  Map<String, dynamic>? _supplierTerpilih;

  // ==== Tambah baris produk (belum tersimpan -- lokal saja sampai "Simpan Faktur") ====
  final _barcodeController = TextEditingController();
  final _qtyController = TextEditingController();
  final _hargaController = TextEditingController();
  final _batchController = TextEditingController();
  bool _kelolaBatch = true;
  DateTime? _tanggalProduksi;
  DateTime? _tanggalExpired;
  bool _mencari = false;
  String? _errorForm;
  Map<String, dynamic>? _produkDitemukan;
  final List<_ItemFaktur> _itemsFaktur = [];
  bool _menyimpanFaktur = false;
  VoidCallback? _refreshHalamanEntri;

  // ==== Riwayat (per-faktur) ====
  bool _memuatRiwayat = true;
  String? _errorRiwayat;
  List<Map<String, dynamic>> _riwayat = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunciRiwayat = '';
  // Diff emisi baca lokal-dulu (daftarCacheDulu) -- menggerakkan kilau baris
  // + banner "pembaruan dari server" (faktur yang dicatat petugas lain).
  final DiffDaftarLokal _diff = DiffDaftarLokal();

  /// Kunci satu baris utk [KilauBaris]. Riwayat faktur kulakan TIDAK punya
  /// kolom 'id' -- identitasnya `fakturId` (dipakai juga oleh
  /// `kulakan_faktur_detail`). MasterOffline menyusun kunci diff-nya sbg
  /// `namaKolom=nilai` (lihat MasterOffline._kunciDiff) sehingga format di
  /// sini WAJIB sama, kalau tidak kilau tidak pernah cocok.
  String _kunciKilau(Map<String, dynamic> f) => 'fakturId=${f['fakturId'] ?? ''}';

  void _setStateEntri(VoidCallback fn) {
    setStateIfMounted(fn);
    _refreshHalamanEntri?.call();
  }

  @override
  void initState() {
    super.initState();
    _muatRiwayat();
  }

  @override
  void dispose() {
    _fakturController.dispose();
    _totalManualController.dispose();
    _keteranganController.dispose();
    _barcodeController.dispose();
    _qtyController.dispose();
    _hargaController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    if (!mounted) return;
    _setStateEntri(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      // BACA LOKAL DULU (MasterOffline.daftarCacheDulu): snapshot cache tampil
      // seketika, hasil server menyusul + diff utk kilau baris. Jalur SIMPAN
      // FAKTUR tetap online-only lewat ApiClient (transaksional).
      await MasterOffline.daftarCacheDulu('kulakan_faktur_list', {
        'page': _halaman,
        'page_size': _pageSize,
        if (_kataKunciRiwayat.isNotEmpty) 'keyword': _kataKunciRiwayat,
      }, 'master:kulakan_faktur', kolomKunci: 'fakturId', onData: (hasil) {
        if (!mounted) return;
        _setStateEntri(() {
          _riwayat = _diff.terapkan(hasil);
          _total = _diff.total ?? _riwayat.length;
          _memuatRiwayat = false;
        });
      });
    } catch (e) {
      if (!mounted) return;
      _setStateEntri(() => _errorRiwayat = terapkanGalat(e));
    } finally {
      if (mounted) _setStateEntri(() => _memuatRiwayat = false);
    }
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muatRiwayat();
  }

  Future<void> _cariProduk(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    if (!mounted) return;
    _setStateEntri(() {
      _mencari = true;
      _errorForm = null;
      _produkDitemukan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (!mounted) return;
      _setStateEntri(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
        if (!Sesi.instance.bolehUbahHarga) {
          // Akun ini tidak boleh mengubah harga, jadi kolomnya tampil sbg
          // label. Nilainya diisikan otomatis dari harga penerimaan terakhir
          // (jatuh ke harga beli master bila belum pernah diterima) supaya
          // penerimaan barang tetap bisa diselesaikan tanpa mengetik harga.
          final terakhir = (hasil['hargaBeliTerakhir'] as num?)?.toDouble() ?? 0;
          final master = (hasil['hargaBeli'] as num?)?.toDouble() ?? 0;
          final dipakai = terakhir > 0 ? terakhir : master;
          if (dipakai > 0) {
            _hargaController.text = dipakai.toStringAsFixed(0);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      _setStateEntri(() => _errorForm = terapkanGalat(e));
    } finally {
      if (mounted) _setStateEntri(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context,
        judul: 'Scan Barcode Produk');
    if (!mounted) return;
    if (kode != null) {
      _barcodeController.text = kode;
      await _cariProduk(kode);
    }
  }

  void _tambahKeDaftar() {
    final p = _produkDitemukan;
    if (p == null) return;
    final qty = parseDesimal(_qtyController.text);
    final harga = parseDesimal(_hargaController.text);
    if (qty == null || qty <= 0) {
      _setStateEntri(() => _errorForm = 'Jumlah masuk harus lebih dari 0.');
      return;
    }
    if (harga == null || harga <= 0) {
      _setStateEntri(
          () => _errorForm = 'Harga beli satuan harus lebih dari 0.');
      return;
    }
    if (_kelolaBatch &&
        (_batchController.text.trim().isEmpty || _tanggalExpired == null)) {
      _setStateEntri(() => _errorForm =
          'Nomor batch dan tanggal kedaluwarsa wajib diisi untuk stok terpantau.');
      return;
    }
    _setStateEntri(() {
      _itemsFaktur.add(_ItemFaktur(
        produkId: p['produkId'] as int,
        nama: '${p['nama'] ?? ''}',
        kode: '${p['kode'] ?? ''}',
        qty: qty,
        harga: harga,
        nomorBatch: _kelolaBatch ? _batchController.text.trim() : null,
        tanggalProduksi: _kelolaBatch ? _tanggalProduksi : null,
        tanggalExpired: _kelolaBatch ? _tanggalExpired : null,
      ));
      _produkDitemukan = null;
      _barcodeController.clear();
      _qtyController.clear();
      _hargaController.clear();
      _batchController.clear();
      _tanggalProduksi = null;
      _tanggalExpired = null;
      _errorForm = null;
    });
  }

  Future<void> _pilihTanggalBatch({required bool expired}) async {
    final sekarang = DateTime.now();
    final hasil = await showDatePicker(
      context: context,
      initialDate: expired
          ? (_tanggalExpired ?? sekarang.add(const Duration(days: 365)))
          : (_tanggalProduksi ?? sekarang),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (hasil != null) {
      _setStateEntri(
          () => expired ? _tanggalExpired = hasil : _tanggalProduksi = hasil);
    }
  }

  void _hapusDariDaftar(int index) {
    _setStateEntri(() => _itemsFaktur.removeAt(index));
  }

  double get _totalHitung =>
      _itemsFaktur.fold<double>(0, (a, it) => a + it.total);

  double? get _totalManual => parseDesimal(_totalManualController.text);

  double get _diskonPreview {
    final manual = _totalManual;
    if (manual == null) return 0;
    final selisih = _totalHitung - manual;
    return selisih > 0 ? selisih : 0;
  }

  Future<void> _pilihTanggal() async {
    final hasil = await showDatePicker(
      context: context,
      initialDate: _tanggalFaktur,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (hasil != null) _setStateEntri(() => _tanggalFaktur = hasil);
  }

  Future<void> _pilihSupplier() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihSupplier(),
    );
    if (dipilih != null) _setStateEntri(() => _supplierTerpilih = dipilih);
  }

  Future<void> _simpanFaktur({bool tutupSetelahSimpan = false}) async {
    final nomorFaktur = _fakturController.text.trim();
    if (nomorFaktur.isEmpty) {
      _setStateEntri(() => _errorForm = 'Nomor Faktur wajib diisi.');
      return;
    }
    if (_itemsFaktur.isEmpty) {
      _setStateEntri(() =>
          _errorForm = 'Belum ada barang yang dimasukkan untuk faktur ini.');
      return;
    }
    _setStateEntri(() {
      _menyimpanFaktur = true;
      _errorForm = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kulakan_faktur_simpan', {
        'nomor_faktur': nomorFaktur,
        'tanggal_faktur': _tanggalFaktur.toIso8601String(),
        if (_supplierTerpilih != null) 'supplier_id': _supplierTerpilih!['id'],
        if (_totalManual != null) 'total_faktur_manual': _totalManual,
        'keterangan': _keteranganController.text.trim(),
        'items': _itemsFaktur
            .map((it) => {
                  'produk_id': it.produkId,
                  'qty': it.qty,
                  'harga_beli_satuan': it.harga,
                  if (it.nomorBatch != null) 'nomor_batch': it.nomorBatch,
                  if (it.tanggalProduksi != null)
                    'tanggal_produksi':
                        DateFormat('yyyy-MM-dd').format(it.tanggalProduksi!),
                  if (it.tanggalExpired != null)
                    'tanggal_expired':
                        DateFormat('yyyy-MM-dd').format(it.tanggalExpired!),
                })
            .toList(),
      });
      final diskon = (hasil['diskon'] as num?)?.toDouble() ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(diskon > 0
                ? 'Faktur tersimpan (${_itemsFaktur.length} item). Diskon/potongan: ${_formatRupiah.format(diskon)}.'
                : 'Faktur tersimpan (${_itemsFaktur.length} item).')));
      }
      if (!mounted) return;
      _setStateEntri(() {
        _fakturController.clear();
        _totalManualController.clear();
        _keteranganController.clear();
        _supplierTerpilih = null;
        _tanggalFaktur = DateTime.now();
        _itemsFaktur.clear();
      });
      _halaman = 1;
      await _muatRiwayat();
      if (tutupSetelahSimpan && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      _setStateEntri(() => _errorForm = terapkanGalat(e));
    } finally {
      if (mounted) _setStateEntri(() => _menyimpanFaktur = false);
    }
  }

  Future<void> _bukaEntriFaktur() async {
    final berubah = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _KulakanFakturEntryPage(state: this),
      ),
    );
    if (berubah == true && mounted) {
      _halaman = 1;
      await _muatRiwayat();
    }
  }

  Widget _buildFormEntriFaktur() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppFormSection(
          judul: 'Faktur Baru',
          deskripsi:
              'Isi info faktur sekali, lalu tambahkan barang-barang di faktur ini di bawah.',
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fakturController,
                    decoration: AppFormStyle.fieldDecoration(context,
                        labelText: 'Nomor Faktur *'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: _pilihTanggal,
                    child: InputDecorator(
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Tanggal Faktur *'),
                      child: Text(_formatTanggal.format(_tanggalFaktur)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pilihSupplier,
              child: InputDecorator(
                decoration: AppFormStyle.fieldDecoration(context,
                    labelText: 'Supplier (opsional)',
                    prefixIcon: const Icon(Icons.local_shipping_outlined)),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(_supplierTerpilih == null
                            ? '-- Pilih Supplier --'
                            : '${_supplierTerpilih!['nama']}')),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _totalManualController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: AppFormStyle.fieldDecoration(context,
                  labelText: 'Total Faktur (opsional)',
                  hintText: 'Kosongkan bila sama dgn hitungan baris di bawah'),
              onChanged: (_) => _setStateEntri(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keteranganController,
              decoration: AppFormStyle.fieldDecoration(context,
                  labelText: 'Keterangan (opsional)'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppFormSection(
          judul: 'Tambah Barang',
          children: [
            Row(
              children: [
                Expanded(
                  child: PencarianProdukBanbox(
                    controller: _barcodeController,
                    label: 'Kode / Barcode / Nama Produk',
                    icon: Icons.search,
                    onPilih: _cariProduk,
                    decorationBuilder: (context) =>
                        AppFormStyle.fieldDecoration(context,
                            labelText: 'Kode / Barcode / Nama Produk',
                            prefixIcon: const Icon(Icons.search)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _scanKamera,
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan pakai kamera'),
              ],
            ),
            if (_mencari)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator())),
            if (_errorForm != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.danger),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_errorForm!,
                    style: TextStyle(color: AppColors.danger)),
                  AppDetailGalatOpsional(detail: detailUntuk(_errorForm)),
                ]),
              ),
            if (_produkDitemukan != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.warning),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_produkDitemukan!['nama'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                        'Kode: ${_produkDitemukan!['kode'] ?? ''} Â· Stok: ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}',
                        style: const TextStyle(fontSize: 11.5)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: AppFormStyle.fieldDecoration(context,
                                labelText: 'Jumlah Masuk *', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          // Tanpa hak ubah harga: nilainya ditampilkan sbg
                          // label, bukan kolom isian yang di-disable.
                          child: Sesi.instance.bolehUbahHarga
                              ? TextField(
                                  controller: _hargaController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: AppFormStyle.fieldDecoration(
                                      context,
                                      labelText: 'Harga Beli Satuan *',
                                      isDense: true),
                                )
                              : AppHargaTerkunci(
                                  label: 'Harga Beli Satuan',
                                  nilai: _formatRupiah.format(
                                      double.tryParse(_hargaController.text
                                              .replaceAll(',', '.')
                                              .trim()) ??
                                          0),
                                  catatan:
                                      Sesi.instance.pesanTidakBolehUbahHarga,
                                ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                            onPressed: _tambahKeDaftar,
                            icon: const Icon(Icons.add),
                            tooltip: 'Tambah ke daftar'),
                      ],
                    ),
                    CheckboxListTile(
                      value: _kelolaBatch,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                          'Pantau batch & kedaluwarsa (disarankan)',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Stok dari penerimaan ini akan dikeluarkan otomatis dengan FEFO.',
                          style: TextStyle(fontSize: 11)),
                      onChanged: (v) =>
                          _setStateEntri(() => _kelolaBatch = v ?? true),
                    ),
                    if (_kelolaBatch) ...[
                      Row(children: [
                        Expanded(
                            child: TextField(
                          controller: _batchController,
                          decoration: AppFormStyle.fieldDecoration(context,
                              labelText: 'Nomor Batch / Lot *', isDense: true),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: InkWell(
                          onTap: () => _pilihTanggalBatch(expired: false),
                          child: InputDecorator(
                            decoration: AppFormStyle.fieldDecoration(context,
                                labelText: 'Tanggal Produksi', isDense: true),
                            child: Text(_tanggalProduksi == null
                                ? 'Opsional'
                                : _formatTanggal.format(_tanggalProduksi!)),
                          ),
                        )),
                        const SizedBox(width: 8),
                        Expanded(
                            child: InkWell(
                          onTap: () => _pilihTanggalBatch(expired: true),
                          child: InputDecorator(
                            decoration: AppFormStyle.fieldDecoration(context,
                                labelText: 'Tanggal Kedaluwarsa *',
                                isDense: true),
                            child: Text(_tanggalExpired == null
                                ? 'Pilih tanggal'
                                : _formatTanggal.format(_tanggalExpired!)),
                          ),
                        )),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
            if (_itemsFaktur.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Barang di Faktur Ini',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              ..._itemsFaktur.asMap().entries.map((e) {
                final it = e.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    title: Text(it.nama, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${_formatAngka.format(it.qty)}x @ ${_formatRupiah.format(it.harga)}'
                        '${it.nomorBatch == null ? '' : ' Â· Batch ${it.nomorBatch} Â· Exp ${_formatTanggal.format(it.tanggalExpired!)}'}',
                        style: const TextStyle(fontSize: 11.5)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_formatRupiah.format(it.total),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _hapusDariDaftar(e.key)),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(height: 20),
              _barisRingkas(
                  'Total Hitungan Baris', _formatRupiah.format(_totalHitung)),
              if (_diskonPreview > 0)
                _barisRingkas('Diskon/Potongan (kelebihan hitungan)',
                    '- ${_formatRupiah.format(_diskonPreview)}'),
              _barisRingkas('Total Faktur',
                  _formatRupiah.format(_totalManual ?? _totalHitung),
                  tebal: true),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _menyimpanFaktur
                      ? null
                      : () => _simpanFaktur(tutupSetelahSimpan: true),
                  icon: _menyimpanFaktur
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan Faktur'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Batalkan faktur (aksi `kulakan_faktur_batal`): stok & batch yang diterima
  /// faktur ini DIBALIKKAN server lalu baris + header dihapus ber-audit Envers
  /// (jejak tetap ada di Riwayat Data sbg revisi HAPUS). SENGAJA online-only --
  /// pembatalan mengubah stok, terlalu berisiko diantre diam-diam saat offline.
  Future<void> _batalkanFaktur(
      Map<String, dynamic> f, Map<String, dynamic> header) async {
    final yakin = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Batalkan Faktur?'),
        content: Text(
            'Faktur ${header['nomorFaktur'] ?? ''} akan dibatalkan: stok barang '
            'yang diterima dari faktur ini dikurangi kembali dan datanya dihapus '
            '(riwayat tetap tercatat di audit). Batch yang stoknya sudah '
            'terpakai transaksi lain akan membuat pembatalan DITOLAK server.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Kembali')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Ya, Batalkan')),
        ],
      ),
    );
    if (yakin != true || !mounted) return;
    try {
      final res = await ApiClient.instance
          .aksi('kulakan_faktur_batal', {'faktur_id': f['fakturId']});
      final sukses = res['status'] == '00' || res['status'] == 'success';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(sukses
              ? '${res['description'] ?? 'Faktur dibatalkan.'}'
              : 'Gagal: ${res['description'] ?? res['status']}')));
      if (sukses) {
        Navigator.of(context).pop(); // tutup dialog detail faktur.
        await _muatRiwayat();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membatalkan: $e')));
    }
  }

  /// Perbaiki faktur yang sudah terlanjur diinput.
  ///
  /// Server tidak punya aksi "ubah faktur" — dan memang tidak sepele, karena satu faktur sudah
  /// terlanjur menambah stok, membentuk batch, serta memperbarui harga beli. Karena itu Edit di
  /// sini dijalankan sebagai koreksi yang jujur dan memakai jalur yang sudah teruji:
  /// **faktur lama DIBATALKAN** (stok & batch dikembalikan oleh server, jejaknya tetap tersimpan
  /// sebagai faktur batal), lalu form Entri Faktur dibuka sudah TERISI data lama supaya pengguna
  /// tinggal membetulkan bagian yang salah dan menyimpannya kembali.
  ///
  /// Konsekuensinya disampaikan lebih dulu di dialog konfirmasi, termasuk risiko bila pengguna
  /// menutup form sebelum menyimpan: faktur lama sudah terlanjur batal dan harus dientri ulang.
  Future<void> _editFaktur(Map<String, dynamic> f, Map<String, dynamic> header,
      List<Map<String, dynamic>> items) async {
    final nomor = '${header['nomorFaktur'] ?? ''}';
    final setuju = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit Faktur'),
        content: Text(
            'Faktur $nomor akan DIBATALKAN lebih dulu (stok dan batch yang pernah masuk '
            'dikembalikan), lalu datanya dimuat ke form Entri Faktur agar dapat diperbaiki '
            'dan disimpan kembali.\n\n'
            'Perhatian: bila form ditutup sebelum disimpan, faktur lama tetap dalam keadaan '
            'batal dan perlu dientri ulang.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Lanjut Edit'),
          ),
        ],
      ),
    );
    if (setuju != true) return;

    try {
      final res = await ApiClient.instance
          .aksi('kulakan_faktur_batal', {'faktur_id': f['fakturId']});
      if ('${res['status']}' != '00') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Faktur tidak dapat dibatalkan: ${res['description'] ?? res['status']}')));
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal membatalkan faktur: $e')));
      return;
    }

    if (!mounted) return;
    // Isi ulang form entri dengan data faktur lama.
    _fakturController.text = nomor;
    final tglTeks = '${header['tanggalFaktur'] ?? ''}';
    _tanggalFaktur = DateTime.tryParse(tglTeks) ?? _tanggalFaktur;
    final idSupplier = header['supplierId'];
    _supplierTerpilih = idSupplier == null
        ? null
        : {'id': idSupplier, 'nama': '${header['namaSupplier'] ?? ''}'};
    _keteranganController.text = '${header['keterangan'] ?? ''}';
    _itemsFaktur
      ..clear()
      ..addAll(items.map((it) => _ItemFaktur(
            produkId: ((it['produkId'] as num?) ?? 0).toInt(),
            nama: '${it['namaProduk'] ?? ''}',
            kode: '${it['kodeProduk'] ?? ''}',
            qty: ((it['qty'] as num?) ?? 0).toDouble(),
            harga: ((it['hargaBeliSatuan'] as num?) ?? 0).toDouble(),
          )));
    setStateIfMounted(() {});

    Navigator.of(context).pop(); // tutup dialog detail.
    await _muatRiwayat();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Faktur $nomor dibatalkan. Perbaiki datanya lalu simpan '
            'kembali sebagai faktur pengganti.')));
    await _bukaEntriFaktur();
  }

  Future<void> _lihatDetailFaktur(Map<String, dynamic> f) async {
    Map<String, dynamic>? detail;
    try {
      detail = await ApiClient.instance
          .aksi('kulakan_faktur_detail', {'faktur_id': f['fakturId']});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memuat detail: $e')));
      }
      return;
    }
    if (!mounted) return;
    final header = (detail['header'] as Map?)?.cast<String, dynamic>() ?? {};
    final items =
        ((detail['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    await showDialog<void>(
      context: context,
      builder: (_) => AppDetailDialogShell(
        title: 'Detail Faktur ${header['nomorFaktur'] ?? ''}',
        actions: [
          // Pembatalan faktur: supervisor / pemegang hak akses HAPUS kulakan
          // (server menegakkan lagi lewat bolehAksiCrud -- gating di sini
          // hanya menyembunyikan tombol dari yang jelas tidak berhak).
          if (Sesi.instance.bolehKelola ||
              Sesi.instance.bolehAksiPos('kulakan', 'delete'))
            OutlinedButton.icon(
              onPressed: () => _batalkanFaktur(f, header),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger),
              icon: const Icon(Icons.block_outlined, size: 18),
              label: const Text('Batalkan'),
            ),
          // Perbaikan faktur yang sudah terlanjur diinput. Butuh hak HAPUS (faktur
          // lama dibatalkan) sekaligus hak TAMBAH (faktur pengganti disimpan).
          if (Sesi.instance.bolehKelola ||
              (Sesi.instance.bolehAksiPos('kulakan', 'delete') &&
                  Sesi.instance.bolehAksiPos('kulakan', 'create')))
            OutlinedButton.icon(
              onPressed: () => _editFaktur(f, header, items),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          OutlinedButton.icon(
            onPressed: () => _unduhFakturPdf(header, items),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Pdf'),
          ),
          OutlinedButton.icon(
            onPressed: () => _unduhFakturExcel(header, items),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Excel'),
          ),
          OutlinedButton.icon(
            onPressed: () => _cetakFaktur(header, items),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'))
        ],
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppDetailChip(
                  icon: Icons.schedule_outlined,
                  label: 'Tanggal: ${header['tanggalFaktur'] ?? '-'}'),
              AppDetailChip(
                  icon: Icons.local_shipping_outlined,
                  label:
                      'Supplier: ${(header['namaSupplier'] as String?)?.isNotEmpty == true ? header['namaSupplier'] : '-'}'),
            ],
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            judul: 'Barang (${items.length})',
            child: Column(
              children: items
                  .map((it) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text('${it['namaProduk']}',
                                    style: const TextStyle(fontSize: 13))),
                            Text('${_formatAngka.format(it['qty'] ?? 0)}x',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(width: 10),
                            SizedBox(
                                width: 90,
                                child: Text(
                                    _formatRupiah.format(it['totalHarga'] ?? 0),
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            judul: 'Ringkasan',
            child: Column(
              children: [
                _barisRingkas('Total Hitungan Baris',
                    _formatRupiah.format(header['totalHitung'] ?? 0)),
                if ((header['diskon'] as num? ?? 0) > 0)
                  _barisRingkas('Diskon/Potongan Faktur',
                      '- ${_formatRupiah.format(header['diskon'])}'),
                const Divider(height: 20),
                _barisRingkas('Total Faktur',
                    _formatRupiah.format(header['totalFakturFinal'] ?? 0),
                    tebal: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _LaporanFakturKulakan _buatLaporanFaktur(
      Map<String, dynamic> header, List<Map<String, dynamic>> items) {
    String teks(Map<String, dynamic> sumber, List<String> kunci,
        {String fallback = ''}) {
      for (final k in kunci) {
        final nilai = sumber[k];
        if (nilai != null && '$nilai'.trim().isNotEmpty) return '$nilai'.trim();
      }
      return fallback;
    }

    double angka(Map<String, dynamic> sumber, List<String> kunci) {
      for (final k in kunci) {
        final nilai = sumber[k];
        if (nilai is num) return nilai.toDouble();
        final raw = '$nilai'.trim();
        if (raw.isEmpty || raw == 'null') continue;
        final normal = raw.contains(',')
            ? raw.replaceAll('.', '').replaceAll(',', '.')
            : raw;
        final parsed = double.tryParse(normal) ??
            double.tryParse(raw.replaceAll('.', '').replaceAll(',', '.'));
        if (parsed != null) return parsed;
      }
      return 0;
    }

    final nomorFaktur = teks(header, ['nomorFaktur', 'nomor_faktur'],
        fallback: 'Faktur Kulakan');
    final nomorReferensi = teks(
      header,
      ['nomorReferensi', 'nomorRiwayat', 'nomorPembelian', 'nomorRef'],
      fallback: nomorFaktur.startsWith('PI.')
          ? nomorFaktur.replaceFirst('PI.', 'RI.')
          : '',
    );
    final daftarItem = items.map((it) {
      final qty = angka(it, ['qty', 'jumlah', 'kts']);
      final harga = angka(it, [
        'hargaBeliSatuan',
        'hargaSatuan',
        'harga_beli_satuan',
        'hargaBeli',
        'harga'
      ]);
      final diskon = angka(it, ['diskon', 'diskonBaris', 'potongan']);
      final total = angka(it, ['totalHarga', 'total', 'jumlahHarga']);
      return _ItemLaporanFakturKulakan(
        kode: teks(it, ['kodeBarang', 'kodeProduk', 'barcode', 'sku', 'kode'],
            fallback: '-'),
        nama: teks(it, ['namaProduk', 'namaBarang', 'nama', 'produk'],
            fallback: '-'),
        qty: qty,
        harga: harga,
        diskon: diskon,
        total: total > 0 ? total : (qty * harga) - diskon,
      );
    }).toList();
    final subtotalHeader = angka(header, ['totalHitung', 'subtotal']);
    final subtotal = subtotalHeader > 0
        ? subtotalHeader
        : daftarItem.fold<double>(0, (sum, it) => sum + it.total);
    final diskon = angka(header, ['diskon', 'potongan']);
    final ppn = angka(header, ['ppn', 'pajak']);
    final biayaLain = angka(header, ['biayaLain', 'biaya_lain']);
    final totalHeader =
        angka(header, ['totalFakturFinal', 'totalFaktur', 'total']);
    final total =
        totalHeader > 0 ? totalHeader : subtotal - diskon + ppn + biayaLain;

    return _LaporanFakturKulakan(
      toko: Sesi.instance.tokoNama.trim().isEmpty
          ? 'Ekonomi Syariah'
          : Sesi.instance.tokoNama.trim(),
      alamat: Sesi.instance.tokoAlamat.trim().isEmpty
          ? 'Kab. Cirebon Jawa Barat 45611\nIndonesia'
          : Sesi.instance.tokoAlamat.trim(),
      supplier: teks(header, ['namaSupplier', 'supplier', 'supplierNama'],
          fallback: '-'),
      nomorFaktur: nomorFaktur,
      nomorReferensi: nomorReferensi,
      tanggal: _formatTanggalLaporan(header['tanggalFaktur']),
      keterangan: teks(header, ['keterangan', 'catatan']),
      subtotal: subtotal,
      diskon: diskon,
      ppn: ppn,
      biayaLain: biayaLain,
      total: total,
      items: daftarItem,
    );
  }

  String _formatTanggalLaporan(Object? nilai) {
    if (nilai is DateTime) {
      return DateFormat('dd MMM yyyy', 'id_ID').format(nilai);
    }
    final raw = '$nilai'.trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return DateFormat('dd MMM yyyy', 'id_ID').format(parsed);
    }
    return raw.isEmpty || raw == 'null' ? '-' : raw;
  }

  String _formatQtyLaporan(double nilai) {
    if (nilai == nilai.roundToDouble()) {
      return _formatAngka.format(nilai.round());
    }
    return _formatAngka.format(nilai);
  }

  String _namaFileAman(String nilai) => nilai
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  Future<void> _simpanUnduhanLaporan({
    required String namaFile,
    required Uint8List bytes,
    required String ekstensi,
    required String judulDialog,
    required String pesanSukses,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: judulDialog,
      fileName: namaFile,
      type: FileType.custom,
      allowedExtensions: [ekstensi],
      bytes: bytes,
    );
    if (path == null) return;
    await File(path).writeAsBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(pesanSukses)));
  }

  Future<void> _unduhFakturExcel(
      Map<String, dynamic> header, List<Map<String, dynamic>> items) async {
    try {
      final data = _buatLaporanFaktur(header, items);
      const tableRow = 9;
      final totalRow = tableRow + data.items.length + 5;
      final rows = <List<Object?>>[
        ['', '', data.toko],
        ['', '', data.alamat],
        const [],
        ['Dari', '', '', '', 'Faktur Pembelian'],
        [data.supplier, '', '', '', ': ${data.nomorFaktur}'],
        [
          '',
          '',
          '',
          '',
          if (data.nomorReferensi.isEmpty) '' else ': ${data.nomorReferensi}'
        ],
        ['', '', '', '', ': ${data.tanggal}'],
        const [],
        const [
          'Kode Barang',
          'Nama Barang',
          'Kts.',
          '@Harga',
          'Diskon',
          'Total Harga'
        ],
        ...data.items.map((it) => [
              it.kode,
              it.nama,
              it.qty,
              it.harga,
              it.diskon,
              it.total,
            ]),
        ['Keterangan', data.keterangan, '', '', 'Sub Total', data.subtotal],
        ['', '', '', '', 'Diskon', data.diskon],
        ['', '', '', '', 'PPN (0%)', data.ppn],
        ['Bagian Pembelian,', '', '', '', 'Biaya Lain-lain', data.biayaLain],
        ['Tgl.', '', '', '', 'Total', data.total],
        ['', '', '', '', 'Halaman 1 dari', 1],
      ];
      final bytes = buildSimpleXlsxReport(
        sheetName: 'Faktur Pembelian',
        rows: rows,
        boldRows: {1, 4, totalRow},
        darkRows: {tableRow, totalRow},
        columnWidths: const [16, 36, 10, 14, 12, 16],
      );
      final aman = _namaFileAman(data.nomorFaktur);
      await _simpanUnduhanLaporan(
        namaFile: 'Faktur-Pembelian-$aman.xlsx',
        bytes: bytes,
        ekstensi: 'xlsx',
        judulDialog: 'Simpan Faktur Pembelian Excel',
        pesanSukses: 'File Excel faktur berhasil dibuat.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat Excel faktur: $e')));
    }
  }

  /// Bangun dokumen faktur. Dipisah dari penyimpanan supaya tombol Pdf
  /// (simpan berkas) dan Print (kirim ke printer) memakai SATU sumber tata
  /// letak -- kalau digandakan, format cetak akan diam-diam menyimpang dari
  /// format PDF setiap kali salah satunya diubah.
  pw.Document _dokumenFakturPdf(
      Map<String, dynamic> header, List<Map<String, dynamic>> items) {
    final data = _buatLaporanFaktur(header, items);
      final biru = PdfColor.fromInt(0xff0f3b5f);
      final abu = PdfColor.fromInt(0xffe5e7eb);
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          footer: (ctx) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8)),
          ),
          build: (_) => [
            pw.Center(
              child: pw.Column(children: [
                pw.Text(data.toko,
                    style: pw.TextStyle(
                        fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text(data.alamat,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        decoration: pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 1))),
                        child: pw.Text('Dari',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      ),
                      pw.Container(
                        width: double.infinity,
                        height: 42,
                        color: PdfColor.fromInt(0xffd8dde5),
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text(data.supplier,
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 42),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        decoration: pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(width: 1))),
                        child: pw.Text('Faktur Pembelian',
                            style: const pw.TextStyle(fontSize: 18)),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(': ${data.nomorFaktur}'),
                      if (data.nomorReferensi.isNotEmpty)
                        pw.Text(': ${data.nomorReferensi}'),
                      pw.Text(': ${data.tanggal}'),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: abu, width: 0.4),
              headerDecoration: pw.BoxDecoration(color: biru),
              headerStyle: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              columnWidths: {
                0: const pw.FixedColumnWidth(75),
                1: const pw.FlexColumnWidth(2.2),
                2: const pw.FixedColumnWidth(45),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FixedColumnWidth(60),
                5: const pw.FixedColumnWidth(80),
              },
              cellAlignments: {
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              headers: const [
                'Kode Barang',
                'Nama Barang',
                'Kts.',
                '@Harga',
                'Diskon',
                'Total Harga'
              ],
              data: data.items
                  .map((it) => [
                        it.kode,
                        it.nama,
                        _formatQtyLaporan(it.qty),
                        _formatAngka.format(it.harga),
                        _formatAngka.format(it.diskon),
                        _formatAngka.format(it.total),
                      ])
                  .toList(),
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Keterangan',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Container(
                        width: double.infinity,
                        height: 54,
                        padding: const pw.EdgeInsets.all(5),
                        decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: biru, width: 0.8)),
                        child: pw.Text(data.keterangan),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text('Bagian Pembelian,'),
                      pw.SizedBox(height: 12),
                      pw.Text('Tgl.'),
                    ],
                  ),
                ),
                pw.SizedBox(width: 28),
                pw.Container(
                  width: 230,
                  child: pw.Column(children: [
                    _barisTotalPdf('Sub Total', data.subtotal),
                    _barisTotalPdf('Diskon', data.diskon),
                    _barisTotalPdf('PPN (0%)', data.ppn),
                    _barisTotalPdf('Biaya Lain-lain', data.biayaLain),
                    _barisTotalPdf('Total', data.total,
                        gelap: true, warnaGelap: biru),
                  ]),
                ),
              ],
            ),
          ],
        ),
      );
    return doc;
  }

  Future<void> _unduhFakturPdf(
      Map<String, dynamic> header, List<Map<String, dynamic>> items) async {
    try {
      final doc = _dokumenFakturPdf(header, items);
      final aman = _namaFileAman(_buatLaporanFaktur(header, items).nomorFaktur);
      await _simpanUnduhanLaporan(
        namaFile: 'Faktur-Pembelian-$aman.pdf',
        bytes: await doc.save(),
        ekstensi: 'pdf',
        judulDialog: 'Simpan Faktur Pembelian PDF',
        pesanSukses: 'File PDF faktur berhasil dibuat.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuat PDF faktur: $e')));
    }
  }

  /// Kirim faktur langsung ke printer, memakai tata letak yang PERSIS SAMA
  /// dengan tombol Pdf.
  Future<void> _cetakFaktur(
      Map<String, dynamic> header, List<Map<String, dynamic>> items) async {
    try {
      final doc = _dokumenFakturPdf(header, items);
      final aman = _namaFileAman(_buatLaporanFaktur(header, items).nomorFaktur);
      await Printing.layoutPdf(
        name: 'Faktur-Pembelian-$aman',
        onLayout: (format) async => doc.save(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencetak faktur: $e')));
    }
  }

  pw.Widget _barisTotalPdf(String label, double nilai,
      {bool gelap = false, PdfColor? warnaGelap}) {
    return pw.Container(
      color: gelap ? warnaGelap : PdfColors.white,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  color: gelap ? PdfColors.white : PdfColors.black,
                  fontWeight: gelap ? pw.FontWeight.bold : pw.FontWeight.normal,
                  fontSize: 8)),
          pw.Text(_formatAngka.format(nilai),
              style: pw.TextStyle(
                  color: gelap ? PdfColors.white : PdfColors.black,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 8)),
        ],
      ),
    );
  }

  Widget _barisRingkas(String label, String nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textSecondaryOf(context))),
          Text(nilai,
              style: TextStyle(
                  fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
                  color: tebal
                      ? AppColors.primary
                      : AppColors.textPrimaryOf(context))),
        ],
      ),
    );
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muatRiwayat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (Sesi.instance.bolehKelola) ...[
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _bukaEntriFaktur,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Entri Faktur'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final berubah = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => const KulakanBulkEntryScreen(),
                        ),
                      );
                      if (berubah == true) {
                        _halaman = 1;
                        await _muatRiwayat();
                      }
                    },
                    icon: const Icon(Icons.playlist_add_outlined, size: 18),
                    label: const Text('Bulk Entry Faktur'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                  'Hanya admin/supervisor toko yang dapat mencatat kulakan baru. Riwayat di bawah tetap bisa dilihat.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontStyle: FontStyle.italic)),
            ),
          const Text('Riwayat Faktur',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(
                    width: 190,
                    child: AppKpiCard(
                        icon: Icons.receipt_long_outlined,
                        warna: AppColors.primary,
                        nilai: '$_total',
                        label: 'Total Faktur')),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.payments_outlined,
                    warna: AppColors.teal,
                    nilai: _formatRupiah.format(_riwayat.fold<num>(
                        0, (a, f) => a + ((f['totalHitung'] as num?) ?? 0))),
                    label: 'Nilai (hal. ini)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: AppFormStyle.fieldDecoration(context,
                labelText: 'Cari Riwayat',
                hintText: 'Cari nomor faktur/nama supplier...',
                prefixIcon: const Icon(Icons.search),
                isDense: true),
            onSubmitted: (v) {
              _kataKunciRiwayat = v;
              _halaman = 1;
              _muatRiwayat();
            },
          ),
          const SizedBox(height: 8),
          BannerPerubahanServer(
            key: ValueKey('perubahan:${_diff.versi}'),
            baru: _diff.idBaru.length,
            berubah: _diff.idBerubah.length,
            dihapus: _diff.jumlahHapus,
          ),
          if (_memuatRiwayat)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()))
          else if (_errorRiwayat != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_errorRiwayat!),
                  AppDetailGalatOpsional(detail: detailUntuk(_errorRiwayat)),
                ])))
          else
            AppDataTable(
              minWidth: 900,
              emptyText: 'Belum ada riwayat faktur.',
              columns: const [
                AppTableColumn('Faktur', flex: 2),
                AppTableColumn('Tanggal', flex: 2),
                AppTableColumn('Supplier', flex: 2),
                AppTableColumn('Item', flex: 1, align: TextAlign.right),
                AppTableColumn('Total', flex: 2, align: TextAlign.right),
              ],
              rows: _riwayat.map((f) {
                final supplier =
                    (f['namaSupplier'] as String?)?.isNotEmpty == true
                        ? '${f['namaSupplier']}'
                        : '-';
                final diskon = (f['diskon'] as num?) ?? 0;
                final totalFinal = diskon > 0
                    ? ((f['totalHitung'] as num? ?? 0) - diskon)
                    : (f['totalHitung'] ?? 0);
                return AppTableRowData(cells: [
                  AppTableCell(
                    flex: 2,
                    child: KilauBaris(
                      kunci: _kunciKilau(f),
                      idBaru: _diff.idBaru,
                      idBerubah: _diff.idBerubah,
                      child: Text('${f['nomorFaktur']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                  AppTableCell.text('${f['tanggalFaktur']}', flex: 2),
                  AppTableCell.text(supplier, flex: 2),
                  AppTableCell.text('${f['jumlahItem'] ?? 0}',
                      flex: 1, align: TextAlign.right),
                  AppTableCell.text(_formatRupiah.format(totalFinal),
                      flex: 2,
                      align: TextAlign.right,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12.5)),
                ], onTap: () => _lihatDetailFaktur(f));
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'faktur',
                onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman
                    ? () => _pindah(_halaman + 1)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _KulakanFakturEntryPage extends StatefulWidget {
  final _TabKulakanFakturState state;

  const _KulakanFakturEntryPage({required this.state});

  @override
  State<_KulakanFakturEntryPage> createState() =>
      _KulakanFakturEntryPageState();
}

class _KulakanFakturEntryPageState extends State<_KulakanFakturEntryPage> {
  @override
  void initState() {
    super.initState();
    widget.state._refreshHalamanEntri = () {
      if (mounted) setState(() {});
    };
  }

  @override
  void dispose() {
    if (widget.state._refreshHalamanEntri != null) {
      widget.state._refreshHalamanEntri = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kulakan,
      judul: 'Entri Faktur Kulakan',
      subjudul: 'Input faktur pembelian dan barang yang diterima',
      scrollable: false,
      body: widget.state._buildFormEntriFaktur(),
      aksiHeader: OutlinedButton.icon(
        onPressed: () => Navigator.of(context).pop(false),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: const Text('Kembali'),
      ),
    );
  }
}

/// Bottom-sheet picker Supplier (`library.Penyedia`, gap-closure "supplier belum ngelink ke
/// master supplier") -- cari via `penyedia_list`, tambah cepat via `penyedia_simpan` (inline,
/// tanpa perlu pindah ke modul lain) supaya alur "supplier baru belum terdaftar" tidak memblokir.
class _SheetPilihSupplier extends StatefulWidget {
  const _SheetPilihSupplier();
  @override
  State<_SheetPilihSupplier> createState() => _SheetPilihSupplierState();
}

class _SheetPilihSupplierState extends State<_SheetPilihSupplier> {
  final _cariController = TextEditingController();
  final _namaBaruController = TextEditingController();
  bool _memuat = true;
  bool _menyimpanBaru = false;
  bool _tampilFormBaru = false;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  void dispose() {
    _cariController.dispose();
    _namaBaruController.dispose();
    super.dispose();
  }

  Future<void> _cari(String keyword) async {
    setStateIfMounted(() => _memuat = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('penyedia_list', {'keyword': keyword});
      setStateIfMounted(() => _daftar =
          ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (_) {
      // gagal muat -- biarkan daftar kosong, bukan blocker fatal utk sheet ini.
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _simpanSupplierBaru() async {
    final nama = _namaBaruController.text.trim();
    if (nama.isEmpty) return;
    setStateIfMounted(() => _menyimpanBaru = true);
    try {
      final hasil =
          await ApiClient.instance.aksi('penyedia_simpan', {'nama': nama});
      if (mounted) {
        Navigator.of(context).pop({'id': hasil['id'], 'nama': hasil['nama']});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menambah supplier: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpanBaru = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Pilih Supplier',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _cariController,
              decoration: AppFormStyle.fieldDecoration(context,
                  labelText: 'Cari nama supplier...',
                  prefixIcon: const Icon(Icons.search)),
              onSubmitted: _cari,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollController,
                      children: [
                        ..._daftar.map((s) => ListTile(
                              leading:
                                  const Icon(Icons.local_shipping_outlined),
                              title: Text('${s['nama']}'),
                              subtitle:
                                  (s['telp'] as String?)?.isNotEmpty == true
                                      ? Text('${s['telp']}')
                                      : null,
                              onTap: () => Navigator.of(context).pop(s),
                            )),
                        if (_daftar.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(20),
                              child: Text('Tidak ada supplier ditemukan.')),
                      ],
                    ),
            ),
            const Divider(),
            if (!_tampilFormBaru)
              TextButton.icon(
                onPressed: () =>
                    setStateIfMounted(() => _tampilFormBaru = true),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Supplier Baru'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _namaBaruController,
                      decoration: AppFormStyle.fieldDecoration(context,
                          labelText: 'Nama Supplier Baru', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _menyimpanBaru ? null : _simpanSupplierBaru,
                    icon: _menyimpanBaru
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LaporanFakturKulakan {
  final String toko;
  final String alamat;
  final String supplier;
  final String nomorFaktur;
  final String nomorReferensi;
  final String tanggal;
  final String keterangan;
  final double subtotal;
  final double diskon;
  final double ppn;
  final double biayaLain;
  final double total;
  final List<_ItemLaporanFakturKulakan> items;

  const _LaporanFakturKulakan({
    required this.toko,
    required this.alamat,
    required this.supplier,
    required this.nomorFaktur,
    required this.nomorReferensi,
    required this.tanggal,
    required this.keterangan,
    required this.subtotal,
    required this.diskon,
    required this.ppn,
    required this.biayaLain,
    required this.total,
    required this.items,
  });
}

class _ItemLaporanFakturKulakan {
  final String kode;
  final String nama;
  final double qty;
  final double harga;
  final double diskon;
  final double total;

  const _ItemLaporanFakturKulakan({
    required this.kode,
    required this.nama,
    required this.qty,
    required this.harga,
    required this.diskon,
    required this.total,
  });
}
