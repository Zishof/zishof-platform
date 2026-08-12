import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_db/core_db.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../services/kompresi_gambar.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import 'impor_excel_produk_screen.dart';
import 'price_tag_screen.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
const _itemPerHalaman = 20;

/// Palet warna avatar placeholder (foto belum ada) -- deterministik dari
/// nama, sama persis dgn `_paletKartuProduk` di kasir_screen.dart, tapi
/// diduplikasi (BUKAN diimpor) krn keduanya berdiri sendiri dan skala
/// duplikasinya kecil (satu daftar warna, tak layak file baru sendiri).
const _paletKartuProduk = [
  Color(0xFF2563EB),
  Color(0xFF0D9488),
  Color(0xFFC0563D),
  Color(0xFF7C3AED),
  Color(0xFFEA580C),
  Color(0xFF0284C7)
];

/// Mode pencocokan duplikat -- persis 5 mode yg didukung `produk_duplikat_cari`/
/// `produk_duplikat_hapus` server (field `jenis`, BUKAN `mode`).
const _labelJenisDuplikat = {
  'kode': 'Berdasarkan Kode',
  'barcode': 'Berdasarkan Barcode',
  'nama': 'Berdasarkan Nama',
  'kode_barcode': 'Kode + Barcode',
  'kode_barcode_nama': 'Kode + Barcode + Nama',
};

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
/// Perkakas admin lanjutan yang sudah ada: resep/Bahan Baku & HPP otomatis
/// (lihat `_FormProdukState._bahanBaku`), impor/ekspor Excel, pembersihan
/// produk duplikat (5 mode, lihat `_labelJenisDuplikat`), cetak Price Tag/label.
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

  /// Filter tampilan Jenis Item -- CLIENT-SIDE saja dari [_semuaProduk] yang
  /// sudah dimuat penuh (JUAL+BAHAN+EKSTRA, tanpa filter server `jenisItem`,
  /// lihat JavaDoc `prosesKatalog`) -- tidak perlu round-trip server baru.
  /// `'SEMUA'` = tanpa filter (default).
  String _filterJenisItem = 'SEMUA';

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      final katalog = await ApiClient.instance.aksi('katalog');
      final produkJson = (katalog['produk'] as List?) ?? [];
      final produk = produkJson
          .map((e) => Produk.fromJson(e as Map<String, dynamic>))
          .toList();
      final kategori = ((katalog['kategori'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();

      // Segarkan jg cache lokal yg dipakai Kasir, supaya produk baru/berubah
      // di sini langsung terlihat di Kasir tanpa kasir harus menekan sinkron manual.
      await CoreDb.instance.replaceProdukCache(produkJson
          .map((e) => Produk.baseKeCacheRow(e as Map<String, dynamic>))
          .toList());

      Map<String, dynamic>? statistik;
      try {
        statistik = await ApiClient.instance.aksi('produk_statistik');
      } catch (_) {
        // dasbor KPI gagal muat bukan blocker -- daftar produk tetap tampil normal.
      }

      setStateIfMounted(() {
        _semuaProduk = produk;
        _kategori = kategori;
        _statistik = statistik;
        _halaman = 0;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  List<Produk> get _produkTersaring {
    return _semuaProduk.where((p) {
      final cocokKategori =
          _kategoriTerpilih == null || p.kategoriId == _kategoriTerpilih;
      final kw = _kataKunci.toLowerCase();
      final cocokKeyword = kw.isEmpty ||
          p.nama.toLowerCase().contains(kw) ||
          p.kode.toLowerCase().contains(kw) ||
          p.barcode.toLowerCase().contains(kw);
      final cocokJenisItem =
          _filterJenisItem == 'SEMUA' || p.jenisItem == _filterJenisItem;
      return cocokKategori && cocokKeyword && cocokJenisItem;
    }).toList();
  }

  List<Produk> get _produkHalamanIni {
    final semua = _produkTersaring;
    final awal = _halaman * _itemPerHalaman;
    if (awal >= semua.length) return [];
    final akhir = (awal + _itemPerHalaman).clamp(0, semua.length);
    return semua.sublist(awal, akhir);
  }

  int get _totalHalaman =>
      (_produkTersaring.length / _itemPerHalaman).ceil().clamp(1, 999999);

  Future<void> _bukaFormProduk({Produk? produk}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormProduk(
          produk: produk, kategori: _kategori, semuaProduk: _semuaProduk),
    );
    if (tersimpan == true) {
      await _muatSemua();
    }
  }

  /// Bersihkan Duplikat -- preview (`produk_duplikat_cari`) lalu konfirmasi
  /// hapus (`produk_duplikat_hapus`), keduanya digerbang server-side ke
  /// admin/supervisor toko. `jenis` menentukan kunci pencocokan duplikat.
  Future<void> _bersihkanDuplikat(String jenis, String label) async {
    Map<String, dynamic> hasil;
    try {
      hasil = await ApiClient.instance
          .aksi('produk_duplikat_cari', {'jenis': jenis});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memeriksa duplikat: $e')));
      }
      return;
    }
    final grup = ((hasil['grup'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (grup.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tidak ada produk duplikat ($label).')));
      }
      return;
    }
    if (!mounted) return;
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${grup.length} Grup Duplikat ($label)'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Total ${hasil['totalProdukTerlibat'] ?? 0} produk terlibat. Produk dgn transaksi terbanyak (atau id terlama) akan dipertahankan, sisanya digabung & dihapus.'),
                const Divider(height: 20),
                ...grup.take(10).map((g) {
                  final items = ((g['items'] as List?) ?? [])
                      .cast<Map<String, dynamic>>();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kunci: ${g['kunci']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                        ...items.map((it) => Text(
                            '  • ${it['nama']} (${it['kode']}) -- stok ${it['stok']}, transaksi ${it['jumlahTransaksi']}',
                            style: const TextStyle(fontSize: 11))),
                      ],
                    ),
                  );
                }),
                if (grup.length > 10)
                  Text('... dan ${grup.length - 10} grup lainnya.',
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Gabung & Hapus')),
        ],
      ),
    );
    if (konfirmasi != true) return;
    try {
      final hasilHapus = await ApiClient.instance
          .aksi('produk_duplikat_hapus', {'jenis': jenis});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(hasilHapus['description']?.toString() ??
                'Duplikat berhasil dibersihkan.')));
      }
      await _muatSemua();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membersihkan: $e')));
      }
    }
  }

  Future<void> _bukaImporExcel() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ImporExcelProdukScreen()));
    await _muatSemua();
  }

  /// "Unduh Excel" (spec §Produk, khusus supervisor/admin -- gerbang SAMA
  /// dgn `produk_simpan` di server) -- format identik "Daftar Barang dan
  /// Jasa" (Accurate) yg bisa diedit lalu diunggah kembali lewat Impor Excel
  /// tanpa menata ulang kolom (lihat JavaDoc `produkEksporExcel` di server).
  Future<void> _eksporExcel() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('produk_ekspor_excel', {'hanya_aktif': true});
      final b64 = hasil['fileBase64'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw Exception('Server tidak mengembalikan berkas.');
      }
      final bytes = base64Decode(b64);
      final namaFile = (hasil['namaFile'] as String?) ?? 'Katalog.xlsx';
      final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Simpan Katalog Produk',
          fileName: namaFile,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['xlsx']);
      if (path == null) return;
      // Di Desktop, saveFile HANYA mengembalikan path pilihan (belum menulis apa
      // pun) -- mobile sudah menulis via `bytes`, tulis ulang di sini idempoten
      // (byte sama) supaya satu jalur kode bekerja di kedua platform.
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Katalog disimpan: $path')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tombolAksi = [
      HeaderActionButton(
        icon: Icons.sell_outlined,
        label: 'Price Tag',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const PriceTagScreen())),
      ),
      HeaderActionButton(
        icon: Icons.download_outlined,
        label: 'Ekspor',
        onPressed: _eksporExcel,
      ),
      HeaderActionButton(
        icon: Icons.upload_file_outlined,
        label: 'Impor',
        onPressed: _bukaImporExcel,
      ),
      if (Sesi.instance.bolehKelola)
        PopupMenuButton<String>(
          tooltip: 'Bersihkan Duplikat',
          onSelected: (jenis) =>
              _bersihkanDuplikat(jenis, _labelJenisDuplikat[jenis]!),
          itemBuilder: (_) => _labelJenisDuplikat.entries
              .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          child: const HeaderActionSurface(
            icon: Icons.cleaning_services_outlined,
            label: 'Bersihkan',
          ),
        ),
      HeaderActionButton(
        icon: Icons.refresh,
        label: 'Muat Ulang',
        onPressed: _muatSemua,
      ),
    ];
    return AppShell(
      menuAktif: MenuEBisnis.produk,
      judul: 'Manajemen Produk',
      subjudul: 'Kelola katalog produk toko Anda',
      aksiHeader: Wrap(
        alignment: WrapAlignment.end,
        runSpacing: 8,
        children: tombolAksi,
      ),
      actionsAppBar: tombolAksi,
      scrollable: false,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaFormProduk(),
        icon: const Icon(
          Icons.add,
          color: AppColors.darkTextPrimary,
        ),
        label: const Text(
          'Tambah Produk',
          style: TextStyle(color: AppColors.darkTextPrimary),
        ),
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
                        const Icon(Icons.error_outline,
                            size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_pesanError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                            onPressed: _muatSemua,
                            child: const Text('Coba Lagi')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _muatSemua,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      if (_statistik != null)
                        _KartuStatistik(statistik: _statistik!),
                      const SizedBox(height: 12),
                      AppSearchField(
                        hintText: 'Cari produk (nama/kode/barcode)...',
                        onChanged: (v) => setStateIfMounted(() {
                          _kataKunci = v;
                          _halaman = 0;
                        }),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'SEMUA', label: Text('Semua')),
                            ButtonSegment(
                                value: 'JUAL', label: Text('Produk')),
                            ButtonSegment(
                                value: 'BAHAN', label: Text('Bahan')),
                            ButtonSegment(
                                value: 'EKSTRA', label: Text('Ekstra')),
                          ],
                          selected: {_filterJenisItem},
                          onSelectionChanged: (s) => setStateIfMounted(() {
                            _filterJenisItem = s.first;
                            _halaman = 0;
                          }),
                        ),
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
                                onSelected: (_) => setStateIfMounted(() {
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
                                    onSelected: (_) => setStateIfMounted(() {
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
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              constraints.maxWidth >= kAmbangLebarDesktop
                                  ? _TabelProduk(
                                      produkList: _produkHalamanIni,
                                      onTap: (p) => _bukaFormProduk(produk: p))
                                  : Column(
                                      children: _produkHalamanIni
                                          .map((p) => _BarisProduk(
                                              produk: p,
                                              onTap: () =>
                                                  _bukaFormProduk(produk: p)))
                                          .toList()),
                        ),
                      if (_produkTersaring.length > _itemPerHalaman)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: _halaman > 0
                                    ? () => setStateIfMounted(() => _halaman--)
                                    : null,
                              ),
                              Text('Halaman ${_halaman + 1} / $_totalHalaman'),
                              IconButton(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: _halaman < _totalHalaman - 1
                                    ? () => setStateIfMounted(() => _halaman++)
                                    : null,
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

  static const double _tinggiKartu = 96;

  @override
  Widget build(BuildContext context) {
    final item = <(IconData, String, String, Color)>[
      (
        Icons.inventory_2_outlined,
        'Total',
        '${statistik['totalProduk'] ?? 0}',
        AppColors.primary
      ),
      (
        Icons.check_circle_outline,
        'Aktif',
        '${statistik['totalAktif'] ?? 0}',
        AppColors.success
      ),
      (
        Icons.pause_circle_outline,
        'Nonaktif',
        '${statistik['totalNonaktif'] ?? 0}',
        AppColors.textSecondaryOf(context)
      ),
      (
        Icons.remove_shopping_cart_outlined,
        'Stok Habis',
        '${statistik['stokHabis'] ?? 0}',
        AppColors.danger
      ),
      (
        Icons.warning_amber_outlined,
        'Stok Rendah',
        '${statistik['stokRendah'] ?? 0}',
        AppColors.warning
      ),
      (
        Icons.payments_outlined,
        'Nilai Stok',
        _formatRupiah.format((statistik['totalNilaiStok'] as num?) ?? 0),
        AppColors.teal
      ),
    ];
    return SizedBox(
      height: _tinggiKartu,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: item.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (icon, label, nilai, warna) = item[i];
          return SizedBox(
              width: 190,
              height: _tinggiKartu,
              child: AppKpiCard(
                  icon: icon, warna: warna, nilai: nilai, label: label));
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
            child: Text(
                produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white)),
          ),
          title: Text(produk.nama,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '${produk.kode} · ${produk.kategoriNama.isEmpty ? "Tanpa Kategori" : produk.kategoriNama}'),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_formatRupiah.format(produk.hargaJual),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              StatusPill(
                  label: habis ? 'Habis' : 'Stok ${produk.stok}',
                  warna: habis
                      ? AppColors.danger
                      : (rendah ? AppColors.warning : AppColors.success)),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Tampilan tabel padat (Desktop, lebar >= [kAmbangLebarDesktop]) -- padanan
/// visual DataTable pada referensi (Produk|SKU/Barcode|Kategori|Harga
/// Jual|Stok|Status), TANPA kolom Brand/Outlet/Channel krn data itu tak ada
/// di model kita (single-outlet) -- lihat keputusan "visual style only" saat
/// diminta menyamakan tampilan dgn mockup multi-outlet.
class _TabelProduk extends StatelessWidget {
  final List<Produk> produkList;
  final void Function(Produk) onTap;
  const _TabelProduk({required this.produkList, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gayaHeaderTabel = _gayaHeaderTabel(context);
    return AppSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.pageBgOf(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12))),
            child: Row(
              children: [
                Expanded(
                    flex: 4, child: Text('PRODUK', style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('SKU / BARCODE', style: gayaHeaderTabel)),
                Expanded(
                    flex: 2, child: Text('KATEGORI', style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('HARGA JUAL',
                        textAlign: TextAlign.right, style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('STOK',
                        textAlign: TextAlign.center, style: gayaHeaderTabel)),
                Expanded(
                    flex: 2,
                    child: Text('STATUS',
                        textAlign: TextAlign.center, style: gayaHeaderTabel)),
              ],
            ),
          ),
          for (final p in produkList)
            _BarisTabelProduk(produk: p, onTap: () => onTap(p)),
        ],
      ),
    );
  }
}

TextStyle _gayaHeaderTabel(BuildContext context) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.bold,
    color: AppColors.textSecondaryOf(context),
    letterSpacing: 0.4);

class _BarisTabelProduk extends StatelessWidget {
  final Produk produk;
  final VoidCallback onTap;
  const _BarisTabelProduk({required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    final rendah = !habis && produk.stok <= 5;
    final warnaAvatar = _paletKartuProduk[produk.nama.isEmpty
        ? 0
        : produk.nama.codeUnitAt(0) % _paletKartuProduk.length];
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            border:
                Border(top: BorderSide(color: AppColors.borderOf(context)))),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.latarLembut(warnaAvatar),
                    child: Text(
                        produk.nama.isNotEmpty
                            ? produk.nama[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                            color: warnaAvatar,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(produk.nama,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13))),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(produk.kode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryOf(context),
                      fontFamily: 'monospace')),
            ),
            Expanded(
                flex: 2,
                child: Text(
                    produk.kategoriNama.isEmpty ? '-' : produk.kategoriNama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5))),
            Expanded(
                flex: 2,
                child: Text(_formatRupiah.format(produk.hargaJual),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5))),
            Expanded(
              flex: 2,
              child: Center(
                child: StatusPill(
                    label: '${produk.stok}',
                    warna: habis
                        ? AppColors.danger
                        : (rendah ? AppColors.warning : AppColors.success)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: StatusPill(
                    label: produk.aktif ? 'Aktif' : 'Nonaktif',
                    warna: produk.aktif
                        ? AppColors.success
                        : AppColors.textSecondaryOf(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form Tambah/Ubah -- bottom sheet, dipakai utk kedua mode (produk == null berarti Tambah).
class _FormProduk extends StatefulWidget {
  final Produk? produk;
  final List<Kategori> kategori;
  final List<Produk> semuaProduk;
  const _FormProduk(
      {required this.produk,
      required this.kategori,
      required this.semuaProduk});

  @override
  State<_FormProduk> createState() => _FormProdukState();
}

/// Satu baris Bahan Baku (komponen resep) -- `produkId`/`nama` sekadar
/// identitas tampilan (server tak memakainya utk hitungan, lihat JavaDoc
/// [Produk.bahanBaku]), `qty`/`harga` adalah yg benar-benar dijumlahkan
/// server jadi hargaBeli produk induk.
class _BahanBakuBaris {
  int? produkId;
  String nama;
  final TextEditingController qty;
  final TextEditingController harga;
  _BahanBakuBaris(
      {this.produkId,
      required this.nama,
      String qtyAwal = '1',
      String hargaAwal = '0'})
      : qty = TextEditingController(text: qtyAwal),
        harga = TextEditingController(text: hargaAwal);
  void dispose() {
    qty.dispose();
    harga.dispose();
  }
}

/// Satu foto produk -- dua kondisi:
/// - Sudah tersimpan server: [id]+[url] terisi, [bytes] null (ditampilkan
///   lewat `Image.network`).
/// - Staged lokal (BELUM diunggah -- HANYA terjadi saat form ini "Tambah
///   Produk" baru, produk belum punya id server): [bytes] terisi (sudah
///   melalui kompresi), [id]/[url] null. Diunggah SETELAH `_simpan()` sukses
///   dapat id baru -- lihat `_FormProdukState._simpan`.
class _FotoBaris {
  int? id;
  String? url;
  Uint8List? bytes;
  String? namaFile;
  bool mengunggah = false;
  _FotoBaris({this.id, this.url, this.bytes, this.namaFile});
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
  String _jenisItem = 'JUAL';
  bool _menyimpan = false;
  String? _pesanError;
  final List<_BahanBakuBaris> _bahanBaku = [];

  /// Pilihan Produk Ekstra (add-on/modifier) -- cuma daftar id (beda dari
  /// [_bahanBaku] yang perlu qty/harga per baris), server cukup menyimpan
  /// APA ADANYA lewat `ekstra_pilihan` (lihat JavaDoc [Produk.ekstraPilihan]).
  final List<int> _ekstraPilihan = [];

  /// Foto produk (maks 10, lihat [KantinHelper.MAKS_FOTO_PRODUK] server) --
  /// utk produk YANG SUDAH ADA, dimuat dari server via [_muatFoto] &amp; tiap
  /// baris diunggah SEGERA saat dipilih (produk_id sudah ada). Utk produk
  /// BARU (`widget.produk == null`), baris ditahan di memori (`id == null`)
  /// sampai `produk_simpan` sukses dapat id baru -- lihat [_simpan].
  final List<_FotoBaris> _foto = [];
  bool _memuatFoto = false;

  @override
  void initState() {
    super.initState();
    if (widget.produk != null) _muatFoto();
    final p = widget.produk;
    _kode = TextEditingController(text: p?.kode ?? '');
    _nama = TextEditingController(text: p?.nama ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _hargaBeli = TextEditingController(
        text: p == null ? '0' : p.hargaBeli.toStringAsFixed(0));
    _hargaJual = TextEditingController(
        text: p == null ? '0' : p.hargaJual.toStringAsFixed(0));
    _stok = TextEditingController(text: p == null ? '0' : p.stok.toString());
    _keterangan = TextEditingController(text: p?.keterangan ?? '');
    _kategoriId = p?.kategoriId;
    _izinkanJualMinusStok = p?.izinkanJualMinusStok ?? false;
    _aktif = p?.aktif ?? true;
    _jenisItem = p?.jenisItem ?? 'JUAL';
    for (final b in p?.bahanBaku ?? const <Map<String, dynamic>>[]) {
      _bahanBaku.add(_BahanBakuBaris(
        produkId: (b['produkId'] as num?)?.toInt(),
        nama: (b['nama'] as String?) ?? '-',
        qtyAwal: '${b['qty'] ?? 1}',
        hargaAwal: '${b['harga'] ?? 0}',
      ));
    }
    _ekstraPilihan.addAll(p?.ekstraPilihan ?? const <int>[]);
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
    for (final b in _bahanBaku) {
      b.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _totalHpp => _bahanBaku.fold(
      0, (s, b) => s + _angka(b.qty.text) * _angka(b.harga.text));

  Future<void> _tambahBahanBaku() async {
    final dipilih = await showDialog<Produk>(
      context: context,
      // Komponen resep HARUS Bahan Baku (jenisItem == 'BAHAN') -- gap-closure
      // "Jenis Item", produk JUAL biasa tidak boleh dipakai sbg bahan resep.
      builder: (_) => _DialogPilihProduk(
          daftar: widget.semuaProduk
              .where((p) =>
                  p.id != widget.produk?.id && p.jenisItem == 'BAHAN')
              .toList()),
    );
    if (dipilih == null) return;
    setStateIfMounted(() => _bahanBaku.add(_BahanBakuBaris(
        produkId: dipilih.id,
        nama: dipilih.nama,
        hargaAwal: dipilih.hargaBeli.toStringAsFixed(0))));
  }

  void _hapusBahanBaku(_BahanBakuBaris b) {
    setStateIfMounted(() => _bahanBaku.remove(b));
    b.dispose();
  }

  /// Reuse [_DialogPilihProduk] (padanan persis [_tambahBahanBaku], hanya
  /// filternya `jenisItem == 'EKSTRA'` & yang sudah dipilih disembunyikan
  /// dari daftar supaya kasir tak bisa pilih dobel produk ekstra yg sama).
  Future<void> _tambahEkstra() async {
    final dipilih = await showDialog<Produk>(
      context: context,
      builder: (_) => _DialogPilihProduk(
          title: 'Pilih Ekstra',
          tampilkanHargaJual: true,
          daftar: widget.semuaProduk
              .where((p) =>
                  p.id != widget.produk?.id &&
                  p.jenisItem == 'EKSTRA' &&
                  !_ekstraPilihan.contains(p.id))
              .toList()),
    );
    if (dipilih == null) return;
    setStateIfMounted(() => _ekstraPilihan.add(dipilih.id));
  }

  void _hapusEkstra(int produkId) {
    setStateIfMounted(() => _ekstraPilihan.remove(produkId));
  }

  /// Nama tampilan produk ekstra yg sudah dipilih -- dicari dari
  /// [widget.semuaProduk] (katalog lengkap yang sudah dimuat layar Produk,
  /// sama seperti sumber data [_DialogPilihProduk]).
  String _namaProduk(int id) {
    for (final p in widget.semuaProduk) {
      if (p.id == id) return p.nama;
    }
    return '#$id';
  }

  Future<void> _muatFoto() async {
    if (widget.produk == null) return;
    setStateIfMounted(() => _memuatFoto = true);
    try {
      final hasil = await ApiClient.instance
          .aksi('produk_foto_list', {'produk_id': widget.produk!.id});
      final data = (hasil['data'] as List?) ?? const [];
      setStateIfMounted(() {
        _foto
          ..clear()
          ..addAll(data.map((d) => _FotoBaris(
              id: (d['id'] as num).toInt(), url: d['urlGambar'] as String?)));
      });
    } catch (e) {
      // Gagal muat foto bukan error fatal utk form ini -- form tetap bisa
      // dipakai edit field lain, kasir/admin tinggal buka ulang utk retry.
    } finally {
      if (mounted) setStateIfMounted(() => _memuatFoto = false);
    }
  }

  /// Ekstensi berkas yg diterima -- validasi klien "wajib gambar" (spesifikasi
  /// user), pengecekan SUNGGUHAN (bisa dibaca sbg gambar) tetap terjadi lewat
  /// [kompresGambar] yg melempar [FormatException] kalau `decodeImage` gagal.
  static const _ekstensiGambarValid = {
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'
  };

  Future<void> _pilihFoto(ImageSource sumber) async {
    if (_foto.length >= 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Maksimal 10 foto per produk.')));
      }
      return;
    }
    final XFile? berkas =
        await ImagePicker().pickImage(source: sumber, imageQuality: 100);
    if (berkas == null) return;
    final namaFile = berkas.name;
    final ekstensi = namaFile.contains('.')
        ? namaFile.split('.').last.toLowerCase()
        : '';
    if (!_ekstensiGambarValid.contains(ekstensi)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Format berkas wajib berupa gambar.')));
      }
      return;
    }
    final bytesAsli = await berkas.readAsBytes();
    if (bytesAsli.length > 10 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Ukuran berkas maksimal 10 MB.')));
      }
      return;
    }

    final baris = _FotoBaris(bytes: bytesAsli, namaFile: namaFile)
      ..mengunggah = true;
    setStateIfMounted(() => _foto.add(baris));

    Uint8List bytesKompres;
    try {
      // compute() -> isolate terpisah spy decode+encode JPEG foto kamera
      // resolusi tinggi tak menjank UI (lihat JavaDoc kompresGambar).
      bytesKompres = await compute(kompresGambarKeBawah500Kb, bytesAsli);
    } catch (e) {
      setStateIfMounted(() => _foto.remove(baris));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memproses gambar: $e')));
      }
      return;
    }
    baris.bytes = bytesKompres;

    if (widget.produk == null) {
      // Produk baru: belum punya id server -- tahan di memori, diunggah
      // batch SETELAH _simpan() sukses (lihat _simpan).
      setStateIfMounted(() => baris.mengunggah = false);
      return;
    }
    await _unggahBaris(baris, widget.produk!.id);
  }

  Future<void> _unggahBaris(_FotoBaris baris, int produkId) async {
    setStateIfMounted(() => baris.mengunggah = true);
    try {
      await ApiClient.instance.aksi('produk_foto_upload', {
        'produk_id': produkId,
        'file_base64': base64Encode(baris.bytes!),
        'nama_file': baris.namaFile ?? 'foto.jpg',
      });
      // Muat ulang daftar dari server supaya baris ini dapat urlGambar yg
      // benar (produk_foto_upload sendiri cuma balas {status,id}) -- ukuran
      // daftar kecil (maks 10), round-trip tambahan ini murah.
      await _muatFoto();
    } catch (e) {
      setStateIfMounted(() => _foto.remove(baris));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengunggah foto: $e')));
      }
    }
  }

  Future<void> _hapusFoto(_FotoBaris baris) async {
    if (baris.id == null) {
      // Staged, belum pernah sampai ke server -- cukup buang dari memori.
      setStateIfMounted(() => _foto.remove(baris));
      return;
    }
    setStateIfMounted(() => baris.mengunggah = true);
    try {
      await ApiClient.instance.aksi('produk_foto_hapus', {'id': baris.id});
      setStateIfMounted(() => _foto.remove(baris));
    } catch (e) {
      setStateIfMounted(() => baris.mengunggah = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menghapus foto: $e')));
      }
    }
  }

  Future<void> _bukaPemilihSumberFoto() async {
    final sumber = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Ambil Foto (Kamera)'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (sumber != null) await _pilihFoto(sumber);
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('produk_simpan', {
        if (widget.produk != null) 'id': widget.produk!.id,
        'kode': _kode.text.trim(),
        'nama': _nama.text.trim(),
        'barcode': _barcode.text.trim(),
        'harga_beli':
            _bahanBaku.isNotEmpty ? _totalHpp : _angka(_hargaBeli.text),
        'harga_jual': _angka(_hargaJual.text),
        'stok': _angka(_stok.text),
        'keterangan': _keterangan.text.trim(),
        'kategori_id': _kategoriId,
        'izinkan_jual_minus_stok': _izinkanJualMinusStok,
        'aktif': _aktif,
        'jenis_item': _jenisItem,
        'bahan_baku': _bahanBaku
            .map((b) => {
                  'produk_id': b.produkId,
                  'nama': b.nama,
                  'qty': _angka(b.qty.text),
                  'harga': _angka(b.harga.text)
                })
            .toList(),
        'ekstra_pilihan': _ekstraPilihan,
      });
      // Produk baru: baris foto yg ditahan di memori (id==null, blm pernah
      // diunggah krn belum ada produk_id) diunggah SEKARANG pakai id baru
      // dari respons ini -- lihat JavaDoc _foto/_pilihFoto.
      if (widget.produk == null) {
        final produkIdBaru = (hasil['id'] as num?)?.toInt();
        if (produkIdBaru != null) {
          for (final baris in _foto.where((b) => b.id == null).toList()) {
            await ApiClient.instance.aksi('produk_foto_upload', {
              'produk_id': produkIdBaru,
              'file_base64': base64Encode(baris.bytes!),
              'nama_file': baris.namaFile ?? 'foto.jpg',
            });
          }
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ubah = widget.produk != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: AppFormSheet(
            scrollController: scrollController,
            title: ubah ? 'Ubah Produk' : 'Tambah Produk',
            subtitle:
                'Atur identitas, harga, stok, dan resep bahan baku produk.',
            icon: ubah ? Icons.edit_note_outlined : Icons.add_box_outlined,
            errorText: _pesanError,
            children: [
              AppFormSection(
                judul: 'Identitas Produk',
                deskripsi:
                    'Kode dan nama produk digunakan di kasir, laporan, dan pencarian stok.',
                children: [
                  AppFormTextField(
                    label: 'Kode Produk *',
                    controller: _kode,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                    label: 'Nama Produk *',
                    controller: _nama,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  AppFormTextField(
                    label: 'Barcode (opsional)',
                    controller: _barcode,
                  ),
                  DropdownButtonFormField<int?>(
                    value: _kategoriId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Kategori',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('-- Tanpa Kategori --')),
                      ...widget.kategori.map((k) => DropdownMenuItem<int?>(
                          value: k.id, child: Text(k.nama))),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _kategoriId = v),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Jenis Item',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context))),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'JUAL', label: Text('Produk (Dijual)')),
                      ButtonSegment(
                          value: 'BAHAN', label: Text('Bahan Baku')),
                      ButtonSegment(
                          value: 'EKSTRA', label: Text('Ekstra')),
                    ],
                    selected: {_jenisItem},
                    onSelectionChanged: (s) =>
                        setStateIfMounted(() => _jenisItem = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppFormSection(
                judul: 'Harga & Stok',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppFormTextField(
                          label: 'Harga Beli',
                          controller: _hargaBeli,
                          enabled: _bahanBaku.isEmpty,
                          keyboardType: TextInputType.number,
                          helperText: _bahanBaku.isNotEmpty
                              ? 'Otomatis dari Bahan Baku (${_formatRupiah.format(_totalHpp)})'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppFormTextField(
                          label: 'Harga Jual *',
                          controller: _hargaJual,
                          keyboardType: TextInputType.number,
                          validator: (v) =>
                              _angka(v ?? '') <= 0 ? 'Wajib > 0' : null,
                        ),
                      ),
                    ],
                  ),
                  AppFormTextField(
                    label: 'Stok',
                    controller: _stok,
                    keyboardType: TextInputType.number,
                  ),
                  AppFormTextField(
                    label: 'Keterangan',
                    controller: _keterangan,
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                judul: 'Bahan Baku (Resep) & HPP Otomatis',
                aksiJudul: TextButton.icon(
                    onPressed: _tambahBahanBaku,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah')),
                child: _bahanBaku.isEmpty
                    ? Text(
                        'Belum ada resep -- Harga Beli diisi manual. Tambahkan komponen di sini kalau produk ini dirakit dari bahan lain (HPP dihitung otomatis).',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context)))
                    : Column(
                        children: [
                          ..._bahanBaku.map((b) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Expanded(
                                        flex: 3,
                                        child: Text(b.nama,
                                            style:
                                                const TextStyle(fontSize: 13))),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextField(
                                        controller: b.qty,
                                        keyboardType: TextInputType.number,
                                        decoration: AppFormStyle.fieldDecoration(
                                          context,
                                          labelText: 'Qty',
                                          isDense: true,
                                        ),
                                        onChanged: (_) =>
                                            setStateIfMounted(() {}),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: b.harga,
                                        keyboardType: TextInputType.number,
                                        decoration: AppFormStyle.fieldDecoration(
                                          context,
                                          labelText: 'Harga Satuan',
                                          isDense: true,
                                        ),
                                        onChanged: (_) =>
                                            setStateIfMounted(() {}),
                                      ),
                                    ),
                                    IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () => _hapusBahanBaku(b)),
                                  ],
                                ),
                              )),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total HPP',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Text(_formatRupiah.format(_totalHpp),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                judul: 'Pilih Ekstra (Add-on)',
                aksiJudul: TextButton.icon(
                    onPressed: _tambahEkstra,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah')),
                child: _ekstraPilihan.isEmpty
                    ? Text(
                        'Belum ada ekstra -- tambahkan produk bertipe "Ekstra" di sini kalau produk ini boleh dijual bersama add-on pilihan (mis. topping/rasa tambahan). Pelanggan memilihnya lewat kotak "Pilih Ekstra" saat produk ini ditambahkan ke keranjang di Kasir.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context)))
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _ekstraPilihan
                            .map((id) => Chip(
                                  label: Text(_namaProduk(id)),
                                  onDeleted: () => _hapusEkstra(id),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                judul: 'Foto Produk (maks 10)',
                aksiJudul: TextButton.icon(
                    onPressed: _foto.length >= 10 || _memuatFoto
                        ? null
                        : _bukaPemilihSumberFoto,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                    label: const Text('Tambah Foto')),
                child: _memuatFoto
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                      )
                    : _foto.isEmpty
                        ? Text(
                            'Belum ada foto -- tambahkan hingga 10 foto (galeri atau kamera). Berkas otomatis dikompres di bawah 500 KB sebelum diunggah. Kalau lebih dari 1 foto, tampilan di Kasir akan berganti otomatis tiap 3 detik.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondaryOf(context)))
                        : Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _foto
                                .map((baris) => Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: SizedBox(
                                            width: 84,
                                            height: 84,
                                            child: baris.bytes != null
                                                ? Image.memory(baris.bytes!,
                                                    fit: BoxFit.cover)
                                                : Image.network(
                                                    baris.url ?? '',
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (_, __, ___) =>
                                                            Container(
                                                      color: AppColors
                                                          .borderOf(context),
                                                      child: const Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                          size: 20),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        if (baris.mengunggah)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black38,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color:
                                                              Colors.white),
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Positioned(
                                            top: -6,
                                            right: -6,
                                            child: InkWell(
                                              onTap: () => _hapusFoto(baris),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(2),
                                                decoration:
                                                    const BoxDecoration(
                                                  color: Colors.black87,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close,
                                                    size: 14,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ))
                                .toList(),
                          ),
              ),
              const SizedBox(height: 8),
              AppFormSection(
                judul: 'Pengaturan',
                children: [
                  AppFormSwitchTile(
                    title: 'Boleh dijual walau stok minus',
                    value: _izinkanJualMinusStok,
                    onChanged: (v) =>
                        setStateIfMounted(() => _izinkanJualMinusStok = v),
                  ),
                  AppFormSwitchTile(
                    title: 'Aktif (tampil di Kasir)',
                    value: _aktif,
                    onChanged: (v) => setStateIfMounted(() => _aktif = v),
                  ),
                ],
              ),
            ],
            actions: [
              OutlinedButton.icon(
                onPressed:
                    _menyimpan ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batal'),
              ),
              ElevatedButton.icon(
                onPressed: _menyimpan ? null : _simpan,
                icon: _menyimpan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: const Text('Simpan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog pencarian produk sederhana -- dipakai [_FormProdukState._tambahBahanBaku]
/// (Bahan Baku) & [_FormProdukState._tambahEkstra] (Ekstra) utk memilih dari
/// daftar produk yg SUDAH dimuat layar Produk (tak perlu round-trip server
/// baru, katalog di memori sudah cukup) -- [title] membedakan judul dialog
/// antara kedua pemanggil, filter `daftar`-nya sendiri jadi tanggung jawab
/// pemanggil (lihat `jenisItem == 'BAHAN'` vs `jenisItem == 'EKSTRA'`).
class _DialogPilihProduk extends StatefulWidget {
  final List<Produk> daftar;
  final String title;

  /// `false` (default, Bahan Baku) = kolom harga menampilkan Harga Beli
  /// (dipakai HPP). `true` (Ekstra) = menampilkan Harga Jual (itulah harga
  /// yg dibebankan ke pelanggan saat add-on ini dipilih di Kasir).
  final bool tampilkanHargaJual;
  const _DialogPilihProduk(
      {required this.daftar,
      this.title = 'Pilih Bahan Baku',
      this.tampilkanHargaJual = false});

  @override
  State<_DialogPilihProduk> createState() => _DialogPilihProdukState();
}

class _DialogPilihProdukState extends State<_DialogPilihProduk> {
  String _kataKunci = '';

  @override
  Widget build(BuildContext context) {
    final tersaring = widget.daftar
        .where((p) =>
            _kataKunci.isEmpty ||
            p.nama.toLowerCase().contains(_kataKunci.toLowerCase()) ||
            p.kode.toLowerCase().contains(_kataKunci.toLowerCase()))
        .take(50)
        .toList();
    return AppDetailDialogShell(
      title: widget.title,
      children: [
        TextField(
          autofocus: true,
          decoration: AppFormStyle.fieldDecoration(
            context,
            labelText: 'Cari Produk',
            hintText: 'Cari produk...',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setStateIfMounted(() => _kataKunci = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 420,
          child: tersaring.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ditemukan.',
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                )
              : AppDataTable(
                  minWidth: 620,
                  emptyText: 'Tidak ditemukan.',
                  columns: [
                    const AppTableColumn('Produk', flex: 3),
                    const AppTableColumn('Kode', flex: 2),
                    AppTableColumn(
                        widget.tampilkanHargaJual ? 'Harga Jual' : 'Harga Beli',
                        flex: 2,
                        align: TextAlign.right),
                  ],
                  rows: tersaring.map((p) {
                    return AppTableRowData(
                      cells: [
                        AppTableCell.text(p.nama, flex: 3),
                        AppTableCell.text(p.kode, flex: 2),
                        AppTableCell.text(
                          _formatRupiah.format(widget.tampilkanHargaJual
                              ? p.hargaJual
                              : p.hargaBeli),
                          flex: 2,
                          align: TextAlign.right,
                        ),
                      ],
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  }).toList(),
                ),
        ),
      ],
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'))
      ],
    );
  }
}
