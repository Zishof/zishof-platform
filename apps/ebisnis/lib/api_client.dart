import 'dart:async';
import 'dart:convert';
import 'package:core_auth/core_auth.dart';
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

  /// Memberi tahu gerbang aplikasi ketika sesi benar-benar dibuang, termasuk
  /// saat server menolak token dengan HTTP 401. Tanpa sinyal ini layar lama
  /// tetap hidup dan terus mengirim permintaan dengan konteks sesi kosong.
  final StreamController<void> _sesiBerakhirController =
      StreamController<void>.broadcast(sync: true);

  Stream<void> get sesiBerakhir => _sesiBerakhirController.stream;

  /// Tenant aktif perangkat ini. Dikirim sebagai header `X-Tenant-Id` pada
  /// setiap permintaan.
  ///
  /// Satu perangkat melayani satu tenant, jadi nilainya diikat sekali saat
  /// login dan bertahan sampai perangkat dialihkan. Klien **tidak pernah**
  /// mengirim nama schema — hanya id ini; server yang menerjemahkannya sesudah
  /// keanggotaan tervalidasi.
  int? _tenantId;

  int? get tenantId => _tenantId;

  Future<void> muatTokenTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString('token');
    final t = sp.getInt('tenant_id');
    _tenantId = (t != null && t > 0) ? t : null;
    if (_tenantId != null) {
      Sesi.instance.tenantId = _tenantId;
      Sesi.instance.tenantKode = sp.getString('tenant_kode') ?? '';
      Sesi.instance.tenantNama = sp.getString('tenant_nama') ?? '';
    } else {
      Sesi.instance.bersihkanTenant();
    }
  }

  Future<void> simpanTenantId(int? tenantId,
      {String? tenantKode, String? tenantNama}) async {
    _tenantId = (tenantId != null && tenantId > 0) ? tenantId : null;
    final sp = await SharedPreferences.getInstance();
    if (_tenantId == null) {
      await sp.remove('tenant_id');
      await sp.remove('tenant_kode');
      await sp.remove('tenant_nama');
      Sesi.instance.bersihkanTenant();
      return;
    }
    await sp.setInt('tenant_id', _tenantId!);
    await sp.setString('tenant_kode', tenantKode ?? '');
    await sp.setString('tenant_nama', tenantNama ?? '');
    // Bilah atas membaca dari Sesi, bukan dari SharedPreferences -- satu sumber
    // di memori, supaya tidak ada layar yang menampilkan nilai basi.
    Sesi.instance.tenantId = _tenantId;
    Sesi.instance.tenantKode = tenantKode ?? '';
    Sesi.instance.tenantNama = tenantNama ?? '';
  }

  Future<void> simpanToken(String token) async {
    _token = token;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('token', token);
    await PengaturanSesiLokal.instance.catatAktifSekarang();
  }

  /// Buang sesi perangkat SELURUHNYA: token, catatan aktif, dan bukti kata
  /// sandi luring. Ketiganya satu paket -- identitas yang tidak lagi dipakai di
  /// perangkat ini tidak boleh menyisakan jalan masuk luring.
  Future<void> hapusToken({bool tutupBasisData = false}) async {
    final sebelumnyaMasuk = _token != null;
    _token = null;
    if (sebelumnyaMasuk) _sesiBerakhirController.add(null);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('token');
    await PengaturanSesiLokal.instance.hapusCatatanAktif();
    await VerifikatorSandiLokal.instance.hapus();
    // Tenant aktif ikut dibuang: identitas yang tidak lagi dipakai di perangkat
    // ini tidak boleh menyisakan tenant aktifnya untuk pengguna berikutnya.
    _tenantId = null;
    await sp.remove('tenant_id');
    await sp.remove('tenant_kode');
    await sp.remove('tenant_nama');
    Sesi.instance.bersihkanTenant();

    // Basis data tenant ditutup HANYA pada keluar akun yang disengaja.
    //
    // Metode ini juga dipanggil dari jalur 401 (token ditolak server) lewat
    // `unawaited`, dan di sana kueri lain bisa sedang berjalan -- menutup
    // basis data di tengahnya membuat operasi yang sah gagal. Data lokalnya
    // pun tidak menjadi lebih aman karena ditutup: ia tetap ada di disk, dan
    // yang menjaga pengguna berikutnya adalah pengikatan tenant saat login.
    if (tutupBasisData) {
      await CoreDb.instance.tutup();
    }
  }

  bool get sudahLogin => _token != null;

  /// Token sesi untuk permintaan yang TIDAK lewat [aksi] -- khususnya unggahan
  /// multipart ke servlet `DoUpload`, yang menerima token sebagai FIELD form
  /// (bukan header `Authorization`). Lihat `unggah_lampiran_sop.dart`.
  ///
  /// Sengaja hanya-baca: tidak ada jalan menulis token dari luar kelas ini.
  String? get token => _token;

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
    'produk_mutasi_ringkasan',
    'produk_statistik',
    'produk_statistik_detail',
    'price_tag_list_produk',
    'so_simpan',
    'so_batalkan',
    'so_perubahan_stok',
    'so_riwayat',
    'so_ringkasan',
    'so_harian',
    'so_harian_download_excel',
    'so_harian_upload_excel_preview',
    'so_harian_upload_excel',
    'so_harian_ekspor_excel',
    'so_ekspor_excel',
    'so_impor_excel',
    'stok_dashboard',
    'stok_mutasi_ledger',
    'kulakan_faktur_simpan',
    'peringkat_mitra',
    'diskon_simpan',
    'pencairan_diskon_list',
    'pencairan_diskon_simpan',
    'mutasi_stok_list',
    'mutasi_stok_produk_list',
    'otomatis_layani_jalankan',
    'layani_transaksi',
    'detail_transaksi',
    'layar_pelanggan_slide_list',
    'layar_pelanggan_slide_upload',
    'layar_pelanggan_slide_ubah',
    'layar_pelanggan_slide_hapus',
    'layar_pelanggan_slide_untuk_tampil',
    'layar_pelanggan_screensaver_config_ambil',
    'layar_pelanggan_screensaver_config_simpan',
    'distribusi_list',
    'distribusi_detail',
    'distribusi_simpan',
    'distribusi_status',
  };

  static bool _nilaiTokoValid(Object? nilai) {
    if (nilai is num) return nilai.toInt() > 0;
    final id = int.tryParse('$nilai');
    return id != null && id > 0;
  }

  /// Menyusun payload akhir sebuah aksi, termasuk penyisipan toko.
  ///
  /// Dipisah dari [aksi] supaya aturan tokonya bisa dikunci uji tanpa jaringan --
  /// aturan ini yang menentukan ke toko MANA sebuah simpanan mendarat, dan salah
  /// di sini tidak memunculkan galat apa pun, hanya data di tempat yang keliru.
  static Map<String, dynamic> susunPayload(
      String namaAksi, Map<String, dynamic>? body) {
    final payload = <String, dynamic>{'action': namaAksi, ...?body};
    // `toko_id: null` bukan pilihan eksplisit. Beberapa layar lama selalu
    // membentuk kunci itu meski nilainya kosong; bila hanya keberadaan kunci
    // yang diperiksa, penyisipan toko aktif di bawah tidak pernah berjalan.
    const kunciToko = ['tokoId', 'id_toko', 'idToko', 'toko_id'];
    for (final kunci in kunciToko) {
      if (payload.containsKey(kunci) && !_nilaiTokoValid(payload[kunci])) {
        payload.remove(kunci);
      }
    }
    final sudahAdaToko =
        kunciToko.any((kunci) => _nilaiTokoValid(payload[kunci]));
    final sudahAdaLingkupKatalog =
        sudahAdaToko || payload.containsKey('semuaToko');
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
      if (idToko != null) {
        payload['toko_id'] = idToko;
      }
    }
    // `katalog` memiliki kontrak khusus di peladen: admin tanpa toko terikat
    // hanya memperoleh daftar bila menyatakan `semuaToko=true`. Beberapa
    // layar mencari produk langsung (Kasir, Kulakan, SPJ, Riwayat), sehingga
    // pengaman ini dipusatkan agar satu pemanggil yang lupa tidak menampilkan
    // cache sesaat lalu menimpanya dengan respons server kosong.
    if (namaAksi == 'katalog' && !sudahAdaLingkupKatalog) {
      final idToko = Sesi.instance.idTokoTerpilih;
      if (idToko != null) {
        payload['toko_id'] = idToko;
      } else if (Sesi.instance.isAdmin) {
        payload['semuaToko'] = true;
      }
    }
    return payload;
  }

  /// Apakah [namaAksi] menerima `toko_id` dari sesi (lihat [_aksiBerTokoId]).
  static bool aksiMemakaiTokoId(String namaAksi) =>
      _aksiBerTokoId.contains(namaAksi);

  /// Nama field yang isinya TIDAK BOLEH ikut tercatat di log teknis.
  ///
  /// Log error dapat disalin dan dikirim ke pengembang lewat WhatsApp/e-mail,
  /// jadi apa pun yang bisa dipakai masuk ke akun orang lain harus disamarkan
  /// lebih dulu -- bukan diserahkan pada kehati-hatian penyalin.
  static const Set<String> _fieldRahasia = {
    'password',
    'pass',
    'sandi',
    'kata_sandi',
    'pin',
    'pin_supervisor',
    'token',
    'authorization',
    'otp',
    'secret',
    'api_key',
    'apikey',
    'template_base64',
    'probe_base64',
    'biometric_template',
  };

  /// Menyalin payload untuk keperluan log: nilai rahasia diganti penanda, dan
  /// nilai yang sangat panjang (mis. base64 foto/Excel) dipotong supaya satu
  /// baris log tidak menelan seluruh berkas.
  static Object? _samarkanUntukLog(Object? nilai, [int kedalaman = 0]) {
    if (kedalaman > 6) return '...';
    if (nilai is Map) {
      final hasil = <String, Object?>{};
      nilai.forEach((kunci, isi) {
        final nama = '$kunci'.toLowerCase();
        if (_fieldRahasia.contains(nama)) {
          hasil['$kunci'] = '***disamarkan***';
        } else {
          hasil['$kunci'] = _samarkanUntukLog(isi, kedalaman + 1);
        }
      });
      return hasil;
    }
    if (nilai is List) {
      // Daftar panjang (mis. ribuan baris impor) cukup diwakili sebagian.
      final potong = nilai.length > 50 ? nilai.take(50).toList() : nilai;
      final hasil = potong
          .map((e) => _samarkanUntukLog(e, kedalaman + 1))
          .toList(growable: true);
      if (nilai.length > 50) {
        hasil.add('...(${nilai.length - 50} item lain tidak dicatat)');
      }
      return hasil;
    }
    if (nilai is String && nilai.length > 500) {
      return '${nilai.substring(0, 500)}...(${nilai.length} karakter)';
    }
    return nilai;
  }

  /// Payload permintaan dalam bentuk siap tempel ke laporan pengembang.
  static String _permintaanUntukLog(Map<String, dynamic> payload) {
    try {
      final teks = jsonEncode(_samarkanUntukLog(payload));
      return teks.length > 4000
          ? '${teks.substring(0, 4000)}...(${teks.length} karakter)'
          : teks;
    } catch (e) {
      return '(payload tidak dapat diserialisasi: $e)';
    }
  }

  /// Potongan badan respons; dipakai apa adanya karena justru bentuk mentahnya
  /// (mis. halaman HTML 502 dari gateway) yang menjelaskan kegagalannya.
  static String _responsUntukLog(String body) {
    if (body.isEmpty) return '(kosong)';
    return body.length > 4000
        ? '${body.substring(0, 4000)}...(${body.length} karakter)'
        : body;
  }

  /// Endpoint hasil redirect yang sudah terbukti, per URL asal.
  ///
  /// Diingat selama aplikasi berjalan supaya ongkos redirect hanya dibayar
  /// sekali, bukan pada setiap permintaan.
  static final Map<String, String> _endpointSetelahRedirect = {};

  /// POST yang MENGIKUTI redirect 301/302/307/308.
  ///
  /// <b>Mengapa perlu.</b> Server produksi memasang pengalihan permanen dari
  /// http ke https (Apache: `301 Moved Permanently`). Pustaka HTTP Dart hanya
  /// mengikuti redirect otomatis untuk GET/HEAD -- untuk POST, badan permintaan
  /// tidak ikut dikirim ulang, sehingga aplikasi menerima halaman HTML 301 dan
  /// gagal mengurainya sebagai JSON. Gejalanya: 'FormatException: Unexpected
  /// character (at character 1) <!DOCTYPE HTML...' pada aksi apa pun, termasuk
  /// login, padahal servernya sehat dan alamatnya benar.
  ///
  /// <b>Batas keamanan.</b> Redirect HANYA diikuti bila host tujuannya SAMA
  /// dengan host asal (skema boleh naik http -> https). Payload aksi ini berisi
  /// kata sandi dan token; mengikuti pengalihan ke host lain berarti
  /// menyerahkan kredensial pengguna ke pihak yang belum tentu tepercaya.
  static Future<http.Response> _postIkutiRedirect(
    String url,
    Map<String, String> headers,
    String body,
    Duration batasWaktu,
  ) async {
    var tujuan = _endpointSetelahRedirect[url] ?? url;
    for (var lompatan = 0; lompatan < 3; lompatan++) {
      final resp = await http
          .post(Uri.parse(tujuan), headers: headers, body: body)
          .timeout(batasWaktu);
      final kode = resp.statusCode;
      final pindah = kode == 301 || kode == 302 || kode == 307 || kode == 308;
      final lokasi = resp.headers['location'];
      if (!pindah || lokasi == null || lokasi.trim().isEmpty) {
        return resp;
      }
      final asal = Uri.parse(tujuan);
      final baru = asal.resolve(lokasi.trim());
      if (baru.host.toLowerCase() != asal.host.toLowerCase()) {
        // Host berbeda -- jangan pernah kirim ulang kredensial ke sana.
        return resp;
      }
      tujuan = baru.toString();
      if (kode == 301 || kode == 308) {
        // Pengalihan PERMANEN: simpan supaya permintaan berikutnya langsung.
        _endpointSetelahRedirect[url] = tujuan;
      }
    }
    // Terlalu banyak lompatan; kembalikan percobaan terakhir apa adanya.
    return await http
        .post(Uri.parse(tujuan), headers: headers, body: body)
        .timeout(batasWaktu);
  }

  Future<Map<String, dynamic>> aksi(String namaAksi,
      [Map<String, dynamic>? body]) async {
    final payload = susunPayload(namaAksi, body);
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null) headers['Authorization'] = 'Bearer $_token';
    // Kontrak §7.1: klien hanya menyebut tenantId, tidak pernah nama schema.
    // Server menolak dengan TENANT_CONTEXT_MISMATCH bila header dan body beda.
    if (_tenantId != null) headers['X-Tenant-Id'] = '$_tenantId';

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
      resp = await _postIkutiRedirect(
          baseUrl, headers, jsonEncode(payload), batasWaktu);
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
            'Permintaan: ${_permintaanUntukLog(payload)}\n'
            'Respons: (tidak ada -- server tidak menjawab)\n'
            'Stack trace klien:\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    Map<String, dynamic> json;
    try {
      json =
          jsonDecode(normalisasiJsonRespons(resp.body)) as Map<String, dynamic>;
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
            'Permintaan: ${_permintaanUntukLog(payload)}\n'
            'Respons: $cuplikan\n$stack',
      );
      unawaited(_catatKegagalan(gagal));
      throw gagal;
    }

    if (resp.statusCode == 401) {
      // Server MENOLAK token: dicabut, kedaluwarsa, atau tidak dikenal. Ini
      // satu-satunya alasan sah membuang sesi perangkat -- batas waktu lokal
      // hanya mengunci layar (lihat LayarKunciScreen).
      unawaited(hapusToken());
    }

    if (!statusResponsSukses(json['status'])) {
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
                'status=${json['status']}; kode=${json['kode']}; message=${json['message']}\n'
                'Permintaan: ${_permintaanUntukLog(payload)}\n'
                'Respons: ${_responsUntukLog(resp.body)}'
            : 'Request ID: $referensiPermintaan\nEndpoint: $baseUrl\n'
                'HTTP ${resp.statusCode}; action=$namaAksi\n'
                '${json['teknis'] ?? json['technical']}\n'
                'Permintaan: ${_permintaanUntukLog(payload)}\n'
                'Respons: ${_responsUntukLog(resp.body)}',
      );
      if (!_kegagalanYangDiharapkan(gagal)) {
        unawaited(_catatKegagalan(gagal));
      }
      throw gagal;
    }
    return json;
  }

  /// Server eBisnis lama memakai `00`, sedangkan endpoint POS baru memakai
  /// `success`. Keduanya merupakan kontrak sukses yang sah.
  static bool statusResponsSukses(Object? status) =>
      status == 'success' || status == '00';

  /// Beberapa handler AIS lama masih menulis toast JavaScript melalui helper
  /// JSP sebelum menulis objek JSON yang sah. Respons seperti itu berstatus
  /// HTTP 200 dan bagian setelah `</script>` tetap merupakan kontrak API yang
  /// dapat diproses. Hanya prefix `<script>...</script>` pada awal respons yang
  /// dibuang; halaman HTML biasa atau JSON rusak tetap ditolak fail-closed.
  static String normalisasiJsonRespons(String body) {
    final trimmed = body.trimLeft();
    if (!trimmed.toLowerCase().startsWith('<script')) return body;
    final end = trimmed.toLowerCase().indexOf('</script>');
    if (end < 0) return body;
    final kandidat = trimmed.substring(end + '</script>'.length).trimLeft();
    if (!kandidat.startsWith('{')) return body;

    // Legacy renderer juga dapat menambahkan script telemetry SESUDAH JSON.
    // Cari penutup objek terluar dengan tetap menghormati kurung kurawal di
    // dalam string/escape, lalu serahkan hanya objek lengkap ke jsonDecode.
    var dalamString = false;
    var escape = false;
    var depth = 0;
    for (var i = 0; i < kandidat.length; i++) {
      final char = kandidat[i];
      if (dalamString) {
        if (escape) {
          escape = false;
        } else if (char == r'\') {
          escape = true;
        } else if (char == '"') {
          dalamString = false;
        }
        continue;
      }
      if (char == '"') {
        dalamString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return kandidat.substring(0, i + 1);
      }
    }
    return body;
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
      await _postIkutiRedirect(
          baseUrl,
          const {'Content-Type': 'application/json'},
          jsonEncode({
            'action': 'client_error_log',
            'sumber': gagal.aktivitas ?? 'unknown',
            'pesan': info.pesan,
            'detail': gagal.teknis,
            'referensi': info.kodeReferensi,
          }),
          const Duration(seconds: 5));
    } catch (_) {
      // Catatan lokal sudah tersimpan dan dapat disinkronkan/diperiksa nanti.
    }
  }

  bool _kegagalanYangDiharapkan(ApiException gagal) {
    // Instalasi lama boleh belum memakai tenant. PengikatanTenant menangani
    // respons ini sebagai mode legacy/tanpa tenant, sehingga bukan error yang
    // perlu memenuhi Log Error dan endpoint client_error_log.
    return gagal.aktivitas == 'tenant_context' &&
        gagal.kode == 'TENANT_ACCESS_DENIED';
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
    final panduan =
        panduanResolusiGalat(pesan, aktivitas: aktivitas, kode: kode);
    final solusiServerGenerik = solusi.isNotEmpty &&
        solusi.every((s) {
          final lower = s.toLowerCase();
          return lower.contains('perbaiki data sesuai penjelasan') ||
              lower.contains('hubungi admin/supervisor') ||
              lower.contains('coba kembali');
        });
    final judulServer = judul?.trim() ?? '';
    final judulServerGenerik = judulServer.isEmpty ||
        judulServer == 'Belum dapat diproses' ||
        judulServer == 'Proses belum berhasil';
    return AppErrorInfo(
      judul: rincianPesananBerbeda
          ? 'Pesanan perlu dimuat ulang'
          : !offline && judulServerGenerik && panduan.judul != null
              ? panduan.judul!
              : judulServer.isNotEmpty
                  ? judulServer
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
      solusi: solusi.isNotEmpty && !solusiServerGenerik
          ? solusi
          : rincianPesananBerbeda
              ? solusiPesananBerbeda
              : !offline
                  ? panduan.solusi
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
