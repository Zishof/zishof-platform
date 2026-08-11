import 'dart:async';

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

  @override
  void initState() {
    super.initState();
    _daftarkanLiveChannel();
    _ambil();
    _timer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _ambil());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerSukses?.cancel();
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
                : _bodyIdle(key: const ValueKey('idle'))),
      ),
    );
  }

  Widget _bodyIdle({required Key key}) {
    return Center(
      key: key,
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
