import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngka = NumberFormat.decimalPattern('id_ID');

/// Layar Kulakan (padanan kulakan.html/kulakan-renderer.js Electron) --
/// catat pengadaan/pembelian stok dari supplier. Pencarian produk memakai
/// aksi `so_produk_scan` yg sama dgn Stok Opname (kartu produk identik).
/// Riwayat (`kulakan_list`) bisa dilihat siapa saja; entri baru
/// (`kulakan_simpan`) digerbang admin/supervisor server-side, dicerminkan
/// lewat Sesi.instance.bolehKelola.
class KulakanScreen extends StatefulWidget {
  const KulakanScreen({super.key});
  @override
  State<KulakanScreen> createState() => _KulakanScreenState();
}

class _KulakanScreenState extends State<KulakanScreen> {
  static const _pageSize = 20;
  final _barcodeController = TextEditingController();
  final _qtyController = TextEditingController();
  final _hargaController = TextEditingController();
  final _fakturController = TextEditingController();
  final _supplierController = TextEditingController();
  final _keteranganController = TextEditingController();

  bool _mencari = false;
  bool _menyimpan = false;
  String? _errorForm;
  Map<String, dynamic>? _produkDitemukan;

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
    _barcodeController.dispose();
    _qtyController.dispose();
    _hargaController.dispose();
    _fakturController.dispose();
    _supplierController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    if (!mounted) return;
    setStateIfMounted(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kulakan_list', {
        'page': _halaman,
        'page_size': _pageSize,
        if (_kataKunciRiwayat.isNotEmpty) 'keyword': _kataKunciRiwayat,
      });
      if (!mounted) return;
      setStateIfMounted(() {
        _riwayat = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
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
      final hasil = await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      if (!mounted) return;
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
        _fakturController.clear();
        _supplierController.clear();
        _keteranganController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context, judul: 'Scan Barcode Produk');
    if (!mounted) return;
    if (kode != null) {
      _barcodeController.text = kode;
      await _cariProduk(kode);
    }
  }

  Future<void> _simpanKulakan() async {
    final p = _produkDitemukan;
    if (p == null) return;
    final qty = double.tryParse(_qtyController.text.replaceAll(',', '.'));
    final harga = double.tryParse(_hargaController.text.replaceAll(',', '.'));
    if (qty == null || qty <= 0) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = 'Jumlah masuk harus lebih dari 0.');
      return;
    }
    if (harga == null || harga <= 0) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = 'Harga beli satuan harus lebih dari 0.');
      return;
    }
    if (!mounted) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _errorForm = null;
    });
    try {
      await ApiClient.instance.aksi('kulakan_simpan', {
        'produk_id': p['produkId'],
        'qty': qty,
        'harga_beli_satuan': harga,
        'nomor_faktur': _fakturController.text.trim(),
        'nama_supplier': _supplierController.text.trim(),
        'keterangan': _keteranganController.text.trim(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kulakan tersimpan.')));
      if (!mounted) return;
      setStateIfMounted(() {
        _produkDitemukan = null;
        _barcodeController.clear();
      });
      _halaman = 1;
      await _muatRiwayat();
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<void> _lihatDetailKulakan(Map<String, dynamic> k) async {
    final supplier =
        (k['namaSupplier'] as String?)?.isNotEmpty == true ? '${k['namaSupplier']}' : '-';
    final faktur =
        (k['nomorFaktur'] as String?)?.isNotEmpty == true ? '${k['nomorFaktur']}' : '-';
    final qty = (k['qty'] as num?) ?? 0;
    final total = (k['totalHarga'] as num?) ?? 0;
    final hargaSatuan = qty == 0 ? 0 : total / qty;
    await showDialog<void>(
      context: context,
      builder: (_) => AppDetailDialogShell(
        title: 'Detail Kulakan',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppDetailChip(
                icon: Icons.inventory_2_outlined,
                label: '${k['namaProduk'] ?? '-'}',
                color: AppColors.primary,
              ),
              AppDetailChip(
                icon: Icons.schedule_outlined,
                label: 'Waktu: ${k['waktuPengadaan'] ?? '-'}',
              ),
              AppDetailChip(
                icon: Icons.local_shipping_outlined,
                label: 'Supplier: $supplier',
              ),
              AppDetailChip(
                icon: Icons.receipt_long_outlined,
                label: 'Faktur: $faktur',
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppSectionCard(
            judul: 'Ringkasan Pengadaan',
            child: Column(
              children: [
                _barisDetailKulakan('Jumlah Masuk', '${_formatAngka.format(qty)}x'),
                _barisDetailKulakan(
                    'Harga Beli Satuan', _formatRupiah.format(hargaSatuan)),
                const Divider(height: 20),
                _barisDetailKulakan(
                  'Total',
                  _formatRupiah.format(total),
                  tebal: true,
                ),
              ],
            ),
          ),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _barisDetailKulakan(String label, String nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context))),
          Text(
            nilai,
            style: TextStyle(
              fontWeight: tebal ? FontWeight.w800 : FontWeight.w600,
              color: tebal ? AppColors.primary : AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.kulakan,
      judul: 'Kulakan',
      subjudul: 'Catat pengadaan/pembelian stok dari supplier',
      scrollable: false,
      body: RefreshIndicator(
        onRefresh: _muatRiwayat,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (Sesi.instance.bolehKelola) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeController,
                      decoration: AppFormStyle.fieldDecoration(
                        context,
                        labelText: 'Kode / Barcode Produk',
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onSubmitted: _cariProduk,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: _scanKamera, icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan pakai kamera'),
                ],
              ),
              const SizedBox(height: 12),
              if (_mencari) const Center(child: CircularProgressIndicator()),
              if (_errorForm != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Text(_errorForm!, style: TextStyle(color: Colors.red.shade700)),
                ),
              if (_produkDitemukan != null) ...[
                AppFormSection(
                  judul: 'Tambah Kulakan',
                  deskripsi:
                      'Produk ditemukan. Lengkapi jumlah masuk, harga beli, dan catatan supplier.',
                  aksiJudul: StatusPill(
                    label:
                        'Stok ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}',
                    warna: AppColors.warning,
                  ),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppDetailChip(
                          icon: Icons.inventory_2_outlined,
                          label: '${_produkDitemukan!['nama'] ?? ''}',
                          color: AppColors.primary,
                        ),
                        AppDetailChip(
                          icon: Icons.qr_code_2_outlined,
                          label: 'Kode: ${_produkDitemukan!['kode'] ?? ''}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                  context,
                                  labelText: 'Jumlah Masuk *',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _hargaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: AppFormStyle.fieldDecoration(
                                  context,
                                  labelText: 'Harga Beli Satuan *',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _fakturController,
                          decoration: AppFormStyle.fieldDecoration(
                            context,
                            labelText: 'Nomor Faktur',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _supplierController,
                          decoration: AppFormStyle.fieldDecoration(
                            context,
                            labelText: 'Nama Supplier',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _keteranganController,
                          decoration: AppFormStyle.fieldDecoration(
                            context,
                            labelText: 'Keterangan',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _menyimpan ? null : _simpanKulakan,
                            icon: _menyimpan
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Simpan Kulakan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 12),
                            ),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Hanya admin/supervisor toko yang dapat mencatat kulakan baru. Riwayat di bawah tetap bisa dilihat.',
                    style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
              ),
            const Text('Riwayat Kulakan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  SizedBox(width: 190, child: AppKpiCard(icon: Icons.local_shipping_outlined, warna: AppColors.primary, nilai: '$_total', label: 'Total Kulakan')),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 190,
                    child: AppKpiCard(
                      icon: Icons.payments_outlined,
                      warna: AppColors.teal,
                      nilai: _formatRupiah.format(_riwayat.fold<num>(0, (a, k) => a + ((k['totalHarga'] as num?) ?? 0))),
                      label: 'Nilai (hal. ini)',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: AppFormStyle.fieldDecoration(
                context,
                labelText: 'Cari Riwayat',
                hintText: 'Cari nama produk/faktur/supplier...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onSubmitted: (v) {
                _kataKunciRiwayat = v;
                _halaman = 1;
                _muatRiwayat();
              },
            ),
            const SizedBox(height: 8),
            if (_memuatRiwayat)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            else if (_errorRiwayat != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(_errorRiwayat!)))
            else
              AppDataTable(
                minWidth: 900,
                emptyText: 'Belum ada riwayat kulakan.',
                columns: const [
                  AppTableColumn('Produk', flex: 3),
                  AppTableColumn('Waktu', flex: 2),
                  AppTableColumn('Supplier', flex: 2),
                  AppTableColumn('Faktur', flex: 2),
                  AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                  AppTableColumn('Total', flex: 2, align: TextAlign.right),
                ],
                rows: _riwayat.map((k) {
                  final supplier = (k['namaSupplier'] as String?)?.isNotEmpty == true ? '${k['namaSupplier']}' : '-';
                  final faktur = (k['nomorFaktur'] as String?)?.isNotEmpty == true ? '${k['nomorFaktur']}' : '-';
                  return AppTableRowData(cells: [
                    AppTableCell.text('${k['namaProduk']}', flex: 3, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    AppTableCell.text('${k['waktuPengadaan']}', flex: 2),
                    AppTableCell.text(supplier, flex: 2),
                    AppTableCell.text(faktur, flex: 2),
                    AppTableCell.text('${_formatAngka.format(k['qty'] ?? 0)}x', flex: 1, align: TextAlign.right),
                    AppTableCell.text(_formatRupiah.format(k['totalHarga'] ?? 0), flex: 2, align: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  ], onTap: () => _lihatDetailKulakan(k));
                }).toList(),
                pagination: AppTablePagination(
                  halaman: _halaman,
                  totalHalaman: _totalHalaman,
                  totalData: _total,
                  labelData: 'kulakan',
                  onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                  onBerikutnya: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
