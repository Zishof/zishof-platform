import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter/foundation.dart';
import 'package:core_device/core_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'pelayanan_transaksi.dart';
import 'pengaturan_nomor_struk.dart';
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
  TransaksiOutboxService._() : _jalankanUji = null;

  /// Menjalankan pengujian antrean tanpa jaringan atau data kasir sungguhan.
  @visibleForTesting
  TransaksiOutboxService.untukUji(this._jalankanUji);

  final Future<HasilSinkronisasiTransaksi> Function({
    required bool sertakanGagal,
    required Duration jedaRetry,
  })? _jalankanUji;
  Future<HasilSinkronisasiTransaksi>? _manualMenunggu;
  final Map<String, Future<void>> _pekerjaanPerKode = <String, Future<void>>{};

  static final TransaksiOutboxService instance = TransaksiOutboxService._();

  /// Metode pengganti untuk transaksi yang sudah terlanjur dilayani hanya boleh
  /// berupa penerimaan manual yang tidak menyentuh saldo/piutang pusat. Kasir
  /// tetap harus mengonfirmasi bahwa uang/bukti pembayaran benar-benar diterima.
  static bool metodeAmanUntukKoreksiOffline(CaraBayar caraBayar) =>
      caraBayar.manual &&
      !caraBayar.memotongDepositEfektif &&
      !caraBayar.masukSebagaiHutang &&
      !caraBayar.wajibPin;

  /// Kasbon boleh dipilih saat koreksi hanya karena payload akan dikirim ulang
  /// ke server untuk validasi piutang. Metode ini tidak pernah dianggap aman
  /// untuk penyelesaian lokal/offline.
  static bool metodeKasbonUntukKoreksiServer(CaraBayar caraBayar) =>
      caraBayar.masukSebagaiHutang &&
      caraBayar.wajibPilihMember &&
      !caraBayar.wajibPin;

  /// PENDING mencakup timeout/kehilangan respons dan mungkin sudah tersimpan
  /// di server; hanya penolakan final GAGAL boleh mengubah metode transaksi.
  static bool dapatDikoreksiSetelahPenolakan(String status) =>
      status.trim().toUpperCase() == 'GAGAL';

  /// Membuat payload non-split yang setara dengan checkout normal. Kode, waktu,
  /// item, nominal, kasir, toko, dan perangkat tidak diubah agar audit serta
  /// idempotensi transaksi tetap utuh.
  static Map<String, dynamic> payloadDenganMetodePengganti(
      Map<String, dynamic> sumber, CaraBayar caraBayar) {
    return payloadDenganMetodeTerkoreksi(sumber, caraBayar);
  }

  /// Mengganti metode bayar pada transaksi lokal yang belum diterima server.
  ///
  /// Untuk metode manual aman, payload dapat dikoreksi sepenuhnya di perangkat.
  /// Untuk voucher/saldo, pemanggil wajib memilih [izinkanValidasiServer] agar
  /// status dikembalikan ke PENDING dan server tetap menjadi penentu saldo,
  /// izin member, serta penolakan bisnisnya.
  static Map<String, dynamic> payloadDenganMetodeTerkoreksi(
      Map<String, dynamic> sumber, CaraBayar caraBayar,
      {bool izinkanValidasiServer = false}) {
    if (!metodeAmanUntukKoreksiOffline(caraBayar)) {
      if (!izinkanValidasiServer) {
        throw ArgumentError(
            'Metode pengganti harus manual dan tidak memotong saldo/piutang.');
      }
      if (caraBayar.wajibPin) {
        throw ArgumentError(
            'Metode ini memerlukan PIN dan belum dapat dikoreksi dari antrean lokal.');
      }
      final memberId = sumber['id_member'] ?? sumber['memberId'];
      final memberAngka = memberId is num
          ? memberId.toInt()
          : int.tryParse('${memberId ?? ''}');
      final memberValid = memberAngka != null && memberAngka > 0;
      if (caraBayar.masukSebagaiHutang && !memberValid) {
        throw ArgumentError(
            'Kasbon Divisi memerlukan member/PIC yang sah dan validasi server.');
      }
      if (caraBayar.wajibPilihMember && !memberValid) {
        throw ArgumentError(
            'Pilih transaksi yang sudah memiliki member sebelum memakai voucher/saldo.');
      }
    }
    final hasil = Map<String, dynamic>.from(sumber)
      ..['caraBayar'] = caraBayar.id
      ..['caraBayarNama'] = caraBayar.nama
      ..['pengiriman_pending'] = true;
    for (final kunci in const [
      'caraBayarNominal',
      'nominalCaraBayar',
      'caraBayarUtamaNominal',
      'caraBayarTambahan',
      'cara_bayar_tambahan',
      'pembayaran',
      'rincianPembayaran',
      'metodePembayaranList',
      'splitPembayaran',
      'multiPembayaran',
    ]) {
      hasil.remove(kunci);
    }
    return hasil;
  }

  static int? _idCaraBayarDariPayload(Map<String, dynamic> payload) {
    for (final key in const ['caraBayar', 'caraBayarId', 'idCaraBayar']) {
      final nilai = payload[key];
      final angka = nilai is num ? nilai.toInt() : int.tryParse('$nilai');
      if (angka != null && angka > 0) return angka;
    }
    return null;
  }

  static Map<String, dynamic> payloadDenganMemberTerkoreksi(
    Map<String, dynamic> sumber,
    Anggota member, {
    List<CaraBayar>? metodeDiizinkan,
  }) {
    final memberId = member.id;
    if (memberId <= 0) {
      throw ArgumentError('Member/Pembeli yang dipilih belum memiliki ID sah.');
    }
    final caraBayarId = _idCaraBayarDariPayload(sumber);
    if (metodeDiizinkan != null && caraBayarId != null) {
      final cocok = metodeDiizinkan.where((m) => m.id == caraBayarId);
      if (cocok.isEmpty) {
        throw ArgumentError(
            'Metode pembayaran transaksi tidak diizinkan untuk member yang dipilih.');
      }
      if (cocok.first.wajibPin) {
        throw ArgumentError(
            'Metode pembayaran ini memerlukan PIN dan belum dapat dikoreksi dari antrean lokal.');
      }
    }
    return Map<String, dynamic>.from(sumber)
      ..['id_member'] = memberId
      ..['memberId'] = memberId
      ..['nama_member'] = member.nama
      ..['namaMember'] = member.nama
      ..['namaPembeli'] = member.nama
      ..['pembeli'] = member.nama
      ..['pengiriman_pending'] = true;
  }

  Future<void> koreksiMetodePembayaran(String kodeUnik, CaraBayar caraBayar,
      {bool izinkanValidasiServer = false}) async {
    final row = await CoreDb.instance.transaksiLokalDenganKode(kodeUnik);
    if (row == null) {
      throw StateError('Transaksi $kodeUnik tidak ditemukan di perangkat ini.');
    }
    final status = '${row['status']}';
    if (!dapatDikoreksiSetelahPenolakan(status)) {
      throw StateError(
          'Metode hanya dapat dikoreksi setelah server memberi penolakan final. Status transaksi saat ini: $status.');
    }
    final payload = Map<String, dynamic>.from(
        jsonDecode('${row['payload_json'] ?? '{}'}') as Map);
    final asalBackup = '${payload['asal_backup'] ?? ''}'.trim().toUpperCase();
    final hasilServerAda =
        '${row['hasil_server_json'] ?? ''}'.trim().isNotEmpty;
    final selesaiLokalBelumCocok =
        status == 'SYNCED' && !hasilServerAda && asalBackup.isEmpty;
    if (status == 'SYNCED' && !selesaiLokalBelumCocok) {
      throw StateError(
          'Transaksi sudah diterima server dan tidak boleh diubah dari perangkat.');
    }
    final koreksi = payloadDenganMetodeTerkoreksi(payload, caraBayar,
        izinkanValidasiServer: izinkanValidasiServer);
    final berubah = await CoreDb.instance.koreksiPayloadTransaksi(
        kodeUnik, jsonEncode(koreksi),
        izinkanSelesaiLokal: selesaiLokalBelumCocok);
    if (!berubah) {
      throw StateError(
          'Transaksi tidak dapat dikoreksi karena statusnya sudah berubah.');
    }
    kirimDiBackground();
  }

  Future<void> koreksiMemberPembeli(
    String kodeUnik,
    Anggota member, {
    List<CaraBayar>? metodeDiizinkan,
  }) async {
    final row = await CoreDb.instance.transaksiLokalDenganKode(kodeUnik);
    if (row == null) {
      throw StateError('Transaksi $kodeUnik tidak ditemukan di perangkat ini.');
    }
    final status = '${row['status']}';
    final payload = Map<String, dynamic>.from(
        jsonDecode('${row['payload_json'] ?? '{}'}') as Map);
    final asalBackup = '${payload['asal_backup'] ?? ''}'.trim().toUpperCase();
    final hasilServerAda =
        '${row['hasil_server_json'] ?? ''}'.trim().isNotEmpty;
    final selesaiLokalBelumCocok =
        status == 'SYNCED' && !hasilServerAda && asalBackup.isEmpty;
    if (status == 'SYNCED' && !selesaiLokalBelumCocok) {
      throw StateError(
          'Transaksi sudah diterima server dan tidak boleh diubah dari perangkat.');
    }
    final koreksi = payloadDenganMemberTerkoreksi(
      payload,
      member,
      metodeDiizinkan: metodeDiizinkan,
    );
    final berubah = await CoreDb.instance.koreksiPayloadTransaksi(
        kodeUnik, jsonEncode(koreksi),
        izinkanSelesaiLokal: selesaiLokalBelumCocok);
    if (!berubah) {
      throw StateError(
          'Transaksi tidak dapat dikoreksi karena statusnya sudah berubah.');
    }
    kirimDiBackground();
  }

  /// Memperbarui nomor nota transaksi pending yang bentrok di server pusat dengan nomor nota baru yang unik,
  /// lalu langsung mengirimkannya secara paksa ke server.
  Future<HasilKirimManual> perbaruiNomorNotaDanKirim(String kodeLama) async {
    final kode = kodeLama.trim();
    if (kode.isEmpty) {
      return const HasilKirimManual(
          total: 0, berhasil: 0, pesan: 'Kode transaksi tidak dikenali.');
    }
    final row = await CoreDb.instance.transaksiLokalDenganKode(kode);
    if (row == null) {
      return HasilKirimManual(
          total: 0,
          berhasil: 0,
          pesan: 'Transaksi $kode tidak ada di perangkat ini.');
    }
    final payload = Map<String, dynamic>.from(
        jsonDecode('${row['payload_json'] ?? '{}'}') as Map);

    // Buat kode baru unik
    final kodeBaru = await PengaturanNomorStruk.instance.buatNomor();
    final kodeEfektif = (kodeBaru.trim().isEmpty || kodeBaru.trim() == kode)
        ? '$kode-R${DateTime.now().millisecondsSinceEpoch % 1000}'
        : kodeBaru.trim();

    payload['kodeUnik'] = kodeEfektif;
    payload['clientTrxId'] = kodeEfektif;
    payload['kode_nota_asal'] = kode;

    final sukses = await CoreDb.instance.gantiKodeUnikTransaksi(
      kode,
      kodeEfektif,
      jsonEncode(payload),
    );
    if (!sukses) {
      return const HasilKirimManual(
          total: 1,
          berhasil: 0,
          pesan: 'Gagal memperbarui nomor nota di database lokal.');
    }

    return kirimSatuManual(kodeEfektif, paksa: true);
  }

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
    if (aktif != null) {
      if (!sertakanGagal) return aktif;
      // Klik manual tidak boleh hilang di balik sapuan otomatis. Gabungkan
      // klik bersamaan menjadi satu sapuan tambahan, setelah mutex dilepas.
      return _manualMenunggu ??= aktif
          .then(
            (_) => sinkronkan(sertakanGagal: true),
            onError: (Object _, StackTrace __) =>
                sinkronkan(sertakanGagal: true),
          )
          .whenComplete(() => _manualMenunggu = null);
    }
    final jalankan = _jalankanUji ?? _sinkronkanInternal;
    final proses = jalankan(
      sertakanGagal: sertakanGagal,
      jedaRetry: sertakanGagal
          ? Duration.zero
          : Duration(minutes: _intervalRetryMenit),
    );
    final terjaga = proses.whenComplete(() => _prosesAktif = null);
    _prosesAktif = terjaga;
    return terjaga;
  }

  /// Jumlah transaksi yang masih tertahan di perangkat ini: PENDING (menunggu
  /// giliran kirim) dan GAGAL (sudah divonis, tidak akan dijemput retry).
  Future<({int pending, int gagal})> hitungTertahan() async {
    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      tokoId: Sesi.instance.tokoId,
      jedaRetry: Duration.zero,
    );
    final gagal = await CoreDb.instance.transaksiGagalBelumSinkron(
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
      {required bool sertakanGagal, required Duration jedaRetry}) async {
    if (!ApiClient.instance.sudahLogin) {
      return const HasilSinkronisasiTransaksi(total: 0, berhasil: 0);
    }

    if (sertakanGagal) {
      final gagal = await CoreDb.instance.transaksiGagalBelumSinkron(
        tokoId: Sesi.instance.tokoId,
      );
      if (gagal.isNotEmpty) {
        await CoreDb.instance.kembalikanTransaksiKeAntrean(
            gagal.map((r) => '${r['kode_unik'] ?? ''}').toList());
      }
    }

    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      tokoId: Sesi.instance.tokoId,
      jedaRetry: jedaRetry,
    );
    var berhasil = 0;
    for (final row in pending) {
      final vonis = await _kirimSatuBarisTerkunci(row);
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

    // Jika sesi login kasir atau toko belum siap di memori, tunda
    // proses kirim sampai sesi siap, jangan memvonis error palsu.
    if (Sesi.instance.userId.isEmpty || Sesi.instance.tokoId == null) {
      return _VonisKirim.berhentiSementara;
    }

    final tokoPayload = (payload['tokoId'] ?? payload['idToko']) as Object?;
    final tokoPayloadInt =
        tokoPayload is num ? tokoPayload.toInt() : int.tryParse('$tokoPayload');
    final pemulihanSupervisor =
        payload['input_supervisor'] == true || Sesi.instance.bolehKelola;
    final bool tokoSesuai =
        tokoPayloadInt == null || tokoPayloadInt == Sesi.instance.tokoId;

    final alasanDilewati = <String>[];
    // Transaksi dari toko yang sama diizinkan untuk dikirim oleh kasir mana pun yang sedang
    // bertugas di toko tersebut pada perangkat ini, agar pergantian shift tidak terkunci
    // oleh antrean transaksi offline kasir sebelumnya. Identitas kasir asli (mis. satim)
    // dan sesi kas tetap terjaga seutuhnya di dalam payload yang dikirim apa adanya ke server.
    if (!pemulihanSupervisor && !tokoSesuai) {
      alasanDilewati.add('transaksi milik toko $tokoPayloadInt,'
          ' toko aktif ${Sesi.instance.tokoId}');
    }
    if (alasanDilewati.isNotEmpty) {
      final pesan = 'Belum dikirim: ${alasanDilewati.join('; ')}.'
          ' Hubungi supervisor untuk memulihkannya.';
      await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
      return _VonisKirim.dilewati;
    }

    try {
      payload['pengiriman_pending'] = true;
      if (tokoPayloadInt == null && Sesi.instance.tokoId != null) {
        payload['idToko'] = Sesi.instance.tokoId;
        payload['tokoId'] = Sesi.instance.tokoId;
      }
      if ('${payload['kasir'] ?? ''}'.trim().isEmpty &&
          Sesi.instance.userId.isNotEmpty) {
        payload['kasir'] = Sesi.instance.userId;
      }
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
          'idTransaksi': hasilBayar['idTransaksi'] ??
              hasilBayar['pembelianAnggotaKoperasi'] ??
              hasilBayar['id'],
          'total': hasilBayar['total'],
          'totalDiskon': hasilBayar['totalDiskon'],
          'saldo': hasilBayar['saldo'],
          'sisaSaldo': hasilBayar['sisaSaldo'],
          'diskonFaktur': hasilBayar['diskonFaktur'],
          'totalKlien': payload['total'],
          'data': hasilBayar['data'],
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
      // Simpan pesan asli server, bukan hasil toString() yang sudah ditambah
      // langkah bantuan. Dengan begitu kolom kendala tetap ringkas dan detail
      // bantuan dapat dirender konsisten oleh AppErrorPanel.
      final pesan = e is ApiException ? e.pesan : e.toString();
      if (_transaksiSudahAdaDiServer(e)) {
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
        return _VonisKirim.berhasil;
      }
      // Bila server mengembalikan penolakan (mis. saldo/limit dianggap kurang atau
      // terjadi time-out saat respons pertama), periksa apakah transaksi dengan
      // kodeUnik ini sebenarnya SUDAH tersimpan di database server.
      try {
        final cek = await ApiClient.instance.aksi('detail_transaksi', {
          'kode': kodeUnik,
          'kodeUnik': kodeUnik,
          if (tokoPayloadInt != null) 'idToko': tokoPayloadInt,
          if (tokoPayloadInt != null) 'toko_id': tokoPayloadInt,
        });
        final adaId = cek['idTransaksi'] != null || cek['id'] != null;
        final kodeCocok = '${cek['kode'] ?? ''}'.trim().toLowerCase() ==
            kodeUnik.toLowerCase();
        if (adaId || kodeCocok || cek['totalBiaya'] != null) {
          await CoreDb.instance.simpanHasilServerTransaksi(kodeUnik, {
            'idTransaksi': cek['idTransaksi'] ?? cek['id'],
            'total': cek['totalBiaya'],
            'totalDiskon': cek['totalDiskon'],
            'saldo': cek['saldo'],
            'sisaSaldo': cek['sisaSaldo'],
            'data': cek['item'],
          });
          await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
          return _VonisKirim.berhasil;
        }
      } catch (_) {
        // Abaikan pengecekan jika server tidak dapat dihubungi
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

  Future<T> _denganKunciKode<T>(
      String kode, Future<T> Function() operasional) async {
    final sebelumnya = _pekerjaanPerKode[kode];
    final giliranSaya = Completer<void>();
    final penandaSaya = giliranSaya.future;
    _pekerjaanPerKode[kode] = penandaSaya;
    if (sebelumnya != null) await sebelumnya;
    try {
      return await operasional();
    } finally {
      if (identical(_pekerjaanPerKode[kode], penandaSaya)) {
        _pekerjaanPerKode.remove(kode);
      }
      giliranSaya.complete();
    }
  }

  Future<_VonisKirim> _kirimSatuBarisTerkunci(
    Map<String, Object?> row, {
    bool izinkanSudahTersinkron = false,
  }) {
    final kode = '${row['kode_unik'] ?? ''}'.trim();
    return _denganKunciKode(kode, () async {
      // Pengirim bisa saja sudah memuat baris sebelum pembatalan mengambil
      // kunci. Baca ulang setelah kunci didapat agar baris yang baru saja
      // dihapus tidak terkirim dari snapshot lama.
      final terbaru = await CoreDb.instance.transaksiLokalDenganKode(kode);
      if (terbaru == null) return _VonisKirim.dilewati;
      final status = '${terbaru['status'] ?? ''}'.trim().toUpperCase();
      if (status == 'SYNCED' && !izinkanSudahTersinkron) {
        return _VonisKirim.dilewati;
      }
      return _kirimSatuBaris(terbaru);
    });
  }

  /// Preflight tombol pembatalan: hanya mengizinkan tampilan tombol aktif bila
  /// daftar server berhasil dibaca dan kode ini tidak ditemukan di tanggal
  /// serta toko asalnya. Error pemeriksaan harus ditampilkan sebagai aksi
  /// nonaktif oleh pemanggil, bukan dianggap sebagai transaksi yang tidak ada.
  Future<bool> transaksiBolehDibatalkan(String kodeUnik) async {
    final kode = kodeUnik.trim();
    if (kode.isEmpty ||
        !ApiClient.instance.sudahLogin ||
        !Sesi.instance.bolehHapusPesanan) {
      return false;
    }
    return _denganKunciKode<bool>(kode, () async {
      final row = await CoreDb.instance.transaksiLokalDenganKode(kode);
      if (row == null) return false;
      final status = '${row['status'] ?? ''}'.trim().toUpperCase();
      if (status != 'PENDING' && status != 'GAGAL') return false;
      final tokoLokal = (row['toko_id'] as num?)?.toInt();
      final payload = Map<String, dynamic>.from(
          jsonDecode('${row['payload_json'] ?? '{}'}') as Map);
      final nilaiToko = payload['tokoId'] ?? payload['idToko'] ?? tokoLokal;
      final tokoId = nilaiToko is num
          ? nilaiToko.toInt()
          : int.tryParse('${nilaiToko ?? ''}');
      if (tokoId == null || tokoId <= 0 || tokoId != Sesi.instance.tokoId) {
        return false;
      }
      final tanggal = _tanggalTransaksi(payload['waktu']);
      if (tanggal == null) return false;
      return !await _periksaKodePadaServer(
        kode: kode,
        tokoId: tokoId,
        tanggal: tanggal,
      );
    });
  }

  /// Batalkan hanya transaksi PENDING/GAGAL yang sudah dipastikan tidak ada di
  /// arsip server. Pemeriksaan baca ini online-only demi integritas pembayaran;
  /// kegagalan jaringan, hasil tak dikenal, atau baris yang berubah status menahan
  /// penghapusan. Kunci per kode mencegah kirim ulang dari aplikasi ini berjalan
  /// bersamaan dengan pemeriksaan dan penghapusan.
  Future<void> batalkanTransaksiGagalBelumTerkirim(String kodeUnik) async {
    final kode = kodeUnik.trim();
    if (kode.isEmpty) throw ArgumentError('Kode transaksi tidak dikenali.');
    if (!ApiClient.instance.sudahLogin) {
      throw StateError('Sesi login belum siap untuk memeriksa transaksi.');
    }
    if (!Sesi.instance.bolehHapusPesanan) {
      throw StateError(
          'Hak pembatalan transaksi tidak tersedia untuk akun ini.');
    }
    await _denganKunciKode<void>(kode, () async {
      final row = await CoreDb.instance.transaksiLokalDenganKode(kode);
      if (row == null) {
        throw StateError('Transaksi tidak ditemukan pada perangkat ini.');
      }
      final status = '${row['status'] ?? ''}'.trim().toUpperCase();
      if (status != 'PENDING' && status != 'GAGAL') {
        throw StateError(
            'Transaksi yang sudah tercatat tidak dapat dibatalkan dari antrean lokal. Muat ulang status transaksi sebelum melanjutkan.');
      }
      final tokoLokal = (row['toko_id'] as num?)?.toInt();
      final payload = Map<String, dynamic>.from(
          jsonDecode('${row['payload_json'] ?? '{}'}') as Map);
      final nilaiToko = payload['tokoId'] ?? payload['idToko'] ?? tokoLokal;
      final tokoId = nilaiToko is num
          ? nilaiToko.toInt()
          : int.tryParse('${nilaiToko ?? ''}');
      if (tokoId == null || tokoId <= 0 || tokoId != Sesi.instance.tokoId) {
        throw StateError(
            'Toko transaksi tidak sama dengan toko aktif. Minta supervisor membuka toko asal untuk memeriksanya.');
      }
      final tanggal = _tanggalTransaksi(payload['waktu']);
      if (tanggal == null) {
        throw StateError(
            'Tanggal transaksi tidak terbaca; transaksi tidak dihapus demi keamanan.');
      }

      final ditemukan = await _periksaKodePadaServer(
        kode: kode,
        tokoId: tokoId,
        tanggal: tanggal,
      );
      if (ditemukan) {
        throw StateError(
            'Transaksi ini sudah tercatat di server dan tidak dapat dibatalkan dari antrean lokal. Muat ulang Riwayat Penjualan.');
      }
      final terhapus = await CoreDb.instance
          .hapusTransaksiBelumTerkirimTerverifikasiTidakAdaDiServer(
        kode,
        pelaku: Sesi.instance.userId,
      );
      if (!terhapus) {
        throw StateError(
            'Status transaksi berubah saat diperiksa. Muat ulang dan pastikan statusnya masih menunggu atau gagal.');
      }
    });
  }

  Future<bool> _periksaKodePadaServer({
    required String kode,
    required int tokoId,
    required DateTime tanggal,
  }) async {
    const ukuranHalaman = 200;
    final kodeNormal = kode.toLowerCase();
    var halaman = 1;
    var sudahDibaca = 0;
    while (halaman <= 1000) {
      final hasil =
          await ApiClient.instance.aksi('transaksi_backup_toko_list', {
        'toko_id': tokoId,
        'tglMulai': _tanggal(tanggal),
        'tglSampai': _tanggal(tanggal),
        'page': halaman,
        'pageSize': ukuranHalaman,
      });
      dynamic raw = hasil['data'];
      if (raw is Map) {
        raw = raw['rows'] ?? raw['items'] ?? raw['list'] ?? raw['data'];
      }
      raw ??= hasil['rows'] ??
          hasil['items'] ??
          hasil['list'] ??
          hasil['transaksi'];
      if (raw is! List) {
        throw const FormatException(
            'Daftar transaksi server tidak lengkap; pembatalan dihentikan.');
      }
      final baris = raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (baris.any((item) => _kodeServer(item).toLowerCase() == kodeNormal)) {
        return true;
      }
      sudahDibaca += baris.length;
      final dataMap = hasil['data'] is Map
          ? Map<String, dynamic>.from(hasil['data'] as Map)
          : const <String, dynamic>{};
      final totalRaw = hasil['total'] ??
          hasil['totalData'] ??
          hasil['totalRows'] ??
          hasil['recordsTotal'] ??
          hasil['count'] ??
          dataMap['total'] ??
          dataMap['totalData'] ??
          dataMap['totalRows'] ??
          dataMap['recordsTotal'] ??
          dataMap['count'];
      final total =
          totalRaw is num ? totalRaw.toInt() : int.tryParse('$totalRaw');
      if (total != null && sudahDibaca >= total) return false;
      if (baris.length < ukuranHalaman) return false;
      halaman++;
    }
    throw StateError(
        'Pemeriksaan server melebihi batas halaman; transaksi tidak dihapus.');
  }

  DateTime? _tanggalTransaksi(Object? nilai) {
    final teks = '${nilai ?? ''}'.trim();
    final iso = DateTime.tryParse(teks);
    if (iso != null) return iso;
    final cocok = RegExp(r'^(\d{2})[-/](\d{2})[-/](\d{4})').firstMatch(teks);
    if (cocok != null) {
      return DateTime.tryParse(
          '${cocok.group(3)}-${cocok.group(2)}-${cocok.group(1)}');
    }
    return null;
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
    final vonis = await _kirimSatuBarisTerkunci(
      row,
      izinkanSudahTersinkron: paksa,
    );
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
        tokoId: Sesi.instance.tokoId,
        jedaRetry: Duration.zero,
      ));
      baris.addAll(await CoreDb.instance.transaksiGagalBelumSinkron(
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
      final vonis = await _kirimSatuBarisTerkunci(row);
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
    'SALDO_TIDAK_CUKUP',
    'LIMIT_TIDAK_CUKUP',
    'METODE_PEMBAYARAN_TIDAK_VALID',
  };

  /// Beberapa backend lama membalas penolakan bisnis hanya lewat kalimat tanpa
  /// `code`. Pencocokan ini sengaja konservatif dan hanya memakai pasangan kata
  /// yang tidak mungkin pulih karena retry payload identik. Gangguan jaringan
  /// dan HTTP 5xx sudah dikembalikan sebagai retryable sebelum fungsi ini
  /// dipanggil.
  static bool pesanAdalahPenolakanPermanen(String pesan) {
    final nilai = pesan.toLowerCase();
    bool memuatSalahSatu(Iterable<String> pilihan) =>
        pilihan.any(nilai.contains);

    if (nilai.contains('saldo') &&
        memuatSalahSatu(const [
          'tidak mencukupi',
          'tidak cukup',
          'saldo kurang',
          'melebihi saldo',
          'minimal saldo',
        ])) {
      return true;
    }
    if (nilai.contains('limit') &&
        memuatSalahSatu(const [
          'tidak mencukupi',
          'tidak cukup',
          'melebihi',
          'ditolak',
        ])) {
      return true;
    }
    if (nilai.contains('metode pembayaran') &&
        memuatSalahSatu(const [
          'tidak aktif',
          'tidak diizinkan',
          'tidak tersedia',
          'tidak berlaku',
          'tidak sesuai',
        ])) {
      return true;
    }
    if (nilai.contains('pin') &&
        memuatSalahSatu(const ['salah', 'tidak valid', 'tidak cocok'])) {
      return true;
    }
    return nilai.contains('stok tidak cukup') ||
        nilai.contains('produk kadaluarsa') ||
        nilai.contains('produk kedaluwarsa') ||
        (nilai.contains('total master') && nilai.contains('total rincian')) ||
        nilai.contains('tidak memiliki hak akses') ||
        nilai.contains('tidak diizinkan') ||
        nilai.contains('hanya supervisor') ||
        nilai.contains('hanya admin');
  }

  /// Batas percobaan otomatis sebelum transaksi diparkir sbg GAGAL. Mencegah
  /// kode tak dikenal berputar tanpa akhir, sambil tetap menyediakan jalur
  /// Kirim Ulang manual.
  static const int batasPercobaanOtomatis = 20;

  bool dapatDicobaUlang(Object error) {
    if (error is! ApiException) return true;
    if (error.offline || (error.statusHttp ?? 0) >= 500) return true;
    if (pesanAdalahPenolakanPermanen(error.pesan)) return false;
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
