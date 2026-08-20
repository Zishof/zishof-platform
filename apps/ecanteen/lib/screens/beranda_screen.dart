import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/aturan_diskon.dart';
import '../models/keranjang_item.dart';
import '../services/api_client.dart';
import '../services/keranjang.dart';
import '../services/server_config.dart';
import '../services/sesi.dart';
import '../theme/app_colors.dart';
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
                        _kosong(
                          Icons.search_off,
                          _cari.text.trim().isEmpty
                              ? 'Belum ada produk'
                              : 'Produk tidak ditemukan',
                          _cari.text.trim().isEmpty
                              ? 'Toko ini belum memasang produk apa pun. Coba pilih toko lain.'
                              : 'Tidak ada produk yang cocok dengan pencarian Anda di toko ini.',
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

  /// Kartu saldo: satu-satunya elemen bergradasi di halaman ini, sekaligus
  /// pintasan ke Isi Saldo dan Bayar QR supaya anggota tidak perlu membuka
  /// menu untuk dua aksi yang paling sering dipakai.
  Widget _kartuSaldo() {
    final sesi = Sesi.instance;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gradasiSaldoAwal, AppColors.gradasiSaldoAkhir],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.gradasiSaldoAkhir.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sesi.nama.isEmpty ? 'Anggota' : sesi.nama,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sesi.kode.isNotEmpty)
                      Text('Kode ${sesi.kode}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Segarkan saldo',
                onPressed: _segarkanSaldo,
                icon: const Icon(Icons.refresh, color: Colors.white70),
              ),
            ],
          ),
          if (sesi.tampilkanSaldo) ...[
            const SizedBox(height: 10),
            Text(sesi.labelSaldo,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              rupiah(sesi.saldo),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  height: 1.1),
            ),
          ],
          if (sesi.tampilkanCashback || sesi.minimalSaldo > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (sesi.tampilkanCashback)
                  _pil('${sesi.labelCashback} ${rupiah(sesi.sisaCashback)}',
                      Icons.card_giftcard_outlined),
                if (sesi.minimalSaldo > 0)
                  _pil('Mengendap min. ${rupiah(sesi.minimalSaldo)}',
                      Icons.lock_outline),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (sesi.aktifkanTopup)
                Expanded(
                  child: _tombolPintasan(
                    'Isi ${sesi.labelSaldo}',
                    Icons.add_card_outlined,
                    () => navigasiMenu(context, MenuAnggota.isiSaldo),
                  ),
                ),
              if (sesi.aktifkanTopup && sesi.aktifkanBayarQr)
                const SizedBox(width: 10),
              if (sesi.aktifkanBayarQr)
                Expanded(
                  child: _tombolPintasan(
                    'Bayar QR',
                    Icons.qr_code_scanner,
                    () => navigasiMenu(context, MenuAnggota.bayarQr),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pil(String teks, IconData ikon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          Text(teks,
              style: const TextStyle(color: Colors.white, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _tombolPintasan(String label, IconData ikon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(ikon, size: 16, color: Colors.white),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pemilihToko() {
    if (_toko.isEmpty) {
      return const Text('Belum ada toko aktif.',
          style: TextStyle(color: AppColors.textSecondary));
    }
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _toko.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = _toko[i];
          final id = '${t['id']}';
          final aktif = id == _idTokoAktif;
          return Material(
            color: aktif ? AppColors.primary : AppColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _idTokoAktif = id;
                  _halaman = 1;
                });
                _muatProduk();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: aktif ? AppColors.primary : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.storefront_outlined,
                        size: 15,
                        color: aktif ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      '${t['nama'] ?? ''}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            aktif ? FontWeight.bold : FontWeight.normal,
                        color: aktif ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gridProduk() {
    return LayoutBuilder(builder: (context, c) {
      final kolom = c.maxWidth > 1100
          ? 5
          : c.maxWidth > 900
              ? 4
              : c.maxWidth > 600
                  ? 3
                  : 2;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: kolom,
          childAspectRatio: 0.74,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _produk.length,
        itemBuilder: (context, i) => _kartuProduk(_produk[i]),
      );
    });
  }

  Widget _kartuProduk(Map<String, dynamic> p) {
    final harga = (p['harga'] as num?)?.toDouble() ?? 0;
    final nama = '${p['nama'] ?? ''}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gambar mengisi penuh lebar kartu; rasio tetap supaya seluruh
          // kartu di grid sejajar walau tinggi gambarnya berbeda-beda.
          AspectRatio(
            aspectRatio: 1.25,
            child: Container(
              color: AppColors.pageBg,
              child: Image.network(
                ServerConfig.instance.urlGambarProduk(p['id']),
                fit: BoxFit.cover,
                // Produk tanpa lampiran tetap dilayani server (ikon bawaan),
                // dan koneksi bisa gagal -- keduanya jatuh ke lambang lokal
                // supaya kartu tidak pernah kosong.
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.fastfood_outlined,
                      size: 34, color: AppColors.textSecondary),
                ),
                loadingBuilder: (context, anak, progres) => progres == null
                    ? anak
                    : const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      nama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          height: 1.25,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rupiah(harga),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Tombol tambah dibuat bulat & kecil supaya nama produk
                      // tetap mendapat ruang terbesar di kartu.
                      Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _tambahKeKeranjang(p),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.add,
                                size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keadaan kosong yang menjelaskan, bukan sekadar satu baris teks.
  Widget _kosong(IconData ikon, String judul, String penjelasan) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(ikon, size: 34, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(judul,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(penjelasan,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }

}
