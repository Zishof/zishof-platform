import 'dart:async';
import 'dart:convert';
import 'package:core_db/core_db.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'sesi.dart';
import 'services/pengaturan_sesi_lokal.dart';
import 'services/server_config.dart';
import 'widgets/app_error_info.dart';

/// Klien HTTP untuk endpoint Api_eBisnis (branded alias PosApi.java, kontrak
/// JSON identik -- lihat JavaDoc ais.action.servlet.ApiEBisnis di server).
/// Satu method generik [aksi] dipakai semua layar, sama seperti pola
/// panggilPosApi/AisApi.panggil di POS Desktop/Android existing.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  /// Dulu `static const` hardcode `https://ebisnis.id/ebisnis/Api_eBisnis` --
  /// sekarang dibangun dari [ServerConfig] (layar Pengaturan Alamat Server)
  /// supaya satu build APK/EXE bisa dipakai institusi mana pun, padanan
  /// setup.html/main.js desktop-pos-electron.
  static String get baseUrl => ServerConfig.instance.apiBaseUrl;

  String? _token;

  Future<void> muatTokenTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
  }

  Future<void> simpanToken(String token) async {
    _token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await PengaturanSesiLokal.instance.catatAktifSekarang();
  }

  Future<void> hapusToken() async {
    _token = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await PengaturanSesiLokal.instance.hapusCatatanAktif();
  }

  bool get sudahLogin => _token != null;

  /// Memanggil satu aksi Api_eBisnis. [body] digabung dengan {action: aksi}.
  /// Melempar [ApiException] bila status bukan "success" ATAU permintaan HTTP gagal.
  /// Aksi yang ikut disaring oleh combo filter toko di bilah atas.
  ///
  /// Hanya BACA (Dashboard + Laporan). Aksi kasir sengaja TIDAK ikut: itu
  /// operasi pada satu toko, dan menyuntik toko lain ke sana berarti mencatat
  /// transaksi ke toko yang salah.
  static bool _ikutFilterToko(String namaAksi) =>
      namaAksi.startsWith('dashboard_') || namaAksi.startsWith('laporan_');

  /// Aksi yang menentukan tokonya lewat `toko_id` DI PAYLOAD.
  ///
  /// Di server, aksi-aksi ini mengambil toko dari `Tbmuser.pedagang`; kalau akun
  /// tidak punya Pedagang -- persis kasus akun admin -- toko hanya bisa datang
  /// dari payload. Selama ini tidak ada yang mengirimnya, sehingga layar-layar
  /// ini menolak dengan "Toko tidak diketahui." untuk admin, betapapun jelas
  /// satu toko terpilih di kotak toko kiri atas.
  ///
  /// Disisipkan di SINI, bukan di tiap layar. Daftar ini disusun dari penelusuran
  /// handler server satu per satu, dan menambah layar baru berarti menambah satu
  /// baris di sini -- jauh lebih sulit terlewat daripada mengingat memasang
  /// `toko_id` di setiap pemanggilan baru.
  ///
  /// Untuk akun yang PUNYA Pedagang, server tetap memakai toko milik Pedagang
  /// dan mengabaikan nilai ini, jadi penyisipan ini tidak mengubah apa pun bagi
  /// kasir biasa.
  ///
  /// Sengaja TIDAK memuat `sesi_kas_*` dan `pilih_toko_aktif`: itu mengurus toko
  /// AKTIF (tempat transaksi dicatat), bukan toko yang sedang dilihat. Menyuntik
  /// pilihan filter ke sana berarti membuka sesi kas di toko yang salah.
  static const _aksiBerTokoId = <String>{
    'toko_profil_ambil',
    'toko_profil_simpan',
    'pedagang_list',
    'akun_tambah',
    'produk_simpan',
    'produk_ekspor_excel',
    'produk_impor_excel',
    'produk_impor_excel_preview',
    'produk_rekonsiliasi_ledger',
    'so_simpan',
    'so_ekspor_excel',
    'so_impor_excel',
    'kulakan_faktur_simpan',
    'peringkat_mitra',
    'diskon_simpan',
    'pencairan_diskon_list',
    'pencairan_diskon_simpan',
    'mutasi_stok_list',
    'mutasi_stok_produk_list',
    'otomatis_layani_jalankan',
  };

  /// Menyusun payload akhir sebuah aksi, termasuk penyisipan toko.
  ///
  /// Dipisah dari [aksi] supaya aturan tokonya bisa dikunci uji tanpa jaringan --
  /// aturan ini yang menentukan ke toko MANA sebuah simpanan mendarat, dan salah
  /// di sini tidak memunculkan galat apa pun, hanya data di tempat yang keliru.
  static Map<String, dynamic> susunPayload(
      String namaAksi, Map<String, dynamic>? body) {
    final payload = <String, dynamic>{'action': namaAksi, ...?body};
    final sudahAdaToko = payload.containsKey('tokoId') ||
        payload.containsKey('id_toko') ||
        payload.containsKey('idToko') ||
        payload.containsKey('toko_id');
    // Peran berizin lintas toko: pilihan combo disisipkan di satu tempat
    // supaya tiap layar tidak perlu mengingatnya sendiri. Toko yang sudah
    // ditentukan pemanggil TIDAK ditimpa.
    if (Sesi.instance.bolehSemuaToko &&
        Sesi.instance.tokoFilter != null &&
        _ikutFilterToko(namaAksi) &&
        !sudahAdaToko) {
      payload['tokoId'] = Sesi.instance.tokoFilter;
    }
    // Kunci `toko_id` (garis bawah) -- kontrak yang berbeda dari `tokoId` di
    // atas, dan memang beda aksi. Nilainya toko yang TERTULIS di kotak toko,
    // supaya yang tersimpan tidak pernah berbeda dari yang dibaca pengguna.
    // Kalau belum ada toko terpilih, kunci ini tidak dikirim dan server tetap
    // menolak dengan pesannya sendiri -- lebih baik ditolak daripada menebak
    // toko lalu menulis ke tempat yang salah.
    if (_aksiBerTokoId.contains(namaAksi) && !sudahAdaToko) {
      final idToko = Sesi.instance.idTokoTerpilih;
      if (idToko != null) payload['toko_id'] = idToko;
    }
    return payload;
  }

  /// Apakah [namaAksi] menerima `toko_id` dari sesi (lihat [_aksiBerTokoId]).
  static bool aksiMemakaiTokoId(String namaAksi) =>
      _aksiBerTokoId.contains(namaAksi);

  Future<Map<String, dynamic>> aksi(String namaAksi,
      [Map<String, dynamic>? body]) async {
    final payload = susunPayload(namaAksi, body);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';

    final mulai = DateTime.now();
    final referensiPermintaan =
        '${mulai.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-${namaAksi.hashCode.abs().toRadixString(36).toUpperCase()}';
    headers['X-Request-ID'] = referensiPermintaan;
    final batasWaktu = namaAksi == 'produk_impor_excel_preview'
        ? const Duration(minutes: 5)
        : namaAksi == 'produk_impor_excel_komit'
            ? const Duration(minutes: 3)
            : const Duration(seconds: 30);

    http.Response resp;
    try {
      resp = await http
          .post(Uri.parse(baseUrl), headers: headers, body: jsonEncode(payload))
          .timeout(batasWaktu);
    } catch (e, stack) {
      final gagal = ApiException(
        'Aplikasi belum dapat menghubungi server.',
        offline: true,
        aktivitas: namaAksi,
        kodeReferensi: referensiPermintaan,
        teknis: 'Request ID: $referensiPermintaan\n'
            'Waktu mulai: ${mulai.toIso8601String()}\n'
            'Waktu gagal: ${DateTime.now().toIso8601String()}\n'
            'Endpoint: $baseUrl\n'
            'Action: $namaAksi\n'
            'Batas waktu: ${batasWaktu.inSeconds} detik\n'
            'Exception: ${e.runtimeType}: $e\n'
            'Stack trace klien:\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e, stack) {
      final cuplikan = resp.body.length > 1200
          ? '${resp.body.substring(0, 1200)}…'
          : resp.body;
      final gagal = ApiException(
        'Jawaban server belum dapat diproses.',
        aktivitas: namaAksi,
        statusHttp: resp.statusCode,
        kodeReferensi: referensiPermintaan,
        teknis: 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
            'Action: $namaAksi\nHTTP ${resp.statusCode}; ${e.runtimeType}: $e\n'
            'Response: $cuplikan\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    if (json['status'] != 'success') {
      final gagal = ApiException(
        '${json['message'] ?? json['description'] ?? 'Permintaan belum berhasil.'}',
        aktivitas: namaAksi,
        statusHttp: resp.statusCode,
        kodeReferensi:
            '${json['referensi'] ?? json['traceId'] ?? referensiPermintaan}',
        kode: '${json['kode'] ?? ''}',
        judul: '${json['judul'] ?? ''}',
        solusi: json['solusi'] is List
            ? (json['solusi'] as List)
                .map((e) => '$e'.trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : const [],
        teknis: '${json['teknis'] ?? json['technical'] ?? ''}'.trim().isEmpty
            ? 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
                'HTTP ${resp.statusCode}; action=$namaAksi; '
                'status=${json['status']}; kode=${json['kode']}; message=${json['message']}'
            : 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
                'HTTP ${resp.statusCode}; action=$namaAksi\n'
                '${json['teknis'] ?? json['technical']}',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }
    return json;
  }

  Future<void> _catatKegagalan(ApiException gagal) async {
    final info = gagal.info;
    await CoreDb.instance.catatErrorLog(
      sumber: 'api:${gagal.aktivitas ?? 'unknown'}',
      tingkat: 'ERROR',
      pesan: '${info.judul}: ${info.pesan}',
      detail: 'Referensi ${info.kodeReferensi}\n${gagal.teknis}',
    );
    // Best effort: endpoint ini tidak memakai [aksi] agar kegagalan pencatatan
    // tidak memanggil dirinya sendiri tanpa akhir. Password, token, dan body
    // permintaan tidak pernah dimasukkan ke payload audit.
    try {
      await http
          .post(Uri.parse(baseUrl),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'action': 'client_error_log',
                'sumber': gagal.aktivitas ?? 'unknown',
                'pesan': info.pesan,
                'detail': gagal.teknis,
                'referensi': info.kodeReferensi,
              }))
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Catatan lokal sudah tersimpan dan dapat disinkronkan/diperiksa nanti.
    }
  }

  /// Dipakai penangkap error global dan operasi lokal/non-HTTP agar seluruh
  /// exception tetap masuk error_log lokal dan, bila server tersedia, AIS.
  Future<void> catatError(Object error,
      {StackTrace? stack, String sumber = 'aplikasi'}) async {
    final gagal = ApiException(
      error.toString(),
      aktivitas: sumber,
      teknis: '${error.runtimeType}: $error${stack == null ? '' : '\n$stack'}',
    );
    await _catatKegagalan(gagal);
  }
}

class ApiException implements Exception {
  final String pesan;
  final String? aktivitas;
  final String teknis;
  final int? statusHttp;
  final String? kodeReferensi;
  final String? kode;
  final String? judul;
  final List<String> solusi;

  /// true bila kegagalan murni jaringan/timeout (server tidak terjangkau sama
  /// sekali) -- BEDA dari penolakan bisnis (status="error" dgn pesan dari
  /// server, mis. saldo kurang). Dipakai alur offline-first (KeranjangScreen)
  /// utk memutuskan "tetap simpan lokal & lanjut" (offline=true) vs "batalkan
  /// & tampilkan pesan" (offline=false).
  final bool offline;
  ApiException(this.pesan,
      {this.offline = false,
      this.aktivitas,
      this.teknis = '',
      this.statusHttp,
      this.kodeReferensi,
      this.kode,
      this.judul,
      this.solusi = const []});

  AppErrorInfo get info {
    final dasar = AppErrorInfo.dari(
      offline ? 'network timeout: $pesan' : pesan,
      aktivitas: aktivitas,
    );
    final aktivitasPembayaran = aktivitas == 'bayar' ||
        aktivitas == 'pembayaran' ||
        (aktivitas?.endsWith('_bayar') ?? false);
    final lower = pesan.toLowerCase();
    final rincianPesananBerbeda =
        (lower.contains('rincian pesanan') && lower.contains('keranjang')) ||
            lower.contains('produk rincian pesanan tidak sama');
    final solusiPesananBerbeda = const [
      'Tutup jendela pembayaran, lalu muat ulang daftar pesanan.',
      'Buka kembali pesanan tersebut dan periksa nama produk serta jumlahnya.',
      'Jika masih berbeda, jangan membuat transaksi pengganti. Salin Detail Error dan hubungi supervisor/admin.',
    ];
    return AppErrorInfo(
      judul: judul != null && judul!.trim().isNotEmpty
          ? judul!.trim()
          : rincianPesananBerbeda
              ? 'Pesanan perlu dimuat ulang'
              : aktivitasPembayaran && !offline
                  ? 'Pembayaran belum berhasil'
                  : dasar.judul,
      // `message` pada kontrak API memang ditujukan kepada pengguna dan
      // sudah disanitasi server. Stack/SQL tetap hanya muncul di [teknis].
      pesan: offline
          ? dasar.pesan
          : rincianPesananBerbeda
              ? 'Isi pesanan di server berbeda dengan keranjang yang sedang tampil. Pembayaran dihentikan agar barang atau jumlah yang salah tidak tersimpan.'
              : pesan,
      solusi: solusi.isNotEmpty
          ? solusi
          : rincianPesananBerbeda
              ? solusiPesananBerbeda
              : aktivitasPembayaran && !offline
                  ? const [
                      'Jangan langsung menekan Bayar berulang kali. Periksa Riwayat Penjualan dan Riwayat Sinkronisasi untuk memastikan transaksi pertama belum tercatat.',
                      'Periksa kembali keranjang, metode pembayaran, nominal uang diterima, member/saldo, serta status sesi kas.',
                      'Buka Informasi Teknis di bawah ini. Jika belum terselesaikan, salin seluruh detailnya dan kirimkan kepada admin/developer.',
                    ]
                  : dasar.solusi,
      teknis: teknis.isEmpty
          ? 'action=${aktivitas ?? '-'}; HTTP=${statusHttp ?? '-'}; $pesan'
          : teknis,
      kodeReferensi: kodeReferensi == null || kodeReferensi!.trim().isEmpty
          ? dasar.kodeReferensi
          : kodeReferensi!.trim(),
    );
  }

  @override
  String toString() => '${info.pesan} ${info.solusi.first}';
}

/// Dua lapis sebuah kegagalan: kalimat untuk pengguna, dan jejak teknis yang
/// disalin ke admin.
///
/// Kontrak API memang memisahkan `message` dari `teknis`, tetapi layar yang
/// menyimpan `e.toString()` membuang lapis kedua tanpa sisa -- padahal di
/// situlah alasan sebenarnya berada ketika server menyamarkan penolakan.
/// Dipakai bersama `AppFormSheet.errorDetail`.
class GalatTampil {
  /// Kalimat untuk pengguna: pesan server ditambah satu langkah solusi bila ada.
  final String pesan;

  /// Jejak teknis berikut kode referensinya; null untuk galat non-API (mis.
  /// kesalahan parsing lokal) yang memang tidak punya lapis kedua.
  final String? detail;

  const GalatTampil(this.pesan, this.detail);

  factory GalatTampil.dari(Object error) {
    if (error is! ApiException) return GalatTampil(error.toString(), null);
    final info = error.info;
    return GalatTampil(
      info.solusi.isEmpty ? info.pesan : '${info.pesan}\n${info.solusi.first}',
      'Referensi ${info.kodeReferensi}\n${info.teknis}',
    );
  }
}
