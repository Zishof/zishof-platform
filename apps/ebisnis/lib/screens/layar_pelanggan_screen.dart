import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
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

  @override
  void initState() {
    super.initState();
    _ambil();
    _timer =
        Timer.periodic(const Duration(milliseconds: 1500), (_) => _ambil());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _ambil() async {
    try {
      final hasil = await ApiClient.instance.aksi('layar_pelanggan_ambil',
          {'toko_id': widget.tokoIdOverride ?? Sesi.instance.tokoId});
      if (!mounted) return;
      final aktif = hasil['aktif'] == true;
      setStateIfMounted(() {
        _aktif = aktif;
        if (aktif) {
          _items = ((hasil['items'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _subtotal = (hasil['subtotal'] as num?)?.toDouble() ?? 0;
          _diskon = (hasil['diskon'] as num?)?.toDouble() ?? 0;
          _total = (hasil['total'] as num?)?.toDouble() ?? 0;
          final nama = hasil['memberNama'] as String?;
          _memberNama = (nama == null || nama.isEmpty) ? null : nama;
        } else {
          _items = [];
          _memberNama = null;
        }
      });
    } catch (_) {
      // Gagal poll (mis. offline sesaat) -- biarkan tampilan terakhir yang
      // masih ada, jangan kedip ke Idle.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1C2E),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: _aktif
            ? _bodyAktif(key: const ValueKey('aktif'))
            : _bodyIdle(key: const ValueKey('idle')),
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
