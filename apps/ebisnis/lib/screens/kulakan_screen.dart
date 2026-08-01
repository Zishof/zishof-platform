import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';

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
    setState(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('kulakan_list', {'page': _halaman, 'page_size': _pageSize});
      setState(() {
        _riwayat = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setState(() => _errorRiwayat = e.toString());
    } finally {
      if (mounted) setState(() => _memuatRiwayat = false);
    }
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muatRiwayat();
  }

  Future<void> _cariProduk(String barcode) async {
    final kode = barcode.trim();
    if (kode.isEmpty) return;
    setState(() {
      _mencari = true;
      _errorForm = null;
      _produkDitemukan = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      setState(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
        _fakturController.clear();
        _supplierController.clear();
        _keteranganController.clear();
      });
    } catch (e) {
      setState(() => _errorForm = e.toString());
    } finally {
      if (mounted) setState(() => _mencari = false);
    }
  }

  Future<void> _scanKamera() async {
    final kode = await BarcodeScannerScreen.pindai(context, judul: 'Scan Barcode Produk');
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
      setState(() => _errorForm = 'Jumlah masuk harus lebih dari 0.');
      return;
    }
    if (harga == null || harga <= 0) {
      setState(() => _errorForm = 'Harga beli satuan harus lebih dari 0.');
      return;
    }
    setState(() {
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
      setState(() {
        _produkDitemukan = null;
        _barcodeController.clear();
      });
      _halaman = 1;
      await _muatRiwayat();
    } catch (e) {
      setState(() => _errorForm = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
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
                      decoration: const InputDecoration(labelText: 'Kode / Barcode Produk', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)),
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
                Card(
                  color: const Color(0xFFFFF3E0),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_produkDitemukan!['nama'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Kode: ${_produkDitemukan!['kode'] ?? ''} · Stok Sistem: ${_formatAngka.format(_produkDitemukan!['stokSistem'] ?? 0)}'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Jumlah Masuk *', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _hargaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Harga Beli Satuan *', border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: _fakturController, decoration: const InputDecoration(labelText: 'Nomor Faktur', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _supplierController, decoration: const InputDecoration(labelText: 'Nama Supplier', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: _keteranganController, decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _menyimpan ? null : _simpanKulakan,
                            child: _menyimpan ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan Kulakan'),
                          ),
                        ),
                      ],
                    ),
                  ),
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
            if (_memuatRiwayat)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            else if (_errorRiwayat != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(_errorRiwayat!)))
            else if (_riwayat.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Belum ada riwayat kulakan.')))
            else ...[
              ..._riwayat.map((k) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text('${k['namaProduk']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('${k['waktuPengadaan']} · ${(k['namaSupplier'] as String?)?.isNotEmpty == true ? k['namaSupplier'] : "-"}${(k['nomorFaktur'] as String?)?.isNotEmpty == true ? " · ${k['nomorFaktur']}" : ""}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${_formatAngka.format(k['qty'] ?? 0)}x', style: const TextStyle(fontSize: 12)),
                          Text(_formatRupiah.format(k['totalHarga'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  )),
              if (_total > _pageSize)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(icon: const Icon(Icons.chevron_left), onPressed: _halaman > 1 ? () => _pindah(_halaman - 1) : null),
                      Text('Halaman $_halaman / $_totalHalaman'),
                      IconButton(icon: const Icon(Icons.chevron_right), onPressed: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
