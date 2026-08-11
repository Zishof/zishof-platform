import 'dart:async';

import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../sesi.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

/// Layar Pelanggan (customer display, spec §16) -- dijalankan di perangkat
/// KEDUA (HP/tablet/PC terpisah, atau jendela kedua) yang menampilkan isi
/// keranjang kasir secara langsung ke pelanggan. TIDAK dibungkus [AppShell]
/// (tanpa sidebar/topbar admin) krn ini kiosk-style, mengisi layar penuh.
///
/// Model: polling `layar_pelanggan_ambil` tiap ~1.5 detik -- server menyimpan
/// state siaran terakhir per-toko di memori (TTL 90 detik, lihat
/// LayarPelangganBroadcaster), jadi TIDAK perlu websocket/push. Kembali ke
/// Idle otomatis begitu kasir berhenti menyiarkan (pindah layar/transaksi
/// selesai) atau TTL kedaluwarsa.
class LayarPelangganScreen extends StatefulWidget {
  /// `true` HANYA saat layar ini berjalan sbg jendela desktop KEDUA sungguhan
  /// (dibuat `desktop_multi_window` dari tombol/menu Layar Pelanggan).
  /// Penutupan jendela desktop dikelola dari jendela kasir melalui launcher,
  /// supaya tampilan pelanggan tetap bersih tanpa toolbar internal.
  final bool jendelaKedua;
  final int? tokoIdOverride;
  final String? tokoNamaOverride;
  final String? pesanTerimaKasihOverride;

  const LayarPelangganScreen(
      {super.key,
      this.jendelaKedua = false,
      this.tokoIdOverride,
      this.tokoNamaOverride,
      this.pesanTerimaKasihOverride});

  @override
  State<LayarPelangganScreen> createState() => _LayarPelangganScreenState();
}

class _LayarPelangganScreenState extends State<LayarPelangganScreen> {
  Timer? _timer;
  bool _aktif = false;
  List<Map<String, dynamic>> _items = [];
  double _subtotal = 0;
  double _diskon = 0;
  double _total = 0;
  String? _memberNama;
  bool _sedangAmbil = false;
  int _versiTerakhir = 0;
  DateTime? _liveUpdateTerakhir;

  // "Survey Kepuasan Pelanggan" -- state KETIGA di luar idle/aktif, dipicu
  // saat `tipe` broadcast berubah jadi "sukses" (lihat JavaDoc
  // LayarPelangganBroadcaster.kirimSukses). [_tipeSebelumnya] dipakai deteksi
  // "rising edge" (bukan `versi`, krn `layar_pelanggan_ambil` -- jalur polling
  // murni tanpa live channel -- TIDAK mengembalikan `versi` sama sekali) supaya
  // broadcast "sukses" yang SAMA tidak memicu ulang layar rating berkali-kali
  // selama masih terpoll, tapi transaksi SUKSES berikutnya tetap memicu lagi.
  String _tipeSebelumnya = 'keranjang';
  bool _tampilkanSukses = false;
  Timer? _timerSukses;
  int? _ratingDipilih;
  bool _mengirimRating = false;

  // "Screensaver" -- state KEEMPAT, menyala setelah idle (tanpa transaksi)
  // selama [_configScreensaver.idleDetik] detik berturut-turut. Konten (daftar
  // gambar + pengaturan tampilan) dimuat SEKALI di initState (supaya durasi
  // idle siklus PERTAMA sudah pakai nilai konfigurasi sungguhan, bukan
  // default tebakan), lalu disegarkan ULANG setiap kali screensaver benar-benar
  // menyala (lihat JavaDoc server `KantinHelper.layarPelangganSlideUntukTampil`)
  // supaya gambar baru yg diunggah admin dari Konfigurasi ikut muncul tanpa
  // perlu me-restart aplikasi Layar Pelanggan.
  Timer? _timerIdleScreensaver;
  Timer? _timerSlideAdvance;
  Map<String, dynamic>? _configScreensaver;
  List<Map<String, dynamic>> _slideScreensaver = [];
  int _indexSlide = 0;
  bool _tampilkanScreensaver = false;

  @override
  void initState() {
    super.initState();
    _daftarkanLiveChannel();
    _ambil();
    _muatKontenScreensaver();
    _timer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _ambil());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerSukses?.cancel();
    _timerIdleScreensaver?.cancel();
    _timerSlideAdvance?.cancel();
    unawaited(LayarPelangganBroadcaster.channel.setMethodCallHandler(null));
    super.dispose();
  }

  Future<void> _daftarkanLiveChannel() async {
    try {
      await LayarPelangganBroadcaster.channel.setMethodCallHandler((call) async {
        if (call.method != 'update') return null;
        final data = Map<String, dynamic>.from(call.arguments as Map);
        _terapkanData(data, dariLive: true);
        return true;
      });
    } catch (_) {
      // Jika channel tidak tersedia (mis. fallback mobile), polling tetap jalan.
    }
  }

  /// Muat konfigurasi + daftar gambar screensaver. Dipanggil di [initState]
  /// (mengisi durasi idle utk siklus pertama) DAN setiap kali
  /// [_mulaiTimerIdleScreensaver] benar-benar habis (menyegarkan konten
  /// sebelum tampil) -- lihat catatan di deklarasi field di atas.
  Future<void> _muatKontenScreensaver() async {
    try {
      final hasil = await ApiClient.instance.aksi('layar_pelanggan_slide_untuk_tampil', {
        'toko_id': widget.tokoIdOverride ?? Sesi.instance.tokoId,
        'id_mesin': IdentitasMesin.instance.idMesin,
      });
      if (!mounted) return;
      final cfg = (hasil['config'] as Map?) != null
          ? Map<String, dynamic>.from(hasil['config'] as Map)
          : null;
      final slide = ((hasil['slides'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setStateIfMounted(() {
        _configScreensaver = cfg;
        _slideScreensaver = slide;
      });
    } catch (_) {
      // Gagal muat -- screensaver tetap OFF (aman), idle biasa tampil terus.
    }
  }

  int get _idleDetikTerkonfigurasi =>
      (_configScreensaver?['idleDetik'] as num?)?.toInt() ?? 30;

  void _mulaiTimerIdleScreensaver() {
    _timerIdleScreensaver?.cancel();
    _timerIdleScreensaver =
        Timer(Duration(seconds: _idleDetikTerkonfigurasi), () async {
      if (!mounted) return;
      // Segarkan konten dulu (gambar baru/pengaturan berubah) sebelum tampil.
      await _muatKontenScreensaver();
      if (!mounted) return;
      final cfg = _configScreensaver;
      if (cfg == null || cfg['aktif'] != true || _slideScreensaver.isEmpty) {
        return; // Screensaver dimatikan admin atau belum ada gambar -- tetap idle biasa.
      }
      setStateIfMounted(() {
        _indexSlide = 0;
        _tampilkanScreensaver = true;
      });
      _mulaiSlideAdvance();
    });
  }

  void _mulaiSlideAdvance() {
    _timerSlideAdvance?.cancel();
    final durasi = (_configScreensaver?['durasiDetik'] as num?)?.toInt() ?? 6;
    _timerSlideAdvance =
        Timer.periodic(Duration(seconds: durasi), (_) {
      if (!mounted || _slideScreensaver.isEmpty) return;
      setStateIfMounted(
          () => _indexSlide = (_indexSlide + 1) % _slideScreensaver.length);
    });
  }

  void _batalkanScreensaver() {
    _timerIdleScreensaver?.cancel();
    _timerSlideAdvance?.cancel();
    if (_tampilkanScreensaver) {
      setStateIfMounted(() => _tampilkanScreensaver = false);
    }
  }

  void _terapkanData(Map<String, dynamic> hasil, {bool dariLive = false}) {
    if (!mounted) return;
    if (dariLive) {
      _liveUpdateTerakhir = DateTime.now();
    } else {
      final liveUpdateTerakhir = _liveUpdateTerakhir;
      if (liveUpdateTerakhir != null &&
          DateTime.now().difference(liveUpdateTerakhir) <
              const Duration(milliseconds: 900)) {
        return;
      }
    }
    final versi = (hasil['versi'] as num?)?.toInt();
    if (versi != null && versi < _versiTerakhir) return;
    if (versi != null) _versiTerakhir = versi;
    final aktif = hasil['aktif'] == true;
    final tipe = aktif ? ((hasil['tipe'] as String?) ?? 'keranjang') : 'keranjang';
    final suksesBaru = tipe == 'sukses' && _tipeSebelumnya != 'sukses';
    _tipeSebelumnya = tipe;
    setStateIfMounted(() {
      _aktif = aktif;
      if (suksesBaru) {
        _mulaiTampilkanSukses();
      } else if (tipe != 'sukses') {
        // Broadcast pindah balik ke "keranjang" (kasir mulai transaksi baru)
        // ATAU kembali idle -- jangan menahan layar rating lebih lama dari itu.
        _tampilkanSukses = false;
      }
      if (aktif && tipe != 'sukses') {
        _items = ((hasil['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _subtotal = (hasil['subtotal'] as num?)?.toDouble() ?? 0;
        _diskon = (hasil['diskon'] as num?)?.toDouble() ?? 0;
        _total = (hasil['total'] as num?)?.toDouble() ?? 0;
        final nama =
            (hasil['memberNama'] ?? hasil['member_nama']) as String?;
        _memberNama = (nama == null || nama.isEmpty) ? null : nama;
      } else if (!aktif) {
        _items = [];
        _memberNama = null;
      }
      // Screensaver HANYA relevan saat benar-benar idle (tanpa transaksi &
      // bukan layar rating) -- transaksi baru atau layar sukses SELALU
      // membatalkan screensaver seketika, kasir tak boleh tertutupi gambar.
      if (aktif || suksesBaru || tipe == 'sukses') {
        _batalkanScreensaver();
      } else if (!aktif && !_tampilkanScreensaver && _timerIdleScreensaver == null) {
        _mulaiTimerIdleScreensaver();
      }
    });
  }

  /// Buka layar ucapan terima kasih + rating, otomatis kembali ke Idle
  /// setelah ~15 detik kalau pelanggan tidak menyentuh bintang apa pun.
  void _mulaiTampilkanSukses() {
    _timerSukses?.cancel();
    _tampilkanSukses = true;
    _ratingDipilih = null;
    _mengirimRating = false;
    _timerSukses = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setStateIfMounted(() => _tampilkanSukses = false);
      _mulaiTimerIdleScreensaver();
    });
  }

  Future<void> _kirimRating(int rating) async {
    if (_mengirimRating || _ratingDipilih != null) return;
    _timerSukses?.cancel();
    setStateIfMounted(() {
      _ratingDipilih = rating;
      _mengirimRating = true;
    });
    try {
      await ApiClient.instance.aksi('survey_kepuasan_simpan', {
        'rating': rating,
        'toko_id': widget.tokoIdOverride ?? Sesi.instance.tokoId,
      });
    } catch (_) {
      // Gagal kirim (mis. offline sesaat) -- bukan blocker, layar tetap
      // menampilkan ucapan terima kasih lalu kembali ke Idle spt biasa.
    }
    if (!mounted) return;
    setStateIfMounted(() => _mengirimRating = false);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setStateIfMounted(() => _tampilkanSukses = false);
    _mulaiTimerIdleScreensaver();
  }

  Future<void> _ambil() async {
    if (_sedangAmbil) return;
    _sedangAmbil = true;
    try {
      final hasil = await ApiClient.instance.aksi('layar_pelanggan_ambil',
          {'toko_id': widget.tokoIdOverride ?? Sesi.instance.tokoId});
      _terapkanData(hasil);
    } catch (_) {
      // Gagal poll (mis. offline sesaat) -- biarkan tampilan terakhir yang
      // masih ada, jangan kedip ke Idle.
    } finally {
      _sedangAmbil = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1C2E),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _tampilkanSukses
            ? _bodySukses(key: const ValueKey('sukses'))
            : (_aktif
                ? _bodyAktif(key: const ValueKey('aktif'))
                : (_tampilkanScreensaver
                    ? _bodyScreensaver(key: const ValueKey('screensaver'))
                    : _bodyIdle(key: const ValueKey('idle')))),
      ),
    );
  }

  Widget _bodyIdleKonten() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.storefront_outlined,
                color: Color(0xFF2563EB), size: 44),
          ),
          const SizedBox(height: 24),
          Text(
            (widget.tokoNamaOverride ?? Sesi.instance.tokoNama).isEmpty
                ? 'Selamat Datang'
                : (widget.tokoNamaOverride ?? Sesi.instance.tokoNama),
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text('Terima kasih telah berbelanja bersama kami',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _bodyIdle({required Key key}) {
    return SizedBox.expand(key: key, child: _bodyIdleKonten());
  }

  /// Screensaver slideshow -- menyala setelah idle berkepanjangan (lihat
  /// [_mulaiTimerIdleScreensaver]). Mode `SETENGAH` membagi layar: separuh
  /// atas tetap branding toko (spt Idle biasa), separuh bawah gambar berputar
  /// -- mode `FULLSCREEN` (default) gambar mengisi seluruh layar.
  Widget _bodyScreensaver({required Key key}) {
    final mode = (_configScreensaver?['modeTampilan'] as String?) ?? 'FULLSCREEN';
    final slideshow = _ScreensaverSlideshow(
      slides: _slideScreensaver,
      index: _indexSlide,
      animasi: (_configScreensaver?['animasi'] as String?) ?? 'FADE',
      durasiDetik: (_configScreensaver?['durasiDetik'] as num?)?.toInt() ?? 6,
    );
    if (mode == 'SETENGAH') {
      return Column(key: key, children: [
        Expanded(child: _bodyIdleKonten()),
        Expanded(child: slideshow),
      ]);
    }
    return SizedBox.expand(key: key, child: slideshow);
  }

  /// Layar "Survey Kepuasan Pelanggan" -- muncul tepat setelah transaksi
  /// sukses (`tipe == 'sukses'`, lihat [_terapkanData]/[_mulaiTampilkanSukses]).
  /// Ketuk bintang mana pun mengirim `survey_kepuasan_simpan` sekali (bintang
  /// tak bisa diganti setelah terkirim), lalu kembali ke Idle otomatis.
  Widget _bodySukses({required Key key}) {
    final sudahDinilai = _ratingDipilih != null;
    return Center(
      key: key,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: Icon(
                sudahDinilai
                    ? Icons.check_circle_outline
                    : Icons.favorite_outline,
                color: const Color(0xFF2E7D32),
                size: 44),
          ),
          const SizedBox(height: 24),
          const Text('Terima Kasih Atas Kunjungan Anda!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            sudahDinilai
                ? 'Terima kasih atas penilaian Anda.'
                : 'Bagaimana pengalaman belanja Anda hari ini?',
            style: const TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final nilai = i + 1;
              final terisi = _ratingDipilih != null && nilai <= _ratingDipilih!;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: IconButton(
                  iconSize: 52,
                  onPressed: sudahDinilai ? null : () => _kirimRating(nilai),
                  icon: Icon(
                    terisi ? Icons.star : Icons.star_border,
                    color: const Color(0xFFFACC15),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _bodyAktif({required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_cart, color: Colors.white70),
              const SizedBox(width: 10),
              const Text('Belanja Anda',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_memberNama != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.person, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(_memberNama!,
                        style: const TextStyle(color: Colors.white70)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text('Menunggu barang...',
                        style: TextStyle(color: Colors.white38, fontSize: 18)))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => Divider(
                        color: Colors.white.withValues(alpha: 0.08), height: 1),
                    itemBuilder: (context, i) {
                      final it = _items[i];
                      final nama = (it['nama'] as String?) ?? '-';
                      final jumlah = (it['jumlah'] as num?)?.toInt() ?? 0;
                      final harga = (it['harga'] as num?)?.toDouble() ?? 0;
                      final subtotal = (it['subtotal'] as num?)?.toDouble() ??
                          (harga * jumlah);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(nama,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                      '$jumlah x ${_formatRupiah.format(harga)}',
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 13)),
                                ],
                              ),
                            ),
                            Text(_formatRupiah.format(subtotal),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _barisTotal('Subtotal', _subtotal, warna: Colors.white70),
                if (_diskon > 0)
                  _barisTotal('Diskon', -_diskon,
                      warna: const Color(0xFFEA580C)),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(color: Colors.white24, height: 1)),
                _barisTotal('Total Bayar', _total,
                    warna: Colors.white, besar: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _barisTotal(String label, double nilai,
      {required Color warna, bool besar = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: warna,
                  fontSize: besar ? 20 : 15,
                  fontWeight: besar ? FontWeight.bold : FontWeight.normal)),
          Text(
            '${nilai < 0 ? '-' : ''}${_formatRupiah.format(nilai.abs())}',
            style: TextStyle(
                color: warna,
                fontSize: besar ? 24 : 15,
                fontWeight: besar ? FontWeight.bold : FontWeight.normal),
          ),
        ],
      ),
    );
  }
}

/// Widget slideshow murni (tanpa state polling apa pun) -- menampilkan satu
/// gambar (`slides[index]`) dengan salah satu dari 4 efek transisi. Index
/// dikendalikan dari LUAR ([_LayarPelangganScreenState._timerSlideAdvance])
/// supaya widget ini tetap simpel/stateless dan mudah diuji terpisah.
class _ScreensaverSlideshow extends StatelessWidget {
  final List<Map<String, dynamic>> slides;
  final int index;
  final String animasi;
  final int durasiDetik;

  const _ScreensaverSlideshow({
    required this.slides,
    required this.index,
    required this.animasi,
    required this.durasiDetik,
  });

  @override
  Widget build(BuildContext context) {
    if (slides.isEmpty) return const SizedBox.shrink();
    final slide = slides[index % slides.length];
    final url = slide['urlGambar'] as String?;
    final gambar = url == null
        ? const SizedBox.shrink()
        : Image.network(url, key: ValueKey(slide['id']), fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());

    switch (animasi) {
      case 'SLIDE':
        return ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            transitionBuilder: (child, anim) {
              final masuk = Tween<Offset>(
                      begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
              return SlideTransition(position: masuk, child: child);
            },
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [...previousChildren, if (currentChild != null) currentChild],
            ),
            child: SizedBox.expand(key: ValueKey(slide['id']), child: gambar),
          ),
        );
      case 'ZOOM':
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
          child: SizedBox.expand(key: ValueKey(slide['id']), child: gambar),
        );
      case 'KEN_BURNS':
        return ClipRect(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 900),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(slide['id']),
              tween: Tween(begin: 1.0, end: 1.12),
              duration: Duration(seconds: durasiDetik),
              curve: Curves.linear,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: SizedBox.expand(child: gambar),
            ),
          ),
        );
      case 'FADE':
      default:
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 900),
          child: SizedBox.expand(key: ValueKey(slide['id']), child: gambar),
        );
    }
  }
}
