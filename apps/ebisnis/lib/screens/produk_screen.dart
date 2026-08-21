import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../services/dynamic_report.dart';
import 'produk_stok_tanggal.dart';
import '../services/kompresi_gambar.dart';
import '../services/master_offline.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/riwayat_data_dialog.dart';
import 'impor_excel_produk_screen.dart';
import 'price_tag_screen.dart';
import 'produk_mutasi_barang_tab.dart';
import 'produk_rekonsiliasi_ledger_tab.dart';
import '../widgets/safe_state.dart';
import '../widgets/jejak_galat.dart';
import '../widgets/aksi_baris_menu.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
const _itemPerHalaman = 15;

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

/// Tampilkan stok tanpa desimal bila bulat -- stok per tanggal datang sbg
/// pecahan dari server, dan "12" jauh lebih mudah dibaca daripada "12.0".
String _teksStok(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

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
/// Offline-first utk daftar + CRUD master (pola sama dgn cara_bayar_screen):
/// daftar produk & kebijakan retur BACA LOKAL-DULU lewat
/// [MasterOffline.daftarCacheDulu] (snapshot cache tampil seketika, hasil
/// server menyusul dgn kilau baris + banner perubahan -- termasuk perubahan
/// kasir lain), daftar kategori lewat [MasterOffline.daftarDenganCache]
/// (snapshot terakhir tampil saat offline), simpan/hapus master lewat
/// [prosesSimpanMaster] (lokal dulu + dialog animasi kirim; offline diantre).
/// Aksi berkas/bulk (foto, ekspor/impor Excel, bersih duplikat, data sample)
/// tetap online-only -- tidak aman diantre offline.
///
/// Perkakas admin lanjutan yang sudah ada: resep/Bahan Baku & HPP otomatis
/// (lihat `_FormProdukState._bahanBaku`), impor/ekspor Excel, pembersihan
/// produk duplikat (5 mode, lihat `_labelJenisDuplikat`), cetak Price Tag/label.
class ProdukScreen extends StatefulWidget {
  const ProdukScreen({super.key});

  @override
  State<ProdukScreen> createState() => _ProdukScreenState();
}

class _ProdukScreenState extends State<ProdukScreen> with JejakGalat {
  bool _memuat = true;
  String? _pesanError;
  List<Produk> _semuaProduk = [];
  List<Kategori> _kategori = [];
  List<KebijakanRetur> _kebijakanRetur = [];
  int _tabAktif = 0;
  int? _kategoriTerpilih;
  String _kataKunci = '';
  final _controllerCariProduk = TextEditingController();
  int _halaman = 0;
  int _totalProduk = 0;
  Map<String, dynamic>? _statistik;
  bool _memulaiDataSample = false;
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;

  /// Filter tampilan Jenis Item -- CLIENT-SIDE saja dari [_semuaProduk] yang
  /// sudah dimuat penuh (JUAL+BAHAN+EKSTRA, tanpa filter server `jenisItem`,
  /// lihat JavaDoc `prosesKatalog`) -- tidak perlu round-trip server baru.
  /// `'SEMUA'` = tanpa filter (default).
  String _filterJenisItem = 'SEMUA';

  /// Tanggal acuan stok. null = stok berjalan (perilaku lama).
  DateTime? _tanggalStok;
  HasilStokTanggal? _stokTanggal;
  bool _memuatStokTanggal = false;
  DynamicReportModel? _modelLaporan;
  bool _menyiapkanLaporan = false;

  @override
  void initState() {
    super.initState();
    _muatSemua();
  }

  @override
  void dispose() {
    _controllerCariProduk.dispose();
    super.dispose();
  }

  Future<void> _muatSemua() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    try {
      // Baca LOKAL DULU: snapshot cache langsung tampil, lalu hasil server
      // menyusul dgn diff baru/berubah/terhapus utk animasi (daftarCacheDulu).
      await MasterOffline.daftarCacheDulu(
          'katalog',
          {
            'page': _halaman + 1,
            'page_size': _itemPerHalaman,
            if (_kataKunci.trim().isNotEmpty) 'keyword': _kataKunci.trim(),
            if (_kategoriTerpilih != null) 'kategori_id': _kategoriTerpilih,
            if (_filterJenisItem != 'SEMUA') 'jenisItem': _filterJenisItem,
          },
          'master:produk_list', onData: (katalog) {
        if (!mounted) return;
        final produk = ((katalog['produk'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            // Draf create offline belum punya id -- Produk.fromJson
            // mewajibkannya, jadi baris draf dilewati sampai tersinkron.
            .where((e) => e['id'] is int)
            .map(Produk.fromJson)
            .toList();
        final dariServer = katalog['dariServer'] == true;
        setStateIfMounted(() {
          _semuaProduk = produk;
          // Emisi daftarCacheDulu tidak meneruskan 'total' server -- selama
          // halaman penuh, asumsikan masih ada halaman berikutnya supaya
          // kontrol paginasi tetap bisa dipakai menjelajah katalog besar.
          _totalProduk = dariServer
              ? (katalog['total'] as num?)?.toInt() ??
                  (produk.length >= _itemPerHalaman
                      ? (_halaman + 1) * _itemPerHalaman + 1
                      : _halaman * _itemPerHalaman + produk.length)
              : produk.length;
          _idBaru = dariServer
              ? Set<String>.from(katalog['idBaru'] as Set? ?? const <String>{})
              : {};
          _idBerubah = dariServer
              ? Set<String>.from(
                  katalog['idBerubah'] as Set? ?? const <String>{})
              : {};
          _jumlahHapus = dariServer ? (katalog['jumlahHapus'] as int? ?? 0) : 0;
          if (dariServer &&
              (_idBaru.isNotEmpty ||
                  _idBerubah.isNotEmpty ||
                  _jumlahHapus > 0)) {
            _versiPerubahan++;
          }
          // _memuat sengaja TIDAK dimatikan di sini: begitu snapshot cache
          // terisi, spinner penuh otomatis berganti daftar (kondisi build
          // `_memuat && _semuaProduk.isEmpty`), sementara progress tipis tetap
          // tampil sampai seluruh muatan (server/kategori/statistik) selesai.
        });
      }, fieldData: 'produk');
      final hasilKategori = await MasterOffline.daftarDenganCache(
          'jenis_produk_list',
          {'page': 1, 'page_size': 100},
          'master:jenis_produk');
      final kategori = ((hasilKategori['data'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();
      // Kebijakan retur ikut baca-lokal-dulu (tanpa kilau/banner sendiri --
      // daftarnya kecil; animasi perubahan cukup di daftar produk di atas).
      await MasterOffline.daftarCacheDulu(
          'kebijakan_retur_list',
          {'termasuk_nonaktif': true},
          'master:kebijakan_retur', onData: (hasilKebijakan) {
        if (!mounted) return;
        final kebijakanRetur = ((hasilKebijakan['data'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            // KebijakanRetur.fromJson mewajibkan id -- draf offline dilewati.
            .where((e) => e['id'] != null)
            .map(KebijakanRetur.fromJson)
            .toList();
        setStateIfMounted(() => _kebijakanRetur = kebijakanRetur);
      });

      Map<String, dynamic>? statistik;
      try {
        statistik = await ApiClient.instance.aksi('produk_statistik');
      } catch (_) {
        // dasbor KPI gagal muat bukan blocker -- daftar produk tetap tampil normal.
      }

      setStateIfMounted(() {
        _kategori = kategori;
        _statistik = statistik;
      });
    } catch (e) {
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
    } finally {
      if (mounted) setStateIfMounted(() => _memuat = false);
    }
  }

  Future<void> _mulaiDataSampleProduk() async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Masukkan 1.000 Supplier dan 50.000 Produk Demo?'),
        content: const Text(
            'Fitur ini hanya untuk toko demo/UAT. Proses berjalan di server secara background dan aman ditekan ulang karena kode supplier dan produk bersifat idempoten.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Mulai')),
        ],
      ),
    );
    if (setuju != true || !mounted) return;
    setStateIfMounted(() => _memulaiDataSample = true);
    try {
      final hasil = await ApiClient.instance.aksi('pos_demo_seed_products', {
        'toko_id': Sesi.instance.tokoId,
        'konfirmasi': 'SEED-DEMO-PRODUK-50000',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${hasil['description'] ?? 'Job supplier dan produk demo dimulai.'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal memulai data demo: $e')));
    } finally {
      if (mounted) setStateIfMounted(() => _memulaiDataSample = false);
    }
  }

  List<Produk> get _produkTersaring => _semuaProduk;

  List<Produk> get _produkHalamanIni {
    final semua = _produkTersaring;
    return semua;
  }

  int get _totalHalaman =>
      (_totalProduk / _itemPerHalaman).ceil().clamp(1, 999999);

  /// Ambil ulang stok pada tanggal acuan. Dipanggil saat tanggal berubah dan
  /// saat kata kunci berubah, supaya angka di layar selalu cocok dgn filter.
  Future<void> _muatStokTanggal() async {
    if (_tanggalStok == null) {
      setStateIfMounted(() => _stokTanggal = null);
      return;
    }
    setStateIfMounted(() => _memuatStokTanggal = true);
    try {
      final hasil = await StokPerTanggal.ambil(
          tanggal: _tanggalStok, kataKunci: _kataKunci);
      setStateIfMounted(() => _stokTanggal = hasil);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat stok per tanggal: $e')));
        setStateIfMounted(() => _tanggalStok = null);
      }
    } finally {
      setStateIfMounted(() => _memuatStokTanggal = false);
    }
  }

  Future<void> _pilihTanggalStok() async {
    final kini = DateTime.now();
    final pilih = await showDatePicker(
      context: context,
      initialDate: _tanggalStok ?? kini,
      firstDate: DateTime(kini.year - 5),
      // Stok masa depan tidak bermakna: tidak ada mutasi setelah hari ini.
      lastDate: kini,
      helpText: 'Tampilkan stok pada tanggal',
    );
    if (pilih == null) return;
    setStateIfMounted(() => _tanggalStok = pilih);
    await _muatStokTanggal();
  }

  /// Bahan laporan = baris `stok_per_tanggal` yang SUDAH tersaring server
  /// (kata kunci + tanggal), jadi yang diekspor persis yang tampil.
  Future<HasilStokTanggal?> _bahanLaporan() async {
    if (_stokTanggal != null) return _stokTanggal;
    // Belum memilih tanggal -> pakai stok terkini, tetap lewat laporan yang
    // sama supaya kolom dan angkanya konsisten dgn mode tanggal.
    return StokPerTanggal.ambil(kataKunci: _kataKunci);
  }

  String get _subjudulLaporan {
    final k = _kataKunci.trim();
    final tgl = _tanggalStok == null
        ? 'Stok terkini'
        : 'Stok per ${DateFormat('dd/MM/yyyy').format(_tanggalStok!)}';
    var teks = k.isEmpty ? tgl : '$tgl  -  pencarian "$k"';
    // Laporan yang dicetak/diekspor ikut menyandang keterangannya: berkas
    // beredar lepas dari layar, dan pembacanya tidak punya cara lain untuk
    // tahu angkanya berasal dari salinan lama.
    final c = _stokTanggal;
    if (c != null && c.dariCache) {
      teks += c.disimpanPada == null
          ? '  -  dari salinan tersimpan (jaringan terputus)'
          : '  -  dari salinan tersimpan '
              '${DateFormat('dd/MM/yyyy HH:mm').format(c.disimpanPada!)}';
    }
    return teks;
  }

  Future<void> _aturAtauPreviewLaporan({required bool preview}) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final bahan = await _bahanLaporan();
      if (bahan == null || !mounted) return;
      final data = bahan.keLaporan(
          judul: 'Laporan Stok Produk', subjudul: _subjudulLaporan);
      final model = await DynamicReportDesigner.show(context,
          data: data, initial: _modelLaporan, initialTab: preview ? 0 : 1);
      if (model != null) setStateIfMounted(() => _modelLaporan = model);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyiapkan laporan: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  Future<void> _eksporLaporan(String format) async {
    setStateIfMounted(() => _menyiapkanLaporan = true);
    try {
      final bahan = await _bahanLaporan();
      if (bahan == null || !mounted) return;
      final data = bahan.keLaporan(
          judul: 'Laporan Stok Produk', subjudul: _subjudulLaporan);
      final model = _modelLaporan ?? DynamicReportModel.fromData(data);
      _modelLaporan = model;
      final slug = _tanggalStok == null
          ? 'stok-produk'
          : 'stok-produk-${DateFormat('yyyyMMdd').format(_tanggalStok!)}';
      if (format == 'pdf') {
        await DynamicReportDesigner.exportPdf(data, model, '$slug.pdf');
      } else if (format == 'excel') {
        if (!mounted) return;
        await DynamicReportDesigner.exportExcel(
            context, data, model, '$slug.xlsx');
      } else {
        if (!mounted) return;
        await DynamicReportDesigner.exportWord(
            context, data, model, '$slug.doc');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
      }
    } finally {
      setStateIfMounted(() => _menyiapkanLaporan = false);
    }
  }

  /// Bilah filter tanggal + ekspor laporan.
  Widget _bilahStokDanLaporan() {
    final sibuk = _menyiapkanLaporan || _memuatStokTanggal;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: sibuk ? null : _pilihTanggalStok,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(_tanggalStok == null
              ? 'Stok terkini'
              : 'Stok per ${DateFormat('dd/MM/yyyy').format(_tanggalStok!)}'),
        ),
        if (_tanggalStok != null)
          IconButton(
            tooltip: 'Kembali ke stok terkini',
            onPressed: sibuk
                ? null
                : () {
                    setStateIfMounted(() {
                      _tanggalStok = null;
                      _stokTanggal = null;
                    });
                  },
            icon: const Icon(Icons.clear, size: 18),
          ),
        if (_memuatStokTanggal)
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
        // Angka dari salinan tersimpan WAJIB ditandai: stok lama yang disangka
        // terkini lebih berbahaya daripada tidak ada angka sama sekali.
        if (_stokTanggal?.dariCache == true)
          Tooltip(
            message: _stokTanggal?.disimpanPada == null
                ? 'Angka dari salinan tersimpan (jaringan terputus).'
                : 'Salinan tersimpan '
                    '${DateFormat('dd/MM/yyyy HH:mm').format(_stokTanggal!.disimpanPada!)}.',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_outlined,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 6),
                Text(
                  _stokTanggal?.disimpanPada == null
                      ? 'Salinan tersimpan'
                      : 'Salinan ${DateFormat('dd/MM HH:mm').format(_stokTanggal!.disimpanPada!)}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ]),
            ),
          ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed:
              sibuk ? null : () => _aturAtauPreviewLaporan(preview: true),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: const Text('Preview'),
        ),
        OutlinedButton.icon(
          onPressed:
              sibuk ? null : () => _aturAtauPreviewLaporan(preview: false),
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('Atur Model'),
        ),
        OutlinedButton.icon(
          onPressed: sibuk ? null : () => _eksporLaporan('pdf'),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF'),
        ),
        OutlinedButton.icon(
          onPressed: sibuk ? null : () => _eksporLaporan('excel'),
          icon: const Icon(Icons.table_view_outlined, size: 18),
          label: const Text('Excel'),
        ),
        OutlinedButton.icon(
          onPressed: sibuk ? null : () => _eksporLaporan('word'),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text('Word'),
        ),
      ],
    );
  }

  Future<void> _bukaFormProduk({Produk? produk}) async {
    // Daftar relasi resep/ekstra bukan tabel utama, namun tetap dimuat secara
    // terukur (maks. 100 per jenis) agar paging katalog 15 baris tidak membuat
    // pilihan Bahan/Ekstra hanya berisi produk pada halaman yang sedang terlihat.
    final pilihanRelasi = <int, Produk>{for (final p in _semuaProduk) p.id: p};
    for (final jenis in const ['BAHAN', 'EKSTRA']) {
      try {
        final hasil = await ApiClient.instance.aksi('katalog', {
          'page': 1,
          'page_size': 100,
          'jenisItem': jenis,
        });
        for (final raw in (hasil['produk'] as List?) ?? const []) {
          final p = Produk.fromJson(raw as Map<String, dynamic>);
          pilihanRelasi[p.id] = p;
        }
      } catch (_) {
        // Form tetap dapat dibuka memakai data halaman aktif bila jaringan
        // untuk data pilihan tambahan sedang terganggu.
      }
    }
    if (!mounted) return;
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormProduk(
          produk: produk,
          kategori: _kategori,
          kebijakanRetur: _kebijakanRetur.where((e) => e.aktif).toList(),
          semuaProduk: pilihanRelasi.values.toList()),
    );
    if (tersimpan == true) {
      await _muatSemua();
    }
  }

  /// Dialog "Riwayat Data" per baris produk (AuditTrails/Envers, entitas
  /// 'produk') -- tombol ikon jam di tiap baris daftar.
  void _riwayatProduk(Produk p) =>
      tampilkanRiwayatData(context, entitas: 'produk', id: p.id, judul: p.nama);

  Future<void> _bukaFormKebijakan({KebijakanRetur? kebijakan}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormKebijakanRetur(kebijakan: kebijakan),
    );
    if (tersimpan == true) await _muatSemua();
  }

  Future<void> _hapusKebijakan(KebijakanRetur k) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Kebijakan Retur?'),
        content: Text(
            'Kebijakan "${k.nama}" akan dihapus. Kebijakan yang masih dipakai produk tidak dapat dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ya != true || !mounted) return;
    try {
      // Alur "lokal dulu" ber-indikator animasi (prosesSimpanMaster):
      // antre -> coba kirim -> tutup dialog (offline pun langsung lanjut).
      await prosesSimpanMaster(
        context,
        aksi: 'kebijakan_retur_hapus',
        body: {'id': k.id},
        kunci: 'kebijakan_retur:${k.id}',
        cacheKey: 'master:kebijakan_retur',
        rowLokal: {'id': k.id},
        hapusLokal: true,
      );
      await _muatSemua();
    } catch (e) {
      if (mounted) {
        snackbarGalat(context, e);
      }
    }
  }

  /// Isi "Nama Pemasok Utama" produk yang MASIH kosong dari penerimaan barang
  /// (kulakan) terakhir tiap produk. Dua langkah: pratinjau dulu supaya jumlah
  /// yang akan tersentuh terlihat sebelum apa pun disimpan.
  ///
  /// Satuan TIDAK ikut diisi -- tidak ada satu pun tabel yang mencatatnya di
  /// luar impor Excel, jadi tidak ada sumber untuk ditarik.
  Future<void> _isiPemasokDariKulakan() async {
    try {
      final pratinjau = await ApiClient.instance
          .aksi('produk_isi_pemasok_dari_kulakan', {'pratinjau': true});
      final kandidat = (pratinjau['kandidat'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      if (kandidat == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Tidak ada produk yang bisa diisi: pemasoknya sudah terisi, '
                'atau belum pernah ada penerimaan barang.')));
        return;
      }
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Isi Pemasok dari Kulakan'),
          content: Text(
              '$kandidat produk yang pemasoknya masih kosong akan diisi dari '
              'penerimaan barang terakhir masing-masing.\n\n'
              'Produk yang pemasoknya sudah terisi tidak akan diubah.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Batal')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Isi Sekarang')),
          ],
        ),
      );
      if (lanjut != true) return;
      final hasil = await ApiClient.instance
          .aksi('produk_isi_pemasok_dari_kulakan', {'pratinjau': false});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${hasil['description'] ?? 'Selesai.'}')));
      await _muatSemua();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal mengisi pemasok: $e')));
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

  Widget _daftarKebijakanRetur() {
    return RefreshIndicator(
      onRefresh: _muatSemua,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          Text(
            'Tentukan aturan retur yang dapat dipilih pada setiap produk. Produk tanpa pilihan khusus otomatis memakai “Tanpa Kebijakan Retur”.',
            style: TextStyle(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 16),
          AppDataTable(
            minWidth: 720,
            emptyText: 'Belum ada Kebijakan Retur.',
            columns: const [
              AppTableColumn('Nama', flex: 2),
              AppTableColumn('Keterangan', flex: 3),
              AppTableColumn('Status', width: 100, align: TextAlign.center),
              AppTableColumn('Aksi', width: 64, align: TextAlign.center),
            ],
            rows: _kebijakanRetur
                .map((k) => AppTableRowData(
                      onTap: Sesi.instance.bolehKelola
                          ? () => _bukaFormKebijakan(kebijakan: k)
                          : null,
                      cells: [
                        AppTableCell.text(k.nama, flex: 2),
                        AppTableCell.text(
                            k.keterangan.isEmpty ? '-' : k.keterangan,
                            flex: 3),
                        AppTableCell(
                            width: 64,
                            align: TextAlign.center,
                            child: AksiBarisMenu(aksi: [
                              AksiBaris(
                                  ikon: Icons.edit_outlined,
                                  label: 'Ubah kebijakan',
                                  onTap: Sesi.instance.bolehKelola
                                      ? () => _bukaFormKebijakan(kebijakan: k)
                                      : null),
                              AksiBaris(
                                  ikon: Icons.delete_outline,
                                  label: 'Hapus kebijakan',
                                  merusak: true,
                                  onTap: Sesi.instance.bolehKelola && !k.bawaan
                                      ? () => _hapusKebijakan(k)
                                      : null),
                            ])),
                        AppTableCell(
                            width: 100,
                            align: TextAlign.center,
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 18),
                                  onPressed: Sesi.instance.bolehKelola
                                      ? () => _bukaFormKebijakan(kebijakan: k)
                                      : null),
                              if (!k.bawaan)
                                IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: AppColors.danger),
                                    onPressed: Sesi.instance.bolehKelola
                                        ? () => _hapusKebijakan(k)
                                        : null),
                            ])),
                      ],
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tombolAksi = [
      if (Sesi.instance.bolehDataSample)
        HeaderActionButton(
          icon: Icons.science_outlined,
          label: _memulaiDataSample
              ? 'Memulai...'
              : 'Sample 1K Supplier + 600 Jenis + 50K Produk',
          onPressed: _memulaiDataSample ? null : _mulaiDataSampleProduk,
        ),
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
      if (Sesi.instance.bolehKelola)
        HeaderActionButton(
          icon: Icons.local_shipping_outlined,
          label: 'Isi Pemasok',
          onPressed: _isiPemasokDariKulakan,
        ),
      HeaderActionButton(
        icon: Icons.refresh,
        label: 'Muat Ulang',
        onPressed: _muatSemua,
      ),
    ];
    return DefaultTabController(
        length: 4,
        initialIndex: _tabAktif,
        child: AppShell(
          menuAktif: MenuEBisnis.produk,
          judul: 'Manajemen Produk',
          subjudul: 'Kelola katalog produk toko Anda',
          aksiHeader: Wrap(
            alignment: WrapAlignment.end,
            runSpacing: 8,
            children: tombolAksi,
          ),
          actionsAppBar: [const IndikatorSinkronMaster(), ...tombolAksi],
          scrollable: false,
          floatingActionButton: _tabAktif == 1 || _tabAktif == 2
              ? null
              : FloatingActionButton.extended(
                  onPressed: () =>
                      _tabAktif == 0 ? _bukaFormProduk() : _bukaFormKebijakan(),
                  icon: const Icon(
                    Icons.add,
                    color: AppColors.darkTextPrimary,
                  ),
                  label: Text(
                    _tabAktif == 0 ? 'Tambah Produk' : 'Tambah Kebijakan',
                    style: TextStyle(color: AppColors.darkTextPrimary),
                  ),
                  backgroundColor: AppColors.primary,
                ),
          body: Column(children: [
            Material(
              color: Theme.of(context).cardColor,
              child: TabBar(
                onTap: (i) => setStateIfMounted(() => _tabAktif = i),
                tabs: const [
                  Tab(
                      text: 'Data Produk',
                      icon: Icon(Icons.inventory_2_outlined)),
                  Tab(
                      text: 'Mutasi Barang',
                      icon: Icon(Icons.swap_horiz_outlined)),
                  Tab(
                      text: 'Rekonsiliasi Stok',
                      icon: Icon(Icons.fact_check_outlined)),
                  Tab(
                      text: 'Kebijakan Retur',
                      icon: Icon(Icons.assignment_return_outlined)),
                ],
              ),
            ),
            Expanded(
                child: _tabAktif == 1
                    ? const ProdukMutasiBarangTab()
                    : _tabAktif == 2
                        ? const ProdukRekonsiliasiLedgerTab()
                        : _tabAktif == 3
                            ? (_memuat
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _daftarKebijakanRetur())
                            : (_memuat && _semuaProduk.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _pesanError != null && _semuaProduk.isEmpty
                                    ? Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.error_outline,
                                                  size: 48, color: Colors.red),
                                              const SizedBox(height: 12),
                                              Text(_pesanError!,
                                                  textAlign: TextAlign.center),
                                              AppDetailGalatOpsional(
                                                  detail:
                                                      detailUntuk(_pesanError)),
                                              const SizedBox(height: 16),
                                              ElevatedButton(
                                                  onPressed: _muatSemua,
                                                  child:
                                                      const Text('Coba Lagi')),
                                            ],
                                          ),
                                        ),
                                      )
                                    : RefreshIndicator(
                                        onRefresh: _muatSemua,
                                        child: ListView(
                                          padding: const EdgeInsets.fromLTRB(
                                              12, 12, 12, 90),
                                          children: [
                                            if (_statistik != null)
                                              _KartuStatistik(
                                                  statistik: _statistik!),
                                            const SizedBox(height: 12),
                                            AppSearchField(
                                              controller: _controllerCariProduk,
                                              debounce: const Duration(
                                                  milliseconds: 350),
                                              hintText:
                                                  'Cari produk (nama/kode/barcode)...',
                                              onChanged: (v) {
                                                setStateIfMounted(() {
                                                  _kataKunci = v;
                                                  _halaman = 0;
                                                });
                                                _muatSemua();
                                                // Stok per tanggal ikut
                                                // disaring kata kunci, jadi
                                                // harus ditarik ulang.
                                                _muatStokTanggal();
                                              },
                                            ),
                                            const SizedBox(height: 10),
                                            _bilahStokDanLaporan(),
                                            const SizedBox(height: 10),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: SegmentedButton<String>(
                                                segments: const [
                                                  ButtonSegment(
                                                      value: 'SEMUA',
                                                      label: Text('Semua')),
                                                  ButtonSegment(
                                                      value: 'JUAL',
                                                      label: Text('Produk')),
                                                  ButtonSegment(
                                                      value: 'BAHAN',
                                                      label: Text('Bahan')),
                                                  ButtonSegment(
                                                      value: 'EKSTRA',
                                                      label: Text('Ekstra')),
                                                ],
                                                selected: {_filterJenisItem},
                                                onSelectionChanged: (s) {
                                                  setStateIfMounted(() {
                                                    _filterJenisItem = s.first;
                                                    _halaman = 0;
                                                  });
                                                  _muatSemua();
                                                },
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            SizedBox(
                                              height: 40,
                                              child: ListView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            right: 8),
                                                    child: ChoiceChip(
                                                      label:
                                                          const Text('Semua'),
                                                      selected:
                                                          _kategoriTerpilih ==
                                                              null,
                                                      onSelected: (_) {
                                                        setStateIfMounted(() {
                                                          _kategoriTerpilih =
                                                              null;
                                                          _halaman = 0;
                                                        });
                                                        _muatSemua();
                                                      },
                                                    ),
                                                  ),
                                                  ..._kategori.map((k) =>
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(right: 8),
                                                        child: ChoiceChip(
                                                          label: Text(k.nama),
                                                          selected:
                                                              _kategoriTerpilih ==
                                                                  k.id,
                                                          onSelected: (_) {
                                                            setStateIfMounted(
                                                                () {
                                                              _kategoriTerpilih =
                                                                  k.id;
                                                              _halaman = 0;
                                                            });
                                                            _muatSemua();
                                                          },
                                                        ),
                                                      )),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            BannerPerubahanServer(
                                              key: ValueKey(
                                                  'perubahan:$_versiPerubahan'),
                                              baru: _idBaru.length,
                                              berubah: _idBerubah.length,
                                              dihapus: _jumlahHapus,
                                            ),
                                            if (_memuat) ...[
                                              const LinearProgressIndicator(
                                                  minHeight: 2),
                                              const SizedBox(height: 10),
                                            ],
                                            if (_produkTersaring.isEmpty)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                    vertical: 40),
                                                child: Center(
                                                    child: Text(
                                                        'Belum ada produk.')),
                                              )
                                            else
                                              LayoutBuilder(
                                                builder: (context, constraints) => constraints
                                                            .maxWidth >=
                                                        kAmbangLebarDesktop
                                                    ? _TabelProduk(
                                                        produkList:
                                                            _produkHalamanIni,
                                                        stokPerKode: _stokTanggal
                                                            ?.stokPerKode,
                                                        idBaru: _idBaru,
                                                        idBerubah: _idBerubah,
                                                        onTap: (p) => _bukaFormProduk(
                                                            produk: p),
                                                        onRiwayat:
                                                            _riwayatProduk)
                                                    : Column(
                                                        children: _produkHalamanIni
                                                            .map((p) => _BarisProduk(
                                                                produk: p,
                                                                stokTanggal:
                                                                    _stokTanggal?.stokPerKode[
                                                                        p.kode],
                                                                idBaru: _idBaru,
                                                                idBerubah:
                                                                    _idBerubah,
                                                                onTap: () =>
                                                                    _bukaFormProduk(produk: p),
                                                                onRiwayat: () => _riwayatProduk(p)))
                                                            .toList()),
                                              ),
                                            if (_totalProduk > _itemPerHalaman)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 12),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.chevron_left),
                                                      onPressed: _halaman > 0
                                                          ? () {
                                                              setStateIfMounted(
                                                                  () =>
                                                                      _halaman--);
                                                              _muatSemua();
                                                            }
                                                          : null,
                                                    ),
                                                    Text(
                                                        'Halaman ${_halaman + 1} / $_totalHalaman'),
                                                    IconButton(
                                                      icon: const Icon(
                                                          Icons.chevron_right),
                                                      onPressed: _halaman <
                                                              _totalHalaman - 1
                                                          ? () {
                                                              setStateIfMounted(
                                                                  () =>
                                                                      _halaman++);
                                                              _muatSemua();
                                                            }
                                                          : null,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ))),
          ]),
        ));
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
  final Set<String> idBaru;
  final Set<String> idBerubah;
  final VoidCallback onTap;
  final VoidCallback onRiwayat;

  /// Stok pada tanggal acuan bila pengguna memilih tanggal lampau; null
  /// berarti pakai stok berjalan milik [produk].
  final double? stokTanggal;
  const _BarisProduk(
      {required this.produk,
      required this.idBaru,
      required this.idBerubah,
      required this.onTap,
      required this.onRiwayat,
      this.stokTanggal});

  @override
  Widget build(BuildContext context) {
    // Tanggal acuan dipilih -> tampilkan stok pada tanggal itu. Ambang
    // "habis"/"rendah" mengikuti angka yang SEDANG ditampilkan supaya penanda
    // warnanya tidak bertentangan dgn angkanya sendiri.
    final stokTampil = stokTanggal ?? produk.stok.toDouble();
    final habis = stokTampil <= 0;
    final rendah = !habis && stokTampil <= 5;
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
          title: KilauBaris(
            kunci: '${produk.id}',
            idBaru: idBaru,
            idBerubah: idBerubah,
            child: Text(produk.nama,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          subtitle: Text(
              '${produk.kode} · ${produk.kategoriNama.isEmpty ? "Tanpa Kategori" : produk.kategoriNama}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_formatRupiah.format(produk.hargaJual),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  StatusPill(
                      label: habis ? 'Habis' : 'Stok ${_teksStok(stokTampil)}',
                      warna: habis
                          ? AppColors.danger
                          : (rendah ? AppColors.warning : AppColors.success)),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Riwayat data ini (AuditTrails)',
                icon: const Icon(Icons.history, size: 18),
                onPressed: onRiwayat,
              ),
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
  final Set<String> idBaru;
  final Set<String> idBerubah;
  final void Function(Produk) onTap;
  final void Function(Produk) onRiwayat;

  /// Stok pada tanggal acuan, dipetakan per kode produk. null = stok berjalan.
  final Map<String, double>? stokPerKode;

  const _TabelProduk(
      {required this.produkList,
      required this.idBaru,
      required this.idBerubah,
      required this.onTap,
      required this.onRiwayat,
      this.stokPerKode});

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
                // Kolom tombol "Riwayat Data" per baris (ikon jam).
                const SizedBox(width: 36),
              ],
            ),
          ),
          for (final p in produkList)
            _BarisTabelProduk(
                produk: p,
                stokTanggal: stokPerKode?[p.kode],
                idBaru: idBaru,
                idBerubah: idBerubah,
                onTap: () => onTap(p),
                onRiwayat: () => onRiwayat(p)),
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
  final Set<String> idBaru;
  final Set<String> idBerubah;
  final VoidCallback onTap;
  final VoidCallback onRiwayat;

  /// Stok pada tanggal acuan bila pengguna memilih tanggal lampau; null
  /// berarti pakai stok berjalan milik [produk].
  final double? stokTanggal;
  const _BarisTabelProduk(
      {required this.produk,
      required this.idBaru,
      required this.idBerubah,
      required this.onTap,
      required this.onRiwayat,
      this.stokTanggal});

  @override
  Widget build(BuildContext context) {
    // Tanggal acuan dipilih -> tampilkan stok pada tanggal itu. Ambang
    // "habis"/"rendah" mengikuti angka yang SEDANG ditampilkan supaya penanda
    // warnanya tidak bertentangan dgn angkanya sendiri.
    final stokTampil = stokTanggal ?? produk.stok.toDouble();
    final habis = stokTampil <= 0;
    final rendah = !habis && stokTampil <= 5;
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
              child: KilauBaris(
                kunci: '${produk.id}',
                idBaru: idBaru,
                idBerubah: idBerubah,
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
                    label: _teksStok(stokTampil),
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
            SizedBox(
              width: 36,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tooltip: 'Riwayat data ini (AuditTrails)',
                icon: const Icon(Icons.history, size: 18),
                onPressed: onRiwayat,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormKebijakanRetur extends StatefulWidget {
  final KebijakanRetur? kebijakan;
  const _FormKebijakanRetur({this.kebijakan});
  @override
  State<_FormKebijakanRetur> createState() => _FormKebijakanReturState();
}

class _FormKebijakanReturState extends State<_FormKebijakanRetur>
    with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nama;
  late final TextEditingController _keterangan;
  bool _aktif = true;
  bool _menyimpan = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nama = TextEditingController(text: widget.kebijakan?.nama ?? '');
    _keterangan =
        TextEditingController(text: widget.kebijakan?.keterangan ?? '');
    _aktif = widget.kebijakan?.aktif ?? true;
  }

  @override
  void dispose() {
    _nama.dispose();
    _keterangan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _menyimpan = true;
      _error = null;
    });
    try {
      final ubah = widget.kebijakan != null;
      final body = {
        if (ubah) 'id': widget.kebijakan!.id,
        'nama': _nama.text.trim(),
        'keterangan': _keterangan.text.trim(),
        'aktif': _aktif,
      };
      await prosesSimpanMaster(
        context,
        aksi: 'kebijakan_retur_simpan',
        body: body,
        kunci: ubah
            ? 'kebijakan_retur:${widget.kebijakan!.id}'
            : 'kebijakan_retur:baru:${DateTime.now().microsecondsSinceEpoch}',
        // Optimistis HANYA utk edit -- baris create offline belum punya id,
        // sedangkan KebijakanRetur.fromJson mewajibkannya (baris tanpa id di
        // snapshot akan membuat parsing daftar gagal saat offline).
        cacheKey: ubah ? 'master:kebijakan_retur' : null,
        rowLokal: ubah ? body : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = terapkanGalat(e));
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: .65,
          maxChildSize: .9,
          expand: false,
          builder: (context, controller) => Form(
            key: _formKey,
            child: AppFormSheet(
              scrollController: controller,
              title: widget.kebijakan == null
                  ? 'Tambah Kebijakan Retur'
                  : 'Ubah Kebijakan Retur',
              subtitle:
                  'Tuliskan nama dan penjelasan aturan retur yang mudah dipahami petugas.',
              icon: Icons.assignment_return_outlined,
              errorText: _error,
              errorDetail: detailUntuk(_error),
              actions: [
                OutlinedButton.icon(
                  onPressed: _menyimpan ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Batal'),
                ),
                ElevatedButton.icon(
                  onPressed: _menyimpan ? null : _simpan,
                  icon: _menyimpan
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan'),
                ),
              ],
              children: [
                AppFormSection(judul: 'Kebijakan', children: [
                  AppFormTextField(
                      label: 'Nama *',
                      controller: _nama,
                      enabled: widget.kebijakan?.bawaan != true,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Nama wajib diisi'
                          : null),
                  AppFormTextField(
                      label: 'Keterangan',
                      controller: _keterangan,
                      maxLines: 5),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Aktif'),
                    subtitle: Text(widget.kebijakan?.bawaan == true
                        ? 'Kebijakan baku selalu aktif.'
                        : 'Kebijakan aktif dapat dipilih pada produk.'),
                    value: widget.kebijakan?.bawaan == true ? true : _aktif,
                    onChanged: widget.kebijakan?.bawaan == true
                        ? null
                        : (v) => setState(() => _aktif = v),
                  ),
                ]),
              ],
            ),
          ),
        ),
      );
}

/// Form Tambah/Ubah -- bottom sheet, dipakai utk kedua mode (produk == null berarti Tambah).
class _FormProduk extends StatefulWidget {
  final Produk? produk;
  final List<Kategori> kategori;
  final List<KebijakanRetur> kebijakanRetur;
  final List<Produk> semuaProduk;
  const _FormProduk(
      {required this.produk,
      required this.kategori,
      required this.kebijakanRetur,
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

class _FormProdukState extends State<_FormProduk> with JejakGalat {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kode;
  late final TextEditingController _nama;
  late final TextEditingController _barcode;
  late final TextEditingController _hargaBeli;
  late final TextEditingController _hargaJual;
  late final TextEditingController _stok;
  late final TextEditingController _keterangan;

  /// Pemasok utama & satuan (UOM) -- lihat Produk.pemasokNama/satuanNama.
  late final TextEditingController _pemasok;
  late final TextEditingController _satuan;
  int? _kategoriId;
  int? _kebijakanReturId;
  bool _izinkanJualMinusStok = false;
  // Grup harga terpusat: -1 = tidak diubah (payload TIDAK dikirim -- data produk
  // dari server belum membawa grup, jadi simpan biasa tidak boleh melepas grup
  // tanpa sengaja), 0 = lepaskan dari grup, >0 = id grup pilihan.
  int _grupProdukPilihan = -1;
  Future<Map<String, dynamic>>? _grupProdukFuture;
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
    _pemasok = TextEditingController(text: p?.pemasokNama ?? '');
    _satuan = TextEditingController(text: p?.satuanNama ?? '');
    _kategoriId = p?.kategoriId;
    _kebijakanReturId = p?.kebijakanReturId ??
        (widget.kebijakanRetur.where((e) => e.bawaan).isNotEmpty
            ? widget.kebijakanRetur.firstWhere((e) => e.bawaan).id
            : (widget.kebijakanRetur.isEmpty
                ? null
                : widget.kebijakanRetur.first.id));
    _izinkanJualMinusStok = p?.izinkanJualMinusStok ?? false;
    _grupProdukPilihan = -1;
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
    _pemasok.dispose();
    _satuan.dispose();
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
              .where((p) => p.id != widget.produk?.id && p.jenisItem == 'BAHAN')
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
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif'
  };

  Future<void> _pilihFoto(ImageSource sumber) async {
    if (_foto.length >= 10) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maksimal 10 foto per produk.')));
      }
      return;
    }
    final XFile? berkas =
        await ImagePicker().pickImage(source: sumber, imageQuality: 100);
    if (berkas == null) return;
    final namaFile = berkas.name;
    final ekstensi =
        namaFile.contains('.') ? namaFile.split('.').last.toLowerCase() : '';
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ukuran berkas maksimal 10 MB.')));
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
      // Lokal dulu, baru dikirim -- sama seperti master lain.
      await prosesSimpanMaster(context,
          aksi: 'produk_foto_hapus',
          body: {'id': baris.id},
          kunci: 'produk_foto:${baris.id}');
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
      final ubah = widget.produk != null;
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'produk_simpan',
        body: {
          if (ubah) 'id': widget.produk!.id,
          'kode': _kode.text.trim(),
          'nama': _nama.text.trim(),
          'barcode': _barcode.text.trim(),
          'harga_beli':
              _bahanBaku.isNotEmpty ? _totalHpp : _angka(_hargaBeli.text),
          'harga_jual': _angka(_hargaJual.text),
          'stok': _angka(_stok.text),
          'keterangan': _keterangan.text.trim(),
          'pemasok_nama': _pemasok.text.trim(),
          'satuan_nama': _satuan.text.trim(),
          'kategori_id': _kategoriId,
          'kebijakan_retur_id': _kebijakanReturId,
          'izinkan_jual_minus_stok': _izinkanJualMinusStok,
          if (_grupProdukPilihan != -1)
            'grup_produk_id':
                _grupProdukPilihan == 0 ? null : _grupProdukPilihan,
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
        },
        kunci: ubah
            ? 'produk:${widget.produk!.id}'
            : 'produk:baru:${DateTime.now().microsecondsSinceEpoch}',
        // Optimistis HANYA utk edit -- baris create offline belum punya id,
        // sedangkan Produk.fromJson mewajibkannya (baris tanpa id di snapshot
        // akan membuat parsing daftar gagal saat offline). rowLokal memakai
        // nama field camelCase respons `katalog` (bukan snake_case payload)
        // supaya perubahan langsung terlihat di snapshot daftar.
        cacheKey: ubah ? 'master:produk_list' : null,
        rowLokal: ubah
            ? {
                'id': widget.produk!.id,
                'kode': _kode.text.trim(),
                'nama': _nama.text.trim(),
                'barcode': _barcode.text.trim(),
                'hargaBeli':
                    _bahanBaku.isNotEmpty ? _totalHpp : _angka(_hargaBeli.text),
                'hargaJual': _angka(_hargaJual.text),
                'stok': _angka(_stok.text),
                'keterangan': _keterangan.text.trim(),
                'kategoriId': _kategoriId,
                'kebijakanReturId': _kebijakanReturId,
                'izinkanJualMinusStok': _izinkanJualMinusStok,
                'aktif': _aktif,
                'jenisItem': _jenisItem,
              }
            : null,
      );
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
      setStateIfMounted(() => _pesanError = terapkanGalat(e));
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
            errorDetail: detailUntuk(_pesanError),
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
                  // Pemasok & Satuan: sengaja isian bebas, bukan dropdown.
                  // Master-nya dibuat otomatis di server bila nama belum ada,
                  // jadi tidak perlu membuka layar master lebih dulu. Kedua
                  // kolom ini yang mengisi "Nama Pemasok Utama" dan "Satuan"
                  // pada ekspor Daftar Barang dan Jasa.
                  Row(
                    children: [
                      Expanded(
                        child: AppFormTextField(
                          label: 'Nama Pemasok Utama',
                          controller: _pemasok,
                          hintText: 'mis. AB Grosir',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppFormTextField(
                          label: 'Satuan',
                          controller: _satuan,
                          hintText: 'mis. Pcs',
                        ),
                      ),
                    ],
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
                  DropdownButtonFormField<int?>(
                    value: _kebijakanReturId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Kebijakan Retur',
                    ),
                    items: widget.kebijakanRetur
                        .map((k) => DropdownMenuItem<int?>(
                            value: k.id, child: Text(k.nama)))
                        .toList(),
                    onChanged: (v) =>
                        setStateIfMounted(() => _kebijakanReturId = v),
                    validator: (v) => v == null
                        ? 'Pilih kebijakan retur; nilai baku adalah Tanpa Kebijakan Retur'
                        : null,
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
                      ButtonSegment(value: 'BAHAN', label: Text('Bahan Baku')),
                      ButtonSegment(value: 'EKSTRA', label: Text('Ekstra')),
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
                  // Kebijakan ubah harga per toko: bila akun ini tidak diberi akses,
                  // kolom harga dikunci dan alasannya ditampilkan -- bukan dibiarkan
                  // diketik lalu ditolak server setelah tombol Simpan ditekan.
                  if (!Sesi.instance.bolehUbahHarga)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.45)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock_outline,
                            size: 18, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(Sesi.instance.pesanTidakBolehUbahHarga,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Sesi.instance.bolehUbahHarga
                            ? AppFormTextField(
                                label: 'Harga Beli',
                                controller: _hargaBeli,
                                enabled: _bahanBaku.isEmpty,
                                keyboardType: TextInputType.number,
                                helperText: _bahanBaku.isNotEmpty
                                    ? 'Otomatis dari Bahan Baku (${_formatRupiah.format(_totalHpp)})'
                                    : null,
                              )
                            : AppHargaTerkunci(
                                label: 'Harga Beli',
                                nilai: _formatRupiah
                                    .format(_angka(_hargaBeli.text)),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Sesi.instance.bolehUbahHarga
                            ? AppFormTextField(
                                label: 'Harga Jual *',
                                controller: _hargaJual,
                                keyboardType: TextInputType.number,
                                validator: (v) =>
                                    _angka(v ?? '') <= 0 ? 'Wajib > 0' : null,
                              )
                            : AppHargaTerkunci(
                                label: 'Harga Jual',
                                nilai: _formatRupiah
                                    .format(_angka(_hargaJual.text)),
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
                                        decoration:
                                            AppFormStyle.fieldDecoration(
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
                                        decoration:
                                            AppFormStyle.fieldDecoration(
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))),
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
                                                      color: AppColors.borderOf(
                                                          context),
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
                                                          color: Colors.white),
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
                                                decoration: const BoxDecoration(
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
                  if (Sesi.instance.bolehMenuVarianBaru('grup_produk'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _grupProdukFuture ??=
                            ApiClient.instance.aksi('grup_produk_list', {}),
                        builder: (c, snap) {
                          final data = ((snap.data?['data'] as List?) ?? [])
                              .map((e) => Map<String, dynamic>.from(e as Map))
                              .toList();
                          return DropdownButtonFormField<int>(
                            value: _grupProdukPilihan,
                            decoration: const InputDecoration(
                                labelText: 'Grup Produk (Harga Terpusat)',
                                helperText:
                                    'Bila dipilih, HPP/harga jual produk ini ditimpa setiap grup disimpan'),
                            items: [
                              const DropdownMenuItem<int>(
                                  value: -1, child: Text('(Tidak diubah)')),
                              const DropdownMenuItem<int>(
                                  value: 0,
                                  child: Text('Tanpa Grup (lepaskan)')),
                              ...data.map((g) => DropdownMenuItem<int>(
                                  value: (g['id'] as num).toInt(),
                                  child: Text('${g['nama']}'))),
                            ],
                            onChanged: (v) => setStateIfMounted(
                                () => _grupProdukPilihan = v ?? -1),
                          );
                        },
                      ),
                    ),
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
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'))
      ],
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
                        AppTableCell(
                          flex: 3,
                          child: SelTeksDenganSinkron(
                              kunci: 'produk:${p.id}', teks: p.nama),
                        ),
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
    );
  }
}
