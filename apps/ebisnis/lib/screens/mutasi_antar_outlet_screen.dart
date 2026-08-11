import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../parse_util.dart';
import '../sesi.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_components.dart';
import '../theme/app_colors.dart';
import '../widgets/safe_state.dart';

final _formatAngka = NumberFormat.decimalPattern('id_ID');

/// Layar "Mutasi Stok Antar Outlet" (Fase 3 roadmap F&B, gap-closure permintaan user 2026-08-11)
/// -- kirim/transfer stok dari toko ini ke toko lain. Padanan langsung JSP `mutasi_antar_outlet.jsp`
/// & Electron `mutasi-antar-outlet-renderer.js`, lewat aksi server `mutasi_stok_simpan`/`_list`/
/// `_toko_list`/`_produk_list` (lihat JavaDoc `KantinHelper.mutasiStokSimpan` dkk).
///
/// Karena tiap outlet punya baris Produk TERPISAH utk "barang yang sama", server MENCOCOKKAN
/// OTOMATIS produk tujuan via kode/barcode -- kalau gagal/ambigu (`butuhPilihManual`), kotak "pilih
/// manual" muncul, form resubmit dgn `produk_tujuan_id` eksplisit.
///
/// Server MENOLAK aksi simpan/produk_list bila pemanggil bukan supervisor/admin -- layar ini
/// menyembunyikan form entri utk kasir biasa (`Sesi.instance.bolehKelola`) dan hanya menampilkan
/// riwayat (readonly).
class MutasiAntarOutletScreen extends StatefulWidget {
  const MutasiAntarOutletScreen({super.key});
  @override
  State<MutasiAntarOutletScreen> createState() => _MutasiAntarOutletScreenState();
}

class _MutasiAntarOutletScreenState extends State<MutasiAntarOutletScreen> {
  Map<String, dynamic>? _tokoAsalTerpilih; // hanya diisi manual utk admin; non-admin pakai Sesi.instance.tokoId
  Map<String, dynamic>? _tokoTujuanTerpilih;
  Map<String, dynamic>? _produkAsalTerpilih;
  Map<String, dynamic>? _produkTujuanManualTerpilih;

  final _qtyController = TextEditingController();
  final _keteranganController = TextEditingController();
  bool _menyimpan = false;
  String? _errorForm;
  bool _butuhPilihManual = false;

  bool _memuatRiwayat = false;
  String? _errorRiwayat;
  List<Map<String, dynamic>> _riwayat = [];

  bool get _isAdmin => Sesi.instance.isAdmin;

  String? get _tokoAsalId => _isAdmin
      ? (_tokoAsalTerpilih == null ? null : '${_tokoAsalTerpilih!['id']}')
      : (Sesi.instance.tokoId == null ? null : '${Sesi.instance.tokoId}');

  @override
  void initState() {
    super.initState();
    if (!_isAdmin) _muatRiwayat();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  Future<void> _muatRiwayat() async {
    final tokoId = _tokoAsalId;
    if (tokoId == null) {
      setStateIfMounted(() => _riwayat = []);
      return;
    }
    setStateIfMounted(() {
      _memuatRiwayat = true;
      _errorRiwayat = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('mutasi_stok_list', {'toko_id': tokoId, 'limit': 100});
      setStateIfMounted(() => _riwayat = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _errorRiwayat = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuatRiwayat = false);
    }
  }

  Future<void> _pilihTokoAsal() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihToko(judul: 'Pilih Toko Asal'),
    );
    if (dipilih == null) return;
    setStateIfMounted(() {
      _tokoAsalTerpilih = dipilih;
      _produkAsalTerpilih = null;
      _resetPilihManual();
    });
    await _muatRiwayat();
  }

  Future<void> _pilihTokoTujuan() async {
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SheetPilihToko(judul: 'Pilih Toko Tujuan'),
    );
    if (dipilih == null) return;
    setStateIfMounted(() {
      _tokoTujuanTerpilih = dipilih;
      _resetPilihManual();
    });
  }

  Future<void> _pilihProdukAsal() async {
    final tokoId = _tokoAsalId;
    if (tokoId == null) {
      setStateIfMounted(() => _errorForm = 'Pilih Toko Asal terlebih dahulu.');
      return;
    }
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetPilihProduk(tokoId: tokoId, judul: 'Pilih Produk Asal'),
    );
    if (dipilih != null) setStateIfMounted(() => _produkAsalTerpilih = dipilih);
  }

  Future<void> _pilihProdukTujuanManual() async {
    final tokoTujuanId = _tokoTujuanTerpilih?['id'];
    if (tokoTujuanId == null) return;
    final dipilih = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetPilihProduk(tokoId: '$tokoTujuanId', judul: 'Pilih Produk Tujuan'),
    );
    if (dipilih != null) setStateIfMounted(() => _produkTujuanManualTerpilih = dipilih);
  }

  void _resetPilihManual() {
    _butuhPilihManual = false;
    _produkTujuanManualTerpilih = null;
  }

  Future<void> _kirimStok() async {
    final tokoAsalId = _tokoAsalId;
    final tokoTujuanId = _tokoTujuanTerpilih?['id'];
    final produkAsalId = _produkAsalTerpilih?['id'];
    final qty = parseDesimal(_qtyController.text);

    if (tokoAsalId == null || tokoTujuanId == null || produkAsalId == null) {
      setStateIfMounted(() => _errorForm = 'Toko asal, toko tujuan, dan produk wajib diisi.');
      return;
    }
    if (qty == null || qty <= 0) {
      setStateIfMounted(() => _errorForm = 'Jumlah (qty) wajib diisi lebih dari 0.');
      return;
    }

    setStateIfMounted(() {
      _menyimpan = true;
      _errorForm = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('mutasi_stok_simpan', {
        'toko_id': tokoAsalId,
        'produk_asal_id': produkAsalId,
        'toko_tujuan_id': tokoTujuanId,
        'qty': qty,
        'keterangan': _keteranganController.text.trim(),
        if (_produkTujuanManualTerpilih != null) 'produk_tujuan_id': _produkTujuanManualTerpilih!['id'],
      });
      // Gap-closure: server memetakan "00" DAN "92" (butuh pilih manual) ke status HTTP "success"
      // (bukan cuma "00") supaya ApiClient.aksi tidak melempar ApiException dan membuang body
      // (butuhPilihManual/kandidat) -- lihat komentar di PosApi.java dispatch mutasi_stok_simpan.
      // Bedakan via flag butuhPilihManual, BUKAN exception.
      if (hasil['butuhPilihManual'] == true) {
        setStateIfMounted(() {
          _butuhPilihManual = true;
          _errorForm = hasil['description'] as String?;
        });
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Stok berhasil dikirim ke ${hasil['produkTujuanNama'] ?? ''}.')));
      }
      setStateIfMounted(() {
        _qtyController.clear();
        _keteranganController.clear();
        _produkAsalTerpilih = null;
        _resetPilihManual();
      });
      await _muatRiwayat();
    } catch (e) {
      setStateIfMounted(() => _errorForm = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  Widget _kotakPilih(String label, String? nilai, VoidCallback onTap, {bool aktif = true}) {
    return InkWell(
      onTap: aktif ? onTap : null,
      child: InputDecorator(
        decoration: AppFormStyle.fieldDecoration(context, labelText: label),
        child: Row(
          children: [
            Expanded(child: Text(nilai ?? '-- Belum dipilih --', style: TextStyle(color: nilai == null ? Colors.black38 : null))),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.mutasiAntarOutlet,
      judul: 'Mutasi Stok Antar Outlet',
      subjudul: 'Kirim/transfer stok produk ke toko/outlet lain',
      body: RefreshIndicator(
        onRefresh: _muatRiwayat,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (Sesi.instance.bolehKelola) ...[
              AppFormSection(
                judul: 'Kirim Stok ke Toko Lain',
                deskripsi:
                    'Sistem mencocokkan produk tujuan otomatis via kode/barcode. Bila tidak ditemukan/ambigu, pilih produk tujuan secara manual.',
                children: [
                  if (_isAdmin) ...[
                    _kotakPilih('Toko Asal *', _tokoAsalTerpilih == null ? null : '${_tokoAsalTerpilih!['nama']}', _pilihTokoAsal),
                    const SizedBox(height: 12),
                  ],
                  _kotakPilih('Toko Tujuan *', _tokoTujuanTerpilih == null ? null : '${_tokoTujuanTerpilih!['nama']}', _pilihTokoTujuan),
                  const SizedBox(height: 12),
                  _kotakPilih(
                    'Produk / Barang (Toko Asal) *',
                    _produkAsalTerpilih == null ? null : '${_produkAsalTerpilih!['nama']}',
                    _pilihProdukAsal,
                    aktif: _tokoAsalId != null,
                  ),
                  if (_produkAsalTerpilih != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Stok saat ini: ${_formatAngka.format(_produkAsalTerpilih!['stok'] ?? 0)}',
                          style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: AppFormStyle.fieldDecoration(context, labelText: 'Jumlah (Qty) *'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keteranganController,
                    decoration: AppFormStyle.fieldDecoration(context, labelText: 'Keterangan (opsional)'),
                  ),
                  if (_butuhPilihManual) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.latarLembut(AppColors.warning), borderRadius: BorderRadius.circular(10)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Produk yang sama tidak ditemukan otomatis di toko tujuan -- pilih produk tujuan secara manual:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warning)),
                          const SizedBox(height: 10),
                          _kotakPilih('Produk Tujuan',
                              _produkTujuanManualTerpilih == null ? null : '${_produkTujuanManualTerpilih!['nama']}',
                              _pilihProdukTujuanManual),
                        ],
                      ),
                    ),
                  ],
                  if (_errorForm != null && !_butuhPilihManual)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Text(_errorForm!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _menyimpan ? null : _kirimStok,
                      icon: _menyimpan
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.compare_arrows, size: 18),
                      label: const Text('Kirim Stok'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Hanya admin/supervisor toko yang dapat mencatat Mutasi Stok Antar Outlet. Riwayat di bawah tetap bisa dilihat.',
                    style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
              ),
            const Text('Riwayat Mutasi Stok', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (_tokoAsalId == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('Pilih Toko Asal di atas untuk melihat riwayat mutasi toko itu.'),
              )
            else if (_memuatRiwayat)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
            else if (_errorRiwayat != null)
              Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Center(child: Text(_errorRiwayat!)))
            else
              AppDataTable(
                minWidth: 900,
                emptyText: 'Belum ada riwayat mutasi stok.',
                columns: const [
                  AppTableColumn('Waktu', flex: 2),
                  AppTableColumn('Arah', flex: 1),
                  AppTableColumn('Produk Asal', flex: 2),
                  AppTableColumn('Produk Tujuan', flex: 2),
                  AppTableColumn('Qty', flex: 1, align: TextAlign.right),
                  AppTableColumn('Keterangan', flex: 2),
                ],
                rows: _riwayat.map((m) {
                  final masuk = m['arah'] == 'masuk';
                  return AppTableRowData(cells: [
                    AppTableCell.text('${m['waktu']}', flex: 2),
                    AppTableCell(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.latarLembut(masuk ? AppColors.success : AppColors.danger),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(masuk ? 'Masuk' : 'Keluar',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: masuk ? AppColors.success : AppColors.danger)),
                      ),
                    ),
                    AppTableCell.text('${m['produkAsalNama'] ?? '-'}', flex: 2),
                    AppTableCell.text('${m['produkTujuanNama'] ?? '-'}', flex: 2),
                    AppTableCell.text(_formatAngka.format(m['qty'] ?? 0), flex: 1, align: TextAlign.right),
                    AppTableCell.text('${m['keterangan'] ?? '-'}', flex: 2),
                  ]);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet picker Toko (SEMUA toko aktif, bukan cuma toko sendiri -- lihat JavaDoc server
/// `KantinHelper.mutasiStokTokoList`).
class _SheetPilihToko extends StatefulWidget {
  final String judul;
  const _SheetPilihToko({required this.judul});
  @override
  State<_SheetPilihToko> createState() => _SheetPilihTokoState();
}

class _SheetPilihTokoState extends State<_SheetPilihToko> {
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];

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
      final hasil = await ApiClient.instance.aksi('mutasi_stok_toko_list', {});
      setStateIfMounted(() => _daftar = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
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
            Text(widget.judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : ListView(
                          controller: scrollController,
                          children: [
                            ..._daftar.map((t) => ListTile(
                                  leading: const Icon(Icons.storefront_outlined),
                                  title: Text('${t['nama']}'),
                                  onTap: () => Navigator.of(context).pop(t),
                                )),
                            if (_daftar.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada toko ditemukan.')),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet picker Produk DI TOKO MANAPUN (lihat JavaDoc server `KantinHelper.mutasiStokProdukList`
/// -- beda dari `PencarianProdukBanbox` yg bersumber dari cache lokal toko SENDIRI, di sini `toko_id`
/// eksplisit boleh toko lain).
class _SheetPilihProduk extends StatefulWidget {
  final String tokoId;
  final String judul;
  const _SheetPilihProduk({required this.tokoId, required this.judul});
  @override
  State<_SheetPilihProduk> createState() => _SheetPilihProdukState();
}

class _SheetPilihProdukState extends State<_SheetPilihProduk> {
  final _cariController = TextEditingController();
  bool _memuat = true;
  String? _error;
  List<Map<String, dynamic>> _daftar = [];

  @override
  void initState() {
    super.initState();
    _cari('');
  }

  @override
  void dispose() {
    _cariController.dispose();
    super.dispose();
  }

  Future<void> _cari(String keyword) async {
    setStateIfMounted(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('mutasi_stok_produk_list', {'toko_id': widget.tokoId, 'keyword': keyword});
      setStateIfMounted(() => _daftar = ((hasil['data'] as List?) ?? []).cast<Map<String, dynamic>>());
    } catch (e) {
      setStateIfMounted(() => _error = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.judul, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: _cariController,
              decoration: AppFormStyle.fieldDecoration(context, labelText: 'Cari nama/kode produk...', prefixIcon: const Icon(Icons.search)),
              onSubmitted: _cari,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!))
                      : ListView(
                          controller: scrollController,
                          children: [
                            ..._daftar.map((p) => ListTile(
                                  leading: const Icon(Icons.inventory_2_outlined),
                                  title: Text('${p['nama']}'),
                                  subtitle: Text('Kode: ${p['kode'] ?? '-'} · Stok: ${_formatAngka.format(p['stok'] ?? 0)}'),
                                  onTap: () => Navigator.of(context).pop(p),
                                )),
                            if (_daftar.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada produk ditemukan.')),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
