import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:core_db/core_db.dart';
import 'package:core_hw/core_hw.dart';
import '../api_client.dart';
import '../models.dart';
import '../services/dynamic_report.dart';
import 'harga_grosir_editor.dart';
import 'produk_stok_tanggal.dart';
import '../services/kompresi_gambar.dart';
import '../services/master_offline.dart';
import '../services/simpan_gambar_local_first.dart';
import '../services/sinkron_stok_opname.dart';
import '../services/url_media.dart';
import '../services/uom_konversi.dart';
import '../widgets/indikator_baris_sinkron.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import '../widgets/kilau_perubahan.dart';
import '../widgets/penanda_data_tersimpan.dart';
import '../widgets/proses_simpan_master.dart';
import '../widgets/progress_sinkron_awal.dart';
import '../widgets/riwayat_data_dialog.dart';
import 'impor_excel_produk_screen.dart';
import 'price_tag_screen.dart';
import 'foto_produk_camera_screen.dart';
import 'produk_mutasi_barang_tab.dart';
import 'produk_rekonsiliasi_ledger_tab.dart';
import 'produk_riwayat_perubahan_tab.dart';
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
/// Hak CRUD produk dari peladen (balasan `katalog`), dipakai bersama oleh layar
/// dan formulirnya -- keduanya kelas terpisah di berkas ini.
///
/// Peta kosong = belum dimuat, dan selama itu tombol TIDAK dipadamkan: peladen
/// tetap gerbang sebenarnya, dan memadamkan tombol hanya karena haknya belum
/// tiba justru mengunci pengguna yang sebenarnya berhak.
Map<String, bool> _hakProduk = {};

bool _bolehProduk(String aksi) =>
    _hakProduk.isEmpty || _hakProduk[aksi] != false;

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
  bool _statistikDariCache = false;
  bool _memulaiDataSample = false;
  bool _menyinkronProduk = false;
  // Diff dari emisi server daftarCacheDulu -- menggerakkan kilau baris +
  // banner "pembaruan dari server" (termasuk perubahan kasir lain).
  Set<String> _idBaru = {};
  Set<String> _idBerubah = {};
  int _jumlahHapus = 0;
  int _versiPerubahan = 0;
  int _generasiMuat = 0;

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
    MasterOffline.revisiBaris.addListener(_saatCacheBerubah);
    SinkronStokOpname.mulai();
    _muatSemua();
  }

  @override
  void dispose() {
    MasterOffline.revisiBaris.removeListener(_saatCacheBerubah);
    _controllerCariProduk.dispose();
    super.dispose();
  }

  void _saatCacheBerubah() {
    if (mounted) unawaited(_muatHalamanLokal());
  }

  Future<void> _muatHalamanLokal() async {
    final baris = await CoreDb.instance.produkCacheMaster(
      keyword: _kataKunci.trim(),
      kategoriId: _kategoriTerpilih,
      jenisItem: _filterJenisItem,
      limit: _itemPerHalaman,
      offset: _halaman * _itemPerHalaman,
    );
    final total = await CoreDb.instance.jumlahProdukCacheMaster(
      keyword: _kataKunci.trim(),
      kategoriId: _kategoriTerpilih,
      jenisItem: _filterJenisItem,
    );
    if (!mounted) return;
    setStateIfMounted(() {
      _semuaProduk = baris
          .map(Produk.cacheRowKeJson)
          .map(Produk.fromJson)
          .toList(growable: false);
      _totalProduk = total;
    });
  }

  Future<void> _muatSemua() async {
    final generasi = ++_generasiMuat;
    final halaman = _halaman;
    final kataKunci = _kataKunci.trim();
    final kategoriId = _kategoriTerpilih;
    final jenisItem = _filterJenisItem;
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });
    var lokalTersedia = false;
    var idProdukDilindungi = <int>{};
    try {
      // Jangan mengurai `master:produk_list` di thread UI: setelah sinkron
      // penuh snapshot itu dapat berisi 50 ribu baris. SQLite mengerjakan
      // filter, hitung, dan pagination; layar hanya membentuk 15 model.
      final hasilLokal = await Future.wait<Object>([
        CoreDb.instance.produkCacheMaster(
          keyword: kataKunci,
          kategoriId: kategoriId,
          jenisItem: jenisItem,
          limit: _itemPerHalaman,
          offset: halaman * _itemPerHalaman,
        ),
        CoreDb.instance.jumlahProdukCacheMaster(
          keyword: kataKunci,
          kategoriId: kategoriId,
          jenisItem: jenisItem,
        ),
        CoreDb.instance.outboxMasterPending(),
        CoreDb.instance.outboxMasterGagal(batas: 500),
      ]);
      if (!mounted || generasi != _generasiMuat) return;
      final barisLokal = hasilLokal[0] as List<Map<String, Object?>>;
      final produkLokal = barisLokal
          .map(Produk.cacheRowKeJson)
          .map(Produk.fromJson)
          .toList(growable: false);
      final totalLokal = hasilLokal[1] as int;
      idProdukDilindungi = <int>{
        for (final baris in <Map<String, Object?>>[
          ...(hasilLokal[2] as List<Map<String, Object?>>),
          ...(hasilLokal[3] as List<Map<String, Object?>>),
        ])
          if ('${baris['kunci'] ?? ''}'.startsWith('produk:'))
            if (int.tryParse('${baris['kunci']}'.substring('produk:'.length)) !=
                null)
              int.parse('${baris['kunci']}'.substring('produk:'.length)),
      };
      lokalTersedia = produkLokal.isNotEmpty || totalLokal > 0;
      if (lokalTersedia) {
        setStateIfMounted(() {
          _semuaProduk = produkLokal;
          _totalProduk = totalLokal;
          _memuat = false;
        });
      }

      // Segarkan SATU halaman dari server. Kegagalan server tidak membuang
      // daftar lokal yang sudah tampil dan tidak mengunci seluruh halaman.
      final katalog = await ApiClient.instance.aksi('katalog', {
        'page': halaman + 1,
        'page_size': _itemPerHalaman,
        if (kataKunci.isNotEmpty) 'keyword': kataKunci,
        if (kategoriId != null) 'kategori_id': kategoriId,
        if (jenisItem != 'SEMUA') 'jenisItem': jenisItem,
        // LINGKUP TOKO wajib eksplisit untuk admin lintas toko.
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
      });
      if (!mounted || generasi != _generasiMuat) return;
      final hakBaru = katalog['hak'];
      if (hakBaru is Map) {
        _hakProduk = hakBaru.map((k, v) => MapEntry('$k', v == true));
      }
      final dataServer = ((katalog['produk'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['id'] is num)
          .toList(growable: false);
      // Respons server tidak boleh menimpa edit local-first yang masih
      // PENDING/GAGAL. Baris tersebut tetap memakai versi SQLite sampai
      // outbox membuktikan kiriman berhasil.
      await CoreDb.instance.upsertProdukCache(dataServer
          .where((e) => !idProdukDilindungi.contains((e['id'] as num).toInt()))
          .map(Produk.baseKeCacheRow)
          .toList());
      if (!mounted || generasi != _generasiMuat) return;
      final idLokal = {for (final p in _semuaProduk) p.id: p};
      final produkServer = dataServer.map(Produk.fromJson).map((p) {
        return idProdukDilindungi.contains(p.id) ? (idLokal[p.id] ?? p) : p;
      }).toList();
      final idBaru = <String>{};
      final idBerubah = <String>{};
      for (final p in produkServer) {
        final lama = idLokal[p.id];
        if (lama == null) {
          idBaru.add('${p.id}');
        } else if (lama.nama != p.nama ||
            lama.kode != p.kode ||
            lama.barcode != p.barcode ||
            lama.hargaJual != p.hargaJual ||
            lama.stok != p.stok ||
            lama.aktif != p.aktif) {
          idBerubah.add('${p.id}');
        }
      }
      setStateIfMounted(() {
        _semuaProduk = produkServer;
        _totalProduk = (katalog['total'] as num?)?.toInt() ??
            (produkServer.length >= _itemPerHalaman
                ? (halaman + 1) * _itemPerHalaman + 1
                : halaman * _itemPerHalaman + produkServer.length);
        _idBaru = idBaru;
        _idBerubah = idBerubah;
        _jumlahHapus = 0;
        if (idBaru.isNotEmpty || idBerubah.isNotEmpty) _versiPerubahan++;
      });

      final hasilKategori = await MasterOffline.daftarDenganCache(
          'jenis_produk_list',
          {'page': 1, 'page_size': 100},
          'master:jenis_produk');
      if (!mounted || generasi != _generasiMuat) return;
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
        statistik = await MasterOffline.objekDenganCache(
            'produk_statistik', const {}, 'produk_statistik');
      } catch (_) {
        // dasbor KPI gagal muat bukan blocker -- daftar produk tetap tampil normal.
      }

      setStateIfMounted(() {
        _kategori = kategori;
        _statistik = statistik;
        _statistikDariCache = statistik?['offline'] == true;
      });
    } catch (e) {
      if (!mounted || generasi != _generasiMuat) return;
      final pesan = terapkanGalat(e);
      setStateIfMounted(() {
        _pesanError = lokalTersedia
            ? 'Data lokal tetap dapat digunakan. Penyegaran dari server belum '
                'berhasil: $pesan Periksa koneksi atau Log Error, lalu tekan '
                'Muat Ulang; tidak perlu menutup aplikasi.'
            : pesan;
      });
    } finally {
      if (mounted && generasi == _generasiMuat) {
        setStateIfMounted(() => _memuat = false);
      }
    }
  }

  /// Unduh seluruh katalog sesuai lingkup toko aktif, lalu ganti cache SQLite
  /// secara atomik. Tidak ada cache parsial: bila satu halaman gagal, cache
  /// lama tetap utuh dan masih dapat dipakai kasir saat offline.
  Future<int> _sinkronSeluruhProduk(
      void Function(int tersinkron, int? total) lapor) async {
    // Dorong perubahan lokal lebih dahulu. Yang masih gagal/tertunda tetap
    // dilindungi oleh simpanDaftarLengkapDariServer, bukan ditimpa server.
    await MasterOffline.flush();

    const ukuranHalaman = 100; // batas maksimum prosesKatalog di backend.
    final perId = <int, Map<String, dynamic>>{};
    var halaman = 1;
    int? total;
    while (true) {
      final hasil = await ApiClient.instance.aksi('katalog', {
        'page': halaman,
        'page_size': ukuranHalaman,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
      });
      final data = ((hasil['produk'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final totalMentah = hasil['total'];
      if (totalMentah is num) total ??= totalMentah.toInt();

      final sebelum = perId.length;
      for (final baris in data) {
        final id = (baris['id'] as num?)?.toInt();
        if (id == null) {
          throw StateError(
              'Server mengirim produk tanpa ID pada halaman $halaman.');
        }
        perId[id] = baris;
      }
      lapor(perId.length, total);

      final selesai = data.length < ukuranHalaman ||
          (total != null && perId.length >= total);
      if (selesai) break;
      if (perId.length == sebelum) {
        throw StateError(
            'Paging katalog tidak bergerak pada halaman $halaman; cache lama dipertahankan.');
      }
      halaman++;
      if (halaman > 1000) {
        throw StateError(
            'Sinkron katalog dihentikan karena jumlah halaman tidak wajar.');
      }
    }

    if (total != null && perId.length != total) {
      throw StateError(
          'Katalog belum lengkap (${perId.length}/$total); cache lama dipertahankan.');
    }
    final semua = perId.values.toList(growable: false);
    await CoreDb.instance.replaceProdukCache(
        semua.map(Produk.baseKeCacheRow).toList(growable: false));
    await MasterOffline.simpanDaftarLengkapDariServer(
        'master:produk_list', semua);
    return semua.length;
  }

  Future<void> _sinkronProdukKeLokal() async {
    if (_menyinkronProduk) return;
    setStateIfMounted(() => _menyinkronProduk = true);
    try {
      final jumlah = await jalankanDenganProgressSinkron<int>(
        context,
        judul: 'Sinkron produk server ke lokal',
        satuan: 'produk',
        tugas: _sinkronSeluruhProduk,
      );
      if (!mounted || jumlah == null) return;
      setStateIfMounted(() => _halaman = 0);
      await _muatSemua();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '$jumlah produk tersimpan lengkap di perangkat dan siap dipakai offline.')));
    } finally {
      if (mounted) setStateIfMounted(() => _menyinkronProduk = false);
    }
  }

  Future<void> _bukaDetailStatistik(String tipe, String judul) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _DialogDetailStatistikProduk(
        tipe: tipe,
        judul: judul,
        tokoId: Sesi.instance.idTokoTerpilih,
      ),
    );
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
    final pilihanUom = <Map<String, dynamic>>[];
    try {
      final hasil = await ApiClient.instance.aksi('uom_list', {
        'keyword': '',
        'page': 1,
        'page_size': 500,
        'termasuk_nonaktif': true,
      });
      for (final raw in (hasil['data'] as List?) ?? const []) {
        pilihanUom.add(Map<String, dynamic>.from(raw as Map));
      }
    } catch (_) {
      // Form tetap dibuka. Validator UOM akan memberi petunjuk yang dapat
      // dilakukan user bila daftar master belum berhasil dimuat.
    }
    if (!mounted) return;
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormProduk(
          produk: produk,
          kategori: _kategori,
          kebijakanRetur: _kebijakanRetur.where((e) => e.aktif).toList(),
          pilihanUom: pilihanUom,
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
          // ONLINE-ONLY: pratinjau & komit adalah sepasang. Yang disetujui pengguna
          // adalah hasil hitungan server barusan; menunda komitnya membuat pasangan
          // itu bisa tidak cocok lagi.
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
        icon: Icons.sync_alt,
        label: _menyinkronProduk ? 'Menyinkron...' : 'Sinkron Produk',
        onPressed: _menyinkronProduk ? null : _sinkronProdukKeLokal,
        loading: _menyinkronProduk
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : null,
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
        length: 5,
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
          floatingActionButton: _tabAktif == 1 ||
                  _tabAktif == 2 ||
                  _tabAktif == 4 ||
                  (_tabAktif == 0 && !_bolehProduk('create'))
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
                  Tab(
                      text: 'Riwayat Perubahan',
                      icon: Icon(Icons.manage_history_outlined)),
                ],
              ),
            ),
            Expanded(
                child: _tabAktif == 1
                    ? const ProdukMutasiBarangTab()
                    : _tabAktif == 2
                        ? const ProdukRekonsiliasiLedgerTab()
                        : _tabAktif == 4
                            ? const ProdukRiwayatPerubahanTab()
                            : _tabAktif == 3
                                ? (_memuat
                                    ? const Center(
                                        child: CircularProgressIndicator())
                                    : _daftarKebijakanRetur())
                                : (_memuat && _semuaProduk.isEmpty
                                    ? const Center(
                                        child: CircularProgressIndicator())
                                    : _pesanError != null &&
                                            _semuaProduk.isEmpty
                                        ? Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(24),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                      Icons.error_outline,
                                                      size: 48,
                                                      color: Colors.red),
                                                  const SizedBox(height: 12),
                                                  Text(_pesanError!,
                                                      textAlign:
                                                          TextAlign.center),
                                                  AppDetailGalatOpsional(
                                                      detail: detailUntuk(
                                                          _pesanError)),
                                                  const SizedBox(height: 16),
                                                  ElevatedButton(
                                                      onPressed: _muatSemua,
                                                      child: const Text(
                                                          'Coba Lagi')),
                                                ],
                                              ),
                                            ),
                                          )
                                        : RefreshIndicator(
                                            onRefresh: _muatSemua,
                                            child: ListView(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 12, 12, 90),
                                              children: [
                                                PenandaDataTersimpan(
                                                    tampil:
                                                        _statistikDariCache),
                                                if (_pesanError != null) ...[
                                                  Card(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .errorContainer,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              12),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .cloud_off_outlined,
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onErrorContainer,
                                                          ),
                                                          const SizedBox(
                                                              width: 10),
                                                          Expanded(
                                                            child: Text(
                                                              _pesanError!,
                                                              style: TextStyle(
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onErrorContainer,
                                                              ),
                                                            ),
                                                          ),
                                                          TextButton.icon(
                                                            onPressed: _memuat
                                                                ? null
                                                                : _muatSemua,
                                                            icon: const Icon(Icons
                                                                .refresh_outlined),
                                                            label: const Text(
                                                                'Coba Lagi'),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                ],
                                                if (_statistik != null)
                                                  _KartuStatistik(
                                                    statistik: _statistik!,
                                                    onTap: _bukaDetailStatistik,
                                                  ),
                                                const SizedBox(height: 12),
                                                AppSearchField(
                                                  controller:
                                                      _controllerCariProduk,
                                                  scanProduk: true,
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
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child:
                                                      SegmentedButton<String>(
                                                    segments: const [
                                                      ButtonSegment(
                                                          value: 'SEMUA',
                                                          label: Text('Semua')),
                                                      ButtonSegment(
                                                          value: 'JUAL',
                                                          label:
                                                              Text('Produk')),
                                                      ButtonSegment(
                                                          value: 'BAHAN',
                                                          label: Text('Bahan')),
                                                      ButtonSegment(
                                                          value: 'EKSTRA',
                                                          label:
                                                              Text('Ekstra')),
                                                    ],
                                                    selected: {
                                                      _filterJenisItem
                                                    },
                                                    onSelectionChanged: (s) {
                                                      setStateIfMounted(() {
                                                        _filterJenisItem =
                                                            s.first;
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
                                                            const EdgeInsets
                                                                .only(right: 8),
                                                        child: ChoiceChip(
                                                          label: const Text(
                                                              'Semua'),
                                                          selected:
                                                              _kategoriTerpilih ==
                                                                  null,
                                                          onSelected: (_) {
                                                            setStateIfMounted(
                                                                () {
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
                                                                    .only(
                                                                    right: 8),
                                                            child: ChoiceChip(
                                                              label:
                                                                  Text(k.nama),
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
                                                    padding:
                                                        EdgeInsets.symmetric(
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
                                                            idBerubah:
                                                                _idBerubah,
                                                            onTap: (p) =>
                                                                _bukaFormProduk(
                                                                    produk: p),
                                                            onRiwayat:
                                                                _riwayatProduk)
                                                        : Column(
                                                            children: _produkHalamanIni
                                                                .map((p) => _BarisProduk(
                                                                    produk: p,
                                                                    stokTanggal: _stokTanggal?.stokPerKode[
                                                                        p.kode],
                                                                    idBaru:
                                                                        _idBaru,
                                                                    idBerubah:
                                                                        _idBerubah,
                                                                    onTap: () => _bukaFormProduk(produk: p),
                                                                    onRiwayat: () => _riwayatProduk(p)))
                                                                .toList()),
                                                  ),
                                                if (_totalProduk >
                                                    _itemPerHalaman)
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        vertical: 12),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(Icons
                                                              .chevron_left),
                                                          onPressed:
                                                              _halaman > 0
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
                                                          icon: const Icon(Icons
                                                              .chevron_right),
                                                          onPressed: _halaman <
                                                                  _totalHalaman -
                                                                      1
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
  final void Function(String tipe, String judul) onTap;
  const _KartuStatistik({
    required this.statistik,
    required this.onTap,
  });

  static const double _tinggiKartu = 96;

  @override
  Widget build(BuildContext context) {
    final item = <(IconData, String, String, Color, String)>[
      (
        Icons.inventory_2_outlined,
        'Total',
        '${statistik['totalProduk'] ?? 0}',
        AppColors.primary,
        'total',
      ),
      (
        Icons.check_circle_outline,
        'Aktif',
        '${statistik['totalAktif'] ?? 0}',
        AppColors.success,
        'aktif',
      ),
      (
        Icons.pause_circle_outline,
        'Nonaktif',
        '${statistik['totalNonaktif'] ?? 0}',
        AppColors.textSecondaryOf(context),
        'nonaktif',
      ),
      (
        Icons.remove_shopping_cart_outlined,
        'Stok Habis',
        '${statistik['stokHabis'] ?? 0}',
        AppColors.danger,
        'stokHabis',
      ),
      (
        Icons.trending_down_outlined,
        'Stok Minus',
        '${statistik['stokMinus'] ?? 0}',
        const Color(0xFFB91C1C),
        'stokMinus',
      ),
      (
        Icons.warning_amber_outlined,
        'Stok Rendah',
        '${statistik['stokRendah'] ?? 0}',
        AppColors.warning,
        'stokRendah',
      ),
      (
        Icons.payments_outlined,
        'Nilai Stok',
        _formatRupiah.format((statistik['totalNilaiStok'] as num?) ?? 0),
        AppColors.teal,
        'nilaiStok',
      ),
    ];
    return SizedBox(
      height: _tinggiKartu,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: item.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (icon, label, nilai, warna, tipe) = item[i];
          return SizedBox(
              width: 190,
              height: _tinggiKartu,
              child: AppKpiCard(
                icon: icon,
                warna: warna,
                nilai: nilai,
                label: label,
                tooltip: 'Lihat daftar produk $label',
                onTap: () => onTap(tipe, label),
              ));
        },
      ),
    );
  }
}

class _DialogDetailStatistikProduk extends StatefulWidget {
  final String tipe;
  final String judul;
  final int? tokoId;

  const _DialogDetailStatistikProduk({
    required this.tipe,
    required this.judul,
    required this.tokoId,
  });

  @override
  State<_DialogDetailStatistikProduk> createState() =>
      _DialogDetailStatistikProdukState();
}

class _DialogDetailStatistikProdukState
    extends State<_DialogDetailStatistikProduk> {
  bool _memuat = true;
  bool _mengekspor = false;
  String? _error;
  List<Map<String, dynamic>> _produk = const [];
  int _barisPerHalaman = 10;
  int _halaman = 0;

  int get _jumlahHalaman => _produk.isEmpty
      ? 1
      : ((_produk.length + _barisPerHalaman - 1) ~/ _barisPerHalaman);

  void _keHalaman(int halaman) {
    setState(() => _halaman = halaman.clamp(0, _jumlahHalaman - 1));
  }

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _error = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('produk_statistik_detail', {
        'tipe': widget.tipe,
        if (widget.tokoId != null) 'toko_id': widget.tokoId,
      });
      if (!mounted) return;
      setState(() {
        _produk = ((hasil['produk'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();
        _halaman = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  String _tanggal(dynamic value) {
    final teks = '${value ?? ''}'.trim();
    if (teks.isEmpty) return 'Belum pernah';
    final parsed = DateTime.tryParse(teks);
    return parsed == null
        ? teks
        : DateFormat('dd/MM/yyyy HH:mm').format(parsed.toLocal());
  }

  String _keterangan(Map<String, dynamic> row) {
    final keterangan = '${row['keterangan'] ?? ''}'.trim();
    final alasan = '${row['alasanStok'] ?? ''}'.trim();
    if (keterangan.isEmpty) return alasan.isEmpty ? '-' : alasan;
    if (alasan.isEmpty) return keterangan;
    return '$keterangan — $alasan';
  }

  DynamicReportData _dataLaporan() => DynamicReportData(
        title: 'Daftar Produk — ${widget.judul}',
        subtitle:
            '${_produk.length} produk · dibuat ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        columns: const [
          DynamicReportColumn('kode', 'Kode'),
          DynamicReportColumn('barcode', 'Barcode'),
          DynamicReportColumn('nama', 'Nama'),
          DynamicReportColumn('hargaJual', 'Harga Jual', numeric: true),
          DynamicReportColumn('hargaBeli', 'Harga Beli', numeric: true),
          DynamicReportColumn('stok', 'Stok', numeric: true),
          DynamicReportColumn('stokMinimal', 'Stok Minimal', numeric: true),
          DynamicReportColumn('terakhirPengadaan', 'Terakhir Pengadaan'),
          DynamicReportColumn('keterangan', 'Keterangan'),
        ],
        rows: _produk
            .map((row) => <String, dynamic>{
                  'kode': '${row['kode'] ?? ''}',
                  'barcode': '${row['barcode'] ?? ''}',
                  'nama': '${row['nama'] ?? ''}',
                  'hargaJual': (row['hargaJual'] as num?) ?? 0,
                  'hargaBeli': (row['hargaBeli'] as num?) ?? 0,
                  'stok': (row['stok'] as num?) ?? 0,
                  'stokMinimal': (row['stokMinimal'] as num?) ?? 0,
                  'terakhirPengadaan': _tanggal(row['terakhirPengadaan']),
                  'keterangan': _keterangan(row),
                })
            .toList(),
      );

  Future<void> _ekspor(String format) async {
    if (_produk.isEmpty) return;
    setState(() => _mengekspor = true);
    try {
      final data = _dataLaporan();
      final model = DynamicReportModel.fromData(data)
        ..landscape = true
        ..fontSize = 7.5
        ..showTotals = false;
      final slug = widget.tipe.replaceAll(RegExp('[^A-Za-z0-9_-]'), '-');
      if (format == 'pdf') {
        await DynamicReportDesigner.exportPdf(data, model, 'produk-$slug.pdf');
      } else {
        if (!mounted) return;
        await DynamicReportDesigner.exportExcel(
            context, data, model, 'produk-$slug.xlsx');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _mengekspor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ukuran = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.all(ukuran.width < 700 ? 8 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1500,
          maxHeight: ukuran.height * 0.92,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daftar Produk — ${widget.judul}',
                                style: Theme.of(context).textTheme.titleLarge),
                            Text('${_produk.length} barang',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _mengekspor || _produk.isEmpty
                            ? null
                            : () => _ekspor('pdf'),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Cetak PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _mengekspor || _produk.isEmpty
                            ? null
                            : () => _ekspor('excel'),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Download Excel'),
                      ),
                    ],
                  ),
                  if (_produk.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Halaman ${_halaman + 1} dari $_jumlahHalaman'),
                        const Spacer(),
                        Text('Baris per halaman: $_barisPerHalaman'),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Halaman pertama',
                          onPressed: _halaman > 0 ? () => _keHalaman(0) : null,
                          icon: const Icon(Icons.first_page),
                        ),
                        IconButton(
                          tooltip: 'Halaman sebelumnya',
                          onPressed: _halaman > 0
                              ? () => _keHalaman(_halaman - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Halaman berikutnya',
                          onPressed: _halaman < _jumlahHalaman - 1
                              ? () => _keHalaman(_halaman + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                        IconButton(
                          tooltip: 'Halaman terakhir',
                          onPressed: _halaman < _jumlahHalaman - 1
                              ? () => _keHalaman(_jumlahHalaman - 1)
                              : null,
                          icon: const Icon(Icons.last_page),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _memuat
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 44, color: AppColors.danger),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _muat,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Coba Lagi'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _produk.isEmpty
                          ? const Center(
                              child:
                                  Text('Tidak ada produk pada kelompok ini.'))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(12),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: PaginatedDataTable(
                                  key: ValueKey(
                                      'produk-statistik-$_barisPerHalaman-$_halaman'),
                                  showFirstLastButtons: true,
                                  initialFirstRowIndex:
                                      _halaman * _barisPerHalaman,
                                  rowsPerPage: _barisPerHalaman,
                                  availableRowsPerPage: const [10, 25, 50, 100],
                                  onRowsPerPageChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _barisPerHalaman = value;
                                        _halaman = 0;
                                      });
                                    }
                                  },
                                  onPageChanged: (firstRowIndex) {
                                    final halaman =
                                        firstRowIndex ~/ _barisPerHalaman;
                                    if (halaman != _halaman) {
                                      setState(() => _halaman = halaman);
                                    }
                                  },
                                  columns: const [
                                    DataColumn(label: Text('Kode')),
                                    DataColumn(label: Text('Barcode')),
                                    DataColumn(label: Text('Nama')),
                                    DataColumn(
                                        label: Text('Harga Jual'),
                                        numeric: true),
                                    DataColumn(
                                        label: Text('Harga Beli'),
                                        numeric: true),
                                    DataColumn(
                                        label: Text('Stok'), numeric: true),
                                    DataColumn(
                                        label: Text('Stok Minimal'),
                                        numeric: true),
                                    DataColumn(
                                        label: Text('Terakhir Pengadaan')),
                                    DataColumn(label: Text('Keterangan')),
                                  ],
                                  source: _SumberDetailStatistikProduk(
                                    rows: _produk,
                                    tanggal: _tanggal,
                                    keterangan: _keterangan,
                                  ),
                                ),
                              ),
                            ),
            ),
            if (_mengekspor) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}

class _SumberDetailStatistikProduk extends DataTableSource {
  final List<Map<String, dynamic>> rows;
  final String Function(dynamic value) tanggal;
  final String Function(Map<String, dynamic> row) keterangan;

  _SumberDetailStatistikProduk({
    required this.rows,
    required this.tanggal,
    required this.keterangan,
  });

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rows.length) return null;
    final row = rows[index];
    final stok = (row['stok'] as num?)?.toDouble() ?? 0;
    return DataRow.byIndex(
      index: index,
      color: stok < 0
          ? WidgetStatePropertyAll(AppColors.danger.withValues(alpha: 0.06))
          : null,
      cells: [
        DataCell(SelectableText('${row['kode'] ?? ''}')),
        DataCell(SelectableText('${row['barcode'] ?? ''}')),
        DataCell(SizedBox(
            width: 220,
            child: Text('${row['nama'] ?? ''}',
                maxLines: 2, overflow: TextOverflow.ellipsis))),
        DataCell(Text(_formatRupiah.format((row['hargaJual'] as num?) ?? 0))),
        DataCell(Text(_formatRupiah.format((row['hargaBeli'] as num?) ?? 0))),
        DataCell(Text(_teksStok(stok),
            style: TextStyle(
                color: stok < 0 ? AppColors.danger : null,
                fontWeight: stok < 0 ? FontWeight.w700 : null))),
        DataCell(
            Text(_teksStok((row['stokMinimal'] as num?)?.toDouble() ?? 0))),
        DataCell(Text(tanggal(row['terakhirPengadaan']))),
        DataCell(SizedBox(
          width: 380,
          child: Text(keterangan(row),
              maxLines: 3, overflow: TextOverflow.ellipsis),
        )),
      ],
    );
  }

  @override
  int get rowCount => rows.length;

  @override
  bool get isRowCountApproximate => false;

  @override
  int get selectedRowCount => 0;
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
/// visual DataTable pada referensi (Produk|SKU/Barcode|Kategori|HPP|Harga
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
                    child: Text('HPP',
                        textAlign: TextAlign.right, style: gayaHeaderTabel)),
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
                child: Text(_formatRupiah.format(produk.hargaBeli),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: AppColors.textSecondaryOf(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5))),
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
  final List<Map<String, dynamic>> pilihanUom;
  final List<Produk> semuaProduk;
  const _FormProduk(
      {required this.produk,
      required this.kategori,
      required this.kebijakanRetur,
      required this.pilihanUom,
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

class _KemasanBaris {
  final TextEditingController nama;
  final TextEditingController barcode;
  final TextEditingController qtyDasar;
  bool aktif;

  _KemasanBaris({
    String namaAwal = '',
    String barcodeAwal = '',
    String qtyDasarAwal = '1',
    this.aktif = true,
  })  : nama = TextEditingController(text: namaAwal),
        barcode = TextEditingController(text: barcodeAwal),
        qtyDasar = TextEditingController(text: qtyDasarAwal);

  void dispose() {
    nama.dispose();
    barcode.dispose();
    qtyDasar.dispose();
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
  int? idAntreanLokal;
  final String kunciLokal;
  bool mengunggah = false;
  _FotoBaris({
    this.id,
    this.url,
    this.bytes,
    this.namaFile,
    this.idAntreanLokal,
    String? kunciLokal,
  }) : kunciLokal = kunciLokal ??
            'foto:${DateTime.now().microsecondsSinceEpoch}:${identityHashCode(bytes)}';
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

  /// Pemasok utama tetap berupa nama. Satuan wajib menunjuk master UOM lewat
  /// ID; teks hanya label tampilan, bukan sumber identitas relasi.
  late final TextEditingController _pemasok;
  int? _satuanId;
  late String _satuanNamaAwal;
  int? _satuanPembelianId;
  late String _satuanPembelianNamaAwal;
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
  String _rute = '';
  bool _perluQc = false;
  bool _hargaBeliManual = false;
  bool _packAktif = false;
  int? _satuanPackId;
  late final TextEditingController _hargaPack;
  bool _menyimpan = false;
  String? _pesanError;
  final List<_BahanBakuBaris> _bahanBaku = [];
  final List<_KemasanBaris> _kemasan = [];

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
  late final int _idProdukEfektif;

  @override
  void initState() {
    super.initState();
    _idProdukEfektif = widget.produk?.id ?? MasterOffline.idSementaraBaru();
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
    _satuanId = p?.satuanId;
    _satuanNamaAwal = p?.satuanNama ?? '';
    _satuanPembelianId = p?.satuanPembelianId ?? p?.satuanId;
    _satuanPembelianNamaAwal = p?.satuanPembelianNama.isNotEmpty == true
        ? p!.satuanPembelianNama
        : (p?.satuanNama ?? '');
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
    _rute = p?.rute ?? '';
    _perluQc = p?.perluQc ?? false;
    _hargaBeliManual = p?.hargaBeliManual ?? false;
    _packAktif = p?.packAktif ?? false;
    _satuanPackId = p?.satuanPackId;
    _hargaPack = TextEditingController(
        text: p?.hargaPack == null ? '' : '${p!.hargaPack}');
    for (final b in p?.bahanBaku ?? const <Map<String, dynamic>>[]) {
      _bahanBaku.add(_BahanBakuBaris(
        produkId: (b['produkId'] as num?)?.toInt(),
        nama: (b['nama'] as String?) ?? '-',
        qtyAwal: '${b['qty'] ?? 1}',
        hargaAwal: '${b['harga'] ?? 0}',
      ));
    }
    _ekstraPilihan.addAll(p?.ekstraPilihan ?? const <int>[]);
    for (final k in p?.kemasan ?? const <Map<String, dynamic>>[]) {
      _kemasan.add(_KemasanBaris(
        namaAwal: '${k['nama'] ?? ''}',
        barcodeAwal: '${k['barcode'] ?? ''}',
        qtyDasarAwal: '${k['qtyDasar'] ?? 1}',
        aktif: k['aktif'] != false,
      ));
    }
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
    _hargaPack.dispose();
    for (final b in _bahanBaku) {
      b.dispose();
    }
    for (final k in _kemasan) {
      k.dispose();
    }
    super.dispose();
  }

  double _angka(String s) =>
      double.tryParse(s.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;

  double get _totalHpp => _bahanBaku.fold(
      0, (s, b) => s + _angka(b.qty.text) * _angka(b.harga.text));

  String _namaUom(int? id) {
    if (id == null) return '';
    for (final uom in widget.pilihanUom) {
      if ((uom['id'] as num?)?.toInt() == id) {
        return '${uom['nama'] ?? ''}';
      }
    }
    return _satuanNamaAwal;
  }

  Map<String, dynamic>? _uom(int? id) {
    if (id == null) return null;
    for (final uom in widget.pilihanUom) {
      if ((uom['id'] as num?)?.toInt() == id) return uom;
    }
    return null;
  }

  String _ringkasanKonversiPembelian() {
    final dasar = _uom(_satuanId);
    final beli = _uom(_satuanPembelianId);
    if (dasar == null || beli == null) return '';
    final faktor = UomKonversi.konversi(jumlah: 1, dari: beli, ke: dasar);
    final angka = faktor == faktor.roundToDouble()
        ? faktor.toStringAsFixed(0)
        : faktor.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
    return '1 ${beli['nama']} = $angka ${dasar['nama']} stok. Contoh PO 10 ${beli['nama']} menambah ${_angkaFormat(10 * faktor)} ${dasar['nama']}.';
  }

  String _angkaFormat(double nilai) => nilai == nilai.roundToDouble()
      ? nilai.toStringAsFixed(0)
      : nilai.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');

  /// Cache hasil merge dapat sementara membawa id referensi ganda, sedangkan
  /// DropdownButton Flutter mensyaratkan tepat satu item untuk nilai aktif.
  /// Deduplikasi dilakukan di batas UI dan nilai lama tetap disediakan sebagai
  /// fallback agar produk masih dapat diedit ketika referensinya belum masuk
  /// halaman cache yang sedang tersedia.
  List<DropdownMenuItem<int?>> _itemKategori() {
    final unik = <int, Kategori>{};
    for (final kategori in widget.kategori) {
      unik.putIfAbsent(kategori.id, () => kategori);
    }
    final hasil = <DropdownMenuItem<int?>>[
      const DropdownMenuItem<int?>(
          value: null, child: Text('-- Tanpa Kategori --')),
      for (final kategori in unik.values)
        DropdownMenuItem<int?>(value: kategori.id, child: Text(kategori.nama)),
    ];
    final aktif = _kategoriId;
    if (aktif != null && !unik.containsKey(aktif)) {
      final nama = widget.produk?.kategoriNama.trim() ?? '';
      hasil.add(DropdownMenuItem<int?>(
          value: aktif,
          child: Text(nama.isEmpty
              ? 'Kategori #$aktif (belum tersinkron)'
              : '$nama (referensi belum tersinkron)')));
    }
    return hasil;
  }

  List<DropdownMenuItem<int?>> _itemKebijakanRetur() {
    final unik = <int, KebijakanRetur>{};
    for (final kebijakan in widget.kebijakanRetur) {
      unik.putIfAbsent(kebijakan.id, () => kebijakan);
    }
    final hasil = <DropdownMenuItem<int?>>[
      for (final kebijakan in unik.values)
        DropdownMenuItem<int?>(
            value: kebijakan.id, child: Text(kebijakan.nama)),
    ];
    final aktif = _kebijakanReturId;
    if (aktif != null && !unik.containsKey(aktif)) {
      hasil.add(DropdownMenuItem<int?>(
          value: aktif,
          child: Text('Kebijakan #$aktif (referensi belum tersinkron)')));
    }
    return hasil;
  }

  Widget _pemilihUom({bool pembelian = false}) {
    final idTerpilih = pembelian ? _satuanPembelianId : _satuanId;
    final namaAwal = pembelian ? _satuanPembelianNamaAwal : _satuanNamaAwal;
    final kategoriDasar = '${_uom(_satuanId)?['kategori'] ?? ''}';
    return Autocomplete<Map<String, dynamic>>(
      key: ValueKey('${pembelian ? 'purchase' : 'base'}:$idTerpilih'),
      initialValue: TextEditingValue(text: namaAwal),
      displayStringForOption: (uom) => '${uom['nama'] ?? ''}',
      optionsBuilder: (nilai) {
        final q = nilai.text.trim().toLowerCase();
        return widget.pilihanUom.where((uom) {
          final id = (uom['id'] as num?)?.toInt();
          final bolehDipilih = uom['aktif'] != false || id == idTerpilih;
          final kategoriSama = !pembelian ||
              kategoriDasar.isEmpty ||
              '${uom['kategori'] ?? 'UNIT'}'.toUpperCase() ==
                  kategoriDasar.toUpperCase();
          return bolehDipilih &&
              kategoriSama &&
              (q.isEmpty || '${uom['nama'] ?? ''}'.toLowerCase().contains(q));
        });
      },
      onSelected: (uom) => setStateIfMounted(() {
        final id = (uom['id'] as num?)?.toInt();
        if (pembelian) {
          _satuanPembelianId = id;
          _satuanPembelianNamaAwal = '${uom['nama'] ?? ''}';
        } else {
          _satuanId = id;
          _satuanNamaAwal = '${uom['nama'] ?? ''}';
          final beli = _uom(_satuanPembelianId);
          if (beli == null ||
              '${beli['kategori'] ?? 'UNIT'}'.toUpperCase() !=
                  '${uom['kategori'] ?? 'UNIT'}'.toUpperCase()) {
            _satuanPembelianId = id;
            _satuanPembelianNamaAwal = '${uom['nama'] ?? ''}';
          }
        }
      }),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: AppFormStyle.fieldDecoration(
            context,
            labelText:
                pembelian ? 'Satuan Pembelian/PO *' : 'Satuan Stok/Dasar *',
            hintText: pembelian
                ? 'Cari UOM satu kategori, mis. Dus'
                : 'Cari UOM, mis. Botol',
            helperText: widget.pilihanUom.isEmpty
                ? 'Daftar UOM belum termuat. Tekan Sinkronkan/Muat Ulang, atau kelola di Master Data > Satuan/UOM.'
                : 'Pilih dari Master Data > Satuan/UOM; teks bebas tidak disimpan.',
          ),
          onChanged: (teks) {
            final namaDipilih =
                _namaUom(pembelian ? _satuanPembelianId : _satuanId);
            if (teks.trim().toLowerCase() != namaDipilih.trim().toLowerCase()) {
              if (pembelian) {
                _satuanPembelianId = null;
              } else {
                _satuanId = null;
              }
            }
          },
          validator: (_) {
            if ((pembelian ? _satuanPembelianId : _satuanId) == null) {
              return widget.pilihanUom.isEmpty
                  ? 'Daftar UOM belum tersedia; sinkronkan lalu buka form kembali'
                  : 'Pilih satuan dari hasil pencarian UOM';
            }
            return null;
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 360),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (_, index) {
                final uom = options.elementAt(index);
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.straighten_outlined),
                  title: Text('${uom['nama'] ?? ''}'),
                  trailing: Text('${uom['kategori'] ?? 'UNIT'}'),
                  subtitle: uom['aktif'] == false
                      ? const Text('Nonaktif — ganti ke UOM aktif')
                      : null,
                  onTap: () => onSelected(uom),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

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

  void _tambahKemasan() =>
      setStateIfMounted(() => _kemasan.add(_KemasanBaris()));

  void _hapusKemasan(_KemasanBaris k) {
    setStateIfMounted(() => _kemasan.remove(k));
    k.dispose();
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
    final fotoServer = <_FotoBaris>[];
    try {
      final hasil = await ApiClient.instance
          .aksi('produk_foto_list', {'produk_id': widget.produk!.id});
      final data = (hasil['data'] as List?) ?? const [];
      fotoServer.addAll(data.map((d) {
        final id = (d['id'] as num).toInt();
        final url = normalisasiUrlMedia(d['urlGambar'] as String?);
        return _FotoBaris(
          id: id,
          url: url.isEmpty ? urlFotoProdukDariId(id) : url,
        );
      }));
    } catch (e) {
      // Gagal muat foto bukan error fatal utk form ini -- form tetap bisa
      // dipakai dan preview antrean lokal tetap dipulihkan di bawah.
    } finally {
      final fotoLokal = await muatGambarLokalTertunda(
        aksi: 'produk_foto_upload',
        awalanKunci: 'produk_foto:${widget.produk!.id}:',
        termasukTersinkron: true,
      );
      final lokalPerId = <int, GambarLokalTertunda>{
        for (final foto in fotoLokal)
          if (foto.idServer != null) foto.idServer!: foto,
      };
      final terpakai = <int>{};
      for (final server in fotoServer) {
        final lokal = server.id == null ? null : lokalPerId[server.id!];
        if (lokal == null) continue;
        server
          ..bytes = lokal.bytes
          ..namaFile = lokal.namaFile
          ..idAntreanLokal = lokal.idAntrean;
        terpakai.add(lokal.idAntrean);
      }

      // Migrasi antrean versi lama yang belum menyimpan id hasil server.
      // Upload ditambahkan di akhir daftar, sehingga pasangan lama diambil
      // dari belakang. Antrean baru selalu memakai idServer eksak di atas.
      final lamaTanpaId = fotoLokal
          .where((e) =>
              e.status == 'SYNCED' &&
              e.idServer == null &&
              !terpakai.contains(e.idAntrean))
          .toList();
      final serverTanpaBytes =
          fotoServer.where((e) => e.bytes == null).toList(growable: false);
      var indeksServer = serverTanpaBytes.length - 1;
      for (var i = lamaTanpaId.length - 1;
          i >= 0 && indeksServer >= 0;
          i--, indeksServer--) {
        final lokal = lamaTanpaId[i];
        serverTanpaBytes[indeksServer]
          ..bytes = lokal.bytes
          ..namaFile = lokal.namaFile
          ..idAntreanLokal = lokal.idAntrean;
        terpakai.add(lokal.idAntrean);
      }
      if (mounted) {
        setStateIfMounted(() {
          _foto
            ..clear()
            ..addAll(fotoServer)
            ..addAll(fotoLokal
                .where((foto) => foto.status != 'SYNCED')
                .where((foto) => !terpakai.contains(foto.idAntrean))
                .map((foto) => _FotoBaris(
                      bytes: foto.bytes,
                      namaFile: foto.namaFile,
                      idAntreanLokal: foto.idAntrean,
                      kunciLokal: foto.kunci,
                    )));
          _memuatFoto = false;
        });
      }
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
    XFile? berkas;
    if (sumber == ImageSource.camera) {
      if (!mounted) return;
      berkas = await FotoProdukCameraScreen.ambil(context);
    } else {
      berkas = await ImagePicker().pickImage(source: sumber, imageQuality: 100);
    }
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
    // kompresGambarKeBawah500Kb selalu menghasilkan JPEG. Nama/ekstensi yang
    // dikirim harus ikut JPEG; mempertahankan `.png`/`.heic` asli membuat
    // servlet media mengirim Content-Type yang tidak cocok dengan isi berkas
    // dan sebagian renderer menampilkan ikon gambar rusak.
    final namaDasar = namaFile.replaceFirst(RegExp(r'\.[^.]+$'), '');
    baris.namaFile = '${namaDasar.isEmpty ? 'foto' : namaDasar}.jpg';

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
      final hasil = await simpanGambarLocalFirst(
        aksi: 'produk_foto_upload',
        kunci: 'produk_foto:$produkId:${baris.kunciLokal}',
        body: {
          'produk_id': produkId,
          'file_base64': base64Encode(baris.bytes!),
          'nama_file': baris.namaFile ?? 'foto.jpg',
        },
      );
      if (hasil.tertunda) {
        setStateIfMounted(() {
          baris.mengunggah = false;
          baris.idAntreanLokal = hasil.idAntrean;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
              'Foto tersimpan di perangkat. Server belum dapat menerima; '
              'pengiriman akan dicoba otomatis tanpa memilih foto ulang.',
            ),
          ));
        }
        return;
      }
      // Bytes preview tidak dibuang setelah server menerima foto. URL media
      // dapat belum tersedia sesaat atau servlet server belum diperbarui.
      final idServer = (hasil.respons['id'] as num?)?.toInt();
      setStateIfMounted(() {
        baris
          ..id = idServer
          ..url = idServer == null ? null : urlFotoProdukDariId(idServer)
          ..idAntreanLokal = hasil.idAntrean
          ..mengunggah = false;
      });
    } catch (e) {
      // Preview dipertahankan. Pengguna dapat melihat foto yang dipilih dan
      // memperbaiki penolakan bisnis tanpa harus memilih berkas dari awal.
      final lokal = await muatGambarLokalTertunda(
        aksi: 'produk_foto_upload',
        awalanKunci: 'produk_foto:$produkId:${baris.kunciLokal}',
      );
      setStateIfMounted(() {
        baris.mengunggah = false;
        if (lokal.isNotEmpty) baris.idAntreanLokal = lokal.last.idAntrean;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Foto tersimpan lokal, tetapi server menolak datanya: $e. '
                    'Periksa Log Error lalu coba sinkronkan kembali.')));
      }
    }
  }

  Future<void> _hapusFoto(_FotoBaris baris) async {
    if (baris.id == null) {
      final antreanLokal = baris.idAntreanLokal;
      if (antreanLokal != null) {
        await hapusGambarLokalTertunda(antreanLokal);
      }
      // Staged/tertunda dan belum pernah sampai ke server.
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

  Future<void> _pindaiBarcodeProduk() async {
    final hasil = await BarcodeScannerScreen.pindai(
      context,
      judul: 'Scan Barcode / QR-Code Produk',
    );
    if (hasil == null || !mounted) return;
    setStateIfMounted(() {
      _barcode.text = hasil.trim();
      _barcode.selection = TextSelection.collapsed(
        offset: _barcode.text.length,
      );
    });
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setStateIfMounted(() {
      _menyimpan = true;
      _pesanError = null;
    });
    try {
      final ubah = widget.produk != null;
      final idProduk = _idProdukEfektif;
      final hasil = await prosesSimpanMaster(
        context,
        aksi: 'produk_simpan',
        body: {
          if (ubah) 'id': idProduk,
          'kode': _kode.text.trim(),
          'nama': _nama.text.trim(),
          'barcode': _barcode.text.trim(),
          'harga_beli':
              _bahanBaku.isNotEmpty ? _totalHpp : _angka(_hargaBeli.text),
          'harga_jual': _angka(_hargaJual.text),
          'stok': _angka(_stok.text),
          'keterangan': _keterangan.text.trim(),
          'pemasok_nama': _pemasok.text.trim(),
          'satuan_id': _satuanId,
          'satuan_pembelian_id': _satuanPembelianId,
          'kategori_id': _kategoriId,
          'kebijakan_retur_id': _kebijakanReturId,
          'izinkan_jual_minus_stok': _izinkanJualMinusStok,
          if (_grupProdukPilihan != -1)
            'grup_produk_id':
                _grupProdukPilihan == 0 ? null : _grupProdukPilihan,
          'aktif': _aktif,
          'jenis_item': _jenisItem,
          'rute': _rute.isEmpty ? null : _rute,
          'perlu_qc': _perluQc,
          'harga_beli_manual': _hargaBeliManual,
          'pack_aktif': _packAktif,
          if (_packAktif) 'satuan_pack_id': _satuanPackId,
          if (_packAktif) 'harga_pack': _angka(_hargaPack.text),
          'bahan_baku': _bahanBaku
              .map((b) => {
                    'produk_id': b.produkId,
                    'nama': b.nama,
                    'qty': _angka(b.qty.text),
                    'harga': _angka(b.harga.text)
                  })
              .toList(),
          'ekstra_pilihan': _ekstraPilihan,
          'kemasan': _kemasan
              .map((k) => {
                    'nama': k.nama.text.trim(),
                    'barcode': k.barcode.text.trim(),
                    'qtyDasar': _angka(k.qtyDasar.text),
                    'aktif': k.aktif,
                  })
              .toList(),
        },
        kunci: 'produk:$idProduk',
        // Optimistis HANYA utk edit -- baris create offline belum punya id,
        // sedangkan Produk.fromJson mewajibkannya (baris tanpa id di snapshot
        // akan membuat parsing daftar gagal saat offline). rowLokal memakai
        // nama field camelCase respons `katalog` (bukan snake_case payload)
        // supaya perubahan langsung terlihat di snapshot daftar.
        cacheKey: 'master:produk_list',
        idLokal: ubah ? null : idProduk,
        entitas: 'produk',
        rowLokal: {
          'id': idProduk,
          'kode': _kode.text.trim(),
          'nama': _nama.text.trim(),
          'barcode': _barcode.text.trim(),
          'hargaBeli':
              _bahanBaku.isNotEmpty ? _totalHpp : _angka(_hargaBeli.text),
          'hargaJual': _angka(_hargaJual.text),
          'stok': _angka(_stok.text),
          'keterangan': _keterangan.text.trim(),
          'satuanId': _satuanId,
          'satuanNama': _namaUom(_satuanId),
          'satuanPembelianId': _satuanPembelianId,
          'satuanPembelianNama': _namaUom(_satuanPembelianId),
          'kategoriId': _kategoriId,
          'kebijakanReturId': _kebijakanReturId,
          'izinkanJualMinusStok': _izinkanJualMinusStok,
          'aktif': _aktif,
          'jenisItem': _jenisItem,
          'rute': _rute,
          'perluQc': _perluQc,
          'hargaBeliManual': _hargaBeliManual,
                'packAktif': _packAktif,
                'satuanPackId': _satuanPackId,
                'satuanPackNama': _namaUom(_satuanPackId),
                'hargaPack': _packAktif ? _angka(_hargaPack.text) : null,
          'kemasan': _kemasan
              .map((k) => {
                    'nama': k.nama.text.trim(),
                    'barcode': k.barcode.text.trim(),
                    'qtyDasar': _angka(k.qtyDasar.text),
                    'aktif': k.aktif,
                  })
              .toList(),
        },
      );
      // produk_cache adalah sumber pencarian Kasir, Kulakan, dan Stok Opname;
      // ia terpisah dari snapshot master:produk_list di atas. Setelah edit
      // terbukti tersimpan lokal (baik server sudah menerima maupun masih
      // PENDING), perbarui cache ini juga agar barcode/nama baru langsung bisa
      // dipakai tanpa menunggu server pulih. Create tetap menunggu id server
      // karena produk_cache memakai id sebagai primary key.
      await CoreDb.instance.upsertProdukCache([
        Produk.baseKeCacheRow({
          'id': idProduk,
          'kode': _kode.text.trim(),
          'barcode': _barcode.text.trim(),
          'nama': _nama.text.trim(),
          'hargaJual': _angka(_hargaJual.text),
          'stok': _angka(_stok.text),
          'kategoriId': _kategoriId,
          'kategoriNama': widget.produk?.kategoriNama ?? '',
          'gambarUrl': widget.produk?.gambarUrl ?? '',
          'aktif': _aktif,
          'jenisItem': _jenisItem,
          'ekstraPilihan': _ekstraPilihan,
          'kemasan': _kemasan
              .map((k) => {
                    'nama': k.nama.text.trim(),
                    'barcode': k.barcode.text.trim(),
                    'qtyDasar': _angka(k.qtyDasar.text),
                    'aktif': k.aktif,
                  })
              .toList(),
          'fotoUrls': widget.produk?.fotoUrls ?? const <String>[],
          'izinkanJualMinusStok': _izinkanJualMinusStok,
        })
      ]);
      // Produk baru: baris foto yg ditahan di memori (id==null, blm pernah
      // diunggah krn belum ada produk_id) diunggah SEKARANG pakai id baru
      // dari respons ini -- lihat JavaDoc _foto/_pilihFoto.
      if (widget.produk == null) {
        final produkIdBaru = (hasil['id'] as num?)?.toInt() ?? idProduk;
        for (final baris in _foto.where((b) => b.id == null).toList()) {
          await _unggahBaris(baris, produkIdBaru);
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
                // Produk baru butuh create; menyunting yang sudah ada butuh
                // update. Baris produk sendiri TETAP dapat diketuk walau tidak
                // berhak: formulirnya juga dipakai MELIHAT rincian, dan
                // mengunci ketukannya menutup pembacaan, bukan penyuntingan.
                onPressed: _menyimpan ||
                        !_bolehProduk(
                            widget.produk == null ? 'create' : 'update')
                    ? null
                    : _simpan,
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
                    helperText:
                        'Pindai barcode/QR-Code dengan kamera, scanner USB, atau ketik manual.',
                    suffixIcon: IconButton(
                      onPressed: _menyimpan ? null : _pindaiBarcodeProduk,
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: 'Scan barcode / QR-Code dengan kamera',
                    ),
                  ),
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
                        child: _pemilihUom(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _pemilihUom(pembelian: true),
                  if (_ringkasanKonversiPembelian().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        _ringkasanKonversiPembelian(),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                  DropdownButtonFormField<int?>(
                    value: _kategoriId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Kategori',
                    ),
                    items: _itemKategori(),
                    onChanged: (v) => setStateIfMounted(() => _kategoriId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _kebijakanReturId,
                    decoration: AppFormStyle.fieldDecoration(
                      context,
                      labelText: 'Kebijakan Retur',
                    ),
                    items: _itemKebijakanRetur(),
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
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Rute Pemenuhan Ulang Stok',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryOf(context))),
                  ),
                  const SizedBox(height: 6),
                  // Fase C/E: dibaca server -- BELI/PRODUKSI oleh penjadwal
                  // ambang stok; MTO_* oleh konfirmasi Sales Order lapangan.
                  DropdownButtonFormField<String>(
                    value: _rute,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Beli (bawaan)')),
                      DropdownMenuItem(
                          value: 'PRODUKSI', child: Text('Produksi Sendiri')),
                      DropdownMenuItem(
                          value: 'MTO_BELI',
                          child: Text('MTO Beli (pesan dulu, beli saat SO)')),
                      DropdownMenuItem(
                          value: 'MTO_PRODUKSI',
                          child: Text('MTO Produksi (pesan dulu, WO saat SO)')),
                    ],
                    onChanged: (v) => setStateIfMounted(() => _rute = v ?? ''),
                  ),
                  const SizedBox(height: 6),
                  // PDF Pack 31-08: settingan Pack/Combo -- jual per pack di
                  // POS dengan harga TETAP per pack.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Dapat dijual berupa Pack (Combo) di POS'),
                    subtitle: const Text(
                        'Kasir mendapat pilihan satuan vs pack; harga pack tetap (mis. Rp 65.000/Dus, bukan isi x harga satuan). Stok tetap turun per satuan dasar.'),
                    value: _packAktif,
                    onChanged: (v) => setStateIfMounted(() => _packAktif = v),
                  ),
                  if (_packAktif) ...[
                    DropdownButtonFormField<int>(
                      value: _satuanPackId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'UOM Pack (sekategori satuan dasar) *'),
                      items: widget.pilihanUom
                          .where((u) {
                            final dasar = _uom(_satuanId);
                            final katDasar =
                                '${dasar?['kategori'] ?? 'UNIT'}'.toUpperCase();
                            return u['aktif'] != false &&
                                (u['id'] as num?)?.toInt() != _satuanId &&
                                '${u['kategori'] ?? 'UNIT'}'.toUpperCase() ==
                                    katDasar;
                          })
                          .map((u) => DropdownMenuItem(
                              value: (u['id'] as num?)?.toInt(),
                              child: Text('${u['nama']}')))
                          .toList(),
                      onChanged: (v) =>
                          setStateIfMounted(() => _satuanPackId = v),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _hargaPack,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Harga jual per pack *',
                        helperText:
                            'Harga TETAP per pack, mis. 65000 utk Dus isi 6 (bukan 6 x harga satuan).',
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  // PDF stok & uom 30-08: kebijakan harga beli per produk.
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Harga beli manual (tidak ikut faktur)'),
                    subtitle: const Text(
                        'Mati = harga beli otomatis mengikuti faktur kulakan/BAST tervalidasi, terkonversi ke satuan dasar (Rp 1.200.000/DUS isi 6 menjadi Rp 200.000/botol).'),
                    value: _hargaBeliManual,
                    onChanged: (v) =>
                        setStateIfMounted(() => _hargaBeliManual = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Perlu QC saat hasil produksi'),
                    subtitle: const Text(
                        'OUTPUT yang diposting otomatis membuat Quality Alert dan mengkarantina batch sampai didisposisi.'),
                    value: _perluQc,
                    onChanged: (v) => setStateIfMounted(() => _perluQc = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppSectionCard(
                judul: 'Kemasan / Barcode Multi-unit',
                aksiJudul: TextButton.icon(
                  onPressed: _tambahKemasan,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Tambah Kemasan'),
                ),
                child: _kemasan.isEmpty
                    ? Text(
                        'Opsional. Contoh: Dus 24 dengan barcode dus dan isi 24 ${_namaUom(_satuanId).isEmpty ? 'unit stok' : _namaUom(_satuanId)}. Scan barcode tersebut di Kasir langsung menambah 24 unit; UOM akuntansi tidak berubah.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondaryOf(context)),
                      )
                    : Column(
                        children: _kemasan
                            .map((k) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: k.nama,
                                        decoration:
                                            AppFormStyle.fieldDecoration(
                                                context,
                                                labelText: 'Nama (mis. Dus 24)',
                                                isDense: true),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                                ? 'Wajib'
                                                : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 4,
                                      child: TextFormField(
                                        controller: k.barcode,
                                        decoration:
                                            AppFormStyle.fieldDecoration(
                                                context,
                                                labelText: 'Barcode kemasan',
                                                isDense: true),
                                        validator: (v) =>
                                            v == null || v.trim().isEmpty
                                                ? 'Wajib'
                                                : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: k.qtyDasar,
                                        keyboardType: TextInputType.number,
                                        decoration: AppFormStyle.fieldDecoration(
                                            context,
                                            labelText:
                                                'Isi ${_namaUom(_satuanId)}',
                                            isDense: true),
                                        validator: (v) {
                                          final n = _angka(v ?? '');
                                          return n <= 0 ||
                                                  n != n.roundToDouble()
                                              ? 'Bulat > 0'
                                              : null;
                                        },
                                      ),
                                    ),
                                    Switch(
                                      value: k.aktif,
                                      onChanged: (v) =>
                                          setStateIfMounted(() => k.aktif = v),
                                    ),
                                    IconButton(
                                      onPressed: () => _hapusKemasan(k),
                                      icon: const Icon(Icons.delete_outline),
                                      color: AppColors.danger,
                                      tooltip: 'Hapus kemasan',
                                    ),
                                  ]),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 12),
              // Fase A: aturan harga grosir per produk. Hanya untuk produk
              // TERSIMPAN (butuh id server) dan pemegang izin ubah harga --
              // aturan grosir adalah keputusan harga.
              if (widget.produk?.id != null &&
                  Sesi.instance.bolehUbahHarga) ...[
                HargaGrosirEditor(
                  produkId: widget.produk!.id,
                  satuanNama: _namaUom(_satuanId),
                ),
                const SizedBox(height: 12),
              ],
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
                          final grupUnik = <int, Map<String, dynamic>>{};
                          for (final grup in data) {
                            final id = (grup['id'] as num?)?.toInt();
                            if (id != null && id > 0) {
                              grupUnik.putIfAbsent(id, () => grup);
                            }
                          }
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
                              ...grupUnik.values.map((g) =>
                                  DropdownMenuItem<int>(
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
        AppSearchField(
          labelText: 'Cari Produk',
          hintText: 'Cari produk...',
          scanProduk: true,
          gayaForm: true,
          autofocus: true,
          debounce: Duration.zero,
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
