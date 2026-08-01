import 'dart:convert';
import 'dart:io';

import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'impor_excel_produk_screen.dart';
import 'price_tag_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
const _itemPerHalaman = 20;

/// Layar Produk (padanan produk.html/produk-renderer.js Electron) -- list+
/// cari+filter kategori+paginasi 20/hal+dasbor KPI+tambah/ubah. Reuse aksi
/// server yg SAMA dgn Kasir (`katalog`) utk daftar (lihat catatan di
/// `Produk.baseKeCacheRow`) + `produk_statistik` utk kartu KPI +
/// `produk_simpan` utk simpan.
///
/// SENGAJA online-only (beda dari Kasir yg offline-first) -- ini layar
/// admin/back-office, wajar diakses saat ada koneksi (kantor/wifi toko),
/// jadi tidak menambah kompleksitas cache lokal khusus utk layar ini.
///
/// Belum ada di iterasi ini (menyusul, lihat task #182 & README repo):
/// resep/Bahan Baku & HPP otomatis, impor/ekspor Excel, pembersihan produk
/// duplikat, cetak Price Tag/label -- semua itu perkakas admin lanjutan,
/// bukan alur inti "tambah/ubah satu produk" yang sudah cukup utk toko baru
/// mulai berjualan.
class ProdukScreen extends StatefulWidget {
  const ProdukScreen({super.key});

  @override
  State<ProdukScreen> createState() => _ProdukScreenState();
}

class _ProdukScreenState extends State<ProdukScreen> {
  bool _memuat = true;
  String? _pesanError;
  List<Produk> _semuaProduk = [];
  List<Kategori> _kategori = [];
  int? _kategoriTerpilih;
  String _kataKunci = '';
  int _halaman = 0;
  Map<String, dynamic>? _statistik;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final katalog = await ApiClient.instance.aksi('katalog');
      final produkJson = (katalog['produk'] as List?) ?? [];
      final produk = produkJson.map((e) => Produk.fromJson(e as Map<String, dynamic>)).toList();
      final kategori =
          ((katalog['kategori'] as List?) ?? []).map((e) => Kategori.fromJson(e as Map<String, dynamic>)).toList();

      // Segarkan jg cache lokal yg dipakai Kasir, supaya produk baru/berubah
      // di sini langsung terlihat di Kasir tanpa kasir harus menekan sinkron manual.
      await CoreDb.instance
          .replaceProdukCache(produkJson.map((e) => Produk.baseKeCacheRow(e as Map<String, dynamic>)).toList());

      Map<String, dynamic>? statistik;
      try {
        statistik = await ApiClient.instance.aksi('produk_statistik');
      } catch (_) {
        // dasbor KPI gagal muat bukan blocker -- daftar produk tetap tampil normal.
      }

      setState(() {
        _semuaProduk = produk;
        _kategori = kategori;
        _statistik = statistik;
        _halaman = 0;
      });
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  List<Produk> get _produkTersaring {
    return _semuaProduk.where((p) {
      final cocokKategori = _kategoriTerpilih == null || p.kategoriId == _kategoriTerpilih;
      final kw = _kataKunci.toLowerCase();
      final cocokKeyword = kw.isEmpty ||
          p.nama.toLowerCase().contains(kw) ||
          p.kode.toLowerCase().contains(kw) ||
          p.barcode.toLowerCase().contains(kw);
      return cocokKategori && cocokKeyword;
    }).toList();
  }

  List<Produk> get _produkHalamanIni {
    final semua = _produkTersaring;
    final awal = _halaman * _itemPerHalaman;
    if (awal >= semua.length) return [];
    final akhir = (awal + _itemPerHalaman).clamp(0, semua.length);
    return semua.sublist(awal, akhir);
  }

  int get _totalHalaman => (_produkTersaring.length / _itemPerHalaman).ceil().clamp(1, 999999);

  Future<void> _bukaFormProduk({Produk? produk}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormProduk(produk: produk, kategori: _kategori),
    );
    if (tersimpan == true) {
      await _muatSemua();
    }
  }

  Future<void> _bukaImporExcel() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImporExcelProdukScreen()));
    await _muatSemua();
  }

  /// "Unduh Excel" (spec §Produk, khusus supervisor/admin -- gerbang SAMA
  /// dgn `produk_simpan` di server) -- format identik "Daftar Barang dan
  /// Jasa" (Accurate) yg bisa diedit lalu diunggah kembali lewat Impor Excel
  /// tanpa menata ulang kolom (lihat JavaDoc `produkEksporExcel` di server).
  Future<void> _eksporExcel() async {
    try {
      final hasil = await ApiClient.instance.aksi('produk_ekspor_excel', {'hanya_aktif': true});
      final b64 = hasil['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) throw Exception('Server tidak mengembalikan berkas.');
      final bytes = base64Decode(b64);
      final namaFile = (hasil['namaFile'] as String?) ?? 'Katalog.xlsx';
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Simpan Katalog Produk', fileName: namaFile, bytes: bytes, type: FileType.custom, allowedExtensions: ['xlsx']);
      if (path == null) return;
      // Di Desktop, saveFile HANYA mengembalikan path pilihan (belum menulis apa
      // pun) -- mobile sudah menulis via `bytes`, tulis ulang di sini idempoten
      // (byte sama) supaya satu jalur kode bekerja di kedua platform.
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Katalog disimpan: $path')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tombolAksi = [
      IconButton(icon: const Icon(Icons.sell_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PriceTagScreen())), tooltip: 'Cetak Price Tag'),
      IconButton(icon: const Icon(Icons.download_outlined), onPressed: _eksporExcel, tooltip: 'Ekspor Excel'),
      IconButton(icon: const Icon(Icons.upload_file_outlined), onPressed: _bukaImporExcel, tooltip: 'Impor Excel'),
      IconButton(icon: const Icon(Icons.refresh), onPressed: _muatSemua, tooltip: 'Muat ulang'),
    ];
    return AppShell(
      menuAktif: MenuEBisnis.produk,
      judul: 'Manajemen Produk',
      subjudul: 'Kelola katalog produk toko Anda',
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: tombolAksi),
      actionsAppBar: tombolAksi,
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaFormProduk(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
        backgroundColor: AppColors.primary,
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _pesanError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _muatSemua, child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muatSemua,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      if (_statistik != null) _KartuStatistik(statistik: _statistik!),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cari produk (nama/kode/barcode)...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() {
                          _kataKunci = v;
                          _halaman = 0;
                        }),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: const Text('Semua'),
                                selected: _kategoriTerpilih == null,
                                onSelected: (_) => setState(() {
                                  _kategoriTerpilih = null;
                                  _halaman = 0;
                                }),
                              ),
                            ),
                            ..._kategori.map((k) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(k.nama),
                                    selected: _kategoriTerpilih == k.id,
                                    onSelected: (_) => setState(() {
                                      _kategoriTerpilih = k.id;
                                      _halaman = 0;
                                    }),
                                  ),
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_produkTersaring.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('Belum ada produk.')),
                        )
                      else
                        ..._produkHalamanIni.map((p) => _BarisProduk(produk: p, onTap: () => _bukaFormProduk(produk: p))),
                      if (_produkTersaring.length > _itemPerHalaman)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: _halaman > 0 ? () => setState(() => _halaman--) : null,
                              ),
                              Text('Halaman ${_halaman + 1} / $_totalHalaman'),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: _halaman < _totalHalaman - 1 ? () => setState(() => _halaman++) : null,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _KartuStatistik extends StatelessWidget {
  final Map<String, dynamic> statistik;
  const _KartuStatistik({required this.statistik});

  @override
  Widget build(BuildContext context) {
    final item = <(IconData, String, String, Color)>[
      (Icons.inventory_2_outlined, 'Total', '${statistik['totalProduk'] ?? 0}', AppColors.primary),
      (Icons.check_circle_outline, 'Aktif', '${statistik['totalAktif'] ?? 0}', AppColors.success),
      (Icons.pause_circle_outline, 'Nonaktif', '${statistik['totalNonaktif'] ?? 0}', AppColors.textSecondary),
      (Icons.remove_shopping_cart_outlined, 'Stok Habis', '${statistik['stokHabis'] ?? 0}', AppColors.danger),
      (Icons.warning_amber_outlined, 'Stok Rendah', '${statistik['stokRendah'] ?? 0}', AppColors.warning),
      (Icons.payments_outlined, 'Nilai Stok', _formatRupiah.format((statistik['totalNilaiStok'] as num?) ?? 0), AppColors.teal),
    ];
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: item.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (icon, label, nilai, warna) = item[i];
          return SizedBox(width: 150, child: AppKpiCard(icon: icon, warna: warna, nilai: nilai, label: label));
        },
      ),
    );
  }
}

class _BarisProduk extends StatelessWidget {
  final Produk produk;
  final VoidCallback onTap;
  const _BarisProduk({required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    final rendah = !habis && produk.stok <= 5;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSectionCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Text(produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
          ),
          title: Text(produk.nama, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${produk.kode} · ${produk.kategoriNama.isEmpty ? "Tanpa Kategori" : produk.kategoriNama}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatRupiah.format(produk.hargaJual), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              StatusPill(label: habis ? 'Habis' : 'Stok ${produk.stok}', warna: habis ? AppColors.danger : (rendah ? AppColors.warning : AppColors.success)),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Form Tambah/Ubah -- bottom sheet, dipakai utk kedua mode (produk == null berarti Tambah).
class _FormProduk extends StatefulWidget {
  final Produk? produk;
  final List<Kategori> kategori;
  const _FormProduk({required this.produk, required this.kategori});

  @override
  State<_FormProduk> createState() => _FormProdukState();
}

class _FormProdukState extends State<_FormProduk> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _barcode;
  late final TextEditingController _hargaBeli;
  late final TextEditingController _hargaJual;
  late final TextEditingController _stok;
  late final TextEditingController _keterangan;
  int? _kategoriId;
  bool _izinkanJualMinusStok = false;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _pesanError;

  @override
  void initState() {
    super.initState();
    final p = widget.produk;
    _kode = TextEditingController(text: p?.kode ?? '');
    _nama = TextEditingController(text: p?.nama ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _hargaBeli = TextEditingController(text: p == null ? '0' : p.hargaBeli.toStringAsFixed(0));
    _hargaJual = TextEditingController(text: p == null ? '0' : p.hargaJual.toStringAsFixed(0));
    _stok = TextEditingController(text: p == null ? '0' : p.stok.toString());
    _keterangan = TextEditingController(text: p?.keterangan ?? '');
    _kategoriId = p?.kategoriId;
    _izinkanJualMinusStok = p?.izinkanJualMinusStok ?? false;
    _aktif = p?.aktif ?? true;
  }

  @override
  void dispose() {
    _kode.dispose();
    _nama.dispose();
    _barcode.dispose();
    _hargaBeli.dispose();
    _hargaJual.dispose();
    _stok.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  double _angka(String s) => double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      await ApiClient.instance.aksi('produk_simpan', {
        if (widget.produk != null) 'id': widget.produk!.id,
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'barcode': _barcode.text.trim(),
        'harga_beli': _angka(_hargaBeli.text),
        'harga_jual': _angka(_hargaJual.text),
        'stok': _angka(_stok.text),
        'keterangan': _keterangan.text.trim(),
        'kategori_id': _kategoriId,
        'izinkan_jual_minus_stok': _izinkanJualMinusStok,
        'aktif': _aktif,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.produk != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(ubah ? 'Ubah Produk' : 'Tambah Produk', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              if (_pesanError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(_pesanError!, style: TextStyle(color: Colors.red.shade700)),
                  ),
                ),
              TextFormField(
                controller: _kode,
                decoration: const InputDecoration(labelText: 'Kode Produk *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nama,
                decoration: const InputDecoration(labelText: 'Nama Produk *', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'Barcode (opsional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                value: _kategoriId,
                decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('-- Tanpa Kategori --')),
                  ...widget.kategori.map((k) => DropdownMenuItem<int?>(value: k.id, child: Text(k.nama))),
                ],
                onChanged: (v) => setState(() => _kategoriId = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hargaBeli,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Beli', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _hargaJual,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Harga Jual *', border: OutlineInputBorder()),
                      validator: (v) => _angka(v ?? '') <= 0 ? 'Wajib > 0' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stok,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Stok', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _keterangan,
                decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Boleh dijual walau stok minus'),
                value: _izinkanJualMinusStok,
                onChanged: (v) => setState(() => _izinkanJualMinusStok = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif (tampil di Kasir)'),
                value: _aktif,
                onChanged: (v) => setState(() => _aktif = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _menyimpan ? null : _simpan,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _menyimpan
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Simpan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
