import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:core_hw/core_hw.dart';
import 'package:core_update/core_update.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../app_variant.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../services/layar_pelanggan_launcher.dart';
import '../services/pengaturan_laci.dart';
import '../services/pesanan_poller.dart';
import '../services/toko_aktif_lokal.dart';
import '../services/transaksi_outbox_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/app_error_info.dart';
import 'login_screen.dart';
import 'keranjang_screen.dart';
import 'bantuan_screen.dart';
import 'akun_saya_screen.dart';
import 'laporan_tutup_kas_dialog.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

@visibleForTesting
bool konteksFokusAdalahInputTeks(BuildContext? konteks) {
  return konteks != null &&
      (konteks.widget is EditableText ||
          konteks.findAncestorWidgetOfExactType<EditableText>() != null);
}

@visibleForTesting
bool produkCocokKataKunci(Produk produk, String kataKunci) {
  final kata = kataKunci.trim().toLowerCase();
  return kata.isEmpty ||
      produk.nama.toLowerCase().contains(kata) ||
      produk.kode.toLowerCase().contains(kata) ||
      produk.barcode.toLowerCase().contains(kata);
}

class KasirScreen extends StatefulWidget {
  final List<ItemKeranjang> keranjangAwal;
  final int? draftIdSumber;
  final String? draftKodeSumber;
  final Anggota? memberAwal;
  final DateTime? waktuTransaksiAwal;

  const KasirScreen({
    super.key,
    this.keranjangAwal = const [],
    this.draftIdSumber,
    this.draftKodeSumber,
    this.memberAwal,
    this.waktuTransaksiAwal,
  });

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

enum _AksiKasirMobile { transaksiBaru, kas, sinkron, muatUlang, akun, keluar }

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
  final _fokusKataKunci = FocusNode();

  final List<ItemKeranjang> _keranjang = [];
  int? _draftIdSumber;
  String? _draftKodeSumber;
  Anggota? _memberAwal;
  DateTime? _waktuTransaksiAwal;
  int _versiTransaksi = 0;

  /// "Harga Coret" (preview katalog, gap-closure Fase 2 Stretch) -- peta
  /// produkId->nominal diskon dari evaluasi PUBLIK (`diskon_evaluasi` TANPA
  /// `id_member`, lihat JavaDoc [_evaluasiHargaCoret]). Hanya diisi utk
  /// produk dgn `diskon > 0` (potongan langsung nyata) -- produk dgn
  /// `cashback > 0` saja SENGAJA tidak masuk sini krn harga stiker tidak
  /// berubah. Dibaca [_KartuProduk] lewat `_diskonKatalog[produk.id]`.
  Map<int, double> _diskonKatalog = {};
  Map<int, double> _cashbackKatalog = {};
  Timer? _debounceHargaCoret;
  Timer? _debounceCariProduk;

  static const _batasProdukAwal = 80;
  static const _batasHasilPencarian = 100;

  /// Batas jumlah produk yg dievaluasi sekali panggil -- grid Kasir TIDAK
  /// paginasi sungguhan (GridView.builder lazy-build semua `_produkTersaring`),
  /// jadi batas ini berperan sbg pengganti "halaman aktif" spy panggilan
  /// tetap murah (spec: jangan evaluasi seluruh katalog sekaligus).
  static const _batasPreviewHargaCoret = 60;

  /// null = belum diketahui (masih memeriksa), false = kas tertutup (blokir
  /// layar), true = kas terbuka (boleh jualan) -- lihat _periksaSesiKas &
  /// _OverlayBukaKas. Sengaja gerbang KERAS spt versi Electron: kasir TIDAK
  /// BOLEH mulai transaksi apa pun sebelum kas dibuka.
  bool? _kasTerbuka;
  bool _sesiKasDiPerangkatLain = false;
  String _namaPerangkatSesiLain = '';
  String _pesanSesiKas = '';
  double _modalAwalKas = 0;

  /// Sinkron latar BERKALA (30 detik, pola PERSIS `mulaiSinkronSesiKasBerkala`
  /// versi Electron main.js) selama layar Kasir terbuka -- gap-closure: SEBELUMNYA
  /// `_cobaSinkronBukaKasPending` cuma jalan sbg efek-samping transaksi selesai
  /// ([_muatKasSaatIni], via [_perbaruiJumlahPending]), jadi TRANSAKSI PERTAMA
  /// setelah gagal sinkron (belum pernah ada transaksi sukses sama sekali) tak
  /// pernah dapat kesempatan retry lebih dulu -- checkout tetap ditolak server
  /// walau topbar sudah "Kas Terbuka". Timer ini jalan independen dari
  /// transaksi/navigasi, persis spt versi Electron.
  Timer? _timerSinkronSesiKas;

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
  ///
  /// Disimpan ke SharedPreferences (device-level, bukan per-sesi-login) --
  /// gap-closure: SEBELUMNYA kembali ke false setiap kali `KasirScreen`
  /// dibuat ulang (mis. tombol "Transaksi Baru" di StrukScreen memanggil
  /// `pushReplacement(KasirScreen())`, instance State lama dibuang total),
  /// jadi preferensi kasir seakan "lupa" walau baru saja dipilih. Bertahan
  /// lintas transaksi/logout/restart aplikasi sampai diubah manual.
  bool _fokusKeranjang = false;
  static const _kKunciFokusKeranjang = 'kasir_fokus_keranjang';

  Future<void> _toggleFokusKeranjang() async {
    setStateIfMounted(() => _fokusKeranjang = !_fokusKeranjang);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kKunciFokusKeranjang, _fokusKeranjang);
    _jadwalkanFokusCariItem();
  }

  @override
  void initState() {
    super.initState();
    _keranjang.addAll(widget.keranjangAwal);
    _draftIdSumber = widget.draftIdSumber;
    _draftKodeSumber = widget.draftKodeSumber;
    _memberAwal = widget.memberAwal;
    _waktuTransaksiAwal = widget.waktuTransaksiAwal;
    _muatPreferensiTampilan();
    _muatAwal();
    if (_keranjang.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _siarkanKeranjangKasir();
      });
    }
    _jadwalkanFokusCariItem();
    _timerSinkronSesiKas = Timer.periodic(
        const Duration(seconds: 30), (_) => _cobaSinkronBukaKasPending());
    TransaksiOutboxService.instance.mulai();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _jadwalkanFokusCariItem();
  }

  Future<void> _muatPreferensiTampilan() async {
    final sp = await SharedPreferences.getInstance();
    final tersimpan = sp.getBool(_kKunciFokusKeranjang);
    if (tersimpan != null && mounted) {
      setStateIfMounted(() => _fokusKeranjang = tersimpan);
      _jadwalkanFokusCariItem();
    }
  }

  @override
  void dispose() {
    _debounceHargaCoret?.cancel();
    _debounceCariProduk?.cancel();
    _timerSinkronSesiKas?.cancel();
    _kataKunciController.dispose();
    _fokusKataKunci.dispose();
    super.dispose();
  }

  Future<void> _muatAwal() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    // Baca hanya halaman kecil dari cache lokal. Katalog besar (50 ribu+
    // produk) tidak boleh menahan pembukaan layar Kasir.
    try {
      final cache = await CoreDb.instance.produkCache(limit: _batasProdukAwal);
      if (cache.isNotEmpty) {
        setStateIfMounted(
            () => _semuaProduk = cache.map(_produkDariCache).toList());
        _jadwalkanEvaluasiHargaCoret();
      }
    } catch (_) {
      // cache lokal gagal dibaca (mis. pertama kali install) -- lanjut ke jalur server saja.
    }

    try {
      await _perbaruiJumlahPending();
    } catch (_) {}

    if (mounted) {
      setStateIfMounted(() => _memuat = false);
      _jadwalkanFokusCariItem();
    }

    // Konfigurasi, status sesi, dan halaman pertama katalog server berjalan
    // setelah UI siap. Riwayat transaksi/outbox tetap ditangani service latar
    // dan tidak pernah dibaca seluruhnya oleh pembukaan layar ini.
    unawaited(_lanjutkanMuatAwalJaringan());
  }

  Future<void> _lanjutkanMuatAwalJaringan() async {
    try {
      await _sinkronKatalogDanKonfigurasi(
          tampilkanErrorJikaKosong: _semuaProduk.isEmpty);
      await _periksaSesiKas();
      PesananPoller.instance.mulai();
    } catch (e) {
      if (_semuaProduk.isEmpty && mounted) {
        setStateIfMounted(() => _pesanError = 'Gagal memuat data POS: $e');
      }
    }
  }

  void _jadwalkanFokusCariItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _memuat || _pesanError != null) return;
      if (Sesi.instance.wajibSesiKas && _kasTerbuka != true) return;
      if (!_fokusKataKunci.canRequestFocus) return;
      final fokusAktif = FocusManager.instance.primaryFocus;
      final widgetFokus = fokusAktif?.context?.widget;
      if (fokusAktif != _fokusKataKunci && widgetFokus is EditableText) {
        return;
      }
      _fokusKataKunci.requestFocus();
      _kataKunciController.selection = TextSelection.collapsed(
        offset: _kataKunciController.text.length,
      );
    });
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
        // Offline-first: gerbang "Pilih Ekstra" (_tambahKeKeranjang) harus
        // tetap aktif walau Kasir baru saja start dari cache lokal (belum
        // sempat sinkron katalog dari server) -- tanpa ini produk dgn ekstra
        // yang dimuat dari cache akan diam-diam kehilangan picker-nya.
        ekstraPilihan: _ekstraPilihanDariCache(b['ekstra_pilihan']),
        fotoUrls: _daftarStringDariCache(b['foto_urls']),
      );

  List<int> _ekstraPilihanDariCache(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => (e as num).toInt()).toList();
      }
    } catch (_) {
      // Data cache lama/korup -- anggap tanpa ekstra, bukan error fatal.
    }
    return const [];
  }

  /// Padanan [_ekstraPilihanDariCache] utk kolom `foto_urls` (JSON array
  /// String, bukan int) -- gap-closure "Foto Produk".
  List<String> _daftarStringDariCache(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e as String).toList();
      }
    } catch (_) {
      // Data cache lama/korup -- anggap tanpa foto, bukan error fatal.
    }
    return const [];
  }

  // Pemetaan konfigurasi->Sesi dipindah ke Sesi.terapkanKonfig (dipakai juga
  // landing varian Inventory & Sales) -- wrapper tipis ini dipertahankan
  // supaya seluruh call-site lama di file ini tidak berubah.
  void _terapkanKonfig(Map<String, dynamic> konfig) {
    Sesi.instance.terapkanKonfig(konfig);
  }

  /// Bungkus [_terapkanKonfig] dengan penjagaan toko-per-perangkat -- lihat
  /// JavaDoc [TokoAktifLokal]. Panggil ini (BUKAN [_terapkanKonfig] langsung)
  /// di setiap alur yang mengambil `konfigurasi` dari server.
  ///
  /// [klaimBaru] = true HANYA dari alur pemilihan toko EKSPLISIT oleh kasir
  /// di perangkat ini ([_gantiToko]/[_pastikanTokoDipilih]) -- perangkat ini
  /// "mengklaim" toko yang baru dipilih, menimpa klaim lama bila ada.
  ///
  /// [klaimBaru] = false (default, dipakai refresh biasa) -- kalau perangkat
  /// ini SUDAH punya klaim toko yang masih valid (ada di `daftarToko` toko
  /// yang boleh diakses akun ini), klaim lokal itu yang menang, BUKAN
  /// saran/perubahan dari server (yang bisa saja berasal dari jendela/mesin
  /// LAIN yang berbagi akun sama). Kalau belum punya klaim sama sekali
  /// (mis. baru pertama kali login di perangkat ini), saran server diterima
  /// APA ADANYA dan langsung dijadikan klaim baru perangkat ini.
  Future<void> _terapkanKonfigDenganGuardToko(Map<String, dynamic> konfig,
      {bool klaimBaru = false}) async {
    _terapkanKonfig(konfig);
    final userId = Sesi.instance.userId;
    if (userId.isEmpty) return;
    if (!Sesi.instance.multiToko) {
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(userId, Sesi.instance.tokoId!);
      }
      return;
    }

    if (klaimBaru) {
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(userId, Sesi.instance.tokoId!);
      }
      return;
    }

    final idKlaimLokal = await TokoAktifLokal.instance.muat(userId);
    if (idKlaimLokal == null) {
      // Belum ada pilihan lokal: terima pilihan terakhir server. Jika server
      // juga belum pernah menyimpan pilihan, nilai ini adalah toko bawaan
      // Tbmuser/Pedagang yang dikirim konfigurasi. Simpan pada KEDUA sisi.
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(userId, Sesi.instance.tokoId!);
        await ApiClient.instance
            .aksi('pilih_toko_aktif', {'id_toko': Sesi.instance.tokoId!});
      }
      return;
    }

    final tokoKlaim =
        Sesi.instance.daftarToko.where((t) => t['id'] == idKlaimLokal);
    if (tokoKlaim.isEmpty) {
      // Klaim lama sudah tak berlaku (mis. akses toko itu dicabut) -- lepas
      // klaim lama, terima saran server sbg klaim baru.
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(userId, Sesi.instance.tokoId!);
        await ApiClient.instance
            .aksi('pilih_toko_aktif', {'id_toko': Sesi.instance.tokoId!});
      } else {
        await TokoAktifLokal.instance.hapus(userId);
      }
      return;
    }

    // Klaim lokal masih valid -- MENANG atas saran server, apa pun toko yang
    // server sarankan (bisa jadi hasil pilihan jendela/mesin lain).
    final idDariServer = Sesi.instance.tokoId;
    Sesi.instance.tokoId = idKlaimLokal;
    Sesi.instance.tokoNama = '${tokoKlaim.first['nama'] ?? ''}';
    if (idDariServer != idKlaimLokal) {
      // Pilihan lokal adalah pengalaman login terakhir pada instalasi ini;
      // sinkronkan kembali ke Tbmuser agar API server memakai toko yang sama.
      await ApiClient.instance
          .aksi('pilih_toko_aktif', {'id_toko': idKlaimLokal});
    }
  }

  /// Multi-toko -- gerbang "pilih toko" WAJIB sebelum apa pun lain kalau akun
  /// ini boleh akses >1 toko (`konfigurasi.multiToko`, lihat JavaDoc
  /// `Sesi.multiToko`) dan belum pernah memilih (`tokoAktifId` null). Reuse
  /// aksi `pilih_toko_aktif` yang SUDAH ADA server (padanan `konfigurasi.jsp`
  /// gate multi-toko) -- setelah dipilih, `konfigurasi` diambil ULANG supaya
  /// tokoId/tokoNama/dst mencerminkan toko yang baru dipilih.
  Future<Map<String, dynamic>> _pastikanTokoDipilih(
      Map<String, dynamic> konfig) async {
    if (konfig['multiToko'] != true || konfig['tokoAktifId'] != null) {
      return konfig;
    }
    final daftar =
        ((konfig['daftarToko'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (daftar.isEmpty || !mounted) return konfig;
    final dipilih = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Pilih Toko'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'Akun ini memiliki akses ke lebih dari satu toko. Pilih toko yang akan dioperasikan.')),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: daftar
                      .map((t) => ListTile(
                            title: Text('${t['nama']}'),
                            onTap: () =>
                                Navigator.of(context).pop(t['id'] as int?),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (dipilih == null) return konfig;
    try {
      await ApiClient.instance.aksi('pilih_toko_aktif', {'id_toko': dipilih});
      return await ApiClient.instance.aksi('konfigurasi');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memilih toko: $e')));
      }
      return konfig;
    }
  }

  /// Panggil lagi gerbang pilih-toko kapan saja (mis. dari Konfigurasi, saat
  /// kasir ingin PINDAH ke toko lain di tengah sesi -- bukan cuma sekali di
  /// awal login).
  Future<void> _gantiToko() async {
    final konfig = await ApiClient.instance.aksi('konfigurasi');
    final hasilBaru =
        await _pastikanTokoDipilih({...konfig, 'tokoAktifId': null});
    await _terapkanKonfigDenganGuardToko(hasilBaru, klaimBaru: true);
    if (mounted) setStateIfMounted(() {});
    await _muatAwal();
  }

  Future<void> _sinkronKatalogDanKonfigurasi(
      {bool tampilkanErrorJikaKosong = false}) async {
    try {
      var konfig = await ApiClient.instance.aksi('konfigurasi');
      konfig = await _pastikanTokoDipilih(konfig);
      await _terapkanKonfigDenganGuardToko(konfig);

      await _muatKatalogLazy();
    } catch (e) {
      final off = e is ApiException && e.offline;
      if (tampilkanErrorJikaKosong && _semuaProduk.isEmpty) {
        setStateIfMounted(() => _pesanError = off
            ? 'Belum ada data katalog tersimpan & server tidak terjangkau. Sambungkan internet lalu coba lagi.'
            : e.toString());
      }
    }
  }

  Future<void> _muatKatalogLazy({String keyword = ''}) async {
    final kataPermintaan = keyword.trim();
    final katalog = await ApiClient.instance.aksi('katalog', {
      'page': 1,
      'page_size':
          kataPermintaan.isEmpty ? _batasProdukAwal : _batasHasilPencarian,
      if (kataPermintaan.isNotEmpty) 'keyword': kataPermintaan,
    });
    final produkJson = (katalog['produk'] as List?) ?? [];
    final produk = produkJson
        .map((e) => Produk.fromJson(e as Map<String, dynamic>))
        .where((p) => p.jenisItem != 'BAHAN' && p.jenisItem != 'EKSTRA')
        .toList();
    final kategori = ((katalog['kategori'] as List?) ?? [])
        .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
        .toList();

    await CoreDb.instance.upsertProdukCache(produkJson
        .map((e) => Produk.baseKeCacheRow(e as Map<String, dynamic>))
        .toList());

    // Respons HTTP dapat datang tidak berurutan. Jangan biarkan hasil kata
    // lama menimpa hasil kata yang sedang terlihat di kotak pencarian.
    if (mounted && _kataKunciController.text.trim() == kataPermintaan) {
      setStateIfMounted(() {
        _semuaProduk = produk;
        _kategori = kategori;
      });
      _jadwalkanEvaluasiHargaCoret();
    }
  }

  Future<void> _muatKatalogPencarianAman(String keyword) async {
    try {
      await _muatKatalogLazy(keyword: keyword);
    } catch (_) {
      // Hasil cache lokal tetap dapat dipakai ketika jaringan putus. Error
      // jaringan pencarian tidak boleh menutup dropdown atau mengunci POS.
    }
  }

  void _cariProdukLazy(String nilai) {
    setStateIfMounted(() => _kataKunci = nilai);
    _debounceCariProduk?.cancel();
    _debounceCariProduk = Timer(const Duration(milliseconds: 250), () async {
      final kata = nilai.trim();
      try {
        final cache = await CoreDb.instance.produkCache(
          keyword: kata,
          limit: kata.isEmpty ? _batasProdukAwal : _batasHasilPencarian,
        );
        if (!mounted || _kataKunciController.text.trim() != kata) return;
        setStateIfMounted(
            () => _semuaProduk = cache.map(_produkDariCache).toList());
        _jadwalkanEvaluasiHargaCoret();
        // Cari ke server di belakang agar produk baru yang belum ada di cache
        // tetap ditemukan; hasil dibatasi, bukan seluruh katalog.
        unawaited(_muatKatalogPencarianAman(kata));
      } catch (_) {}
    });
  }

  Future<void> _periksaSesiKas() async {
    // Beri kesempatan sesi lokal yang masih pending (mis. baru dibuka di layar
    // Kasir SEBELUMNYA, gagal sinkron, lalu kasir pindah menu & kembali lagi)
    // utk sinkron DULU sebelum status "tertutup" dari server dipercaya --
    // gap-closure: SEBELUMNYA method ini langsung percaya jawaban server &
    // memanggil tutupSemuaSesiKasLokal() kalau server blm tahu, MENGHAPUS baris
    // pending itu SEBELUM ia pernah dapat kesempatan coba sinkron sama sekali
    // (retry lama cuma jalan lewat _muatKasSaatIni, yg no-op selama _kasTerbuka
    // masih null di pemuatan layar pertama) -- itulah sumber "Buka Kas muncul
    // lagi setiap ganti menu" walau baru saja dibuka.
    await _cobaSinkronBukaKasPending();
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_status', {
        'id_toko': Sesi.instance.tokoId,
        'id_perangkat': IdentitasMesin.instance.idMesin,
        'nama_perangkat': IdentitasMesin.instance.namaMesin,
      });
      final terbuka = hasil['terbuka'] == true;
      final diPerangkatLain = hasil['sesiDiPerangkatLain'] == true;
      if (terbuka) {
        // disinkronkan:true -- ini status ASLI dari server (sudah terkonfirmasi),
        // bukan optimistic-write, jadi tak perlu masuk antrian retry.
        //
        // KE-FIX (61 transaksi tertahan di Toko Al Bahjah, 21-08-2026, ditolak
        // server dengan "Transaksi berasal dari sesi kas yang berbeda").
        // Baris ini DAHULU menyimpan kode KARANGAN 'sesi-<tokoId>' -- kode yang
        // tidak pernah ada di server. Setiap penjualan sesudahnya membawa
        // kode_sesi_kas itu pada payload-nya, server mencarinya, tidak ketemu,
        // lalu menolak seluruh transaksinya. Gejalanya baru muncul ketika status
        // kas datang dari server (mis. aplikasi baru dibuka) dan bukan dari layar
        // Buka Kas -- jalur Buka Kas memang sudah menyimpan kode yang benar,
        // itulah sebabnya sebagian transaksi berhasil dan sebagian tidak.
        //
        // Server SUDAH mengirim kode aslinya lewat `kodeSesiKas` sejak lama;
        // yang kurang hanyalah memakainya. Bila jawabannya tidak memuat kode itu
        // (server lama), kode lokal yang sudah ada dipertahankan apa adanya --
        // lebih baik daripada menimpanya dengan karangan.
        final kodeServer = '${hasil['kodeSesiKas'] ?? ''}'.trim();
        final kodeLokalLama =
            '${(await CoreDb.instance.sesiKasAktif())?['kode'] ?? ''}'.trim();
        final kodeDipakai =
            kodeServer.isNotEmpty ? kodeServer : kodeLokalLama;
        if (kodeDipakai.isNotEmpty) {
          await CoreDb.instance.bukaSesiKasLokal(
            kodeDipakai,
            (hasil['modalAwal'] as num?)?.toDouble() ?? 0,
            disinkronkan: true,
          );
        }
      } else {
        await CoreDb.instance.tutupSemuaSesiKasLokal();
      }
      if (mounted) {
        setStateIfMounted(() {
          _kasTerbuka = terbuka;
          _sesiKasDiPerangkatLain = diPerangkatLain;
          _namaPerangkatSesiLain = '${hasil['namaPerangkatLain'] ?? ''}';
          _pesanSesiKas = '${hasil['description'] ?? ''}';
        });
      }
      if (mounted) {
        setStateIfMounted(() => _kasSaatIni =
            terbuka ? (hasil['kasSaatIni'] as num?)?.toDouble() ?? 0 : null);
        if (terbuka) _jadwalkanFokusCariItem();
      }
    } catch (_) {
      // Offline saat cek status -- pakai sumber lokal (local-first, sama spt Electron).
      final lokal = await CoreDb.instance.sesiKasAktif();
      if (mounted) {
        setStateIfMounted(
            () => _kasTerbuka = lokal != null || !Sesi.instance.wajibSesiKas);
        if (lokal != null || !Sesi.instance.wajibSesiKas) {
          _jadwalkanFokusCariItem();
        }
      }
    }
  }

  /// Muat ulang saldo Kas Sekarang -- dipanggil dari [_perbaruiJumlahPending]
  /// tiap kali transaksi baru selesai (Bayar/Tahan/Sinkronkan) supaya pil
  /// toolbar selalu segar. Sekalian titik retry alami utk buka-kas lokal yang
  /// belum terkonfirmasi server ([_cobaSinkronBukaKasPending]) DAN sekalian
  /// koreksi [_kasTerbuka] dari status server sungguhan -- SEBELUMNYA method
  /// ini cuma update [_kasSaatIni], [_kasTerbuka] dibiarkan apa adanya sampai
  /// layar dimuat ulang penuh, itulah sumber bug topbar "Kas Terbuka" yang
  /// diam2 sudah tak sinkron dgn gerbang checkout server (mandatory sejak
  /// 2026-08-11).
  Future<void> _muatKasSaatIni() async {
    if (_kasTerbuka != true) return;
    await _cobaSinkronBukaKasPending();
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_status', {
        'id_toko': Sesi.instance.tokoId,
        'id_perangkat': IdentitasMesin.instance.idMesin,
        'nama_perangkat': IdentitasMesin.instance.namaMesin,
      });
      final terbuka = hasil['terbuka'] == true;
      if (mounted) {
        setStateIfMounted(() {
          _kasTerbuka = terbuka;
          _sesiKasDiPerangkatLain = hasil['sesiDiPerangkatLain'] == true;
          _namaPerangkatSesiLain = '${hasil['namaPerangkatLain'] ?? ''}';
          _pesanSesiKas = '${hasil['description'] ?? ''}';
          _kasSaatIni =
              terbuka ? (hasil['kasSaatIni'] as num?)?.toDouble() ?? 0 : null;
        });
      }
      if (!terbuka) {
        await CoreDb.instance.tutupSemuaSesiKasLokal();
      }
    } catch (_) {
      // Offline -- biarkan angka/status lama, jangan ganti dgn nilai yg menyesatkan.
    }
  }

  /// Tutup Kas (spec §17) -- selisih SELALU dihitung server (`sesi_kas_tutup`),
  /// klien tak pernah menghitung sendiri. Sukses -> tandai lokal tertutup,
  /// gerbang Buka Kas otomatis muncul lagi utk sesi berikutnya, lalu tampilkan
  /// modal "Produk Perlu Direstok" (stokMenipis) langsung tanpa langkah tambahan.
  Future<void> _bukaDialogTutupKas() async {
    final tokoIdAktif = Sesi.instance.tokoId;
    if (tokoIdAktif == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Pilih toko terlebih dahulu sebelum menutup kas.')));
      }
      return;
    }
    final pending = await CoreDb.instance.jumlahTransaksiPendingPemilik(
      akunKunci: Sesi.instance.userId,
      tokoId: tokoIdAktif,
      idPerangkat: IdentitasMesin.instance.idMesin,
    );
    if (pending > 0) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kas belum dapat ditutup'),
          content: Text(
            'Masih ada $pending transaksi dari akun, toko, dan perangkat ini '
            'yang belum diterima server. Jalankan Sinkronisasi dan pastikan '
            'antrean menjadi kosong. Sesi kas dipertahankan agar transaksi '
            'tersebut tetap masuk ke kasir dan shift yang benar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }
    Map<String, dynamic>? status;
    try {
      status = await ApiClient.instance.aksi('sesi_kas_status', {
        'id_toko': Sesi.instance.tokoId,
        'id_perangkat': IdentitasMesin.instance.idMesin,
        'nama_perangkat': IdentitasMesin.instance.namaMesin,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat status kas: $e')));
      }
      return;
    }
    if (status['terbuka'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada sesi kas yang terbuka.')));
      }
      return;
    }
    final kasSaatIni = (status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    if (!mounted) return;
    final hasilTutup = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogTutupKas(
        status: status!,
        bolehKoreksiNominal: Sesi.instance.bolehKelola,
      ),
    );
    if (hasilTutup == null) return;

    final kodeLokal =
        (await CoreDb.instance.sesiKasAktif())?['kode'] as String?;
    try {
      final payloadTutup = <String, dynamic>{
        'id_toko': Sesi.instance.tokoId,
        'kode': kodeLokal,
        'id_perangkat': IdentitasMesin.instance.idMesin,
        'nama_perangkat': IdentitasMesin.instance.namaMesin,
        'uang_fisik': hasilTutup['uangFisik'],
        'keterangan': hasilTutup['keterangan'],
      };
      if (hasilTutup['modalAwalKoreksi'] != null) {
        payloadTutup['modal_awal_koreksi'] = hasilTutup['modalAwalKoreksi'];
        payloadTutup['alasan_koreksi'] = hasilTutup['alasanKoreksi'];
      }
      if (hasilTutup['penjualanTunaiKoreksi'] != null) {
        payloadTutup['penjualan_tunai_koreksi'] =
            hasilTutup['penjualanTunaiKoreksi'];
        payloadTutup['alasan_koreksi'] = hasilTutup['alasanKoreksi'];
      }
      final hasil =
          await ApiClient.instance.aksi('sesi_kas_tutup', payloadTutup);
      if (kodeLokal != null) await CoreDb.instance.tutupSesiKasLokal(kodeLokal);
      if (mounted) setStateIfMounted(() => _kasTerbuka = false);
      final selisih = (hasil['selisih'] as num?)?.toDouble() ?? 0;
      final stokMenipis =
          ((hasil['stokMenipis'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final laporan = hasil['laporanTutupKas'] is Map
          ? Map<String, dynamic>.from(hasil['laporanTutupKas'] as Map)
          : <String, dynamic>{
              'kasSeharusnya': kasSaatIni,
              'jumlahKasTunai': hasilTutup['uangFisik'],
              'selisih': selisih,
            };
      await showDialog(
        context: context,
        builder: (_) => LaporanTutupKasDialog(laporan: laporan),
      );
      if (stokMenipis.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${stokMenipis.length} produk perlu direstok.'),
          duration: const Duration(seconds: 6),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menutup kas: $e')));
      }
    }
  }

  Future<void> _bukaKas(double modalAwal, String catatan) async {
    final kode =
        'kas-${Sesi.instance.tokoId}-${DateTime.now().millisecondsSinceEpoch}';
    // Buka kas wajib mendapat lease server dahulu. Ini satu-satunya cara menjamin
    // akun yang sama tidak membuka kas pada dua perangkat ketika keduanya berbeda
    // database lokal. Operasi penjualan tetap dapat offline setelah lease diperoleh.
    try {
      final hasilBuka = await ApiClient.instance.aksi('sesi_kas_buka', {
        'id_toko': Sesi.instance.tokoId,
        'kode': kode,
        'modal_awal': modalAwal,
        // Server SUDAH menerima+menyimpan field ini sejak lama
        // (KantinHelper.sesiKasBuka -> SesiKasUtil.buka -> setKeterangan) --
        // hanya form Buka Kas yg belum pernah mengirimkannya.
        'keterangan': catatan,
        'id_perangkat': IdentitasMesin.instance.idMesin,
        'nama_perangkat': IdentitasMesin.instance.namaMesin,
      });
      final kodeAktif = '${hasilBuka['kode'] ?? kode}';
      final modalAktif =
          (hasilBuka['modalAwal'] as num?)?.toDouble() ?? modalAwal;
      await CoreDb.instance
          .bukaSesiKasLokal(kodeAktif, modalAktif, disinkronkan: true);
      if (mounted) {
        setStateIfMounted(() => _kasTerbuka = true);
        _jadwalkanFokusCariItem();
      }
    } catch (e) {
      if (mounted) setStateIfMounted(() => _kasTerbuka = false);
      if (mounted) {
        await tampilkanKesalahan(context, e is ApiException ? e.info : e,
            aktivitas: 'membuka sesi kas');
      }
    }
  }

  /// Retry buka-kas lokal yang optimistic-write-nya belum terkonfirmasi server (lihat
  /// komentar [_bukaKas]) -- dipanggil dari [_muatKasSaatIni] supaya dapat kesempatan
  /// coba lagi tiap kali ada transaksi/aktivitas, tanpa perlu kasir restart aplikasi.
  /// `kode` dipakai ulang APA ADANYA (idempoten di server) supaya retry tak pernah
  /// membuat sesi kas dobel.
  Future<void> _cobaSinkronBukaKasPending() async {
    final pending = await CoreDb.instance.sesiKasLokalBelumSinkron();
    for (final row in pending) {
      final kode = row['kode'] as String;
      try {
        final hasilBuka = await ApiClient.instance.aksi('sesi_kas_buka', {
          'id_toko': Sesi.instance.tokoId,
          'kode': kode,
          'modal_awal': row['modal_awal'],
          'id_perangkat': IdentitasMesin.instance.idMesin,
          'nama_perangkat': IdentitasMesin.instance.namaMesin,
        });
        final kodeServer = '${hasilBuka['kode'] ?? kode}';
        if (kodeServer != kode) {
          await CoreDb.instance.tutupSesiKasLokal(kode);
          await CoreDb.instance.bukaSesiKasLokal(
            kodeServer,
            (hasilBuka['modalAwal'] as num?)?.toDouble() ??
                (row['modal_awal'] as num?)?.toDouble() ??
                0,
            disinkronkan: true,
          );
        } else {
          await CoreDb.instance.tandaiSesiKasTersinkron(kode);
        }
      } catch (e) {
        if (e is ApiException && !e.offline) {
          await CoreDb.instance.tutupSesiKasLokal(kode);
          if (mounted) setStateIfMounted(() => _kasTerbuka = false);
        }
        // Gangguan jaringan masih dicoba lagi di kesempatan berikutnya.
      }
    }
  }

  Future<void> _bukaDialogBukaKas() async {
    final hasil = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogBukaKas(),
    );
    if (hasil == null) return;
    await _bukaKas(
      (hasil['modalAwal'] as num?)?.toDouble() ?? 0,
      (hasil['keterangan'] ?? '') as String,
    );
  }

  Future<void> _perbaruiJumlahPending() async {
    try {
      final n = await CoreDb.instance.jumlahTransaksiPending();
      if (mounted) setStateIfMounted(() => _jumlahPending = n);
    } catch (e) {
      // Gangguan penghitung antrean lokal tidak boleh memblokir seluruh layar
      // Kasir. Sinkron tetap dapat dicoba lagi dari tombol header.
      if (kDebugMode) debugPrint('Gagal membaca jumlah antrean lokal: $e');
    }
    unawaited(_muatKasSaatIni());
  }

  void _setelahTransaksiSelesai() {
    setStateIfMounted(() {
      _draftIdSumber = null;
      _draftKodeSumber = null;
      _memberAwal = null;
      _waktuTransaksiAwal = null;
    });
    unawaited(_perbaruiJumlahPending());
    // Segarkan katalog segera setelah checkout. Server sudah menghitung ulang stok dari jurnal
    // transaksi; mengambil ulang katalog di sini mencegah kartu/monitor kasir terus menampilkan
    // saldo cache sebelum transaksi. Bila sedang offline, helper tetap mempertahankan cache dan
    // sinkron berikutnya akan mencoba lagi tanpa mengganggu kasir.
    unawaited(_sinkronKatalogDanKonfigurasi());
    _jadwalkanFokusCariItem();
  }

  Future<void> _sinkronkanSekarang() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      final hasil = await TransaksiOutboxService.instance.sinkronkan();
      await _perbaruiJumlahPending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${hasil.berhasil} dari ${hasil.total} transaksi berhasil disinkron.')),
        );
      }
    } finally {
      if (mounted) setStateIfMounted(() => _sinkronBerjalan = false);
    }
  }

  List<Produk> get _produkTersaring {
    return _semuaProduk.where((p) {
      final cocokKategori =
          _kategoriTerpilih == null || p.kategoriId == _kategoriTerpilih;
      final cocokKeyword = produkCocokKataKunci(p, _kataKunci);
      return cocokKategori && cocokKeyword;
    }).toList();
  }

  /// Debounce 300ms (padanan pola [PanelKeranjang._jadwalkanEvaluasiDiskon])
  /// -- dipanggil tiap kali himpunan produk yg TERLIHAT di grid bisa berubah
  /// (katalog baru dimuat/disinkron, kategori diganti, kata kunci diketik)
  /// supaya tidak memanggil server di setiap ketukan/klik.
  void _jadwalkanEvaluasiHargaCoret() {
    _debounceHargaCoret?.cancel();
    _debounceHargaCoret =
        Timer(const Duration(milliseconds: 300), _evaluasiHargaCoret);
  }

  /// "Harga Coret" (preview katalog, gap-closure Fase 2 Stretch) -- evaluasi
  /// `diskon_evaluasi` PUBLIK (SENGAJA tanpa `id_member` -- belum ada member
  /// dipilih di tahap lihat-katalog, jadi hanya promo `berlakuSemuaMember=true`
  /// yg akan preview benar di sini; promo khusus member tetap menunggu
  /// keranjang+member spt perilaku lama, TIDAK berubah) HANYA utk produk yg
  /// sedang terlihat (dibatasi [_batasPreviewHargaCoret], bukan seluruh
  /// katalog) supaya panggilan tetap murah. Gagal/offline -> lewati diam-diam
  /// (murni enhancement visual di atas katalog offline-first yg sudah
  /// berjalan, BUKAN alasan memblokir/mengganggu render katalog).
  Future<void> _evaluasiHargaCoret() async {
    final tokoId = Sesi.instance.tokoId;
    if (tokoId == null) return;
    final tampil = _produkTersaring.take(_batasPreviewHargaCoret).toList();
    if (tampil.isEmpty) {
      if (_diskonKatalog.isNotEmpty || _cashbackKatalog.isNotEmpty) {
        setStateIfMounted(() {
          _diskonKatalog = {};
          _cashbackKatalog = {};
        });
      }
      return;
    }
    try {
      final hasil = await ApiClient.instance.aksi('diskon_evaluasi', {
        'toko_id': tokoId,
        'items': tampil
            .map((p) => {'id': p.id, 'harga': p.hargaJual, 'jumlah': 1})
            .toList(),
      });
      final items = (hasil['items'] as List?) ?? [];
      if (!mounted) return;
      final peta = <int, double>{};
      final petaCashback = <int, double>{};
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        final diskon = (m['diskon'] as num?)?.toDouble() ?? 0;
        if (diskon > 0) peta[m['id'] as int] = diskon;
        final cashback = (m['cashback'] as num?)?.toDouble() ?? 0;
        if (cashback > 0) petaCashback[m['id'] as int] = cashback;
      }
      setStateIfMounted(() {
        _diskonKatalog = peta;
        _cashbackKatalog = petaCashback;
      });
    } catch (_) {
      // Offline/gagal -- biarkan katalog tampil harga normal, bukan error.
    }
  }

  /// Produk dgn [Produk.ekstraPilihan] wajib lewat picker "Pilih Ekstra"
  /// (checkbox, lihat [_bukaPickerEkstra]) SEBELUM masuk keranjang -- gerbang
  /// dilewati (jalur lama persis, tanpa perubahan) utk mayoritas produk tanpa
  /// ekstra sama sekali.
  void _tambahKeKeranjang(Produk p) {
    if (p.ekstraPilihan.isNotEmpty) {
      unawaited(_tambahKeKeranjangDenganEkstra(p));
      return;
    }
    setStateIfMounted(() {
      final existing = _keranjang
          .where((i) => i.produk.id == p.id && i.ekstra.isEmpty)
          .toList();
      if (existing.isNotEmpty) {
        final item = existing.first;
        item.jumlah++;
        tempatkanItemKeranjangTerbaruDiDepan(_keranjang, item);
      } else {
        _keranjang.insert(0, ItemKeranjang(produk: p));
      }
      if (_kataKunciController.text.isNotEmpty || _kataKunci.isNotEmpty) {
        _kataKunciController.clear();
        _kataKunci = '';
      }
    });
    _siarkanKeranjangKasir();
    _jadwalkanFokusCariItem();
    _jadwalkanEvaluasiHargaCoret();
  }

  /// Alur "Pilih Ekstra" -- buka bottom sheet checkbox (batal = tidak ada apa
  /// pun ditambahkan), lalu masukkan ke keranjang PERSIS spt [_tambahKeKeranjang]
  /// biasa, hanya kunci penggabungan baris (merge-key) ikut mensyaratkan
  /// set ekstra yg SAMA PERSIS -- 2 baris produk sama tapi ekstra beda TIDAK
  /// digabung jadi satu qty, tetap 2 baris keranjang terpisah.
  Future<void> _tambahKeKeranjangDenganEkstra(Produk p) async {
    final dipilih = await _bukaPickerEkstra(p);
    if (dipilih == null || !mounted) return; // batal -- tidak menambah apa pun
    setStateIfMounted(() {
      final existing = _keranjang
          .where((i) => i.produk.id == p.id && _ekstraSama(i.ekstra, dipilih))
          .toList();
      if (existing.isNotEmpty) {
        final item = existing.first;
        item.jumlah++;
        tempatkanItemKeranjangTerbaruDiDepan(_keranjang, item);
      } else {
        _keranjang.insert(0, ItemKeranjang(produk: p, ekstra: dipilih));
      }
      if (_kataKunciController.text.isNotEmpty || _kataKunci.isNotEmpty) {
        _kataKunciController.clear();
        _kataKunci = '';
      }
    });
    _siarkanKeranjangKasir();
    _jadwalkanFokusCariItem();
    _jadwalkanEvaluasiHargaCoret();
  }

  /// Resolusi [Produk.ekstraPilihan] jadi baris nama/harga siap tampil lewat
  /// cache lokal (TANPA round-trip server, lihat JavaDoc
  /// `CoreDb.produkCacheResolveByIds`) lalu tampilkan bottom sheet checkbox.
  /// `null` = kasir membatalkan (tutup sheet tanpa menekan "Tambahkan").
  Future<List<ItemEkstra>?> _bukaPickerEkstra(Produk p) async {
    List<Map<String, Object?>> daftar;
    try {
      daftar = await CoreDb.instance.produkCacheResolveByIds(p.ekstraPilihan);
    } catch (_) {
      daftar = [];
    }
    if (!mounted) return null;
    return showModalBottomSheet<List<ItemEkstra>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SheetPilihEkstra(produkNama: p.nama, daftar: daftar),
    );
  }

  /// Kunci penggabungan baris keranjang -- 2 himpunan ekstra dianggap SAMA
  /// hanya kalau isinya identik (urutan tidak relevan, lihat JavaDoc
  /// [_tambahKeKeranjangDenganEkstra]).
  bool _ekstraSama(List<ItemEkstra> a, List<ItemEkstra> b) {
    if (a.length != b.length) return false;
    final idsA = a.map((e) => e.id).toList()..sort();
    final idsB = b.map((e) => e.id).toList()..sort();
    for (var i = 0; i < idsA.length; i++) {
      if (idsA[i] != idsB[i]) return false;
    }
    return true;
  }

  /// Dropdown hasil pencarian -- padanan `renderSearchDropdown` pos-renderer.js,
  /// HANYA relevan di mode Fokus Keranjang (grid produk disembunyikan sehingga
  /// kotak cari butuh umpan balik sendiri). Sama seperti Electron: dibatasi 30
  /// baris, sumber sama dgn `_produkTersaring` (nama/kode/barcode, filter
  /// kategori aktif ikut berlaku).
  List<Produk> get _hasilPencarianDropdown =>
      _produkTersaring.take(30).toList();

  /// Dipanggil oleh klik-mouse ATAU pintasan keyboard Ctrl+angka -- padanan
  /// persis `pilihHasilPencarian(p)`: tambah ke keranjang, bersihkan kotak,
  /// tutup dropdown (otomatis krn kata kunci jadi kosong), kembalikan fokus
  /// ke kotak cari supaya kasir bisa langsung mengetik/scan lagi.
  void _pilihHasilPencarian(Produk p) {
    _tambahKeKeranjang(p);
    _kataKunciController.clear();
    setStateIfMounted(() => _kataKunci = '');
    _cariProdukLazy('');
    _jadwalkanFokusCariItem();
  }

  /// Dipanggil saat kasir menekan Enter di kotak pencarian -- padanan
  /// "Enter-keystroke detection" pada scanner barcode HID di pos-renderer.js:
  /// kalau kode/barcode COCOK PERSIS satu produk, langsung tambah ke
  /// keranjang & bersihkan kotak (siap utk scan berikutnya tanpa kasir perlu
  /// mengetuk apa pun).
  Future<void> _submitPencarian(String nilai) async {
    final v = nilai.trim();
    if (v.isEmpty) return;
    var cocok =
        _semuaProduk.where((p) => p.kode == v || p.barcode == v).toList();
    if (cocok.isEmpty) {
      final cache = await CoreDb.instance.produkCache(keyword: v, limit: 10);
      cocok = cache
          .map(_produkDariCache)
          .where((p) => p.kode == v || p.barcode == v)
          .toList();
    }
    if (!mounted) return;
    if (cocok.isNotEmpty) {
      _tambahKeKeranjang(cocok.first);
      // Produk dgn ekstra BELUM tentu jadi masuk keranjang di sini -- masih
      // menunggu picker "Pilih Ekstra" (bottom sheet async, lihat
      // [_tambahKeKeranjangDenganEkstra]), kasir bisa saja membatalkannya.
      // Snackbar "ditambahkan" langsung di sini akan menyesatkan utk kasus
      // itu, jadi dilewati -- munculnya sheet itu sendiri sudah umpan balik
      // yang cukup.
      if (cocok.first.ekstraPilihan.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${cocok.first.nama} ditambahkan'),
              duration: const Duration(milliseconds: 700)),
        );
      }
      _kataKunciController.clear();
      setStateIfMounted(() => _kataKunci = '');
      _cariProdukLazy('');
      _jadwalkanFokusCariItem();
      return;
    }
    _kataKunciController.clear();
    setStateIfMounted(() => _kataKunci = '');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Item tidak ditemukan'),
        duration: Duration(milliseconds: 900),
      ),
    );
    _jadwalkanFokusCariItem();
  }

  double get _totalKeranjang => _keranjang.fold(0, (s, i) => s + i.subtotal);
  int get _jumlahItemKeranjang => _keranjang.fold(0, (s, i) => s + i.jumlah);
  bool get _adaTransaksiAktif =>
      _keranjang.isNotEmpty || _draftIdSumber != null || _memberAwal != null;

  void _siarkanKeranjangKasir() {
    final subtotal = _keranjang.fold<double>(0, (s, i) => s + i.subtotal);
    final diskon = _keranjang.fold<double>(0, (s, i) => s + i.diskon);
    final basisPajak = subtotal - diskon;
    final pajak = basisPajak * Sesi.instance.pajakPersen / 100;
    LayarPelangganBroadcaster.instance.jadwalkanKirim(
      items: _keranjang
          .map((i) => {
                'nama': i.produk.nama,
                'jumlah': i.jumlah,
                'harga': i.produk.hargaJual,
                'subtotal': i.subtotalSetelahDiskon,
              })
          .toList(),
      subtotal: subtotal,
      diskon: diskon,
      total: basisPajak + pajak,
    );
  }

  Future<void> _transaksiBaru() async {
    if (!_adaTransaksiAktif) {
      setStateIfMounted(() {
        _versiTransaksi++;
        _kataKunciController.clear();
        _kataKunci = '';
      });
      _jadwalkanFokusCariItem();
      return;
    }
    if (_keranjang.isNotEmpty) {
      final lanjut = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Mulai Transaksi Baru?'),
          content: const Text(
              'Keranjang aktif akan dikosongkan dan data transaksi saat ini dilepas.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Mulai Baru')),
          ],
        ),
      );
      if (lanjut != true) return;
    }
    setStateIfMounted(() {
      _keranjang.clear();
      _draftIdSumber = null;
      _draftKodeSumber = null;
      _memberAwal = null;
      _waktuTransaksiAwal = null;
      _versiTransaksi++;
      _kataKunciController.clear();
      _kataKunci = '';
    });
    LayarPelangganBroadcaster.instance
        .jadwalkanKirim(items: const [], subtotal: 0, diskon: 0, total: 0);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transaksi baru siap.'),
        duration: Duration(milliseconds: 900),
      ));
    }
    _jadwalkanFokusCariItem();
  }

  Future<void> _bukaKeranjang() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KeranjangScreen(
        keranjang: _keranjang,
        draftIdSumber: _draftIdSumber,
        draftKodeSumber: _draftKodeSumber,
        memberAwal: _memberAwal,
        waktuTransaksiAwal: _waktuTransaksiAwal,
      ),
    ));
    await _perbaruiJumlahPending();
    setStateIfMounted(() {
      if (_keranjang.isEmpty) {
        _draftIdSumber = null;
        _draftKodeSumber = null;
        _memberAwal = null;
        _waktuTransaksiAwal = null;
        _versiTransaksi++;
      }
    });
    _jadwalkanFokusCariItem();
  }

  Future<void> _logout() async {
    await ApiClient.instance.hapusToken();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  bool _bukaLaciBerjalan = false;

  /// F6 Buka Laci -- padanan `pos:buka-laci-kasir` Electron (lihat JavaDoc
  /// `core_hw.bukaLaciKasir`): kirim pulsa ESC/POS ke printer default Windows
  /// yang laci fisiknya nyambung lewat kabelnya. Dipakai manual (mis. tukar
  /// uang tanpa transaksi) -- BUKAN otomatis saat checkout (itu tanggung
  /// jawab alur cetak struk terpisah, belum ada di Flutter).
  Future<void> _bukaLaci() async {
    if (_bukaLaciBerjalan) return;
    setStateIfMounted(() => _bukaLaciBerjalan = true);
    try {
      await PengaturanLaci.instance.muat();
      await bukaLaciKasir(
          pinAlternatif: PengaturanLaci.instance.pinAlternatif,
          namaPrinter: PengaturanLaci.instance.namaPrinter);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Laci kasir dibuka.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuka laci: $e')));
      }
    } finally {
      if (mounted) setStateIfMounted(() => _bukaLaciBerjalan = false);
    }
  }

  /// "Update Sistem" -- pemicu MANUAL cek rilis GitHub terbaru (padanan
  /// pengecekan otomatis di `_GerbangAwal._cekUpdate` pada main.dart, yang
  /// hanya jalan sekali saat app baru dibuka) -- kasir bisa cek ulang kapan
  /// saja lewat toolbar ini tanpa perlu restart aplikasi dulu.
  Future<void> _cekUpdateManual() async {
    if (!mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final info = await PackageInfo.fromPlatform();
      final hasil = await UpdateChecker.cekTerbaru(
          repoOwner: 'Zishof',
          repoName: 'zishof-platform',
          versiSaatIni: info.version,
          assetKeyword: AppVariant.updateAssetKeyword,
          tagPrefix: AppVariant.updateTagPrefix);
      if (!mounted) return;
      Navigator.of(context).pop(); // tutup loading
      if (hasil == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sudah menggunakan versi terbaru.')));
        return;
      }
      final urlVarian = defaultTargetPlatform == TargetPlatform.android
          ? hasil.urlApk
          : hasil.urlExe;
      if (urlVarian == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Versi ${hasil.versi} sudah tercatat, tetapi paket ${AppVariant.namaAplikasi} belum tersedia. Aplikasi tidak akan mengunduh paket varian lain.')));
        return;
      }
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Versi ${hasil.versi} Tersedia'),
          content: Text(hasil.catatanRilis.isEmpty
              ? 'Versi baru telah dirilis.'
              : hasil.catatanRilis),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Nanti')),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(Uri.parse(urlVarian),
                    mode: LaunchMode.externalApplication);
              },
              child: const Text('Unduh'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memeriksa pembaruan: $e')));
    }
  }

  void _bukaBantuan() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            const BantuanScreen(menuId: 'kasir', menuJudul: 'Kasir/POS')));
  }

  void _bukaAkunSaya() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AkunSayaScreen()));
  }

  /// Windows: jendela desktop KEDUA sungguhan (bisa diseret/otomatis pindah
  /// ke monitor kedua) -- lihat JavaDoc `bukaLayarPelangganJendelaKedua`.
  /// Android: tetap `Navigator.push` di jendela yg sama (multi-window
  /// desktop tak berlaku di sana, layar ponsel cuma satu).
  Future<void> _bukaLayarPelanggan() async {
    await bukaLayarPelanggan(context);
  }

  Widget _tombolToolbar({
    required Widget icon,
    required String label,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textPrimaryOf(context),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            textStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  /// Semua aksi operasional pada halaman Kasir dikunci sampai sesi kas aktif.
  /// Navigasi sidebar dikelola AppShell dan Logout sengaja tetap tersedia.
  bool get _aksiKasirAktif =>
      !Sesi.instance.wajibSesiKas || _kasTerbuka == true;

  bool get _bolehMembukaKas => _kasTerbuka == false && !_sesiKasDiPerangkatLain;

  List<Widget> get _tombolAksiMobile => [
        PopupMenuButton<_AksiKasirMobile>(
          key: const Key('menu-aksi-kasir-mobile'),
          icon: const Icon(Icons.more_vert),
          tooltip: 'Aksi kasir lainnya',
          onSelected: (aksi) {
            switch (aksi) {
              case _AksiKasirMobile.transaksiBaru:
                _transaksiBaru();
                return;
              case _AksiKasirMobile.kas:
                if (_kasTerbuka == true) {
                  _bukaDialogTutupKas();
                } else if (_kasTerbuka == false) {
                  _bukaDialogBukaKas();
                }
                return;
              case _AksiKasirMobile.sinkron:
                if (!_sinkronBerjalan) _sinkronkanSekarang();
                return;
              case _AksiKasirMobile.muatUlang:
                _muatAwal();
                return;
              case _AksiKasirMobile.akun:
                _bukaAkunSaya();
                return;
              case _AksiKasirMobile.keluar:
                _logout();
                return;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _AksiKasirMobile.transaksiBaru,
              enabled: _aksiKasirAktif,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.add_shopping_cart_outlined),
                title: Text('Transaksi Baru'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _AksiKasirMobile.kas,
              enabled: _kasTerbuka == true || _bolehMembukaKas,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.point_of_sale_outlined),
                title: Text(_kasTerbuka == true ? 'Tutup Kas' : 'Buka Kas'),
              ),
            ),
            PopupMenuItem(
              value: _AksiKasirMobile.sinkron,
              enabled: _aksiKasirAktif && !_sinkronBerjalan,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync),
                title: Text(_jumlahPending > 0
                    ? 'Sync ($_jumlahPending tertunda)'
                    : 'Sync'),
              ),
            ),
            PopupMenuItem(
              value: _AksiKasirMobile.muatUlang,
              enabled: _aksiKasirAktif,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.refresh),
                title: Text('Muat Ulang'),
              ),
            ),
            PopupMenuItem(
              value: _AksiKasirMobile.akun,
              enabled: _aksiKasirAktif,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.account_circle_outlined),
                title: Text('Akun Saya'),
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _AksiKasirMobile.keluar,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout),
                title: Text('Keluar'),
              ),
            ),
          ],
        ),
      ];

  List<Widget> get _tombolAksi => [
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          _tombolToolbar(
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: 'Transaksi Baru',
              onPressed: _aksiKasirAktif ? _transaksiBaru : null,
              tooltip: 'Mulai transaksi baru'),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton.icon(
              onPressed: _aksiKasirAktif ? _toggleFokusKeranjang : null,
              icon: Icon(
                  _fokusKeranjang
                      ? Icons.grid_view_outlined
                      : Icons.view_sidebar_outlined,
                  size: 16),
              label: Text(
                  _fokusKeranjang ? 'Tampilan Normal' : 'Fokus Keranjang',
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
          if (_kasSaatIni != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Sesi Kasir (ketuk utk lihat rincian & Tutup Kas)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _bukaDialogTutupKas,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.latarLembut(AppColors.success),
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(_formatRupiah.format(_kasSaatIni),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Gap-closure "toko kelihatan berubah saat pindah menu": layar Kasir
          // (toolbar khusus F-key, BUKAN topbar standar AppShell) sebelumnya
          // TIDAK menampilkan nama toko aktif sama sekali -- kasir tak punya
          // cara memverifikasi toko yg sedang aktif di layar ini, sehingga
          // judul sidebar "Al-Bahjah POS"/"eBisnis" (nama BRAND, konstan,
          // BUKAN nama toko) terlihat spt berbeda dr nama toko yg baru
          // tampil di topbar layar lain. Pil ini membuat nama toko SELALU
          // terlihat di sini juga, sama persis dgn `Sesi.instance.tokoNama`
          // yg dipakai topbar AppShell layar lain -- kalau memang tak
          // berubah, kini bisa dibuktikan langsung dari layar Kasir sendiri.
          if (Sesi.instance.tokoNama.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Toko aktif di perangkat ini',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: AppColors.latarLembut(AppColors.primary),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.storefront,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(Sesi.instance.tokoNama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (Sesi.instance.multiToko)
            _tombolToolbar(
                icon: const Icon(Icons.storefront_outlined, size: 18),
                label: 'Toko',
                onPressed: _aksiKasirAktif ? _gantiToko : null,
                tooltip: 'Ganti Toko'),
          _tombolToolbar(
              icon: const Icon(Icons.desktop_windows_outlined, size: 18),
              label: 'Layar',
              onPressed: _aksiKasirAktif ? _bukaLayarPelanggan : null,
              tooltip: 'Layar Pelanggan (F9)'),
          _tombolToolbar(
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: 'Update',
              onPressed: _aksiKasirAktif ? _cekUpdateManual : null,
              tooltip: 'Cek Update Sistem'),
          _tombolToolbar(
            icon: _bukaLaciBerjalan
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.point_of_sale, size: 18),
            label: 'Laci',
            onPressed: !_aksiKasirAktif || _bukaLaciBerjalan ? null : _bukaLaci,
            tooltip: 'Buka Laci (F6)',
          ),
        ],
        _tombolToolbar(
          icon: const Icon(Icons.point_of_sale_outlined, size: 18),
          label: _kasTerbuka == true
              ? 'Kas'
              : (_kasTerbuka == null ? 'Cek Kas' : 'Buka Kas'),
          onPressed:
              _kasTerbuka == null || (_kasTerbuka == false && !_bolehMembukaKas)
                  ? null
                  : (_kasTerbuka == true
                      ? _bukaDialogTutupKas
                      : _bukaDialogBukaKas),
          tooltip: _kasTerbuka == true
              ? 'Sesi Kasir / Tutup Kas'
              : 'Buka sesi kasir',
        ),
        _tombolToolbar(
          icon: Badge(
            label: Text('$_jumlahPending'),
            isLabelVisible: _jumlahPending > 0,
            child: _sinkronBerjalan
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 18),
          ),
          label: 'Sync',
          onPressed:
              !_aksiKasirAktif || _sinkronBerjalan ? null : _sinkronkanSekarang,
          tooltip: 'Sinkronkan transaksi tertunda (F8)',
        ),
        _tombolToolbar(
            icon: const Icon(Icons.refresh, size: 18),
            label: 'Muat Ulang',
            onPressed: _aksiKasirAktif ? _muatAwal : null,
            tooltip: 'Muat ulang katalog'),
        _tombolToolbar(
            icon: const Icon(Icons.account_circle_outlined, size: 18),
            label: 'Akun Saya',
            onPressed: _aksiKasirAktif ? _bukaAkunSaya : null,
            tooltip: 'Akun Saya'),
        _tombolToolbar(
            icon: const Icon(Icons.logout, size: 18),
            label: 'Keluar',
            onPressed: _logout,
            tooltip: 'Keluar'),
      ];

  /// Pintasan keyboard F1-F9 -- padanan pos-renderer.js `PETA_TOMBOL_KASIR`
  /// (F2-F5 Bayar/Tahan/Metode/Member milik KeranjangScreen, bukan layar ini,
  /// krn Kasir & Keranjang adalah 2 layar terpisah di Flutter/Android --
  /// hanya relevan di Windows lewat `PanelKeranjang` yang tertanam).
  /// Desktop-only (fisik keyboard) -- diam di Android via gerbang platform.
  bool _sedangInputTeksAktif() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _tanganiTombolKasir(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Shortcut global ini berada di atas seluruh layar, termasuk overlay
    // "Buka Kas". Saat kas belum aktif, versi lama langsung mengembalikan
    // `handled` sehingga setiap tombol yang sudah diterima TextField Modal
    // Awal tetap ditelan ketika event menggelembung ke Focus induk. Akibatnya
    // kolom terlihat fokus tetapi angka (mis. 300000) tidak pernah masuk.
    // Input yang sedang fokus harus selalu menjadi pemilik event keyboard;
    // gerbang sesi kas hanya memblokir shortcut/aksi di belakang overlay.
    final fokusAktif = FocusManager.instance.primaryFocus;
    final konteksFokus = fokusAktif?.context;
    if (konteksFokusAdalahInputTeks(konteksFokus)) {
      return KeyEventResult.ignored;
    }
    if (_sedangInputTeksAktif()) return KeyEventResult.ignored;
    if (!_aksiKasirAktif) return KeyEventResult.ignored;
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
    // Ctrl+angka -- padanan persis `elCariProduk.addEventListener('keydown', ...)`
    // pos-renderer.js: pilih baris ke-N dropdown hasil pencarian tanpa mouse.
    // Sengaja CTRL+angka (bukan angka polos) supaya mengetik kode produk
    // numerik di kotak cari tidak pernah tersandung jadi pintasan ini.
    if (_fokusKeranjang &&
        _kataKunci.isNotEmpty &&
        HardwareKeyboard.instance.isControlPressed) {
      final indeks = _indeksDariTombolAngka(event.logicalKey);
      if (indeks != null) {
        final hasil = _hasilPencarianDropdown;
        if (indeks < hasil.length) {
          _pilihHasilPencarian(hasil[indeks]);
        }
        return KeyEventResult.handled;
      }
    }
    // Auto-fokus kotak cari saat scanner barcode (mengirim keystroke HID
    // secepat mengetik) atau kasir langsung mengetik TANPA meng-klik kotak
    // cari dulu -- padanan listener global Electron yang mengarahkan fokus
    // ke #cariProduk kecuali activeElement SUDAH sebuah input lain (di sini:
    // kecuali ada widget lebih spesifik yg sudah pegang fokus, mis. field
    // "Uang Diterima" di panel Keranjang -- gerbang `primaryFocus == node`
    // memastikan HANYA menyambar kalau tak ada apa pun yg lebih spesifik
    // sedang fokus, supaya tidak merebut fokus dari pengetikan lain).
    if (FocusManager.instance.primaryFocus == node &&
        !_fokusKataKunci.hasFocus &&
        event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter &&
        event.logicalKey != LogicalKeyboardKey.tab &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final karakter = event.character;
      if (karakter != null && karakter.isNotEmpty) {
        _fokusKataKunci.requestFocus();
        final teksBaru = _kataKunciController.text + karakter;
        _kataKunciController.value = TextEditingValue(
            text: teksBaru,
            selection: TextSelection.collapsed(offset: teksBaru.length));
        setStateIfMounted(() => _kataKunci = teksBaru);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Angka 1-9 -> indeks 0-8, angka 0 -> indeks 9 (baris ke-10) -- sama persis
  /// urutan label nomor yang dirender `_BarisHasilPencarian`.
  int? _indeksDariTombolAngka(LogicalKeyboardKey kunci) {
    final peta = {
      LogicalKeyboardKey.digit1: 0,
      LogicalKeyboardKey.digit2: 1,
      LogicalKeyboardKey.digit3: 2,
      LogicalKeyboardKey.digit4: 3,
      LogicalKeyboardKey.digit5: 4,
      LogicalKeyboardKey.digit6: 5,
      LogicalKeyboardKey.digit7: 6,
      LogicalKeyboardKey.digit8: 7,
      LogicalKeyboardKey.digit9: 8,
      LogicalKeyboardKey.digit0: 9,
      LogicalKeyboardKey.numpad1: 0,
      LogicalKeyboardKey.numpad2: 1,
      LogicalKeyboardKey.numpad3: 2,
      LogicalKeyboardKey.numpad4: 3,
      LogicalKeyboardKey.numpad5: 4,
      LogicalKeyboardKey.numpad6: 5,
      LogicalKeyboardKey.numpad7: 6,
      LogicalKeyboardKey.numpad8: 7,
      LogicalKeyboardKey.numpad9: 8,
      LogicalKeyboardKey.numpad0: 9,
    };
    return peta[kunci];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _tanganiTombolKasir,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => _jadwalkanFokusCariItem(),
        child: AppShell(
          menuAktif: MenuEBisnis.kasir,
          judul: 'Kasir / POS',
          tampilkanJudul: false,
          scrollable: false,
          actionsAppBar: _tombolAksiMobile,
          aksiHeader:
              Row(mainAxisSize: MainAxisSize.min, children: _tombolAksi),
          bottomBar: defaultTargetPlatform == TargetPlatform.windows ||
                  _keranjang.isEmpty
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
                          Text('Keranjang ($_jumlahItemKeranjang)',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_formatRupiah.format(_totalKeranjang),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
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
                                const Icon(Icons.error_outline,
                                    size: 48, color: Colors.red),
                                const SizedBox(height: 12),
                                Text(_pesanError!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                    onPressed: _muatAwal,
                                    child: const Text('Coba Lagi')),
                              ],
                            ),
                          ),
                        )
                      : defaultTargetPlatform == TargetPlatform.windows
                          ? _bodyDesktop()
                          : _kontenKatalog(),
              if (_kasTerbuka == false && Sesi.instance.wajibSesiKas)
                _OverlayBukaKas(
                    sesiDiPerangkatLain: _sesiKasDiPerangkatLain,
                    namaPerangkatLain: _namaPerangkatSesiLain,
                    pesan: _pesanSesiKas,
                    onPeriksaUlang: _periksaSesiKas,
                    onBuka: (modal, catatan) {
                      setStateIfMounted(() => _modalAwalKas = modal);
                      _bukaKas(_modalAwalKas, catatan);
                    }),
            ],
          ),
        ),
      ),
    );
  }

  /// Kartu Keranjang tertanam LANGSUNG di sisi kanan (padanan tampilan
  /// referensi Electron: grid+keranjang satu layar berdampingan, bukan
  /// navigasi terpisah spt Android) -- lihat JavaDoc `_fokusKeranjang` utk
  /// mode F7 yang menyembunyikan grid & melebarkan panel ini sendirian.
  Widget _bodyDesktop() {
    // Panel tetap proporsional terhadap layar. Lebar tetap 420 px sebelumnya
    // terlalu sempit pada monitor Full-HD/2K, sementara nilai terlalu besar
    // akan mengorbankan katalog pada POS 1366 px. Clamp ini memberi ruang
    // nyaman bagi nama, harga, qty, dan checkout tanpa memotong grid produk.
    final lebarLayar = MediaQuery.sizeOf(context).width;
    final lebarPanelKeranjang =
        (lebarLayar * 0.34).clamp(460.0, 640.0).toDouble();
    final panel = PanelKeranjang(
      key: ValueKey('panel-keranjang-$_versiTransaksi'),
      keranjang: _keranjang,
      draftIdSumber: _draftIdSumber,
      draftKodeSumber: _draftKodeSumber,
      memberAwal: _memberAwal,
      waktuTransaksiAwal: _waktuTransaksiAwal,
      pencarianBarang: _fokusKeranjang ? _kotakPencarian() : null,
      tampilkanJudul: !_fokusKeranjang,
      aksiHeader: _fokusKeranjang
          ? null
          : OutlinedButton.icon(
              onPressed: _toggleFokusKeranjang,
              icon: const Icon(Icons.fullscreen, size: 14),
              label: const Text('Fokus Keranjang (F7)',
                  style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero),
            ),
      onSelesai: _setelahTransaksiSelesai,
    );
    if (_fokusKeranjang) {
      // Stack (bukan Column polos) -- dropdown hasil pencarian WAJIB jadi
      // child TERAKHIR di sini supaya urutan cat (paint order) Stack
      // menaruhnya DI ATAS panel Keranjang. Mode Fokus Keranjang sengaja
      // mengisi penuh lebar body supaya kolom item dan checkout tidak
      // menyisakan ruang kosong di kiri/kanan pada layar lebar.
      return SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: panel),
            if (_kataKunci.isNotEmpty)
              Positioned(
                  top: 72,
                  left: 16,
                  right: 388,
                  child: _dropdownHasilPencarian()),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _kontenKatalog()),
        const VerticalDivider(width: 1),
        SizedBox(width: lebarPanelKeranjang, child: panel),
      ],
    );
  }

  Widget _kotakPencarian() {
    return TextField(
      controller: _kataKunciController,
      focusNode: _fokusKataKunci,
      autofocus: true,
      // Windows: matikan keyboard sentuh OTOMATIS utk kotak ini -- kotak ini
      // isinya scan barcode (HID, bukan IME) di layar sentuh POS, tapi
      // Windows tetap memunculkan touch-keyboard tiap kali kotak ini fokus.
      // Kombinasi itu dgn auto-fokus scanner (lihat _tanganiTombolKasir)
      // memicu keyboard sentuh muncul-hilang berulang (dilaporkan pengguna,
      // terlihat di video). `TextInputType.none` memberi tahu Windows utk
      // tak pernah memanggil touch-keyboard di kotak ini -- scan HID tetap
      // masuk normal (lewat key event fisik, bukan lewat IME/touch-keyboard),
      // kasir yg perlu ketik manual tanpa scanner masih bisa pakai keyboard
      // sentuh Windows lewat taskbar secara manual.
      keyboardType: defaultTargetPlatform == TargetPlatform.windows
          ? TextInputType.none
          : null,
      decoration: const InputDecoration(
        hintText: 'Cari / scan barcode produk...',
        prefixIcon: Icon(Icons.search),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10))),
        isDense: true,
      ),
      onChanged: _cariProdukLazy,
      onSubmitted: _submitPencarian,
    );
  }

  /// Dropdown hasil pencarian mode Fokus Keranjang -- padanan visual
  /// `.search-dropdown` pos-renderer.js: kartu melayang di bawah kotak cari,
  /// tiap baris bernomor 1-9 lalu 0 (Ctrl+angka utk pilih tanpa mouse, lihat
  /// `_tanganiTombolKasir`), sisanya (baris ke-11 dst, maks 30) klik-mouse saja.
  Widget _dropdownHasilPencarian() {
    final hasil = _hasilPencarianDropdown;
    return Material(
      color: AppColors.cardBgOf(context),
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 340),
        child: hasil.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Tidak ada produk cocok.',
                    style:
                        TextStyle(color: AppColors.textSecondaryOf(context))),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: hasil.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _BarisHasilPencarian(
                  nomor: i < 9 ? '${i + 1}' : (i == 9 ? '0' : ''),
                  produk: hasil[i],
                  onTap: () => _pilihHasilPencarian(hasil[i]),
                ),
              ),
      ),
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
                  onSelected: (_) {
                    setStateIfMounted(() => _kategoriTerpilih = null);
                    _jadwalkanEvaluasiHargaCoret();
                  },
                ),
              ),
              ..._kategori.map((k) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k.nama),
                      selected: _kategoriTerpilih == k.id,
                      onSelected: (_) {
                        setStateIfMounted(() => _kategoriTerpilih = k.id);
                        _jadwalkanEvaluasiHargaCoret();
                      },
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final produkTampil = _produkTersaring;
              if (produkTampil.isEmpty) {
                final katalogKosong = _semuaProduk.isEmpty;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          katalogKosong
                              ? Icons.inventory_2_outlined
                              : Icons.search_off,
                          size: 48,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          katalogKosong
                              ? 'Katalog produk untuk akun dan toko ini belum tersedia.'
                              : 'Produk tidak ditemukan.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          katalogKosong
                              ? 'Pastikan akun ${Sesi.instance.userId.isEmpty ? 'kasir' : Sesi.instance.userId} sudah diberi akses ke toko POS, lalu tekan Muat Ulang.'
                              : 'Periksa nama, kode, atau barcode; atau pilih kategori Semua.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                );
              }
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
                itemCount: produkTampil.length,
                itemBuilder: (context, i) => _KartuProduk(
                  produk: produkTampil[i],
                  onTap: () => _tambahKeKeranjang(produkTampil[i]),
                  diskon: _diskonKatalog[produkTampil[i].id],
                  cashback: _cashbackKatalog[produkTampil[i].id],
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
class _DialogBukaKas extends StatefulWidget {
  const _DialogBukaKas();

  @override
  State<_DialogBukaKas> createState() => _DialogBukaKasState();
}

class _DialogBukaKasState extends State<_DialogBukaKas> {
  final _controller = TextEditingController(text: '0');
  final _catatanController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  void _konfirmasi() {
    final modal =
        double.tryParse(_controller.text.replaceAll(RegExp('[^0-9.]'), '')) ??
            0;
    Navigator.of(context).pop({
      'modalAwal': modal,
      'keterangan': _catatanController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buka Kasir'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pola sama dgn status hijau "Kas terbuka sejak..." di _DialogTutupKas
            // (padanan `.sesikas-status.buka`/`.tutup` versi Electron) -- sebelumnya
            // dialog ini TIDAK punya status berwarna, cuma hint abu-abu netral.
            const Text('Kas sedang tertutup',
                style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Isi modal awal untuk memulai sesi kasir.',
              style: TextStyle(color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Modal Awal (Rp)', border: OutlineInputBorder()),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onTap: () {
                if (_controller.text == '0') {
                  _controller.selection = TextSelection(
                      baseOffset: 0, extentOffset: _controller.text.length);
                }
              },
              onSubmitted: (_) => _konfirmasi(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _catatanController,
              decoration: const InputDecoration(
                  labelText: 'Catatan Pembukaan (opsional)',
                  border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        ElevatedButton(onPressed: _konfirmasi, child: const Text('Buka Kas')),
      ],
    );
  }
}

class _OverlayBukaKas extends StatefulWidget {
  final void Function(double modalAwal, String catatan) onBuka;
  final bool sesiDiPerangkatLain;
  final String namaPerangkatLain;
  final String pesan;
  final Future<void> Function() onPeriksaUlang;
  const _OverlayBukaKas(
      {required this.onBuka,
      required this.sesiDiPerangkatLain,
      required this.namaPerangkatLain,
      required this.pesan,
      required this.onPeriksaUlang});

  @override
  State<_OverlayBukaKas> createState() => _OverlayBukaKasState();
}

class _OverlayBukaKasState extends State<_OverlayBukaKas> {
  final _controller = TextEditingController(text: '0');
  final _catatanController = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.point_of_sale,
                        size: 32, color: AppColors.primary),
                    const SizedBox(height: 8),
                    Text(
                        widget.sesiDiPerangkatLain
                            ? 'Kas Aktif di Perangkat Lain'
                            : 'Buka Kas Terlebih Dahulu',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    // Padanan `.sesikas-status.tutup` versi Electron -- status
                    // berwarna merah SEBELUM deskripsi netral, konsisten dgn
                    // _DialogBukaKas/_DialogTutupKas.
                    Text(
                        widget.sesiDiPerangkatLain
                            ? 'Transaksi pada perangkat ini dikunci'
                            : 'Kas sedang tertutup',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text(
                      widget.sesiDiPerangkatLain
                          ? (widget.pesan.isNotEmpty
                              ? widget.pesan
                              : 'Akun ini masih memiliki sesi kas aktif di ${widget.namaPerangkatLain.isEmpty ? 'perangkat lain' : widget.namaPerangkatLain}. Tutup kas di perangkat tersebut, lalu periksa ulang. Pembukaan kas dan transaksi baru tidak diizinkan di perangkat ini.')
                          : 'Kasir wajib membuka sesi kas sebelum bisa mulai menjual.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 14),
                    if (!widget.sesiDiPerangkatLain)
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                            labelText: 'Modal Awal (Rp)',
                            isDense: true,
                            border: OutlineInputBorder()),
                        onTap: () {
                          if (_controller.text == '0') {
                            _controller.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _controller.text.length);
                          }
                        },
                        onSubmitted: (_) {
                          final modal = double.tryParse(_controller.text) ?? 0;
                          widget.onBuka(modal, _catatanController.text.trim());
                        },
                      ),
                    if (!widget.sesiDiPerangkatLain) const SizedBox(height: 10),
                    if (!widget.sesiDiPerangkatLain)
                      TextField(
                        controller: _catatanController,
                        decoration: const InputDecoration(
                            labelText: 'Catatan Pembukaan (opsional)',
                            isDense: true,
                            border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.sesiDiPerangkatLain
                            ? widget.onPeriksaUlang
                            : () {
                                final modal = double.tryParse(_controller.text
                                        .replaceAll(RegExp('[^0-9.]'), '')) ??
                                    0;
                                widget.onBuka(
                                    modal, _catatanController.text.trim());
                              },
                        child: Text(widget.sesiDiPerangkatLain
                            ? 'Periksa Ulang Status Kas'
                            : 'Buka Kas'),
                      ),
                    ),
                  ],
                ),
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
const _paletKartuProduk = [
  Color(0xFF2563EB),
  Color(0xFF0D9488),
  Color(0xFFC0563D),
  Color(0xFF7C3AED),
  Color(0xFFEA580C),
  Color(0xFF0284C7)
];

/// Satu baris dropdown hasil pencarian (mode Fokus Keranjang) -- padanan
/// `.baris-hasil` pos-renderer.js: badge nomor (Ctrl+angka), avatar inisial
/// senada `_KartuProduk`, nama+kode (+" · Habis" kalau stok 0), harga di kanan.
class _BarisHasilPencarian extends StatelessWidget {
  final String nomor;
  final Produk produk;
  final VoidCallback onTap;
  const _BarisHasilPencarian(
      {required this.nomor, required this.produk, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final habis = produk.stok <= 0;
    final warnaAvatar = _paletKartuProduk[produk.nama.isEmpty
        ? 0
        : produk.nama.codeUnitAt(0) % _paletKartuProduk.length];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: nomor.isEmpty
                  ? null
                  : Text(nomor,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondaryOf(context))),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.latarLembut(warnaAvatar),
              child: Text(
                  produk.nama.isNotEmpty ? produk.nama[0].toUpperCase() : '?',
                  style: TextStyle(
                      color: warnaAvatar,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(produk.nama,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimaryOf(context))),
                  Text('${produk.kode}${habis ? ' · Habis' : ''}',
                      style: TextStyle(
                          fontSize: 11,
                          color: habis
                              ? AppColors.danger
                              : AppColors.textSecondaryOf(context))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_formatRupiah.format(produk.hargaJual),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

class _KartuProduk extends StatefulWidget {
  final Produk produk;
  final VoidCallback onTap;

  /// "Harga Coret" (gap-closure Fase 2 Stretch) -- nominal diskon dari preview
  /// katalog PUBLIK ([_KasirScreenState._evaluasiHargaCoret]), `null`/`0` utk
  /// mayoritas produk tanpa promo publik aktif (rendering harga tunggal lama,
  /// TIDAK berubah). Hanya diisi pemanggil utk `diskon > 0` (lihat filter di
  /// [_KasirScreenState._evaluasiHargaCoret]) -- kartu ini sendiri tetap jaga
  /// gerbang `> 0` supaya aman dipanggil apa adanya.
  final double? diskon;
  final double? cashback;
  const _KartuProduk(
      {required this.produk, required this.onTap, this.diskon, this.cashback});

  @override
  State<_KartuProduk> createState() => _KartuProdukState();
}

/// Gap-closure "Foto Produk": kartu ini SEKARANG stateful semata-mata utk
/// carousel foto -- kalau [Produk.fotoUrls] > 1, `Timer.periodic` 3 detik
/// menggeser indeks foto yang ditampilkan (permintaan user eksplisit: "tiap
/// 3 detik, ganti-ganti otomatis"). Tepat 1 foto -> statis, timer TIDAK
/// dipasang sama sekali (juga permintaan eksplisit: "kalau hanya 1, tidak
/// perlu ganti-ganti"). 0 foto -> fallback avatar inisial (perilaku lama,
/// tidak berubah).
class _KartuProdukState extends State<_KartuProduk> {
  int _indeksFoto = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _aturTimer();
  }

  @override
  void didUpdateWidget(covariant _KartuProduk old) {
    super.didUpdateWidget(old);
    // Grid Kasir bisa memuat ulang produk (sinkron katalog) sementara kartu
    // yang sama tetap hidup di posisi GridView yg sama -- reset indeks+timer
    // kalau daftar foto produk ini berubah, supaya tak nunjuk indeks basi.
    if (!listEquals(old.produk.fotoUrls, widget.produk.fotoUrls)) {
      _indeksFoto = 0;
      _aturTimer();
    }
  }

  void _aturTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.produk.fotoUrls.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        setState(() =>
            _indeksFoto = (_indeksFoto + 1) % widget.produk.fotoUrls.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final produk = widget.produk;
    final onTap = widget.onTap;
    final diskon = widget.diskon;
    final cashback = widget.cashback;
    final habis = produk.stok <= 0;
    final stokRendah = !habis && produk.stok <= 5;
    final warnaAvatar = _paletKartuProduk[produk.nama.isEmpty
        ? 0
        : produk.nama.codeUnitAt(0) % _paletKartuProduk.length];
    final adaPromo = (diskon ?? 0) > 0;
    final hargaPromo = adaPromo ? produk.hargaJual - diskon! : produk.hargaJual;
    final adaFoto = produk.fotoUrls.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: AppColors.gelap(context)
            ? const []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
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
                    ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      child: adaFoto
                          ? AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              child: Image.network(
                                produk.fotoUrls[
                                    _indeksFoto % produk.fotoUrls.length],
                                key: ValueKey(
                                    _indeksFoto % produk.fotoUrls.length),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.latarLembut(warnaAvatar),
                                  child: Center(
                                    child: Text(
                                      produk.nama.isNotEmpty
                                          ? produk.nama[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                          color: warnaAvatar,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: AppColors.latarLembut(warnaAvatar),
                              child: Center(
                                child: Text(
                                  produk.nama.isNotEmpty
                                      ? produk.nama[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: warnaAvatar,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: habis
                              ? AppColors.danger
                              : (stokRendah
                                  ? AppColors.warning
                                  : AppColors.cardBgOf(context)),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 3)
                          ],
                        ),
                        child: Text(
                          habis ? 'Habis' : 'Stok ${produk.stok}',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: habis || stokRendah
                                  ? Colors.white
                                  : AppColors.textSecondaryOf(context)),
                        ),
                      ),
                    ),
                    if ((cashback ?? 0) > 0)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                              'Cashback ${_formatRupiah.format(cashback)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700)),
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
                    Text(produk.nama,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.textPrimaryOf(context))),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                            child: adaPromo
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                          _formatRupiah.format(
                                              produk.hargaJual),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.textSecondaryOf(
                                                  context),
                                              decoration:
                                                  TextDecoration.lineThrough,
                                              fontSize: 11)),
                                      Text(_formatRupiah.format(hargaPromo),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: AppColors.danger,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                    ],
                                  )
                                : Text(_formatRupiah.format(produk.hargaJual),
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13))),
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                              color: habis
                                  ? AppColors.borderOf(context)
                                  : AppColors.primary,
                              shape: BoxShape.circle),
                          child: Icon(Icons.add,
                              color: habis
                                  ? AppColors.textSecondaryOf(context)
                                  : Colors.white,
                              size: 16),
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
  final bool bolehKoreksiNominal;
  const _DialogTutupKas({
    required this.status,
    required this.bolehKoreksiNominal,
  });

  @override
  State<_DialogTutupKas> createState() => _DialogTutupKasState();
}

class _DialogTutupKasState extends State<_DialogTutupKas> {
  late final TextEditingController _uangFisikController;
  late final TextEditingController _modalAwalController;
  late final TextEditingController _penjualanTunaiController;
  final _keteranganController = TextEditingController();
  final _alasanKoreksiController = TextEditingController();
  bool _modeKoreksi = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final kasSaatIni = (widget.status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    final modalAwal = (widget.status['modalAwal'] as num?)?.toDouble() ?? 0;
    final penjualanTunai =
        (widget.status['totalTunai'] as num?)?.toDouble() ?? 0;
    _uangFisikController =
        TextEditingController(text: kasSaatIni.toStringAsFixed(0));
    _modalAwalController =
        TextEditingController(text: modalAwal.toStringAsFixed(0));
    _penjualanTunaiController =
        TextEditingController(text: penjualanTunai.toStringAsFixed(0));
    _modalAwalController.addListener(_perbaruiTampilanKoreksi);
    _penjualanTunaiController.addListener(_perbaruiTampilanKoreksi);
  }

  void _perbaruiTampilanKoreksi() {
    if (mounted && _modeKoreksi) setState(() {});
  }

  @override
  void dispose() {
    _uangFisikController.dispose();
    _modalAwalController
      ..removeListener(_perbaruiTampilanKoreksi)
      ..dispose();
    _penjualanTunaiController
      ..removeListener(_perbaruiTampilanKoreksi)
      ..dispose();
    _keteranganController.dispose();
    _alasanKoreksiController.dispose();
    super.dispose();
  }

  void _konfirmasi() {
    final uangFisik = double.tryParse(
        _uangFisikController.text.replaceAll(RegExp('[^0-9.]'), ''));
    if (uangFisik == null || uangFisik < 0) {
      setStateIfMounted(
          () => _error = 'Uang fisik wajib berupa angka nol atau lebih.');
      return;
    }
    if (_keteranganController.text.trim().isEmpty) {
      setStateIfMounted(() => _error = 'Catatan penutupan wajib diisi.');
      return;
    }
    double? modalAwalKoreksi;
    double? penjualanTunaiKoreksi;
    if (_modeKoreksi) {
      modalAwalKoreksi = double.tryParse(
          _modalAwalController.text.replaceAll(RegExp('[^0-9.]'), ''));
      if (modalAwalKoreksi == null || modalAwalKoreksi < 0) {
        setStateIfMounted(
            () => _error = 'Modal awal hasil koreksi wajib berupa angka.');
        return;
      }
      penjualanTunaiKoreksi = double.tryParse(
          _penjualanTunaiController.text.replaceAll(RegExp('[^0-9.]'), ''));
      if (penjualanTunaiKoreksi == null || penjualanTunaiKoreksi < 0) {
        setStateIfMounted(
            () => _error = 'Penjualan tunai hasil koreksi wajib berupa angka.');
        return;
      }
      if (_alasanKoreksiController.text.trim().length < 5) {
        setStateIfMounted(() => _error =
            'Alasan koreksi supervisor wajib diisi minimal 5 karakter.');
        return;
      }
    }
    Navigator.of(context).pop(<String, dynamic>{
      'uangFisik': uangFisik,
      'keterangan': _keteranganController.text.trim(),
      if (modalAwalKoreksi != null) 'modalAwalKoreksi': modalAwalKoreksi,
      if (penjualanTunaiKoreksi != null)
        'penjualanTunaiKoreksi': penjualanTunaiKoreksi,
      if (modalAwalKoreksi != null)
        'alasanKoreksi': _alasanKoreksiController.text.trim(),
    });
  }

  String? get _waktuBukaFormatted {
    final raw = widget.status['waktuBuka'] as String?;
    if (raw == null) return null;
    try {
      final w = DateTime.parse(raw);
      return DateFormat('dd/MM, HH:mm').format(w);
    } catch (_) {
      return null;
    }
  }

  Widget _kartuStat(String label, String nilai) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.pageBgOf(context),
            borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryOf(context),
                    letterSpacing: 0.3)),
            const SizedBox(height: 4),
            Text(nilai,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimaryOf(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modalAwalAsli = (widget.status['modalAwal'] as num?)?.toDouble() ?? 0;
    final modalAwalInput = double.tryParse(
        _modalAwalController.text.replaceAll(RegExp('[^0-9.]'), ''));
    final modalAwal =
        _modeKoreksi && modalAwalInput != null ? modalAwalInput : modalAwalAsli;
    final totalTunaiAsli =
        (widget.status['totalTunai'] as num?)?.toDouble() ?? 0;
    final totalTunaiInput = double.tryParse(
        _penjualanTunaiController.text.replaceAll(RegExp('[^0-9.]'), ''));
    final totalTunai = _modeKoreksi && totalTunaiInput != null
        ? totalTunaiInput
        : totalTunaiAsli;
    final totalNonTunai =
        (widget.status['totalNonTunai'] as num?)?.toDouble() ?? 0;
    final kasSaatIniAsli =
        (widget.status['kasSaatIni'] as num?)?.toDouble() ?? 0;
    final kasSaatIni = kasSaatIniAsli +
        modalAwal -
        modalAwalAsli +
        totalTunai -
        totalTunaiAsli;
    final waktuBuka = _waktuBukaFormatted;
    return AlertDialog(
      title: const Text('Sesi Kasir'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: const Icon(Icons.person_outline, size: 17),
                    label: Text(
                        '${widget.status['kasirNama'] ?? Sesi.instance.userId}'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.computer_outlined, size: 17),
                    label: Text(
                        '${widget.status['namaPerangkat'] ?? IdentitasMesin.instance.namaMesin}'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (waktuBuka != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Kas terbuka sejak $waktuBuka',
                      style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
              Row(children: [
                _kartuStat('Modal Awal', _formatRupiah.format(modalAwal)),
                const SizedBox(width: 10),
                _kartuStat('Penjualan Tunai', _formatRupiah.format(totalTunai))
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _kartuStat('Non Tunai', _formatRupiah.format(totalNonTunai)),
                const SizedBox(width: 10),
                _kartuStat('Kas Seharusnya', _formatRupiah.format(kasSaatIni))
              ]),
              if (widget.bolehKoreksiNominal) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _modeKoreksi = !_modeKoreksi;
                      _error = null;
                      if (!_modeKoreksi) {
                        _modalAwalController.text =
                            modalAwalAsli.toStringAsFixed(0);
                        _penjualanTunaiController.text =
                            totalTunaiAsli.toStringAsFixed(0);
                        _alasanKoreksiController.clear();
                      }
                    }),
                    icon: Icon(_modeKoreksi ? Icons.close : Icons.edit_outlined,
                        size: 17),
                    label: Text(
                        _modeKoreksi ? 'Batalkan Edit' : 'Edit Nominal Sesi'),
                  ),
                ),
              ],
              if (_modeKoreksi) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _modalAwalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Modal Awal Hasil Koreksi (Rp) *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _penjualanTunaiController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Penjualan Tunai Hasil Koreksi (Rp) *',
                    helperText:
                        'Kas seharusnya dihitung ulang otomatis dari koreksi ini.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _alasanKoreksiController,
                  decoration: const InputDecoration(
                    labelText: 'Alasan Koreksi Supervisor *',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red))),
              TextField(
                controller: _uangFisikController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Uang Fisik (Rp) *',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keteranganController,
                decoration: const InputDecoration(
                    labelText: 'Keterangan *', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal')),
        ElevatedButton(onPressed: _konfirmasi, child: const Text('Tutup Kas')),
      ],
    );
  }
}

/// Bottom sheet "Pilih Ekstra" -- checkbox per baris ekstra hasil resolusi
/// [Produk.ekstraPilihan] (nama/harga dari cache lokal, lihat JavaDoc
/// `KasirScreen._bukaPickerEkstra`). Ekstra bersifat OPSIONAL -- kasir boleh
/// menekan "Tambahkan ke Keranjang" tanpa mencentang apa pun (produk dasar
/// tetap masuk keranjang tanpa add-on), `null` (batal/tutup sheet) yang
/// membedakannya dari "sengaja tidak pilih ekstra apa pun".
class _SheetPilihEkstra extends StatefulWidget {
  final String produkNama;
  final List<Map<String, Object?>> daftar;
  const _SheetPilihEkstra({required this.produkNama, required this.daftar});

  @override
  State<_SheetPilihEkstra> createState() => _SheetPilihEkstraState();
}

class _SheetPilihEkstraState extends State<_SheetPilihEkstra> {
  final Set<int> _terpilih = {};

  void _toggle(int id) {
    setState(() {
      if (!_terpilih.remove(id)) _terpilih.add(id);
    });
  }

  void _konfirmasi() {
    final hasil =
        widget.daftar.where((b) => _terpilih.contains(b['id'] as int)).map((b) {
      return ItemEkstra(
        id: b['id'] as int,
        kode: (b['kode'] ?? '') as String,
        nama: (b['nama'] ?? '') as String,
        harga: (b['harga_jual'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    Navigator.of(context).pop(hasil);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline,
                        size: 18, color: AppColors.textPrimaryOf(context)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Pilih Ekstra -- ${widget.produkNama}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimaryOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: widget.daftar.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                            'Tidak ada pilihan ekstra tersedia (mungkin belum tersinkron -- coba Muat Ulang katalog).',
                            style: TextStyle(
                                color: AppColors.textSecondaryOf(context))),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: widget.daftar.length,
                        itemBuilder: (context, i) {
                          final b = widget.daftar[i];
                          final id = b['id'] as int;
                          final harga =
                              (b['harga_jual'] as num?)?.toDouble() ?? 0;
                          return CheckboxListTile(
                            value: _terpilih.contains(id),
                            onChanged: (_) => _toggle(id),
                            title: Text('${b['nama'] ?? ''}'),
                            secondary: Text('+${_formatRupiah.format(harga)}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary)),
                            controlAffinity: ListTileControlAffinity.leading,
                            dense: true,
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _konfirmasi,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Tambahkan ke Keranjang'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
