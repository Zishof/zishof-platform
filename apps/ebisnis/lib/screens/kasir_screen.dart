import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_hw/core_hw.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/pesanan_poller.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'keranjang_screen.dart';
import 'layar_pelanggan_screen.dart';
import 'bantuan_screen.dart';
import 'akun_saya_screen.dart';

final _formatRupiah = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  bool _memuat = true;
  String? _pesanError;
  bool _sinkronBerjalan = false;
  int _jumlahPending = 0;

  List<Produk> _semuaProduk = [];
  List<Kategori> _kategori = [];
  int? _kategoriTerpilih; // null = "Semua"
  String _kataKunci = '';
  final _kataKunciController = TextEditingController();

  final List<ItemKeranjang> _keranjang = [];

  /// null = belum diketahui (masih memeriksa), false = kas tertutup (blokir
  /// layar), true = kas terbuka (boleh jualan) -- lihat _periksaSesiKas &
  /// _OverlayBukaKas. Sengaja gerbang KERAS spt versi Electron: kasir TIDAK
  /// BOLEH mulai transaksi apa pun sebelum kas dibuka.
  bool? _kasTerbuka;
  double _modalAwalKas = 0;

  /// Kas Sekarang -- pil saldo kas berjalan di toolbar (padanan indikator
  /// "Rp 1.900.000" pada referensi Electron). `null` = belum diketahui/tak
  /// relevan (mis. toko belum wajib-sesi-kas) -- pil disembunyikan saat itu,
  /// BUKAN ditampilkan "Rp 0" yang menyesatkan.
  double? _kasSaatIni;

  /// "Fokus Keranjang" (F7, padanan PERSIS `elBtnToggleFullLayarHeader` di
  /// pos-renderer.js) -- BUKAN fullscreen level-OS (percobaan sebelumnya
  /// salah tafsir spec ini), melainkan menyembunyikan pencarian+kategori+grid
  /// produk supaya panel Keranjang melebar sendirian, dipakai saat kasir
  /// cuma perlu menuntaskan pembayaran tanpa godaan menambah produk lagi.
  /// Hanya relevan di Windows -- di Android, Kasir & Keranjang tetap 2 layar
  /// terpisah (lihat `_bodyMobile`), konsep ini tak berlaku di sana.
  bool _fokusKeranjang = false;

  void _toggleFokusKeranjang() => setState(() => _fokusKeranjang = !_fokusKeranjang);

  @override
  void initState() {
    super.initState();
    _muatAwal();
  }

  @override
  void dispose() {
    _kataKunciController.dispose();
    super.dispose();
  }

  Future<void> _muatAwal() async {
    setState(() {
      _memuat = true;
      _pesanError = null;
    });

    // 1) Baca cache lokal DULU (offline-first) -- kasir bisa langsung mulai
    //    kerja walau server sedang lambat/offline, produk_cache jadi satu-
    //    satunya sumber yang dibaca layar Kasir (sama seperti pos-renderer.js).
    try {
      final cache = await CoreDb.instance.produkCache();
      if (cache.isNotEmpty) {
        setState(() => _semuaProduk = cache.map(_produkDariCache).toList());
      }
    } catch (_) {
      // cache lokal gagal dibaca (mis. pertama kali install) -- lanjut ke jalur server saja.
    }

    await _perbaruiJumlahPending();
    await _sinkronKatalogDanKonfigurasi(tampilkanErrorJikaKosong: _semuaProduk.isEmpty);
    await _periksaSesiKas();
    PesananPoller.instance.mulai();

    if (mounted) setState(() => _memuat = false);
  }

  Produk _produkDariCache(Map<String, Object?> b) => Produk(
        id: b['id'] as int,
        kode: (b['kode'] ?? '') as String,
        barcode: (b['barcode'] ?? '') as String,
        nama: (b['nama'] ?? '') as String,
        hargaJual: (b['harga_jual'] as num?)?.toDouble() ?? 0,
        stok: (b['stok'] as num?)?.toInt() ?? 0,
        kategoriId: b['kategori_id'] as int?,
        kategoriNama: (b['kategori_nama'] ?? '') as String,
        gambarUrl: b['gambar_url'] as String?,
      );

  Future<void> _sinkronKatalogDanKonfigurasi({bool tampilkanErrorJikaKosong = false}) async {
    try {
      final konfig = await ApiClient.instance.aksi('konfigurasi');
      Sesi.instance
        ..tokoNama = (konfig['tokoNama'] ?? '') as String
        ..tokoId = konfig['tokoId'] as int?
        ..userId = (konfig['userId'] ?? '') as String
        ..pajakPersen = (konfig['pajakPersen'] as num?)?.toDouble() ?? 0
        ..pesanTerimaKasih = (konfig['pesanTerimaKasih'] ?? '') as String
        ..wajibSesiKas = konfig['wajibSesiKas'] == true
        ..isAdmin = konfig['isAdmin'] == true
        ..supervisorPedagang = konfig['supervisorPedagang'] == true
        ..caraBayar = ((konfig['caraBayar'] as List?) ?? [])
            .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
            .toList()
        ..aksesMenu = ((konfig['aksesMenu'] as Map<String, dynamic>?) ?? {}).map((k, v) => MapEntry(k, v == true));

      final katalog = await ApiClient.instance.aksi('katalog');
      final produkJson = (katalog['produk'] as List?) ?? [];
      final produk = produkJson.map((e) => Produk.fromJson(e as Map<String, dynamic>)).toList();
      final kategori = ((katalog['kategori'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();

      await CoreDb.instance.replaceProdukCache(produkJson
          .map((e) => Produk.baseKeCacheRow(e as Map<String, dynamic>))
          .toList());

      if (mounted) {
        setState(() {
          _semuaProduk = produk;
          _kategori = kategori;
        });
      }
    } catch (e) {
      final off = e is ApiException && e.offline;
      if (tampilkanErrorJikaKosong && _semuaProduk.isEmpty) {
        setState(() => _pesanError = off
            ? 'Belum ada data katalog tersimpan & server tidak terjangkau. Sambungkan internet lalu coba lagi.'
            : e.toString());
      }
      // Jika cache lokal SUDAH ada isinya, kegagalan sinkron di sini SENGAJA
      // diabaikan (Kasir tetap bisa jualan pakai data cache terakhir).
    }
  }

  Future<void> _periksaSesiKas() async {
    if (!Sesi.instance.wajibSesiKas) {
      // Toko ini belum mengaktifkan konfigurasi wajib-sesi-kas -- jangan
      // memblokir kasir dgn overlay yg memang tidak berlaku utknya.
      if (mounted) setState(() => _kasTerbuka = true);
      return;
    }
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
      final terbuka = hasil['terbuka'] == true;
      if (terbuka) {
        await CoreDb.instance.bukaSesiKasLokal(
          'sesi-${Sesi.instance.tokoId}',
          (hasil['modalAwal'] as num?)?.toDouble() ?? 0,
        );
      }
      if (mounted) setState(() => _kasTerbuka = terbuka);
      if (mounted) setState(() => _kasSaatIni = terbuka ? (hasil['kasSaatIni'] as num?)?.toDouble() ?? 0 : null);
    } catch (_) {
      // Offline saat cek status -- pakai sumber lokal (local-first, sama spt Electron).
      final lokal = await CoreDb.instance.sesiKasAktif();
      if (mounted) setState(() => _kasTerbuka = lokal != null);
    }
  }

  /// Muat ulang saldo Kas Sekarang saja (tanpa menyentuh gerbang buka/tutup
  /// kas) -- dipanggil dari [_perbaruiJumlahPending] tiap kali transaksi
  /// baru selesai (Bayar/Tahan/Sinkronkan) supaya pil toolbar selalu segar.
  Future<void> _muatKasSaatIni() async {
    if (!Sesi.instance.wajibSesiKas || _kasTerbuka != true) return;
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
      if (mounted) setState(() => _kasSaatIni = (hasil['kasSaatIni'] as num?)?.toDouble() ?? 0);
    } catch (_) {
      // Offline -- biarkan angka lama, jangan ganti dgn 0 yg menyesatkan.
    }
  }

  /// Tutup Kas (spec §17) -- selisih SELALU dihitung server (`sesi_kas_tutup`),
  /// klien tak pernah menghitung sendiri. Sukses -> tandai lokal tertutup,
  /// gerbang Buka Kas otomatis muncul lagi utk sesi berikutnya, lalu tampilkan
  /// modal "Produk Perlu Direstok" (stokMenipis) langsung tanpa langkah tambahan.
  Future<void> _bukaDialogTutupKas() async {
    Map<String, dynamic>? status;
    try {
      status = await ApiClient.instance.aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat status kas: $e')));
      return;
    }
    if (status['terbuka'] != true) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak ada sesi kas yang terbuka.')));
      return;
    }
    final kasSaatIni = (status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    if (!mounted) return;
    final hasilTutup = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogTutupKas(status: status!),
    );
    if (hasilTutup == null) return;

    final kodeLokal = (await CoreDb.instance.sesiKasAktif())?['kode'] as String?;
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_tutup', {
        'id_toko': Sesi.instance.tokoId,
        'kode': kodeLokal,
        'uang_fisik': hasilTutup['uangFisik'],
        'keterangan': hasilTutup['keterangan'],
      });
      if (kodeLokal != null) await CoreDb.instance.tutupSesiKasLokal(kodeLokal);
      if (mounted) setState(() => _kasTerbuka = false);
      final selisih = (hasil['selisih'] as num?)?.toDouble() ?? 0;
      final stokMenipis = ((hasil['stokMenipis'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kas Ditutup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kas Seharusnya: ${_formatRupiah.format(kasSaatIni)}'),
              Text('Uang Fisik: ${_formatRupiah.format(hasilTutup['uangFisik'])}'),
              const SizedBox(height: 8),
              Text('Selisih: ${_formatRupiah.format(selisih)}', style: TextStyle(fontWeight: FontWeight.bold, color: selisih < 0 ? Colors.red : Colors.green.shade700)),
              if (stokMenipis.isNotEmpty) ...[
                const Divider(height: 24),
                Text('${stokMenipis.length} Produk Perlu Direstok:', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: stokMenipis.map((p) => Text('• ${p['nama']} (stok ${p['stok']}, min ${p['stokMinimum']})', style: const TextStyle(fontSize: 12))).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menutup kas: $e')));
    }
  }

  Future<void> _bukaKas(double modalAwal) async {
    final kode = 'kas-${Sesi.instance.tokoId}-${DateTime.now().millisecondsSinceEpoch}';
    await CoreDb.instance.bukaSesiKasLokal(kode, modalAwal);
    if (mounted) setState(() => _kasTerbuka = true);
    try {
      await ApiClient.instance.aksi('sesi_kas_buka', {
        'id_toko': Sesi.instance.tokoId,
        'kode': kode,
        'modal_awal': modalAwal,
      });
    } catch (_) {
      // Gagal tersinkron ke server -- tetap dianggap terbuka secara lokal
      // (local-first), akan disinkron ulang saat "Sinkronkan Sekarang".
    }
  }

  Future<void> _perbaruiJumlahPending() async {
    final n = await CoreDb.instance.jumlahTransaksiPending();
    if (mounted) setState(() => _jumlahPending = n);
    unawaited(_muatKasSaatIni());
  }

  Future<void> _sinkronkanSekarang() async {
    if (_sinkronBerjalan) return;
    setState(() => _sinkronBerjalan = true);
    try {
      final pending = await CoreDb.instance.transaksiPendingBelumSinkron();
      var berhasil = 0;
      for (final row in pending) {
        final kodeUnik = row['kode_unik'] as String;
        final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        try {
          await ApiClient.instance.aksi('bayar', payload);
          await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
          berhasil++;
        } catch (e) {
          final pesan = e.toString();
          // Kode transaksi ini sudah pernah sampai di percobaan sebelumnya --
          // anggap SUKSES, bukan gagal (idempotensi retry offline-first).
          if (pesan.toLowerCase().contains('sudah tercatat')) {
            await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
            berhasil++;
          } else {
            await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
            if (e is ApiException && e.offline) break; // masih offline -- hentikan, coba lagi nanti
          }
        }
      }
      await _perbaruiJumlahPending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$berhasil dari ${pending.length} transaksi berhasil disinkron.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sinkronBerjalan = false);
    }
  }

  List<Produk> get _produkTersaring {
    return _semuaProduk.where((p) {
      final cocokKategori = _kategoriTerpilih == null || p.kategoriId == _kategoriTerpilih;
      final cocokKeyword = _kataKunci.isEmpty ||
          p.nama.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.kode.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.barcode.toLowerCase().contains(_kataKunci.toLowerCase());
      return cocokKategori && cocokKeyword;
    }).toList();
  }

  void _tambahKeKeranjang(Produk p) {
    setState(() {
      final existing = _keranjang.where((i) => i.produk.id == p.id).toList();
      if (existing.isNotEmpty) {
        existing.first.jumlah++;
      } else {
        _keranjang.add(ItemKeranjang(produk: p));
      }
    });
  }

  /// Dipanggil saat kasir menekan Enter di kotak pencarian -- padanan
  /// "Enter-keystroke detection" pada scanner barcode HID di pos-renderer.js:
  /// kalau kode/barcode COCOK PERSIS satu produk, langsung tambah ke
  /// keranjang & bersihkan kotak (siap utk scan berikutnya tanpa kasir perlu
  /// mengetuk apa pun).
  void _submitPencarian(String nilai) {
    final v = nilai.trim();
    if (v.isEmpty) return;
    final cocok = _semuaProduk.where((p) => p.kode == v || p.barcode == v).toList();
    if (cocok.isNotEmpty) {
      _tambahKeKeranjang(cocok.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${cocok.first.nama} ditambahkan'), duration: const Duration(milliseconds: 700)),
      );
      _kataKunciController.clear();
      setState(() => _kataKunci = '');
    }
  }

  double get _totalKeranjang => _keranjang.fold(0, (s, i) => s + i.subtotal);
  int get _jumlahItemKeranjang => _keranjang.fold(0, (s, i) => s + i.jumlah);

  Future<void> _bukaKeranjang() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KeranjangScreen(keranjang: _keranjang),
    ));
    await _perbaruiJumlahPending();
    setState(() {});
  }

  Future<void> _logout() async {
    await ApiClient.instance.hapusToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  bool _bukaLaciBerjalan = false;

  /// F6 Buka Laci -- padanan `pos:buka-laci-kasir` Electron (lihat JavaDoc
  /// `core_hw.bukaLaciKasir`): kirim pulsa ESC/POS ke printer default Windows
  /// yang laci fisiknya nyambung lewat kabelnya. Dipakai manual (mis. tukar
  /// uang tanpa transaksi) -- BUKAN otomatis saat checkout (itu tanggung
  /// jawab alur cetak struk terpisah, belum ada di Flutter).
  Future<void> _bukaLaci() async {
    if (_bukaLaciBerjalan) return;
    setState(() => _bukaLaciBerjalan = true);
    try {
      await bukaLaciKasir();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Laci kasir dibuka.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuka laci: $e')));
    } finally {
      if (mounted) setState(() => _bukaLaciBerjalan = false);
    }
  }

  /// "Update Sistem" -- pemicu MANUAL cek rilis GitHub terbaru (padanan
  /// pengecekan otomatis di `_GerbangAwal._cekUpdate` pada main.dart, yang
  /// hanya jalan sekali saat app baru dibuka) -- kasir bisa cek ulang kapan
  /// saja lewat toolbar ini tanpa perlu restart aplikasi dulu.
  Future<void> _cekUpdateManual() async {
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final info = await PackageInfo.fromPlatform();
      final hasil = await UpdateChecker.cekTerbaru(repoOwner: 'Zishof', repoName: 'zishof-platform', versiSaatIni: info.version);
      if (!mounted) return;
      Navigator.of(context).pop(); // tutup loading
      if (hasil == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sudah menggunakan versi terbaru.')));
        return;
      }
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Versi ${hasil.versi} Tersedia'),
          content: Text(hasil.catatanRilis.isEmpty ? 'Versi baru telah dirilis.' : hasil.catatanRilis),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Nanti')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse(hasil.urlExe ?? hasil.urlRilis), mode: LaunchMode.externalApplication);
              },
              child: const Text('Unduh'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memeriksa pembaruan: $e')));
    }
  }

  void _bukaBantuan() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BantuanScreen()));
  }

  void _bukaAkunSaya() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AkunSayaScreen()));
  }

  void _bukaLayarPelanggan() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LayarPelangganScreen()));
  }

  List<Widget> get _tombolAksi => [
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton.icon(
              onPressed: _toggleFokusKeranjang,
              icon: Icon(_fokusKeranjang ? Icons.grid_view_outlined : Icons.view_sidebar_outlined, size: 16),
              label: Text(_fokusKeranjang ? 'Tampilan Normal' : 'Fokus Keranjang', style: const TextStyle(fontSize: 12)),
            ),
          ),
          if (_kasSaatIni != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Kas Sekarang (saldo kas berjalan sesi ini)',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.latarLembut(AppColors.success), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.payments_outlined, size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(_formatRupiah.format(_kasSaatIni), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.account_circle_outlined), onPressed: _bukaAkunSaya, tooltip: 'Akun Saya'),
          IconButton(icon: const Icon(Icons.desktop_windows_outlined), onPressed: _bukaLayarPelanggan, tooltip: 'Layar Pelanggan (F9)'),
          IconButton(icon: const Icon(Icons.system_update_alt_outlined), onPressed: _cekUpdateManual, tooltip: 'Cek Update Sistem'),
          IconButton(
            icon: _bukaLaciBerjalan
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.point_of_sale),
            onPressed: _bukaLaciBerjalan ? null : _bukaLaci,
            tooltip: 'Buka Laci (F6)',
          ),
        ],
        IconButton(
          icon: Badge(
            label: Text('$_jumlahPending'),
            isLabelVisible: _jumlahPending > 0,
            child: _sinkronBerjalan
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
          ),
          onPressed: _sinkronBerjalan ? null : _sinkronkanSekarang,
          tooltip: 'Sinkronkan transaksi tertunda (F8)',
        ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: _muatAwal, tooltip: 'Muat ulang katalog'),
        if (Sesi.instance.wajibSesiKas && _kasTerbuka == true)
          IconButton(icon: const Icon(Icons.point_of_sale_outlined), onPressed: _bukaDialogTutupKas, tooltip: 'Tutup Kas'),
        if (defaultTargetPlatform == TargetPlatform.windows)
          IconButton(icon: const Icon(Icons.help_outline), onPressed: _bukaBantuan, tooltip: 'Bantuan (F1)'),
        IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Keluar'),
      ];

  /// Pintasan keyboard F1-F9 -- padanan pos-renderer.js `PETA_TOMBOL_KASIR`
  /// (F2-F5 Bayar/Tahan/Metode/Member milik KeranjangScreen, bukan layar ini,
  /// krn Kasir & Keranjang adalah 2 layar terpisah di Flutter/Android --
  /// hanya relevan di Windows lewat `PanelKeranjang` yang tertanam).
  /// Desktop-only (fisik keyboard) -- diam di Android via gerbang platform.
  KeyEventResult _tanganiTombolKasir(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      _bukaBantuan();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f6) {
      if (!_bukaLaciBerjalan) _bukaLaci();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f8) {
      if (!_sinkronBerjalan) _sinkronkanSekarang();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f9) {
      _bukaLayarPelanggan();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.f7) {
      _toggleFokusKeranjang();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _tanganiTombolKasir,
      child: AppShell(
      menuAktif: MenuEBisnis.kasir,
      judul: 'Kasir / POS',
      tampilkanJudul: false,
      scrollable: false,
      actionsAppBar: _tombolAksi,
      aksiHeader: Row(mainAxisSize: MainAxisSize.min, children: _tombolAksi),
      bottomBar: defaultTargetPlatform == TargetPlatform.windows || _keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ElevatedButton(
                  onPressed: _bukaKeranjang,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Keranjang ($_jumlahItemKeranjang)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(_formatRupiah.format(_totalKeranjang), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
      body: Stack(
        children: [
          _memuat
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
                            ElevatedButton(onPressed: _muatAwal, child: const Text('Coba Lagi')),
                          ],
                        ),
                      ),
                    )
                  : defaultTargetPlatform == TargetPlatform.windows
                      ? _bodyDesktop()
                      : _kontenKatalog(),
          if (_kasTerbuka == false && Sesi.instance.wajibSesiKas)
            _OverlayBukaKas(onBuka: (modal) {
              setState(() => _modalAwalKas = modal);
              _bukaKas(_modalAwalKas);
            }),
        ],
      ),
      ),
    );
  }

  /// Kartu Keranjang tertanam LANGSUNG di sisi kanan (padanan tampilan
  /// referensi Electron: grid+keranjang satu layar berdampingan, bukan
  /// navigasi terpisah spt Android) -- lihat JavaDoc `_fokusKeranjang` utk
  /// mode F7 yang menyembunyikan grid & melebarkan panel ini sendirian.
  Widget _bodyDesktop() {
    final panel = PanelKeranjang(
      keranjang: _keranjang,
      tampilkanJudul: true,
      aksiHeader: OutlinedButton.icon(
        onPressed: _toggleFokusKeranjang,
        icon: Icon(_fokusKeranjang ? Icons.grid_view_outlined : Icons.fullscreen, size: 14),
        label: Text(_fokusKeranjang ? 'Tampilan Normal (F7)' : 'Fokus Keranjang (F7)', style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
      ),
      onSelesai: _perbaruiJumlahPending,
    );
    if (_fokusKeranjang) {
      // Di-TENGAH horizontal (bukan topLeft) -- padanan referensi Electron:
      // saat katalog disembunyikan, panel Keranjang jadi satu-satunya fokus
      // layar, jadi ditaruh di tengah spt kartu modal, bukan menempel kiri
      // dgn area kosong besar di kanan.
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Fokus Keranjang TETAP butuh kotak cari/scan -- kasir masih
              // bisa menambah barang lain (mis. pelanggan minta tambah satu)
              // tanpa harus keluar dari mode ini dulu.
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _kotakPencarian()),
              Expanded(child: panel),
            ],
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _kontenKatalog()),
        const VerticalDivider(width: 1),
        SizedBox(width: 420, child: panel),
      ],
    );
  }

  Widget _kotakPencarian() {
    return TextField(
      controller: _kataKunciController,
      decoration: const InputDecoration(
        hintText: 'Cari / scan barcode produk...',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        isDense: true,
      ),
      onChanged: (v) => setState(() => _kataKunci = v),
      onSubmitted: _submitPencarian,
    );
  }

  Widget _kontenKatalog() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: _kotakPencarian(),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Semua'),
                  selected: _kategoriTerpilih == null,
                  onSelected: (_) => setState(() => _kategoriTerpilih = null),
                ),
              ),
              ..._kategori.map((k) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k.nama),
                      selected: _kategoriTerpilih == k.id,
                      onSelected: (_) => setState(() => _kategoriTerpilih = k.id),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Kolom RESPONSIF thd lebar layar -- SEBELUMNYA crossAxisCount
              // tetap 2 apa pun lebar jendela, jadi di Desktop lebar kartu
              // jadi ratusan piksel dan (krn childAspectRatio tetap)
              // tingginya ikut meregang sampai nama+harga terdorong keluar
              // area yang terlihat (tampak seperti kartu kosong).
              final kolom = (constraints.maxWidth / 190).floor().clamp(2, 6);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: kolom,
                  childAspectRatio: 0.92,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _produkTersaring.length,
                itemBuilder: (context, i) => _KartuProduk(
                  produk: _produkTersaring[i],
                  onTap: () => _tambahKeKeranjang(_produkTersaring[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Gerbang wajib "Buka Kas" -- kasir tidak bisa menyentuh apa pun di balik
/// overlay ini sampai mengisi modal awal & menekan "Buka Kas" (padanan gerbang
/// full-screen di pos-renderer.js: menjual tanpa sesi kas terbuka berarti
/// rekonsiliasi tutup-kas nanti tidak akan pernah cocok).
class _OverlayBukaKas extends StatefulWidget {
  final void Function(double modalAwal) onBuka;
  const _OverlayBukaKas({required this.onBuka});

  @override
  State<_OverlayBukaKas> createState() => _OverlayBukaKasState();
}

class _OverlayBukaKasState extends State<_OverlayBukaKas> {
  final _controller = TextEditingController(text: '0');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.point_of_sale, size: 48, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text('Buka Kas Terlebih Dahulu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Kasir wajib membuka sesi kas sebelum bisa mulai menjual.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Modal Awal (Rp)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final modal = double.tryParse(_controller.text.replaceAll(RegExp('[^0-9.]'), '')) ?? 0;
                        widget.onBuka(modal);
                      },
                      child: const Text('Buka Kas'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Palet warna "foto placeholder" berputar per produk (deterministik dari
/// nama, BUKAN acak tiap rebuild) -- sekadar variasi visual pengganti foto
/// asli (`gambarUrl` API ini selalu null di data uji), padanan kesan kartu
/// bergambar pada referensi tanpa berpura-pura ada foto sungguhan.
const _paletKartuProduk = [Color(0xFF2563EB), Color(0xFF0D9488), Color(0xFFC0563D), Color(0xFF7C3AED), Color(0xFFEA580C), Color(0xFF0284C7)];

class _KartuProduk extends StatelessWidget {
  final Produk produk;
  final VoidCallback onTap;
  const _KartuProduk({required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    final stokRendah = !habis && produk.stok <= 5;
    final warnaAvatar = _paletKartuProduk[produk.nama.isEmpty ? 0 : produk.nama.codeUnitAt(0) % _paletKartuProduk.length];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Opacity(
        opacity: habis ? 0.55 : 1,
        child: InkWell(
          onTap: habis ? null : onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(color: AppColors.latarLembut(warnaAvatar), borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                      child: Center(
                        child: Text(
                          produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?',
                          style: TextStyle(color: warnaAvatar, fontSize: 26, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: habis ? AppColors.danger : (stokRendah ? AppColors.warning : Colors.white),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)],
                        ),
                        child: Text(
                          habis ? 'Habis' : 'Stok ${produk.stok}',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: habis || stokRendah ? Colors.white : AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(produk.nama, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(_formatRupiah.format(produk.hargaJual), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13))),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(color: habis ? AppColors.border : AppColors.primary, shape: BoxShape.circle),
                          child: Icon(Icons.add, color: habis ? AppColors.textSecondary : Colors.white, size: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form Tutup Kas -- KPI sesi (dari `sesi_kas_status`) + input Uang Fisik
/// (pre-fill dgn Kas Seharusnya) + catatan wajib. Mengembalikan
/// {uangFisik, keterangan} lewat Navigator.pop kalau dikonfirmasi, null kalau
/// dibatalkan -- perhitungan selisih SENGAJA tidak dilakukan di sini (server
/// yang menghitung dari riwayat transaksi lengkap, lihat _bukaDialogTutupKas).
class _DialogTutupKas extends StatefulWidget {
  final Map<String, dynamic> status;
  const _DialogTutupKas({required this.status});

  @override
  State<_DialogTutupKas> createState() => _DialogTutupKasState();
}

class _DialogTutupKasState extends State<_DialogTutupKas> {
  late final TextEditingController _uangFisikController;
  final _keteranganController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final kasSaatIni = (widget.status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    _uangFisikController = TextEditingController(text: kasSaatIni.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _uangFisikController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  void _konfirmasi() {
    final uangFisik = double.tryParse(_uangFisikController.text.replaceAll(RegExp('[^0-9.]'), ''));
    if (uangFisik == null) {
      setState(() => _error = 'Uang fisik wajib diisi angka.');
      return;
    }
    if (_keteranganController.text.trim().isEmpty) {
      setState(() => _error = 'Catatan penutupan wajib diisi.');
      return;
    }
    Navigator.of(context).pop({'uangFisik': uangFisik, 'keterangan': _keteranganController.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    final modalAwal = (widget.status['modalAwal'] as num?)?.toDouble() ?? 0;
    final totalTunai = (widget.status['totalTunai'] as num?)?.toDouble() ?? 0;
    final totalNonTunai = (widget.status['totalNonTunai'] as num?)?.toDouble() ?? 0;
    final kasSaatIni = (widget.status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    return AlertDialog(
      title: const Text('Tutup Kas'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Modal Awal'), Text(_formatRupiah.format(modalAwal))]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Penjualan Tunai'), Text(_formatRupiah.format(totalTunai))]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Penjualan Non-Tunai'), Text(_formatRupiah.format(totalNonTunai))]),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [const Text('Kas Seharusnya', style: TextStyle(fontWeight: FontWeight.bold)), Text(_formatRupiah.format(kasSaatIni), style: const TextStyle(fontWeight: FontWeight.bold))],
              ),
              const SizedBox(height: 16),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              TextField(
                controller: _uangFisikController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Uang Fisik (hasil hitung aktual) *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keteranganController,
                decoration: const InputDecoration(labelText: 'Catatan Penutupan *', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Batal')),
        ElevatedButton(onPressed: _konfirmasi, child: const Text('Tutup Kas')),
      ],
    );
  }
}
