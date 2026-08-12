import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../parse_util.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';
import 'retur_pembelian_screen.dart';

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

class _TabKulakanFakturState extends State<_TabKulakanFaktur> {
  static const _pageSize = 20;

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

  // ==== Riwayat (per-faktur) ====
  bool _memuatRiwayat = true;
  String? _errorRiwayat;
  List<Map<String, dynamic>> _riwayat = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunciRiwayat = '';

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
    setStateIfMounted(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kulakan_faktur_list', {
        'page': _halaman,
        'page_size': _pageSize,
        if (_kataKunciRiwayat.isNotEmpty) 'keyword': _kataKunciRiwayat,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        _riwayat =
            ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _errorRiwayat = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuatRiwayat = false);
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
    setStateIfMounted(() {
      _mencari = true;
      _errorForm = null;
      _produkDitemukan = null;
    });
    try {
      final hasil =
          await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (!mounted) return;
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
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
      setStateIfMounted(() => _errorForm = 'Jumlah masuk harus lebih dari 0.');
      return;
    }
    if (harga == null || harga <= 0) {
      setStateIfMounted(
          () => _errorForm = 'Harga beli satuan harus lebih dari 0.');
      return;
    }
    if (_kelolaBatch &&
        (_batchController.text.trim().isEmpty || _tanggalExpired == null)) {
      setStateIfMounted(() => _errorForm =
          'Nomor batch dan tanggal kedaluwarsa wajib diisi untuk stok terpantau.');
      return;
    }
    setStateIfMounted(() {
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
    if (hasil != null)
      setStateIfMounted(
          () => expired ? _tanggalExpired = hasil : _tanggalProduksi = hasil);
  }

  void _hapusDariDaftar(int index) {
    setStateIfMounted(() => _itemsFaktur.removeAt(index));
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
    if (hasil != null) setStateIfMounted(() => _tanggalFaktur = hasil);
  }

  Future<void> _pilihSupplier() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihSupplier(),
    );
    if (dipilih != null) setStateIfMounted(() => _supplierTerpilih = dipilih);
  }

  Future<void> _simpanFaktur() async {
    final nomorFaktur = _fakturController.text.trim();
    if (nomorFaktur.isEmpty) {
      setStateIfMounted(() => _errorForm = 'Nomor Faktur wajib diisi.');
      return;
    }
    if (_itemsFaktur.isEmpty) {
      setStateIfMounted(() =>
          _errorForm = 'Belum ada barang yang dimasukkan untuk faktur ini.');
      return;
    }
    setStateIfMounted(() {
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
      setStateIfMounted(() {
        _fakturController.clear();
        _totalManualController.clear();
        _keteranganController.clear();
        _supplierTerpilih = null;
        _tanggalFaktur = DateTime.now();
        _itemsFaktur.clear();
      });
      _halaman = 1;
      await _muatRiwayat();
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpanFaktur = false);
    }
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
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'))
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
                      hintText:
                          'Kosongkan bila sama dgn hitungan baris di bawah'),
                  onChanged: (_) => setStateIfMounted(() {}),
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
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(_errorForm!,
                        style: TextStyle(color: Colors.red.shade700)),
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
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'Kode: ${_produkDitemukan!['kode'] ?? ''} · Stok: ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}',
                            style: const TextStyle(fontSize: 11.5)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Jumlah Masuk *',
                                    isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _hargaController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Harga Beli Satuan *',
                                    isDense: true),
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
                              setStateIfMounted(() => _kelolaBatch = v ?? true),
                        ),
                        if (_kelolaBatch) ...[
                          Row(children: [
                            Expanded(
                                child: TextField(
                              controller: _batchController,
                              decoration: AppFormStyle.fieldDecoration(context,
                                  labelText: 'Nomor Batch / Lot *',
                                  isDense: true),
                            )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: InkWell(
                              onTap: () => _pilihTanggalBatch(expired: false),
                              child: InputDecorator(
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
                                    labelText: 'Tanggal Produksi',
                                    isDense: true),
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
                                decoration: AppFormStyle.fieldDecoration(
                                    context,
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
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ..._itemsFaktur.asMap().entries.map((e) {
                    final it = e.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title:
                            Text(it.nama, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                            '${_formatAngka.format(it.qty)}x @ ${_formatRupiah.format(it.harga)}'
                            '${it.nomorBatch == null ? '' : ' · Batch ${it.nomorBatch} · Exp ${_formatTanggal.format(it.tanggalExpired!)}'}',
                            style: const TextStyle(fontSize: 11.5)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatRupiah.format(it.total),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5)),
                            IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => _hapusDariDaftar(e.key)),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 20),
                  _barisRingkas('Total Hitungan Baris',
                      _formatRupiah.format(_totalHitung)),
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
                      onPressed: _menyimpanFaktur ? null : _simpanFaktur,
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
          if (_memuatRiwayat)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()))
          else if (_errorRiwayat != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(_errorRiwayat!)))
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
                  AppTableCell.text('${f['nomorFaktur']}',
                      flex: 2,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
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
      if (mounted)
        Navigator.of(context).pop({'id': hasil['id'], 'nama': hasil['nama']});
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
