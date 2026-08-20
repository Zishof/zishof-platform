import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/aturan_diskon.dart';
import '../models/keranjang_item.dart';
import '../services/api_client.dart';
import '../services/keranjang.dart';
import '../services/server_config.dart';
import '../services/sesi.dart';
import '../widgets/format.dart';
import '../widgets/panel_galat.dart';
import 'login_screen.dart';
import 'pengaturan_server_screen.dart';
import '../widgets/app_shell.dart';
import '../widgets/navigasi.dart';

/// Beranda member: ringkasan saldo, pemilih toko, dan katalog produk.
class BerandaScreen extends StatefulWidget {
  const BerandaScreen({super.key});

  @override
  State<BerandaScreen> createState() => _BerandaScreenState();
}

class _BerandaScreenState extends State<BerandaScreen> {
  bool _memuat = true;
  String? _galat;

  List<Map<String, dynamic>> _toko = [];
  String? _idTokoAktif;

  final _cari = TextEditingController();
  List<Map<String, dynamic>> _produk = [];
  int _halaman = 1;
  int _totalProduk = 0;
  static const int _perHalaman = 12;
  bool _memuatProduk = false;

  @override
  void initState() {
    super.initState();
    _muatAwal();
    Keranjang.instance.addListener(_gambarUlang);
  }

  @override
  void dispose() {
    Keranjang.instance.removeListener(_gambarUlang);
    _cari.dispose();
    super.dispose();
  }

  void _gambarUlang() {
    if (mounted) setState(() {});
  }

  Future<void> _muatAwal() async {
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final info = await ApiClient.instance.aksi('kantin_info', const {});
      final data = info['data'];
      if (data is Map) {
        Sesi.instance.terapkanInfo(data.map((k, v) => MapEntry('$k', v)));
      }

      final tokoRes =
          await ApiClient.instance.aksi('kantin_toko_list', const {});
      _toko = ApiClient.instance.daftar(tokoRes);
      if (_toko.isNotEmpty) {
        _idTokoAktif ??= '${_toko.first['id']}';
      }

      // Aturan diskon ditarik sekali lalu dipakai ulang utk seluruh keranjang.
      final diskonRes =
          await ApiClient.instance.aksi('kantin_aturan_diskon', const {});
      Keranjang.instance.setAturan(ApiClient.instance
          .daftar(diskonRes)
          .map(AturanDiskon.dariJson)
          .toList());

      await _muatProduk();
      if (!mounted) return;
      setState(() => _memuat = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      // Token kedaluwarsa/ditolak -> kembali ke layar Masuk, jangan biarkan
      // pengguna terjebak di beranda kosong tanpa penjelasan.
      if (e.kodeStatus == '98' || e.kodeStatus == '97') {
        await Sesi.instance.keluar();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }
      setState(() {
        _memuat = false;
        _galat = e.pesan;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _memuat = false;
        _galat = '$e';
      });
    }
  }

  Future<void> _muatProduk() async {
    if (_idTokoAktif == null) {
      setState(() => _produk = []);
      return;
    }
    setState(() => _memuatProduk = true);
    try {
      final res = await ApiClient.instance.aksi('kantin_produk_list', {
        'id_toko': _idTokoAktif,
        'keyword': _cari.text.trim(),
        'page': _halaman,
        'limit': _perHalaman,
      });
      _produk = ApiClient.instance.daftar(res);
      _totalProduk = (res['total'] as num?)?.toInt() ?? _produk.length;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.pesan)));
      }
    } finally {
      if (mounted) setState(() => _memuatProduk = false);
    }
  }

  Future<void> _segarkanSaldo() async {
    try {
      final res = await ApiClient.instance.aksi('kantin_saldo', const {});
      final saldo = res['data'];
      if (saldo is num) Sesi.instance.saldo = saldo.round();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.pesan)));
      }
    }
  }

  void _tambahKeKeranjang(Map<String, dynamic> p) {
    final namaToko = _toko.firstWhere(
      (t) => '${t['id']}' == '${p['id_toko']}',
      orElse: () => const {'nama': ''},
    )['nama'];
    Keranjang.instance.tambah(KeranjangItem(
      id: '${p['id']}',
      kode: '${p['kode'] ?? ''}',
      nama: '${p['nama'] ?? ''}',
      harga: (p['harga'] as num?)?.toDouble() ?? 0,
      idToko: '${p['id_toko']}',
      namaToko: '$namaToko',
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${p['nama']} ditambahkan ke keranjang'),
      duration: const Duration(milliseconds: 900),
    ));
  }

  /// Notifikasi belum punya aksi API tersendiri, jadi dibuka lewat jembatan
  /// sesi web (mobile_auth.jsp) -- pengguna tidak perlu login ulang.
  Future<void> _bukaNotifikasi() async {
    final token = Sesi.instance.token;
    if (token == null || token.isEmpty) return;
    final url = ServerConfig.instance.urlJembatan(token, tujuan: 'notifikasi');
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka notifikasi.')));
    }
  }

  Future<void> _keluar() async {
    await Sesi.instance.keluar();
    Keranjang.instance.kosongkan();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final totalHalaman =
        _totalProduk == 0 ? 1 : ((_totalProduk - 1) ~/ _perHalaman) + 1;

    return AppShell(
      menuAktif: MenuAnggota.belanja,
      judul: 'Belanja',
      subjudul: 'Pilih toko, lalu tambahkan produk ke keranjang.',
      onPilihMenu: navigasiMenu,
      aksi: [
        IconButton(
          tooltip: 'Notifikasi',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: _bukaNotifikasi,
        ),
        IconButton(
          tooltip: 'Alamat Server',
          icon: const Icon(Icons.dns_outlined),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PengaturanServerScreen())),
        ),
        IconButton(
          tooltip: 'Keluar',
          icon: const Icon(Icons.logout),
          onPressed: _keluar,
        ),
      ],
      floatingActionButton: Keranjang.instance.items.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => navigasiMenu(context, MenuAnggota.keranjang),
              icon: Badge.count(
                count: Keranjang.instance.jumlahItem,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              label: Text(rupiah(Keranjang.instance.grandTotal)),
            ),
      child: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: PanelGalat(pesan: _galat!, onCobaLagi: _muatAwal),
                )
              : RefreshIndicator(
                  onRefresh: _muatAwal,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _kartuSaldo(),
                      const SizedBox(height: 12),
                      _pemilihToko(),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _cari,
                        decoration: InputDecoration(
                          hintText: 'Cari produk (nama atau kode)',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _cari.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _cari.clear();
                                    _halaman = 1;
                                    _muatProduk();
                                  },
                                ),
                        ),
                        onSubmitted: (_) {
                          _halaman = 1;
                          _muatProduk();
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_memuatProduk)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_produk.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                              child: Text('Tidak ada produk pada toko ini.')),
                        )
                      else
                        _gridProduk(),
                      if (!_memuatProduk && totalHalaman > 1) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _halaman > 1
                                  ? () {
                                      _halaman--;
                                      _muatProduk();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Text('Hal $_halaman / $totalHalaman'),
                            IconButton(
                              onPressed: _halaman < totalHalaman
                                  ? () {
                                      _halaman++;
                                      _muatProduk();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _kartuSaldo() {
    final sesi = Sesi.instance;
    final warna = Theme.of(context).colorScheme;
    return Card(
      color: warna.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sesi.kode.isEmpty ? 'Member' : 'Kode ${sesi.kode}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  if (sesi.tampilkanSaldo) ...[
                    Text(sesi.labelSaldo, style: const TextStyle(fontSize: 12)),
                    Text(rupiah(sesi.saldo),
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                  if (sesi.tampilkanCashback) ...[
                    const SizedBox(height: 6),
                    Text('${sesi.labelCashback}: ${rupiah(sesi.sisaCashback)}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                  if (sesi.minimalSaldo > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Saldo mengendap minimal ${rupiah(sesi.minimalSaldo)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Segarkan saldo',
              onPressed: _segarkanSaldo,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pemilihToko() {
    if (_toko.isEmpty) {
      return const Text('Belum ada toko aktif.');
    }
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _toko.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = _toko[i];
          final id = '${t['id']}';
          final aktif = id == _idTokoAktif;
          return ChoiceChip(
            label: Text('${t['nama'] ?? ''}'),
            selected: aktif,
            onSelected: (_) {
              setState(() {
                _idTokoAktif = id;
                _halaman = 1;
              });
              _muatProduk();
            },
          );
        },
      ),
    );
  }

  Widget _gridProduk() {
    return LayoutBuilder(builder: (context, c) {
      final kolom = c.maxWidth > 900
          ? 4
          : c.maxWidth > 600
              ? 3
              : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: kolom,
          childAspectRatio: 0.82,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: _produk.length,
        itemBuilder: (context, i) {
          final p = _produk[i];
          final harga = (p['harga'] as num?)?.toDouble() ?? 0;
          return Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        ServerConfig.instance.urlGambarProduk(p['id']),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        // Produk tanpa lampiran tetap dilayani server (ikon
                        // bawaan), dan koneksi bisa gagal -- keduanya jatuh ke
                        // ikon lokal supaya kartu tidak pernah kosong.
                        errorBuilder: (context, error, stack) => Center(
                          child: Icon(Icons.fastfood_outlined,
                              size: 40,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        loadingBuilder: (context, anak, progres) =>
                            progres == null
                                ? anak
                                : const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                      ),
                    ),
                  ),
                  Text(
                    '${p['nama'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(rupiah(harga),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          textStyle: const TextStyle(fontSize: 12)),
                      onPressed: () => _tambahKeKeranjang(p),
                      child: const Text('Tambah'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}
