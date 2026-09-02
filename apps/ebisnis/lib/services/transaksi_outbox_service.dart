import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../sesi.dart';
import 'pelayanan_transaksi.dart';
import 'peringatan_transaksi.dart';

/// Pengirim ulang transaksi POS yang sudah ditulis ke SQLite sebelum request
/// pertama dilakukan. Satu instance hidup selama aplikasi berjalan sehingga
/// retry tidak bergantung pada layar Kasir sedang terbuka atau tombol Sinkron
/// ditekan pengguna.
///
/// Kegagalan jaringan/timeout dan gangguan teknis server terus dicoba sesuai
/// interval yang dapat dikonfigurasi. Penolakan bisnis yang pasti
/// (stok/saldo/hak akses/payload tidak valid) ditandai GAGAL agar tidak
/// membanjiri server. Semua retry memakai `kode_unik` asli, sehingga aman
/// terhadap respons yang hilang setelah server sempat menyimpan transaksi.
///
/// ===================================================================
/// ATURAN YANG TIDAK BOLEH DIUBAH TANPA MEMBACA SELURUH CATATAN INI
/// ===================================================================
///
/// Bagian ini ditulis setelah 61 transaksi Toko Al Bahjah (19-21 Agustus
/// 2026) tertahan berhari-hari: uang sudah diterima di kasir dan struk sudah
/// tercetak, tetapi penjualannya tidak pernah tercatat di server. Setiap
/// aturan di bawah ini adalah hasil penelusuran kejadian nyata, bukan
/// preferensi gaya. Melanggarnya berarti mengulang kehilangan uang yang sama.
///
/// 1. PAYLOAD DIKIRIM APA ADANYA. Baris outbox menyimpan payload lengkap
///    sejak checkout dan dikirim ulang persis seperti itu. JANGAN menyusun
///    ulang payload saat retry, dan JANGAN menambal/menormalkan isinya
///    (mis. mengganti `kode_sesi_kas` yang tampak salah, atau menyegarkan
///    harga). Payload adalah bukti apa yang terjadi di kasir pada saat
///    transaksi; begitu ia ditulis ulang, tidak ada lagi sumber kebenaran
///    untuk merekonsiliasi uang di laci.
///
/// 2. `waktu` TIDAK PERNAH DISENTUH. Server memakainya untuk
///    `tanggal_pembayaran` (lihat `waktuTransaksiDariPayload` di
///    KantinHelper). Kalau di sini diperbarui ke waktu kirim, transaksi yang
///    baru terkirim tiga hari kemudian akan tercatat di tanggal yang salah
///    dan seluruh laporan harian ikut salah.
///
/// 3. PENJAGA KEPEMILIKAN WAJIB MENINGGALKAN JEJAK. Baris milik kasir,
///    toko, atau perangkat lain memang dilewati -- tetapi alasannya HARUS
///    ditulis ke baris itu. Versi lama melewatinya diam-diam, sehingga
///    tombol kirim melaporkan "0 dari 61 berhasil" tanpa satu pun petunjuk
///    dan berjam-jam habis untuk menebak apakah server yang menolak atau
///    klien yang tidak mengirim. Kegagalan yang tidak terlihat jauh lebih
///    mahal daripada kegagalan yang berisik.
///
/// 4. REPLIKASI CADANGAN TIDAK BOLEH BERADA DI JALUR KIRIM. Dahulu
///    `_cadangkanTransaksiTokoTerbaru` di-await di dalam proses sinkronisasi
///    dan dijalankan pada SETIAP checkout, sehingga penjualan berikutnya
///    mengantre di belakang pemindaian dua hari milik seluruh toko yang bisa
///    memakan ratusan request berurutan. Ia sekarang dilepas dari jalur kirim
///    dan dibatasi sekali per interval. Jangan mengembalikannya ke dalam
///    mutex hanya supaya kodenya "lebih rapi berurutan".
///
/// 5. IDEMPOTENSI ADA DI SERVER, BUKAN DI SINI. Server menolak duplikat
///    berdasarkan `kode_unik`. Karena itu mengirim ulang SELALU aman, dan
///    itulah dasar tombol kirim ulang untuk baris yang sudah Sukses (dipakai
///    bila datanya terlanjur terhapus di server). Jangan menambah penjagaan
///    "anti kirim ganda" di klien yang justru memblokir pemulihan itu.
class TransaksiOutboxService {
  TransaksiOutboxService._();

  static final TransaksiOutboxService instance = TransaksiOutboxService._();
  static const int intervalRetryMenitDefault = 10;
  static const String _kunciIntervalRetry =
      'transaksi_pending_interval_retry_menit';

  /// Penanda bahwa pemulihan sekali-jalan di bawah sudah dijalankan pada
  /// perangkat ini. Bertanggal supaya pemulihan berikutnya (bila suatu saat
  /// dibutuhkan lagi) cukup memakai kunci baru, bukan menghapus yang ini.
  static const String _kunciPulihStok2026_09 =
      'transaksi_pending_pulih_penolakan_stok_2026_09';

  /// Cuplikan pesan penolakan stok versi lama. Sengaja dicocokkan pada POTONGAN
  /// yang stabil, bukan kalimat penuh: kalimatnya sudah diperbaiki di server
  /// (lihat docs/pos/73) dan baris lama menyimpan bunyi yang LAMA.
  static const List<String> _cuplikanPenolakanStokLama = [
    'dikunci admin',
    'tidak boleh dijual minus',
    'Wajib Diblokir Jika Stok Tidak Cukup',
  ];

  Timer? _timer;
  Timer? _retryTertunda;
  Future<HasilSinkronisasiTransaksi>? _prosesAktif;
  bool _sedangMemulai = false;
  int _intervalRetryMenit = intervalRetryMenitDefault;
  bool _cadanganBerjalan = false;
  DateTime? _cadanganTerakhir;

  int get intervalRetryMenit => _intervalRetryMenit;

  void mulai() {
    if (_timer != null || _sedangMemulai) return;
    _sedangMemulai = true;
    unawaited(_mulaiInternal());
  }

  Future<void> _mulaiInternal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _intervalRetryMenit = _normalisasiInterval(
          sp.getInt(_kunciIntervalRetry) ?? intervalRetryMenitDefault);
      _pasangTimer();
    } finally {
      _sedangMemulai = false;
    }
    unawaited(pulihkanTerparkirPenolakanStok());
    unawaited(sinkronkan());
  }

  /// Bangunkan transaksi yang terparkir GAGAL karena penolakan stok yang
  /// TERNYATA KELIRU.
  ///
  /// <h3>Kenapa perlu jalur khusus</h3>
  /// `STOK_TIDAK_CUKUP` termasuk [kodePenolakanPermanen], dan retry otomatis
  /// hanya membaca baris berstatus PENDING. Jadi setiap transaksi luring yang
  /// ditolak gerbang stok langsung diparkir GAGAL dan TIDAK PERNAH dicoba lagi
  /// dengan sendirinya. Itu memang benar untuk penolakan yang sah.
  ///
  /// Tetapi sejak r77493 (16-08-2026) sampai perbaikannya pada 02-09-2026,
  /// gerbang itu menolak produk yang tidak pernah dikunci admin sama sekali --
  /// nilai `null` ("Ikut Pengaturan Toko") diperlakukan sebagai "Wajib
  /// Diblokir" (lihat docs/pos/73). Transaksi yang diparkir karenanya adalah
  /// penjualan SAH: uangnya sudah diterima kasir dan struknya sudah tercetak,
  /// tetapi nilainya tidak pernah sampai ke server.
  ///
  /// Perbaikan di server hanya menghentikan yang baru. Baris yang sudah
  /// terparkir tetap diam sampai ada yang menekan "Kirim Ulang" di tiap
  /// perangkat -- dan tidak ada yang tahu harus menekannya. Persis bentuk
  /// kehilangan uang yang dicatat pada aturan 3 di kepala berkas ini:
  /// kegagalan yang tidak terlihat jauh lebih mahal daripada yang berisik.
  ///
  /// <h3>Kenapa aman</h3>
  /// Hanya baris yang pesan galatnya memang berbunyi penolakan stok yang
  /// dibangunkan -- penolakan lain (produk kadaluarsa, data tidak lengkap)
  /// tidak disentuh. Pengiriman ulang memakai `kode_unik` asli, dan server
  /// menolak duplikat lewat `DUPLIKAT_KODE_TRANSAKSI` yang di sini sudah
  /// diperlakukan sebagai "sudah ada di server" -- jadi membangunkan baris yang
  /// ternyata sempat tersimpan TIDAK menghasilkan transaksi ganda.
  ///
  /// Dijalankan sekali per perangkat (ditandai [_kunciPulihStok2026_09]).
  /// Bila gerbangnya masih menolak dengan alasan yang sah, barisnya akan
  /// kembali GAGAL sendiri dengan sebab yang tercatat -- tidak ada yang hilang.
  /// Apakah sebuah baris GAGAL diparkir oleh penolakan stok versi lama.
  ///
  /// Dipisah dan dibuat publik supaya dapat diuji tanpa basis data: yang
  /// menentukan transaksi mana yang dibangunkan adalah pencocokan teks ini, dan
  /// pencocokan teks adalah tempat kesalahan paling mudah lolos -- terlalu
  /// longgar akan membangunkan penolakan yang sah (mis. produk kadaluarsa),
  /// terlalu ketat tidak membangunkan apa pun dan penjualannya tetap hilang.
  bool terparkirPenolakanStokKeliru(String? pesanError) {
    final pesan = (pesanError ?? '').toLowerCase();
    if (pesan.isEmpty) return false;
    return _cuplikanPenolakanStokLama
        .any((c) => pesan.contains(c.toLowerCase()));
  }

  Future<int> pulihkanTerparkirPenolakanStok() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (sp.getBool(_kunciPulihStok2026_09) == true) return 0;

      final gagal = await CoreDb.instance.transaksiGagalBelumSinkron();
      final kode = <String>[];
      for (final row in gagal) {
        if (!terparkirPenolakanStokKeliru('${row['pesan_error'] ?? ''}')) {
          continue;
        }
        final k = '${row['kode_unik'] ?? ''}';
        if (k.isNotEmpty) kode.add(k);
      }

      var dibangunkan = 0;
      if (kode.isNotEmpty) {
        dibangunkan = await CoreDb.instance.kembalikanTransaksiKeAntrean(kode);
      }
      // Ditandai SESUDAH berhasil, bukan sebelum: bila proses ini gagal di
      // tengah jalan, percobaan berikutnya masih menemukan barisnya.
      await sp.setBool(_kunciPulihStok2026_09, true);

      // Jejaknya ditulis walau nol -- supaya pertanyaan "apakah pemulihan itu
      // pernah jalan di perangkat ini?" punya jawaban, bukan tebakan.
      await CoreDb.instance.catatErrorLog(
        sumber: 'outbox-pulih-stok',
        tingkat: dibangunkan > 0 ? 'WARN' : 'INFO',
        pesan: 'Pemulihan penolakan stok keliru: $dibangunkan dari '
            '${gagal.length} transaksi GAGAL dikembalikan ke antrean.',
        detail: kode.join(', '),
      );
      return dibangunkan;
    } catch (e) {
      // Pemulihan tidak boleh menggagalkan start-up service. Penandanya sengaja
      // TIDAK dipasang di jalur ini, jadi percobaan berikutnya masih terjadi.
      await CoreDb.instance.catatErrorLog(
          sumber: 'outbox-pulih-stok',
          tingkat: 'WARN',
          pesan: 'Pemulihan penolakan stok gagal dijalankan: $e');
      return 0;
    }
  }

  int _normalisasiInterval(int menit) => menit.clamp(1, 1440).toInt();

  void _pasangTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(minutes: _intervalRetryMenit), (_) => unawaited(sinkronkan()));
  }

  void _jadwalkanRetrySetelahJeda() {
    if (_retryTertunda?.isActive ?? false) return;
    _retryTertunda = Timer(Duration(minutes: _intervalRetryMenit), () {
      _retryTertunda = null;
      unawaited(sinkronkan());
    });
  }

  Future<void> aturIntervalRetryMenit(int menit) async {
    _intervalRetryMenit = _normalisasiInterval(menit);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kunciIntervalRetry, _intervalRetryMenit);
    _pasangTimer();
  }

  Future<int> muatIntervalRetryMenit() async {
    final sp = await SharedPreferences.getInstance();
    _intervalRetryMenit = _normalisasiInterval(
        sp.getInt(_kunciIntervalRetry) ?? intervalRetryMenitDefault);
    return _intervalRetryMenit;
  }

  /// [sertakanGagal] mengembalikan transaksi ber-status GAGAL ke antrean lebih
  /// dulu. HANYA dipakai oleh pemicu MANUAL (tombol Sinkronkan), bukan timer
  /// otomatis -- supaya penolakan bisnis yang memang permanen tidak dikirim
  /// berulang tanpa sepengetahuan pengguna.
  Future<HasilSinkronisasiTransaksi> sinkronkan({bool sertakanGagal = false}) {
    final aktif = _prosesAktif;
    if (aktif != null) return aktif;
    final proses = _sinkronkanInternal(sertakanGagal: sertakanGagal);
    _prosesAktif = proses;
    return proses.whenComplete(() => _prosesAktif = null);
  }

  /// Jumlah transaksi yang masih tertahan di perangkat ini: PENDING (menunggu
  /// giliran kirim) dan GAGAL (sudah divonis, tidak akan dijemput retry).
  Future<({int pending, int gagal})> hitungTertahan() async {
    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
      jedaRetry: Duration.zero,
    );
    final gagal = await CoreDb.instance.transaksiGagalBelumSinkron(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
    );
    return (pending: pending.length, gagal: gagal.length);
  }

  /// Dipanggil tepat setelah transaksi committed ke SQLite. Jika proses lama
  /// sedang berjalan, tunggu proses itu berakhir lalu lakukan satu sapuan baru
  /// supaya baris yang baru masuk tidak harus menunggu timer periodik.
  void kirimDiBackground() {
    unawaited(_kirimSaatSiap());
  }

  Future<void> _kirimSaatSiap() async {
    final aktif = _prosesAktif;
    if (aktif != null) await aktif;
    await sinkronkan();
  }

  Future<HasilSinkronisasiTransaksi> _sinkronkanInternal(
      {bool sertakanGagal = false}) async {
    if (!ApiClient.instance.sudahLogin) {
      return const HasilSinkronisasiTransaksi(total: 0, berhasil: 0);
    }

    if (sertakanGagal) {
      final gagal = await CoreDb.instance.transaksiGagalBelumSinkron(
        akunKunci: Sesi.instance.userId,
        tokoId: Sesi.instance.tokoId,
      );
      if (gagal.isNotEmpty) {
        await CoreDb.instance.kembalikanTransaksiKeAntrean(
            gagal.map((r) => '${r['kode_unik'] ?? ''}').toList());
      }
    }

    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
      idPerangkat: IdentitasMesin.instance.idMesin,
    );
    var berhasil = 0;
    for (final row in pending) {
      final vonis = await _kirimSatuBaris(row);
      if (vonis == _VonisKirim.berhasil) berhasil++;
      if (vonis == _VonisKirim.berhentiSementara) break;
    }
    // Setiap POS menyimpan pula transaksi kasir lain pada toko yang sama.
    // Endpoint server mengunci toko dari sesi login, sehingga payload toko
    // palsu tidak dapat mengambil data outlet lain.
    //
    // KE-FIX (transaksi baru lama sekali berstatus "Menunggu Sinkronisasi"
    // padahal koneksi lancar). Replikasi ini SEBELUMNYA di-await DI DALAM
    // proses sinkronisasi, dan dijalankan pada SETIAP pemanggilan -- termasuk
    // pemanggilan yang dipicu tiap checkout. Karena `kirimDiBackground`
    // menunggu proses yang sedang berjalan selesai, penjualan berikutnya
    // mengantre di belakang pemindaian 2 hari milik SELURUH toko yang bisa
    // memakan ratusan request berurutan. Kini replikasi:
    //   (a) dilepas dari jalur kirim -- hasil pengiriman dipulangkan lebih
    //       dulu sehingga mutex segera terbuka untuk penjualan berikutnya;
    //   (b) dibatasi paling sering sekali per interval retry, bukan tiap
    //       checkout.
    // Cakupan replikasinya sendiri tidak dikurangi sama sekali.
    unawaited(_cadangkanBilaSudahWaktunya());
    return HasilSinkronisasiTransaksi(
        total: pending.length, berhasil: berhasil);
  }

  /// Mengirim SATU baris outbox. Dipakai oleh sapuan otomatis maupun tombol
  /// kirim manual, supaya keduanya memakai aturan yang persis sama (proteksi
  /// pemilik, idempotensi kode unik, klasifikasi kegagalan).
  ///
  /// PENTING soal tanggal: payload menyimpan `waktu` transaksi APA ADANYA sejak
  /// checkout dan tidak pernah disentuh di sini. Server memakai nilai itu untuk
  /// `tanggal_pembayaran` (lihat waktuTransaksiDariPayload di KantinHelper),
  /// jadi transaksi yang baru terkirim berhari-hari kemudian tetap tercatat
  /// pada tanggal kejadiannya, bukan tanggal pengiriman.
  Future<_VonisKirim> _kirimSatuBaris(Map<String, Object?> row) async {
    final kodeUnik = '${row['kode_unik'] ?? ''}';
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
          jsonDecode('${row['payload_json']}') as Map);
    } catch (e) {
      await CoreDb.instance.tandaiTransaksiDitolak(
          kodeUnik, 'Payload lokal rusak dan tidak dapat dikirim: $e');
      return _VonisKirim.dilewati;
    }

    // Proteksi migrasi utk baris lama yang belum memiliki akun_kunci.
    // Jangan pernah kirim transaksi milik akun/toko lain memakai token
    // pengguna yang sedang login sekarang.
    final kasirPayload = '${payload['kasir'] ?? ''}'.trim();
    final tokoPayload = (payload['tokoId'] ?? payload['idToko']) as Object?;
    final tokoPayloadInt =
        tokoPayload is num ? tokoPayload.toInt() : int.tryParse('$tokoPayload');
    final pemulihanSupervisor =
        payload['input_supervisor'] == true && Sesi.instance.bolehKelola;
    final perangkatPayload = '${payload['id_perangkat'] ?? ''}'.trim();

    // KE-FIX: penjaga ini SEBELUMNYA melewati baris tanpa meninggalkan jejak
    // apa pun. Akibatnya tombol kirim melaporkan '0 dari 61 transaksi berhasil
    // dikirim' sementara kolom Kendala Terakhir tidak berubah sedikit pun dan
    // jumlah percobaan tidak bertambah -- operator tidak punya cara tahu bahwa
    // baris itu tidak pernah dikirim, apalagi alasannya. Alasannya kini ditulis
    // ke baris yang bersangkutan.
    final alasanDilewati = <String>[];
    if (!pemulihanSupervisor &&
        kasirPayload.isNotEmpty &&
        kasirPayload != Sesi.instance.userId) {
      alasanDilewati.add(
          'transaksi milik kasir "$kasirPayload", sedang login sebagai'
          ' "${Sesi.instance.userId}"');
    }
    if (tokoPayloadInt != null && tokoPayloadInt != Sesi.instance.tokoId) {
      alasanDilewati.add('transaksi milik toko $tokoPayloadInt,'
          ' toko aktif ${Sesi.instance.tokoId}');
    }
    if (perangkatPayload.isNotEmpty &&
        perangkatPayload != IdentitasMesin.instance.idMesin) {
      alasanDilewati.add('transaksi berasal dari perangkat lain');
    }
    if (alasanDilewati.isNotEmpty) {
      final pesan = 'Belum dikirim: ${alasanDilewati.join('; ')}.'
          ' Masuk dengan akun kasir yang bersangkutan di perangkat ini,'
          ' atau minta supervisor memulihkannya.';
      await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
      return _VonisKirim.dilewati;
    }

    try {
      payload['pengiriman_pending'] = true;
      final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
      await PelayananTransaksi.tandaiJikaPerlu(
        payload: payload,
        hasilBayar: hasilBayar,
        percobaanCari: 1,
      );
      // Server menghitung ulang promo saat menyimpan dan menimpa diskon
      // kiriman kasir, jadi total tercatat bisa BERBEDA dari total yang dipakai
      // struk. Balasannya disimpan agar layar struk dapat memakai angka server
      // sebelum dicetak, dan agar selisihnya tidak lagi hilang diam-diam.
      try {
        await CoreDb.instance.simpanHasilServerTransaksi(kodeUnik, {
          'total': hasilBayar['total'],
          'totalDiskon': hasilBayar['totalDiskon'],
          'diskonFaktur': hasilBayar['diskonFaktur'],
          'totalKlien': payload['total'],
          'data': hasilBayar['data'],
          // Peringatan pasca-transaksi ikut disimpan, bukan dibuang. Checkout POS
          // bersifat lokal-dulu: responsnya tiba di sini, jauh setelah kasir
          // menutup layar. Kalau tidak ditulis ke baris outbox, satu-satunya tanda
          // bahwa ada yang perlu direkonsiliasi lenyap tanpa pernah terbaca.
          //
          // Disimpan SUDAH DIRATAKAN jadi daftar kalimat: layar struk tinggal
          // menampilkannya, tanpa perlu tahu bentuk amplop respons servernya.
          'peringatanTransaksi': PeringatanTransaksi.dari(hasilBayar),
        });
      } catch (e) {
        // Menyimpan angka pembanding tidak boleh menggagalkan sinkronisasi:
        // transaksinya sendiri sudah tersimpan di server.
        await CoreDb.instance.catatErrorLog(
            sumber: 'outbox-hasil-server',
            tingkat: 'WARN',
            pesan: 'Gagal menyimpan angka server utk $kodeUnik: $e');
      }
      await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
      return _VonisKirim.berhasil;
    } catch (e) {
      final pesan = e.toString();
      if (_transaksiSudahAdaDiServer(e)) {
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
        return _VonisKirim.berhasil;
      }
      await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
      final percobaan = (row['percobaan'] as num?)?.toInt() ?? 0;
      if (dapatDicobaUlang(e) && percobaan < batasPercobaanOtomatis) {
        _jadwalkanRetrySetelahJeda();
        if (e is ApiException && e.offline) {
          // Koneksi masih putus. Berhenti agar baris berikutnya tidak ikut
          // menghasilkan error yang sama; timer akan mencoba lagi sesuai
          // interval yang dikonfigurasi.
          return _VonisKirim.berhentiSementara;
        }
        // Error teknis server dapat bersifat khusus pada satu payload.
        // Biarkan tetap PENDING, lalu lanjutkan transaksi berikutnya.
        return _VonisKirim.dilewati;
      }
      // Penolakan bisnis yang pasti tidak akan membaik hanya dengan retry
      // (mis. stok/saldo/hak akses). Simpan sebagai GAGAL untuk audit, jangan
      // hapus, dan jangan membanjiri server setiap interval.
      await CoreDb.instance.tandaiTransaksiDitolak(kodeUnik, pesan);
      return _VonisKirim.dilewati;
    }
  }

  /// Kirim ulang SATU transaksi tertentu atas permintaan pengguna.
  ///
  /// Berbeda dari sapuan otomatis, jeda antar-percobaan dan status GAGAL TIDAK
  /// menghalangi: kalau kasir menekan tombolnya, ia memang ingin mencoba
  /// sekarang. Idempotensi tetap dijaga server lewat `kode_unik` yang sama.
  /// [paksa] mengirim ulang walaupun barisnya sudah berstatus SYNCED.
  /// Dipakai ketika transaksi terlanjur terhapus di server sementara
  /// perangkat masih menyimpan jurnalnya. Aman diulang: server menolak
  /// duplikat berdasarkan kode unik yang sama, jadi bila transaksinya
  /// ternyata masih ada, kiriman ini tidak membuat baris kedua.
  Future<HasilKirimManual> kirimSatuManual(String kodeUnik,
      {bool paksa = false}) async {
    final kode = kodeUnik.trim();
    if (kode.isEmpty) {
      return const HasilKirimManual(
          total: 0, berhasil: 0, pesan: 'Kode transaksi tidak dikenali.');
    }
    if (!ApiClient.instance.sudahLogin) {
      return const HasilKirimManual(
          total: 1, berhasil: 0, pesan: 'Sesi login belum siap.');
    }
    final row = await CoreDb.instance.transaksiLokalDenganKode(kode);
    if (row == null) {
      return HasilKirimManual(
          total: 0,
          berhasil: 0,
          pesan: 'Transaksi $kode tidak ada di perangkat ini.');
    }
    if (!paksa && '${row['status'] ?? ''}'.toUpperCase() == 'SYNCED') {
      return HasilKirimManual(
          total: 0, berhasil: 0, pesan: 'Transaksi $kode sudah tersinkron.');
    }
    final vonis = await _kirimSatuBaris(row);
    final berhasil = vonis == _VonisKirim.berhasil;
    return HasilKirimManual(
      total: 1,
      berhasil: berhasil ? 1 : 0,
      pesan: berhasil
          ? 'Transaksi $kode berhasil dikirim.'
          : 'Transaksi $kode belum berhasil dikirim. Lihat kolom Kendala Terakhir.',
    );
  }

  /// Kirim ulang BANYAK transaksi sekaligus atas permintaan pengguna.
  ///
  /// [kodeUnik] kosong berarti semua yang belum tersinkron di perangkat ini,
  /// termasuk yang berstatus GAGAL. Baris yang gagal tidak menghentikan baris
  /// berikutnya, KECUALI koneksi terbukti putus -- meneruskan hanya akan
  /// menghasilkan error identik berulang.
  Future<HasilKirimManual> kirimBanyakManual([List<String>? kodeUnik]) async {
    if (!ApiClient.instance.sudahLogin) {
      return const HasilKirimManual(
          total: 0, berhasil: 0, pesan: 'Sesi login belum siap.');
    }
    final baris = <Map<String, Object?>>[];
    if (kodeUnik == null || kodeUnik.isEmpty) {
      // jedaRetry nol: permintaan manual tidak tunduk pada jeda otomatis.
      baris.addAll(await CoreDb.instance.transaksiPendingBelumSinkron(
        akunKunci: Sesi.instance.userId,
        tokoId: Sesi.instance.tokoId,
        idPerangkat: IdentitasMesin.instance.idMesin,
        jedaRetry: Duration.zero,
      ));
      baris.addAll(await CoreDb.instance.transaksiGagalBelumSinkron(
        akunKunci: Sesi.instance.userId,
        tokoId: Sesi.instance.tokoId,
      ));
    } else {
      for (final kode in kodeUnik) {
        final row = await CoreDb.instance.transaksiLokalDenganKode(kode.trim());
        if (row != null && '${row['status'] ?? ''}'.toUpperCase() != 'SYNCED') {
          baris.add(row);
        }
      }
    }
    if (baris.isEmpty) {
      return const HasilKirimManual(
          total: 0,
          berhasil: 0,
          pesan: 'Tidak ada transaksi yang perlu dikirim.');
    }
    var berhasil = 0;
    var terhenti = false;
    for (final row in baris) {
      final vonis = await _kirimSatuBaris(row);
      if (vonis == _VonisKirim.berhasil) berhasil++;
      if (vonis == _VonisKirim.berhentiSementara) {
        terhenti = true;
        break;
      }
    }
    return HasilKirimManual(
      total: baris.length,
      berhasil: berhasil,
      pesan: terhenti
          ? '$berhasil dari ${baris.length} terkirim; sisanya dihentikan karena koneksi terputus.'
          : berhasil == baris.length
              ? 'Semua $berhasil transaksi berhasil dikirim.'
              : '$berhasil dari ${baris.length} transaksi berhasil dikirim.',
    );
  }

  /// Menjalankan replikasi cadangan bila sudah lewat jeda, dan tidak pernah
  /// dua kali bersamaan. Sengaja TIDAK memakai `_prosesAktif`: pengiriman
  /// transaksi baru tidak boleh menunggu pekerjaan latar ini.
  Future<void> _cadangkanBilaSudahWaktunya() async {
    if (_cadanganBerjalan) return;
    final terakhir = _cadanganTerakhir;
    if (terakhir != null &&
        DateTime.now().difference(terakhir) <
            Duration(minutes: _intervalRetryMenit)) {
      return;
    }
    _cadanganBerjalan = true;
    try {
      await _cadangkanTransaksiTokoTerbaru();
      _cadanganTerakhir = DateTime.now();
    } catch (_) {
      // Replikasi cadangan bersifat best-effort dan tidak boleh mengubah hasil
      // pengiriman transaksi utama. Timer periodik akan mencoba kembali.
      _jadwalkanRetrySetelahJeda();
    } finally {
      _cadanganBerjalan = false;
    }
  }

  Future<void> _cadangkanTransaksiTokoTerbaru() async {
    final tokoId = Sesi.instance.tokoId;
    if (tokoId == null) return;
    // Hanya kolom kode_unik: versi lama memakai SELECT * dgn limit sejuta baris
    // sehingga seluruh payload_json ikut dibaca ke memori tiap sinkronisasi.
    final kodeLokal = await CoreDb.instance.kodeTransaksiLokalToko(tokoId);
    final sekarang = DateTime.now();
    final mulai = sekarang.subtract(const Duration(days: 2));
    var page = 1;
    while (page <= 20) {
      final hasil =
          await ApiClient.instance.aksi('transaksi_backup_toko_list', {
        'toko_id': tokoId,
        'tglMulai': _tanggal(mulai),
        'tglSampai': _tanggal(sekarang),
        'page': page,
        'pageSize': 100,
      });
      final daftar = ((hasil['data'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final kodeDiakui = <String>[];
      for (final row in daftar) {
        final kode = _kodeServer(row);
        if (kode.isEmpty) continue;
        if (kodeLokal.contains(kode.toLowerCase())) {
          kodeDiakui.add(kode);
          continue;
        }
        final id = row['idTransaksi'];
        if (id == null) continue;
        final detail = await ApiClient.instance.aksi('detail_transaksi', {
          'id': id,
          'toko_id': tokoId,
        });
        final items = ((detail['item'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((item) => <String, dynamic>{
                  'id': item['produkId'] ?? item['id'],
                  'kode': item['kode'],
                  'nama': item['nama'],
                  'harga': item['harga'] ?? 0,
                  'jumlah': item['qty'] ?? item['jumlah'] ?? 0,
                  'diskon': item['diskon'] ?? 0,
                  'cashback': item['cashback'] ?? 0,
                })
            .toList();
        final username =
            '${detail['kasirUserId'] ?? row['kasirUserId'] ?? row['kasir'] ?? ''}'
                .trim();
        final idPerangkat =
            '${detail['idPerangkat'] ?? row['idPerangkat'] ?? ''}'.trim();
        final namaMesin = '${row['namaMesin'] ?? ''}'.trim();
        final payload = <String, dynamic>{
          'kodeUnik': kode,
          'clientTrxId': kode,
          'idToko': tokoId,
          'tokoId': tokoId,
          'kasir': username,
          'kasir_user_id': username,
          'waktu': '${detail['waktu'] ?? row['waktu'] ?? ''}',
          'caraBayarNama': '${row['metode'] ?? ''}',
          'total': detail['totalBiaya'] ?? row['totalBiaya'] ?? 0,
          'pajak': row['pajak'] ?? 0,
          'nama_member': detail['pembeli'] ?? row['pembeli'],
          'nama_mesin': namaMesin,
          'id_perangkat': idPerangkat,
          'sumber_username': username,
          'sumber_mesin': namaMesin.isNotEmpty ? namaMesin : idPerangkat,
          'asal_backup': 'REPLIKASI_OTOMATIS_TOKO_SAMA',
          'transaksi': items,
        };
        final tersimpan = await CoreDb.instance.simpanTransaksiDariServer(
            kode, jsonEncode(payload),
            akunKunci: username,
            tokoId: tokoId,
            idPerangkat: idPerangkat.isNotEmpty ? idPerangkat : namaMesin);
        if (tersimpan) {
          kodeLokal.add(kode.toLowerCase());
          kodeDiakui.add(kode);
        }
      }
      // ACK baru dikirim setelah baris benar-benar tersedia di SQLite lokal.
      // Dengan demikian server dapat membedakan transaksi yang baru berada di
      // server dari transaksi yang sudah mempunyai salinan pada POS lain.
      if (kodeDiakui.isNotEmpty) {
        await ApiClient.instance.aksi('transaksi_backup_ack', {
          'toko_id': tokoId,
          'kode_transaksi': kodeDiakui,
          'id_perangkat': IdentitasMesin.instance.idMesin,
          'nama_mesin': IdentitasMesin.instance.namaMesin,
        });
      }
      final total = (hasil['total'] as num?)?.toInt() ?? daftar.length;
      if (daftar.isEmpty || page * 100 >= total || daftar.length < 100) break;
      page++;
    }
  }

  String _tanggal(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _kodeServer(Map<String, dynamic> row) {
    for (final key in const <String>[
      'kodeUnik',
      'clientTrxId',
      'kodeTransaksi',
      'nomorTransaksi',
      'nomorNota',
      'kode'
    ]) {
      final nilai = '${row[key] ?? ''}'.trim();
      if (nilai.isEmpty || nilai == '-') continue;
      if (key == 'nomorNota') {
        final cocok = RegExp(r'\(([^()]+)\)\s*$').firstMatch(nilai);
        final kodeLama = cocok?.group(1)?.trim() ?? '';
        if (kodeLama.isNotEmpty) return kodeLama;
      }
      return nilai;
    }
    return '';
  }

  /// Network, HTTP 5xx, respons server yang tidak valid, dan error internal
  /// tanpa kode bisnis adalah kegagalan teknis yang aman dicoba ulang dengan
  /// idempotency key yang sama.
  /// Kode penolakan yang BENAR-BENAR permanen: mengirim ulang tidak akan
  /// mengubah hasilnya karena penyebabnya ada pada data/aturan bisnis, bukan
  /// pada gangguan teknis sesaat.
  ///
  /// Daftar ini sengaja berupa DAFTAR TERTUTUP, bukan "apa pun yang punya
  /// kode". Sebelumnya setiap respons bernomor kode dianggap permanen,
  /// sehingga `SERVER_ERROR` -- kode CADANGAN yang dipakai server untuk
  /// exception tak terklasifikasi, dan dikirim lewat HTTP 200 sehingga tidak
  /// pernah tersaring oleh syarat >= 500 -- ikut divonis permanen. Akibatnya
  /// gangguan sesaat membuat nota berhenti di perangkat kasir dan TIDAK PERNAH
  /// sampai ke server, hilang dari omzet tanpa jejak (insiden Toko Al-Bahjah
  /// 20-08-2026, nota AB22008202600105).
  static const Set<String> kodePenolakanPermanen = {
    'DATA_TIDAK_LENGKAP',
    'TIDAK_DITEMUKAN',
    'PESANAN_PERLU_DIMUAT_ULANG',
    'STOK_TIDAK_CUKUP',
    'PRODUK_KADALUARSA',
  };

  /// Batas percobaan otomatis sebelum transaksi diparkir sbg GAGAL. Mencegah
  /// kode tak dikenal berputar tanpa akhir, sambil tetap menyediakan jalur
  /// Kirim Ulang manual.
  static const int batasPercobaanOtomatis = 20;

  bool dapatDicobaUlang(Object error) {
    if (error is! ApiException) return true;
    if (error.offline || (error.statusHttp ?? 0) >= 500) return true;
    final kode = (error.kode ?? '').trim().toUpperCase();
    if (kode.isEmpty) return true;
    // Selain daftar permanen -- termasuk SERVER_ERROR dan kode baru yang belum
    // dikenal versi ini -- diperlakukan sbg gangguan teknis dan dicoba lagi.
    // Aman thd transaksi ganda karena retry memakai kode_unik asli.
    return !kodePenolakanPermanen.contains(kode);
  }

  bool _transaksiSudahAdaDiServer(Object error) {
    if (error is ApiException &&
        (error.kode ?? '').trim() == 'DUPLIKAT_KODE_TRANSAKSI') {
      return true;
    }
    final pesan = error.toString().toLowerCase();
    return pesan.contains('sudah tercatat') ||
        pesan.contains('kode transaksi yang sama sudah ada') ||
        pesan.contains('duplicate key');
  }
}

class HasilSinkronisasiTransaksi {
  final int total;
  final int berhasil;

  const HasilSinkronisasiTransaksi(
      {required this.total, required this.berhasil});
}

/// Keputusan setelah mencoba mengirim satu baris outbox.
enum _VonisKirim {
  /// Server menerima (atau sudah punya) transaksi ini.
  berhasil,

  /// Baris ini tidak terkirim, tetapi baris lain masih layak dicoba.
  dilewati,

  /// Koneksi terbukti putus -- meneruskan hanya menghasilkan error identik.
  berhentiSementara,
}

/// Hasil pengiriman yang dipicu MANUAL oleh pengguna.
class HasilKirimManual {
  final int total;
  final int berhasil;
  final String pesan;

  const HasilKirimManual(
      {required this.total, required this.berhasil, required this.pesan});

  bool get semuaBerhasil => total > 0 && berhasil == total;
}
