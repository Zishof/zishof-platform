import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import 'keranjang_screen.dart';

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
        ..caraBayar = ((konfig['caraBayar'] as List?) ?? [])
            .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
            .toList();

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
    } catch (_) {
      // Offline saat cek status -- pakai sumber lokal (local-first, sama spt Electron).
      final lokal = await CoreDb.instance.sesiKasAktif();
      if (mounted) setState(() => _kasTerbuka = lokal != null);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(Sesi.instance.tokoNama.isEmpty ? 'eBisnis' : Sesi.instance.tokoNama),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('$_jumlahPending'),
              isLabelVisible: _jumlahPending > 0,
              child: _sinkronBerjalan
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
            ),
            onPressed: _sinkronBerjalan ? null : _sinkronkanSekarang,
            tooltip: 'Sinkronkan transaksi tertunda',
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _muatAwal, tooltip: 'Muat ulang katalog'),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Keluar'),
        ],
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
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: TextField(
                            controller: _kataKunciController,
                            decoration: const InputDecoration(
                              hintText: 'Cari / scan barcode produk...',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _kataKunci = v),
                            onSubmitted: _submitPencarian,
                          ),
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
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.82,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _produkTersaring.length,
                            itemBuilder: (context, i) => _KartuProduk(
                              produk: _produkTersaring[i],
                              onTap: () => _tambahKeKeranjang(_produkTersaring[i]),
                            ),
                          ),
                        ),
                      ],
                    ),
          if (_kasTerbuka == false)
            _OverlayBukaKas(onBuka: (modal) {
              setState(() => _modalAwalKas = modal);
              _bukaKas(_modalAwalKas);
            }),
        ],
      ),
      bottomNavigationBar: _keranjang.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ElevatedButton(
                  onPressed: _bukaKeranjang,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC0563D),
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
                  const Icon(Icons.point_of_sale, size: 48, color: Color(0xFF1E3A5F)),
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

class _KartuProduk extends StatelessWidget {
  final Produk produk;
  final VoidCallback onTap;
  const _KartuProduk({required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: habis ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF1E3A5F),
                    child: Text(
                      produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              Text(produk.nama, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(_formatRupiah.format(produk.hargaJual), style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
              Text(habis ? 'Habis' : 'Stok ${produk.stok}', style: TextStyle(fontSize: 11, color: habis ? Colors.red : Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}
