import 'package:core_hw/core_hw.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../parse_util.dart';
import '../sesi.dart';
import '../widgets/app_components.dart';
import '../widgets/pencarian_produk_banbox.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
final _formatAngka = NumberFormat.decimalPattern('id_ID');

const _daftarAlasanRetur = [
  'Rusak',
  'Salah Kirim',
  'Tidak Sesuai Pesanan',
  'Kadaluarsa',
  'Lainnya',
];

class _ItemReturPembelian {
  final int produkId;
  final String nama;
  final double qty;
  final double harga;
  final String alasan;
  _ItemReturPembelian({required this.produkId, required this.nama, required this.qty, required this.harga, required this.alasan});
  double get total => qty * harga;
}

/// Tab "Retur Pembelian" (gap-closure roadmap Fase 3, permintaan user 2026-08-11) -- barang
/// dikembalikan KE SUPPLIER, kebalikan Retur Penjualan. Beda dari wizard Retur Penjualan (yg
/// WAJIB lacak transaksi penjualan asal lewat `laporan_order_list`/`detail_transaksi`) -- di sini
/// petugas langsung cari produk (pola sama Kulakan/Stok Opname), tanpa perlu jejak faktur
/// pengadaan yg jelas (barang titipan/data lama juga bisa diretur).
class ReturPembelianTab extends StatefulWidget {
  const ReturPembelianTab({super.key});
  @override
  State<ReturPembelianTab> createState() => _ReturPembelianTabState();
}

class _ReturPembelianTabState extends State<ReturPembelianTab> {
  static const _pageSize = 20;

  final _barcodeController = TextEditingController();
  final _qtyController = TextEditingController();
  final _hargaController = TextEditingController();
  String _alasan = _daftarAlasanRetur.first;
  bool _mencari = false;
  String? _errorForm;
  Map<String, dynamic>? _produkDitemukan;
  final List<_ItemReturPembelian> _items = [];
  bool _menyimpan = false;

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
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    setStateIfMounted(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('retur_pembelian_list', {'page': _halaman, 'page_size': _pageSize});
      setStateIfMounted(() {
        _riwayat = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
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
    setStateIfMounted(() {
      _mencari = true;
      _errorForm = null;
      _produkDitemukan = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('so_produk_scan', {'barcode': kode});
      setStateIfMounted(() {
        _produkDitemukan = hasil;
        _qtyController.clear();
        _hargaController.clear();
      });
    } catch (e) {
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

  void _tambahKeDaftar() {
    final p = _produkDitemukan;
    if (p == null) return;
    final qty = parseDesimal(_qtyController.text);
    final harga = parseDesimal(_hargaController.text) ?? 0;
    if (qty == null || qty <= 0) {
      setStateIfMounted(() => _errorForm = 'Jumlah retur harus lebih dari 0.');
      return;
    }
    setStateIfMounted(() {
      _items.add(_ItemReturPembelian(produkId: p['produkId'] as int, nama: '${p['nama'] ?? ''}', qty: qty, harga: harga, alasan: _alasan));
      _produkDitemukan = null;
      _barcodeController.clear();
      _qtyController.clear();
      _hargaController.clear();
      _errorForm = null;
    });
  }

  void _hapusDariDaftar(int index) => setStateIfMounted(() => _items.removeAt(index));

  double get _totalNilai => _items.fold<double>(0, (a, it) => a + it.total);

  Future<void> _simpanRetur() async {
    if (_items.isEmpty) {
      setStateIfMounted(() => _errorForm = 'Belum ada barang yang dipilih untuk diretur.');
      return;
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _errorForm = null;
    });
    try {
      await ApiClient.instance.aksi('retur_pembelian_simpan', {
        'items': _items
            .map((it) => {'produk_id': it.produkId, 'qty': it.qty, 'harga_satuan': it.harga, 'alasan': it.alasan})
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retur Pembelian tersimpan (${_items.length} item).')));
      }
      setStateIfMounted(() => _items.clear());
      _halaman = 1;
      await _muatRiwayat();
    } catch (e) {
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Future<void> _hapusBaris(Map<String, dynamic> r) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Retur?'),
        content: Text('Hapus baris retur "${r['namaProduk']}"? Stok akan dikoreksi ulang.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      await ApiClient.instance.aksi('retur_pembelian_hapus', {'id': r['id']});
      await _muatRiwayat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
    }
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
              judul: 'Retur Pembelian Baru',
              deskripsi: 'Cari produk yang akan dikembalikan ke supplier, tambahkan berulang, lalu simpan.',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PencarianProdukBanbox(
                        controller: _barcodeController,
                        label: 'Kode / Barcode / Nama Produk',
                        icon: Icons.search,
                        onPilih: _cariProduk,
                        decorationBuilder: (context) => AppFormStyle.fieldDecoration(context,
                            labelText: 'Kode / Barcode / Nama Produk', prefixIcon: const Icon(Icons.search)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(onPressed: _scanKamera, icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan pakai kamera'),
                  ],
                ),
                if (_mencari) const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator())),
                if (_errorForm != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(_errorForm!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                if (_produkDitemukan != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration:
                        BoxDecoration(color: AppColors.latarLembut(AppColors.warning), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_produkDitemukan!['nama'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: AppFormStyle.fieldDecoration(context, labelText: 'Jumlah Retur *', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _hargaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: AppFormStyle.fieldDecoration(context, labelText: 'Harga Satuan', isDense: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _alasan,
                          decoration: AppFormStyle.fieldDecoration(context, labelText: 'Alasan', isDense: true),
                          items: _daftarAlasanRetur.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                          onChanged: (v) => setStateIfMounted(() => _alasan = v ?? _alasan),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(onPressed: _tambahKeDaftar, icon: const Icon(Icons.add, size: 18), label: const Text('Tambah ke Daftar')),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_items.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Barang yang Diretur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ..._items.asMap().entries.map((e) {
                    final it = e.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        title: Text(it.nama, style: const TextStyle(fontSize: 13)),
                        subtitle: Text('${_formatAngka.format(it.qty)}x · ${it.alasan}', style: const TextStyle(fontSize: 11.5)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatRupiah.format(it.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _hapusDariDaftar(e.key)),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Divider(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Nilai Retur', style: TextStyle(fontWeight: FontWeight.w800)),
                        Text(_formatRupiah.format(_totalNilai), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _menyimpan ? null : _simpanRetur,
                      icon: _menyimpan
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Simpan Retur Pembelian'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Hanya admin/supervisor toko yang dapat mencatat Retur Pembelian. Riwayat di bawah tetap bisa dilihat.',
                  style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
            ),
          const Text('Riwayat Retur Pembelian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_memuatRiwayat)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
          else if (_errorRiwayat != null)
            Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(_errorRiwayat!)))
          else
            AppDataTable(
              minWidth: 800,
              emptyText: 'Belum ada riwayat retur pembelian.',
              columns: const [
                AppTableColumn('Produk', flex: 3),
                AppTableColumn('Waktu', flex: 2),
                AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                AppTableColumn('Alasan', flex: 2),
                AppTableColumn('Total', flex: 2, align: TextAlign.right),
                AppTableColumn('', flex: 1),
              ],
              rows: _riwayat.map((r) {
                return AppTableRowData(cells: [
                  AppTableCell.text('${r['namaProduk']}', flex: 3, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  AppTableCell.text('${r['waktu']}', flex: 2),
                  AppTableCell.text('${_formatAngka.format(r['qty'] ?? 0)}x', flex: 1, align: TextAlign.right),
                  AppTableCell.text('${r['alasan'] ?? '-'}', flex: 2),
                  AppTableCell.text(_formatRupiah.format(r['totalNilai'] ?? 0), flex: 2, align: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                  AppTableCell(
                    flex: 1,
                    child: Sesi.instance.bolehKelola
                        ? IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger), onPressed: () => _hapusBaris(r))
                        : const SizedBox.shrink(),
                  ),
                ]);
              }).toList(),
              pagination: AppTablePagination(
                halaman: _halaman,
                totalHalaman: _totalHalaman,
                totalData: _total,
                labelData: 'retur',
                onSebelumnya: _halaman > 1 ? () => _pindah(_halaman - 1) : null,
                onBerikutnya: _halaman < _totalHalaman ? () => _pindah(_halaman + 1) : null,
              ),
            ),
        ],
      ),
    );
  }
}
