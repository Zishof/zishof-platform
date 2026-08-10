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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import '../app_variant.dart';
import '../models.dart';
import '../sesi.dart';
import '../services/layar_pelanggan_broadcaster.dart';
import '../services/layar_pelanggan_launcher.dart';
import '../services/pelayanan_transaksi.dart';
import '../services/pengaturan_laci.dart';
import '../services/pesanan_poller.dart';
import '../services/toko_aktif_lokal.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import 'login_screen.dart';
import 'keranjang_screen.dart';
import 'bantuan_screen.dart';
import 'akun_saya_screen.dart';
import '../widgets/safe_state.dart';

final _formatRupiah =
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

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
  final _fokusKataKunci = FocusNode();

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
    _muatPreferensiTampilan();
    _muatAwal();
    _jadwalkanFokusCariItem();
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
    _kataKunciController.dispose();
    _fokusKataKunci.dispose();
    super.dispose();
  }

  Future<void> _muatAwal() async {
    setStateIfMounted(() {
      _memuat = true;
      _pesanError = null;
    });

    // 1) Baca cache lokal DULU (offline-first) -- kasir bisa langsung mulai
    //    kerja walau server sedang lambat/offline, produk_cache jadi satu-
    //    satunya sumber yang dibaca layar Kasir (sama seperti pos-renderer.js).
    try {
      final cache = await CoreDb.instance.produkCache();
      if (cache.isNotEmpty) {
        setStateIfMounted(
            () => _semuaProduk = cache.map(_produkDariCache).toList());
      }
    } catch (_) {
      // cache lokal gagal dibaca (mis. pertama kali install) -- lanjut ke jalur server saja.
    }

    await _perbaruiJumlahPending();
    await _sinkronKatalogDanKonfigurasi(
        tampilkanErrorJikaKosong: _semuaProduk.isEmpty);
    await _periksaSesiKas();
    PesananPoller.instance.mulai();

    if (mounted) {
      setStateIfMounted(() => _memuat = false);
      _jadwalkanFokusCariItem();
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
      );

  void _terapkanKonfig(Map<String, dynamic> konfig) {
    Sesi.instance
      ..tokoNama = (konfig['tokoNama'] ?? '') as String
      ..tokoAlamat = '${konfig['tokoAlamat'] ?? konfig['alamat'] ?? ''}'.trim()
      ..tokoTelp =
          '${konfig['tokoTelp'] ?? konfig['telp'] ?? konfig['picHp'] ?? konfig['kontak'] ?? ''}'
              .trim()
      ..tokoId = konfig['tokoId'] as int?
      ..userId = (konfig['userId'] ?? '') as String
      ..pajakPersen = (konfig['pajakPersen'] as num?)?.toDouble() ?? 0
      ..pesanTerimaKasih = (konfig['pesanTerimaKasih'] ?? '') as String
      ..wajibSesiKas = konfig['wajibSesiKas'] == true
      ..isAdmin = konfig['isAdmin'] == true
      ..supervisorPedagang = konfig['supervisorPedagang'] == true
      ..bolehEntryTopup = konfig['bolehEntryTopup'] == true
      ..caraBayar = ((konfig['caraBayar'] as List?) ?? [])
          .map((e) => CaraBayar.fromJson(e as Map<String, dynamic>))
          .toList()
      ..aksesMenu = ((konfig['aksesMenu'] as Map<String, dynamic>?) ?? {})
          .map((k, v) => MapEntry(k, v == true))
      ..multiToko = konfig['multiToko'] == true
      ..daftarToko =
          ((konfig['daftarToko'] as List?) ?? []).cast<Map<String, dynamic>>();
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
    if (!Sesi.instance.multiToko) return;

    if (klaimBaru) {
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(Sesi.instance.tokoId!);
      }
      return;
    }

    final idKlaimLokal = await TokoAktifLokal.instance.muat();
    if (idKlaimLokal == null) {
      // Belum ada klaim di perangkat ini -- saran server jadi klaim awal.
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(Sesi.instance.tokoId!);
      }
      return;
    }

    final tokoKlaim = Sesi.instance.daftarToko.where((t) => t['id'] == idKlaimLokal);
    if (tokoKlaim.isEmpty) {
      // Klaim lama sudah tak berlaku (mis. akses toko itu dicabut) -- lepas
      // klaim lama, terima saran server sbg klaim baru.
      if (Sesi.instance.tokoId != null) {
        await TokoAktifLokal.instance.simpan(Sesi.instance.tokoId!);
      } else {
        await TokoAktifLokal.instance.hapus();
      }
      return;
    }

    // Klaim lokal masih valid -- MENANG atas saran server, apa pun toko yang
    // server sarankan (bisa jadi hasil pilihan jendela/mesin lain).
    Sesi.instance.tokoId = idKlaimLokal;
    Sesi.instance.tokoNama = '${tokoKlaim.first['nama'] ?? ''}';
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

      final katalog = await ApiClient.instance.aksi('katalog');
      final produkJson = (katalog['produk'] as List?) ?? [];
      final produk = produkJson
          .map((e) => Produk.fromJson(e as Map<String, dynamic>))
          .toList();
      final kategori = ((katalog['kategori'] as List?) ?? [])
          .map((e) => Kategori.fromJson(e as Map<String, dynamic>))
          .toList();

      await CoreDb.instance.replaceProdukCache(produkJson
          .map((e) => Produk.baseKeCacheRow(e as Map<String, dynamic>))
          .toList());

      if (mounted) {
        setStateIfMounted(() {
          _semuaProduk = produk;
          _kategori = kategori;
        });
      }
    } catch (e) {
      final off = e is ApiException && e.offline;
      if (tampilkanErrorJikaKosong && _semuaProduk.isEmpty) {
        setStateIfMounted(() => _pesanError = off
            ? 'Belum ada data katalog tersimpan & server tidak terjangkau. Sambungkan internet lalu coba lagi.'
            : e.toString());
      }
      // Jika cache lokal SUDAH ada isinya, kegagalan sinkron di sini SENGAJA
      // diabaikan (Kasir tetap bisa jualan pakai data cache terakhir).
    }
  }

  Future<void> _periksaSesiKas() async {
    try {
      final hasil = await ApiClient.instance
          .aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
      final terbuka = hasil['terbuka'] == true;
      if (terbuka) {
        await CoreDb.instance.bukaSesiKasLokal(
          'sesi-${Sesi.instance.tokoId}',
          (hasil['modalAwal'] as num?)?.toDouble() ?? 0,
        );
      } else {
        await CoreDb.instance.tutupSemuaSesiKasLokal();
      }
      if (mounted) setStateIfMounted(() => _kasTerbuka = terbuka);
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

  /// Muat ulang saldo Kas Sekarang saja (tanpa menyentuh gerbang buka/tutup
  /// kas) -- dipanggil dari [_perbaruiJumlahPending] tiap kali transaksi
  /// baru selesai (Bayar/Tahan/Sinkronkan) supaya pil toolbar selalu segar.
  Future<void> _muatKasSaatIni() async {
    if (_kasTerbuka != true) return;
    try {
      final hasil = await ApiClient.instance
          .aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
      if (mounted) {
        setStateIfMounted(
            () => _kasSaatIni = (hasil['kasSaatIni'] as num?)?.toDouble() ?? 0);
      }
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
      status = await ApiClient.instance
          .aksi('sesi_kas_status', {'id_toko': Sesi.instance.tokoId});
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
      builder: (_) => _DialogTutupKas(status: status!),
    );
    if (hasilTutup == null) return;

    final kodeLokal =
        (await CoreDb.instance.sesiKasAktif())?['kode'] as String?;
    try {
      final hasil = await ApiClient.instance.aksi('sesi_kas_tutup', {
        'id_toko': Sesi.instance.tokoId,
        'kode': kodeLokal,
        'uang_fisik': hasilTutup['uangFisik'],
        'keterangan': hasilTutup['keterangan'],
      });
      if (kodeLokal != null) await CoreDb.instance.tutupSesiKasLokal(kodeLokal);
      if (mounted) setStateIfMounted(() => _kasTerbuka = false);
      final selisih = (hasil['selisih'] as num?)?.toDouble() ?? 0;
      final stokMenipis =
          ((hasil['stokMenipis'] as List?) ?? []).cast<Map<String, dynamic>>();
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
              Text(
                  'Uang Fisik: ${_formatRupiah.format(hasilTutup['uangFisik'])}'),
              const SizedBox(height: 8),
              Text('Selisih: ${_formatRupiah.format(selisih)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: selisih < 0 ? Colors.red : Colors.green.shade700)),
              if (stokMenipis.isNotEmpty) ...[
                const Divider(height: 24),
                Text('${stokMenipis.length} Produk Perlu Direstok:',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: stokMenipis
                          .map((p) => Text(
                              '• ${p['nama']} (stok ${p['stok']}, min ${p['stokMinimum']})',
                              style: const TextStyle(fontSize: 12)))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'))
          ],
        ),
      );
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
    await CoreDb.instance.bukaSesiKasLokal(kode, modalAwal);
    if (mounted) {
      setStateIfMounted(() => _kasTerbuka = true);
      _jadwalkanFokusCariItem();
    }
    try {
      await ApiClient.instance.aksi('sesi_kas_buka', {
        'id_toko': Sesi.instance.tokoId,
        'kode': kode,
        'modal_awal': modalAwal,
        // Server SUDAH menerima+menyimpan field ini sejak lama
        // (KantinHelper.sesiKasBuka -> SesiKasUtil.buka -> setKeterangan) --
        // hanya form Buka Kas yg belum pernah mengirimkannya.
        'keterangan': catatan,
      });
    } catch (_) {
      // Gagal tersinkron ke server -- tetap dianggap terbuka secara lokal
      // (local-first), akan disinkron ulang saat "Sinkronkan Sekarang".
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
    final n = await CoreDb.instance.jumlahTransaksiPending();
    if (mounted) setStateIfMounted(() => _jumlahPending = n);
    unawaited(_muatKasSaatIni());
  }

  Future<void> _tandaiTerlayaniJikaPerlu(
      Map<String, dynamic> payload, Map<String, dynamic> hasil) async {
    await PelayananTransaksi.tandaiJikaPerlu(
      payload: payload,
      hasilBayar: hasil,
      percobaanCari: 1,
    );
  }

  void _setelahTransaksiSelesai() {
    unawaited(_perbaruiJumlahPending());
    _jadwalkanFokusCariItem();
  }

  Future<void> _sinkronkanSekarang() async {
    if (_sinkronBerjalan) return;
    setStateIfMounted(() => _sinkronBerjalan = true);
    try {
      final pending = await CoreDb.instance.transaksiPendingBelumSinkron();
      var berhasil = 0;
      for (final row in pending) {
        final kodeUnik = row['kode_unik'] as String;
        final payload =
            jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
        try {
          final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
          await _tandaiTerlayaniJikaPerlu(payload, hasilBayar);
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
            if (e is ApiException && e.offline) {
              break; // masih offline -- hentikan, coba lagi nanti
            }
          }
        }
      }
      await _perbaruiJumlahPending();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '$berhasil dari ${pending.length} transaksi berhasil disinkron.')),
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
      final cocokKeyword = _kataKunci.isEmpty ||
          p.nama.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.kode.toLowerCase().contains(_kataKunci.toLowerCase()) ||
          p.barcode.toLowerCase().contains(_kataKunci.toLowerCase());
      return cocokKategori && cocokKeyword;
    }).toList();
  }

  void _tambahKeKeranjang(Produk p) {
    setStateIfMounted(() {
      final existing = _keranjang.where((i) => i.produk.id == p.id).toList();
      if (existing.isNotEmpty) {
        existing.first.jumlah++;
      } else {
        _keranjang.add(ItemKeranjang(produk: p));
      }
      if (_kataKunciController.text.isNotEmpty || _kataKunci.isNotEmpty) {
        _kataKunciController.clear();
        _kataKunci = '';
      }
    });
    _siarkanKeranjangKasir();
    _jadwalkanFokusCariItem();
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
    _jadwalkanFokusCariItem();
  }

  /// Dipanggil saat kasir menekan Enter di kotak pencarian -- padanan
  /// "Enter-keystroke detection" pada scanner barcode HID di pos-renderer.js:
  /// kalau kode/barcode COCOK PERSIS satu produk, langsung tambah ke
  /// keranjang & bersihkan kotak (siap utk scan berikutnya tanpa kasir perlu
  /// mengetuk apa pun).
  void _submitPencarian(String nilai) {
    final v = nilai.trim();
    if (v.isEmpty) return;
    final cocok =
        _semuaProduk.where((p) => p.kode == v || p.barcode == v).toList();
    if (cocok.isNotEmpty) {
      _tambahKeKeranjang(cocok.first);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${cocok.first.nama} ditambahkan'),
            duration: const Duration(milliseconds: 700)),
      );
      _kataKunciController.clear();
      setStateIfMounted(() => _kataKunci = '');
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

  Future<void> _bukaKeranjang() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => KeranjangScreen(keranjang: _keranjang),
    ));
    await _perbaruiJumlahPending();
    setStateIfMounted(() {});
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
          assetKeyword: AppVariant.updateAssetKeyword);
      if (!mounted) return;
      Navigator.of(context).pop(); // tutup loading
      if (hasil == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sudah menggunakan versi terbaru.')));
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
                final url = defaultTargetPlatform == TargetPlatform.android
                    ? (hasil.urlApk ?? hasil.urlRilis)
                    : (hasil.urlExe ?? hasil.urlRilis);
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BantuanScreen()));
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

  List<Widget> get _tombolAksi => [
        if (defaultTargetPlatform == TargetPlatform.windows) ...[
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: OutlinedButton.icon(
              onPressed: _toggleFokusKeranjang,
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
                      const Icon(Icons.storefront,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(Sesi.instance.tokoNama,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
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
                onPressed: _gantiToko,
                tooltip: 'Ganti Toko'),
          _tombolToolbar(
              icon: const Icon(Icons.desktop_windows_outlined, size: 18),
              label: 'Layar',
              onPressed: _bukaLayarPelanggan,
              tooltip: 'Layar Pelanggan (F9)'),
          _tombolToolbar(
              icon: const Icon(Icons.cloud_download_outlined, size: 18),
              label: 'Update',
              onPressed: _cekUpdateManual,
              tooltip: 'Cek Update Sistem'),
          _tombolToolbar(
            icon: _bukaLaciBerjalan
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.point_of_sale, size: 18),
            label: 'Laci',
            onPressed: _bukaLaciBerjalan ? null : _bukaLaci,
            tooltip: 'Buka Laci (F6)',
          ),
        ],
        _tombolToolbar(
          icon: const Icon(Icons.point_of_sale_outlined, size: 18),
          label: _kasTerbuka == true
              ? 'Kas'
              : (_kasTerbuka == null ? 'Cek Kas' : 'Buka Kas'),
          onPressed: _kasTerbuka == null
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
          onPressed: _sinkronBerjalan ? null : _sinkronkanSekarang,
          tooltip: 'Sinkronkan transaksi tertunda (F8)',
        ),
        _tombolToolbar(
            icon: const Icon(Icons.refresh, size: 18),
            label: 'Muat Ulang',
            onPressed: _muatAwal,
            tooltip: 'Muat ulang katalog'),
        if (defaultTargetPlatform == TargetPlatform.windows)
          _tombolToolbar(
              icon: const Icon(Icons.help_outline, size: 18),
              label: 'Bantuan',
              onPressed: _bukaBantuan,
              tooltip: 'Bantuan (F1)'),
        _tombolToolbar(
            icon: const Icon(Icons.account_circle_outlined, size: 18),
            label: 'Akun Saya',
            onPressed: _bukaAkunSaya,
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
  KeyEventResult _tanganiTombolKasir(FocusNode node, KeyEvent event) {
    if (defaultTargetPlatform != TargetPlatform.windows) {
      return KeyEventResult.ignored;
    }
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
          actionsAppBar: _tombolAksi,
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
                _OverlayBukaKas(onBuka: (modal, catatan) {
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
    final panel = PanelKeranjang(
      keranjang: _keranjang,
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
        SizedBox(width: 420, child: panel),
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
      onChanged: (v) => setStateIfMounted(() => _kataKunci = v),
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
                  onSelected: (_) =>
                      setStateIfMounted(() => _kategoriTerpilih = null),
                ),
              ),
              ..._kategori.map((k) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(k.nama),
                      selected: _kategoriTerpilih == k.id,
                      onSelected: (_) =>
                          setStateIfMounted(() => _kategoriTerpilih = k.id),
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
          children: [
            Text(
              'Isi modal awal untuk memulai sesi kasir.',
              style: TextStyle(color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Modal Awal (Rp)', border: OutlineInputBorder()),
              autofocus: true,
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
  const _OverlayBukaKas({required this.onBuka});

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
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.point_of_sale,
                      size: 48, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text('Buka Kas Terlebih Dahulu',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Kasir wajib membuka sesi kas sebelum bisa mulai menjual.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondaryOf(context)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Modal Awal (Rp)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _catatanController,
                    decoration: const InputDecoration(
                        labelText: 'Catatan Pembukaan (opsional)',
                        border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final modal = double.tryParse(_controller.text
                                .replaceAll(RegExp('[^0-9.]'), '')) ??
                            0;
                        widget.onBuka(modal, _catatanController.text.trim());
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
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: AppColors.primary)),
          ],
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
    final stokRendah = !habis && produk.stok <= 5;
    final warnaAvatar = _paletKartuProduk[produk.nama.isEmpty
        ? 0
        : produk.nama.codeUnitAt(0) % _paletKartuProduk.length];
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
                    Container(
                      decoration: BoxDecoration(
                          color: AppColors.latarLembut(warnaAvatar),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12))),
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
                            child: Text(_formatRupiah.format(produk.hargaJual),
                                style: const TextStyle(
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
    _uangFisikController =
        TextEditingController(text: kasSaatIni.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _uangFisikController.dispose();
    _keteranganController.dispose();
    super.dispose();
  }

  void _konfirmasi() {
    final uangFisik = double.tryParse(
        _uangFisikController.text.replaceAll(RegExp('[^0-9.]'), ''));
    if (uangFisik == null) {
      setStateIfMounted(() => _error = 'Uang fisik wajib diisi angka.');
      return;
    }
    if (_keteranganController.text.trim().isEmpty) {
      setStateIfMounted(() => _error = 'Catatan penutupan wajib diisi.');
      return;
    }
    Navigator.of(context).pop({
      'uangFisik': uangFisik,
      'keterangan': _keteranganController.text.trim()
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
    final modalAwal = (widget.status['modalAwal'] as num?)?.toDouble() ?? 0;
    final totalTunai = (widget.status['totalTunai'] as num?)?.toDouble() ?? 0;
    final totalNonTunai =
        (widget.status['totalNonTunai'] as num?)?.toDouble() ?? 0;
    final kasSaatIni = (widget.status['kasSaatIni'] as num?)?.toDouble() ?? 0;
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
