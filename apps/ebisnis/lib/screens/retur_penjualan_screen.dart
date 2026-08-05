import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/safe_state.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

const _daftarAlasan = ['Rusak', 'Salah Ukuran/Varian', 'Tidak Sesuai Pesanan', 'Berubah Pikiran', 'Kadaluarsa', 'Lainnya'];
const _daftarKondisi = ['Baik - Layak Jual Lagi', 'Rusak - Tidak Layak Jual'];
const _daftarMetodePengembalian = ['Tunai', 'Saldo Member', 'Tukar Barang', 'Tanpa Pengembalian'];

/// Layar Retur Penjualan (spec §10) -- wizard 3 langkah (cari transaksi ->
/// pilih barang -> metode pengembalian) + riwayat/edit/hapus (supervisor).
/// Aksi server: retur_penjualan_list (view, siapa saja) dan
/// retur_penjualan_simpan/_ubah/_hapus (gated supervisor/admin, sama pola
/// gerbang dgn Kulakan). "Cari Transaksi" reuse `laporan_order_list`, "Pilih
/// Barang" reuse `detail_transaksi` -- tidak ada aksi baru utk 2 langkah itu.
class ReturPenjualanScreen extends StatefulWidget {
  const ReturPenjualanScreen({super.key});
  @override
  State<ReturPenjualanScreen> createState() => _ReturPenjualanScreenState();
}

class _ReturPenjualanScreenState extends State<ReturPenjualanScreen> with SingleTickerProviderStateMixin {
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
      menuAktif: MenuEBisnis.returPenjualan,
      judul: 'Retur Penjualan',
      subjudul: 'Catat pengembalian barang dari transaksi yang sudah lunas',
      scrollable: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.black54,
            indicatorColor: AppColors.primary,
            tabs: const [Tab(text: 'Buat Retur'), Tab(text: 'Riwayat Retur')],
          ),
          Expanded(child: TabBarView(controller: _tab, children: const [_TabBuatRetur(), _TabRiwayatRetur()])),
        ],
      ),
    );
  }
}

class _BarisRetur {
  final Map<String, dynamic> item; // dari detail_transaksi: {nama, qty, harga, diskon, cashback, produkId}
  bool disertakan = true;
  late final TextEditingController qtyController;
  String alasan = _daftarAlasan.first;
  String kondisi = _daftarKondisi.first;
  bool get kembalikanKeStok => !kondisi.toLowerCase().contains('rusak');
  double get qty => double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 0;
  double get hargaSatuan => (item['harga'] as num?)?.toDouble() ?? 0;
  double get subtotal => qty * hargaSatuan;

  _BarisRetur(this.item) {
    final qtyAsli = (item['qty'] as num?)?.toDouble() ?? 0;
    qtyController = TextEditingController(text: qtyAsli.toStringAsFixed(qtyAsli == qtyAsli.roundToDouble() ? 0 : 2));
  }
}

class _TabBuatRetur extends StatefulWidget {
  const _TabBuatRetur();
  @override
  State<_TabBuatRetur> createState() => _TabBuatReturState();
}

class _TabBuatReturState extends State<_TabBuatRetur> {
  final _kataKunciController = TextEditingController();
  bool _mencari = false;
  String? _errorPencarian;
  List<Map<String, dynamic>> _hasilPencarian = [];

  Map<String, dynamic>? _transaksiTerpilih;
  bool _memuatDetail = false;
  List<_BarisRetur> _baris = [];
  String _metodePengembalian = _daftarMetodePengembalian.first;
  bool _menyimpan = false;
  String? _errorSimpan;

  @override
  void dispose() {
    _kataKunciController.dispose();
    for (final b in _baris) {
      b.qtyController.dispose();
    }
    super.dispose();
  }

  Future<void> _cariTransaksi(String kataKunci) async {
    final v = kataKunci.trim();
    if (v.isEmpty) return;
    setStateIfMounted(() {
      _mencari = true;
      _errorPencarian = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('laporan_order_list', {'cariPembeli': v, 'page': 1, 'pageSize': 30});
      var data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      // laporan_order_list hanya menyaring server-side by nama pembeli -- tambahkan
      // penyaringan client-side by nomor nota supaya "cari nomor nota" spt di spesifikasi tetap kena.
      if (data.isEmpty) {
        final hasilNota = await ApiClient.instance.aksi('laporan_order_list', {'page': 1, 'pageSize': 100});
        data = ((hasilNota['data'] as List?) ?? []).cast<Map<String, dynamic>>().where((r) => '${r['nomorNota']}'.toLowerCase().contains(v.toLowerCase())).toList();
      }
      setStateIfMounted(() => _hasilPencarian = data);
    } catch (e) {
      setStateIfMounted(() => _errorPencarian = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _mencari = false);
    }
  }

  Future<void> _pilihTransaksi(Map<String, dynamic> row) async {
    setStateIfMounted(() {
      _transaksiTerpilih = row;
      _memuatDetail = true;
      _baris = [];
    });
    try {
      final hasil = await ApiClient.instance.aksi('detail_transaksi', {'id': row['idTransaksi']});
      final items = ((hasil['item'] as List?) ?? []).cast<Map<String, dynamic>>();
      setStateIfMounted(() => _baris = items.map((i) => _BarisRetur(i)).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setStateIfMounted(() => _transaksiTerpilih = null);
    } finally {
      if (mounted) setStateIfMounted(() => _memuatDetail = false);
    }
  }

  void _batalkanPemilihan() {
    setStateIfMounted(() {
      _transaksiTerpilih = null;
      _baris = [];
    });
  }

  double get _totalNilaiRetur => _baris.where((b) => b.disertakan).fold(0, (s, b) => s + b.subtotal);

  Future<void> _simpanRetur() async {
    final dipilih = _baris.where((b) => b.disertakan).toList();
    if (dipilih.isEmpty) {
      setStateIfMounted(() => _errorSimpan = 'Pilih minimal satu barang untuk diretur.');
      return;
    }
    for (final b in dipilih) {
      final qtyAsli = (b.item['qty'] as num?)?.toDouble() ?? 0;
      if (b.qty <= 0 || b.qty > qtyAsli) {
        setStateIfMounted(() => _errorSimpan = 'Qty Retur "${b.item['nama']}" harus antara 0 dan ${qtyAsli.toStringAsFixed(qtyAsli == qtyAsli.roundToDouble() ? 0 : 2)} (jumlah asli dibeli).');
        return;
      }
    }
    setStateIfMounted(() {
      _menyimpan = true;
      _errorSimpan = null;
    });
    try {
      await ApiClient.instance.aksi('retur_penjualan_simpan', {
        'pembelian_anggota_koperasi_id': _transaksiTerpilih!['idTransaksi'],
        'kode_transaksi_asal': _transaksiTerpilih!['nomorNota'],
        'nama_pembeli': _transaksiTerpilih!['pembeli'],
        'metode_pengembalian': _metodePengembalian,
        'items': dipilih
            .map((b) => {
                  'produk_id': b.item['produkId'],
                  'qty': b.qty,
                  'harga_satuan': b.hargaSatuan,
                  'alasan': b.alasan,
                  'kondisi_barang': b.kondisi,
                  'kembalikan_ke_stok': b.kembalikanKeStok,
                  'keterangan': '',
                })
            .toList(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Retur berhasil disimpan.')));
        setStateIfMounted(() {
          _transaksiTerpilih = null;
          _baris = [];
          _hasilPencarian = [];
          _kataKunciController.clear();
        });
      }
    } catch (e) {
      setStateIfMounted(() => _errorSimpan = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Sesi.instance.bolehKelola) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Hanya admin/supervisor toko yang dapat mencatat retur penjualan.', textAlign: TextAlign.center),
        ),
      );
    }

    if (_transaksiTerpilih == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Langkah 1: Cari Transaksi Asal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _kataKunciController,
            decoration: const InputDecoration(hintText: 'Cari nomor nota / nama pembeli...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            onSubmitted: _cariTransaksi,
          ),
          const SizedBox(height: 12),
          if (_mencari) const Center(child: CircularProgressIndicator()),
          if (_errorPencarian != null) Text(_errorPencarian!, style: const TextStyle(color: Colors.red)),
          if (!_mencari && _hasilPencarian.isEmpty && _errorPencarian == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Ketik lalu tekan Enter utk mencari transaksi.'))),
          ..._hasilPencarian.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text('${r['nomorNota']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text('${r['waktu']} · ${r['pembeli']}'),
                  trailing: Text(_formatRupiah.format(r['totalBiaya'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                  onTap: () => _pilihTransaksi(r),
                ),
              )),
        ],
      );
    }

    if (_memuatDetail) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: _batalkanPemilihan),
            Expanded(
              child: Text('${_transaksiTerpilih!['nomorNota']} · ${_transaksiTerpilih!['pembeli']}',
                  style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Langkah 2: Pilih Barang & Kondisi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ..._baris.map((b) => AppSectionCard(
              padding: const EdgeInsets.all(12),
              child: StatefulBuilder(
                builder: (context, setBarisState) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Checkbox(value: b.disertakan, onChanged: (v) => setBarisState(() => b.disertakan = v ?? true)),
                        Expanded(child: Text('${b.item['nama']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        Text(_formatRupiah.format(b.hargaSatuan), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                    if (b.disertakan) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Builder(builder: (_) {
                              final qtyAsli = (b.item['qty'] as num?)?.toDouble() ?? 0;
                              final lebih = b.qty > qtyAsli;
                              return TextField(
                                controller: b.qtyController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Qty Retur (maks ${b.item['qty']})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  errorText: lebih ? 'Melebihi jumlah dibeli' : null,
                                ),
                                onChanged: (_) => setBarisState(() {}),
                              );
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: b.alasan,
                              decoration: const InputDecoration(labelText: 'Alasan', border: OutlineInputBorder(), isDense: true),
                              items: _daftarAlasan.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 12)))).toList(),
                              onChanged: (v) => setBarisState(() => b.alasan = v ?? b.alasan),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: b.kondisi,
                        decoration: const InputDecoration(labelText: 'Kondisi Barang', border: OutlineInputBorder(), isDense: true),
                        items: _daftarKondisi.map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 12)))).toList(),
                        onChanged: (v) => setBarisState(() => b.kondisi = v ?? b.kondisi),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        b.kembalikanKeStok ? 'Stok akan dikembalikan.' : 'Stok TIDAK dikembalikan (kondisi rusak).',
                        style: TextStyle(fontSize: 11, color: b.kembalikanKeStok ? AppColors.success : AppColors.danger),
                      ),
                      const SizedBox(height: 4),
                      Align(alignment: Alignment.centerRight, child: Text('Subtotal: ${_formatRupiah.format(b.subtotal)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ],
                ),
              ),
            )),
        const SizedBox(height: 8),
        const Text('Langkah 3: Metode Pengembalian', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: _daftarMetodePengembalian
              .map((m) => ChoiceChip(label: Text(m), selected: _metodePengembalian == m, onSelected: (_) => setStateIfMounted(() => _metodePengembalian = m)))
              .toList(),
        ),
        const SizedBox(height: 16),
        if (_errorSimpan != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
            child: Text(_errorSimpan!, style: TextStyle(color: Colors.red.shade700)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Total Nilai Retur', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(_formatRupiah.format(_totalNilaiRetur), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _menyimpan ? null : _simpanRetur,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _menyimpan ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Simpan Retur'),
          ),
        ),
      ],
    );
  }
}

class _TabRiwayatRetur extends StatefulWidget {
  const _TabRiwayatRetur();
  @override
  State<_TabRiwayatRetur> createState() => _TabRiwayatReturState();
}

class _TabRiwayatReturState extends State<_TabRiwayatRetur> {
  static const _pageSize = 20;
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _data = [];
  int _halaman = 1;
  int _total = 0;
  String _kataKunci = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('retur_penjualan_list', {
        if (_kataKunci.isNotEmpty) 'keyword': _kataKunci,
        'page': _halaman,
        'page_size': _pageSize,
      });
      setStateIfMounted(() {
        _data = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>();
        _total = (hasil['total'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _terapkanFilter(String v) async {
    _kataKunci = v;
    _halaman = 1;
    await _muat();
  }

  Future<void> _pindah(int h) async {
    _halaman = h;
    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> r) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Retur?'),
        content: Text('Retur "${r['namaProduk']}" akan dihapus permanen. Stok akan dihitung ulang.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      await ApiClient.instance.aksi('retur_penjualan_hapus', {'id': r['id']});
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _ubah(Map<String, dynamic> r) async {
    final qtyController = TextEditingController(text: '${r['qty']}');
    final hargaController = TextEditingController(text: '${r['hargaSatuan']}');
    var alasan = _daftarAlasan.contains(r['alasan']) ? r['alasan'] as String : _daftarAlasan.last;
    var kondisi = _daftarKondisi.contains(r['kondisiBarang']) ? r['kondisiBarang'] as String : _daftarKondisi.first;
    final disimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ubah Retur -- ${r['namaProduk']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(controller: qtyController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: hargaController, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Harga Satuan', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: alasan,
                decoration: const InputDecoration(labelText: 'Alasan', border: OutlineInputBorder()),
                items: _daftarAlasan.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                onChanged: (v) => setSheetState(() => alasan = v ?? alasan),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: kondisi,
                decoration: const InputDecoration(labelText: 'Kondisi Barang', border: OutlineInputBorder()),
                items: _daftarKondisi.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (v) => setSheetState(() => kondisi = v ?? kondisi),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Simpan Perubahan')),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (disimpan != true) return;
    try {
      await ApiClient.instance.aksi('retur_penjualan_ubah', {
        'id': r['id'],
        'qty': double.tryParse(qtyController.text) ?? r['qty'],
        'harga_satuan': double.tryParse(hargaController.text) ?? r['hargaSatuan'],
        'alasan': alasan,
        'kondisi_barang': kondisi,
        'kembalikan_ke_stok': !kondisi.toLowerCase().contains('rusak'),
      });
      await _muat();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  int get _totalHalaman => (_total / _pageSize).ceil().clamp(1, 999999);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(width: 190, child: AppKpiCard(icon: Icons.assignment_return_outlined, warna: AppColors.primary, nilai: '$_total', label: 'Total Retur')),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: AppKpiCard(
                    icon: Icons.payments_outlined,
                    warna: AppColors.danger,
                    nilai: _formatRupiah.format(_data.fold<num>(0, (a, r) => a + (((r['qty'] as num?) ?? 0) * ((r['hargaSatuan'] as num?) ?? 0)))),
                    label: 'Nilai (hal. ini)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(hintText: 'Cari produk/nomor nota/pembeli...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
            onSubmitted: _terapkanFilter,
          ),
          const SizedBox(height: 12),
          if (_memuat)
            const Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(_error!)))
          else if (_data.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: Center(child: Text('Belum ada riwayat retur.')))
          else ...[
            ..._data.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    title: Text('${r['namaProduk']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text('${r['waktu']} · ${r['kodeTransaksiAsal']} · ${r['namaPembeli']}\n${r['alasan']} · ${r['kondisiBarang']} · ${r['metodePengembalian']}'),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${r['qty']}x', style: const TextStyle(fontSize: 12)),
                        Text(_formatRupiah.format(r['totalNilai'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    onTap: Sesi.instance.bolehKelola
                        ? () => showModalBottomSheet(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Ubah'), onTap: () {
                                      Navigator.of(context).pop();
                                      _ubah(r);
                                    }),
                                    ListTile(
                                      leading: const Icon(Icons.delete_outline, color: Colors.red),
                                      title: const Text('Hapus'),
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        _hapus(r);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            )
                        : null,
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
    );
  }
}
