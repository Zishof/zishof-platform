import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database offline-first eBisnis -- satu file SQLite per instalasi (`ebisnis.db`),
/// skema meniru `local-db.js` versi Electron (lihat memori sesi
/// `ebisnis-id-pendaftar-brand-toko-mesin-pos-dashboard` utk konteks produk):
/// - `produk_cache`: katalog lengkap, di-replace penuh tiap sinkron (bukan upsert
///   parsial) supaya baris yang dihapus/nonaktif di server ikut hilang dari cache.
/// - `transaksi_pending`: setiap checkout ditulis PENDING di sini SEBELUM mencoba
///   panggilan server -- kalau jaringan gagal, baris tetap PENDING utk disinkron
///   manual belakangan (tidak pernah menghalangi kasir menutup transaksi hanya
///   krn sedang offline).
/// - `cache_referensi`: snapshot generik key->json terakhir (katalog/konfigurasi/dst)
///   dipakai sbg fallback baca saat server tak terjangkau.
/// - `error_log`: log error lokal, dikirim ke server scr berkala/manual.
/// - `sesi_kas_lokal`: status buka/tutup kas -- SUMBER KEBENARAN lokal (bukan
///   server) krn keputusan "apakah kas sedang terbuka" harus instan & tetap
///   benar walau server sedang lambat/offline.
class CoreDb {
  CoreDb._();
  static final CoreDb instance = CoreDb._();

  /// Naik setiap status sesi kas lokal berubah. UI seperti topbar memakai ini
  /// untuk refresh chip "Kas Terbuka/Tertutup" tanpa menunggu rebuild layar.
  final ValueNotifier<int> sesiKasVersi = ValueNotifier<int>(0);

  Database? _db;
  Future<Database>? _openingDb;
  Future<void> _errorLogTail = Future.value();
  String? _lastErrorLogKey;
  DateTime? _lastErrorLogAt;

  Future<Database> get db async {
    final currentDb = _db;
    if (currentDb != null && currentDb.isOpen) return currentDb;
    if (currentDb != null && !currentDb.isOpen) _db = null;

    final openingDb = _openingDb ??= _buka();
    try {
      _db = await openingDb;
      return _db!;
    } finally {
      _openingDb = null;
    }
  }

  Future<Database> _buka() async {
    String path;
    DatabaseFactory factory;
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      path = p.join(dir.path, 'ebisnis.db');
    } else {
      factory = databaseFactory;
      path = p.join(await getDatabasesPath(), 'ebisnis.db');
    }
    try {
      return await _bukaDanVerifikasi(factory, path);
    } catch (e) {
      // Gap-closure "app tidak bisa dibuka lagi stlh mati listrik": file DB
      // (atau sidecar -wal/-shm-nya) korup krn proses tulis terputus paksa
      // tidak akan pernah bisa dibuka lagi TANPA campur tangan -- sebelum
      // ini, satu-satunya jalan keluar user adalah hapus manual seluruh
      // folder AppData. Cadangkan file lama (BUKAN dihapus, spy masih bisa
      // diperiksa manual kalau perlu) lalu buat ulang dari nol supaya app
      // tetap bisa dibuka -- konsekuensinya transaksi PENDING yg belum
      // sempat tersinkron ke server ikut hilang, tapi itu jauh lebih baik
      // drpd app tak bisa dibuka sama sekali.
      await _cadangkanFileKorup(path, alasan: e.toString());
      return _bukaDanVerifikasi(factory, path);
    }
  }

  Future<Database> _bukaDanVerifikasi(
      DatabaseFactory factory, String path) async {
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onConfigure: _konfigurasiDb,
        onCreate: _buatSkema,
        onUpgrade: _upgradeSkema,
      ),
    );
    // `openDatabase` bisa saja LOLOS walau sebagian halaman file korup
    // (header masih valid, badan file rusak) -- korupsi separuh-jalan spt
    // ini baru ketahuan belakangan saat query menyentuh halaman yg rusak
    // (mis. di tengah transaksi kasir). `quick_check` jauh lebih murah drpd
    // `integrity_check` penuh (tak verifikasi index silang) jadi aman
    // dijalankan tiap start tanpa menambah lambat buka app scr terasa.
    final hasil = await database.rawQuery('PRAGMA quick_check');
    final status =
        hasil.isNotEmpty ? hasil.first.values.first?.toString() : null;
    if (status != 'ok') {
      await database.close();
      throw StateError('PRAGMA quick_check gagal: $status');
    }
    return database;
  }

  Future<void> _cadangkanFileKorup(String path,
      {required String alasan}) async {
    for (final akhiran in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$akhiran');
      if (!file.existsSync()) continue;
      try {
        file.renameSync(
            '$path$akhiran.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {
        // Rename gagal (mis. file terkunci proses lain) -- coba hapus
        // langsung spy percobaan buka berikutnya minimal tak nyangkut di
        // file yg sama; kalau ini pun gagal, itu di luar kendali kita.
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
    if (kDebugMode) {
      debugPrint(
          'CoreDb: $path korup ($alasan) -- dicadangkan & dibuat ulang.');
    }
  }

  Future<void> _konfigurasiDb(Database db) async {
    // Kedua PRAGMA ini mengembalikan result-set. Driver SQLite Android
    // menolak pemanggilan lewat `execute()` (walau driver FFI Windows
    // menerimanya) dengan pesan "Queries can be performed using ...
    // query or rawQuery methods only". Gunakan rawQuery agar konfigurasi
    // bekerja konsisten di Android maupun desktop.
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  /// Migrasi skema -- PERTAMA KALI sejak versi 1 dirilis (semua instalasi
  /// yang sudah ada di lapangan hanya punya `onCreate`, tak pernah lewat
  /// `onUpgrade` sebelumnya). Gap-closure "Jenis Item" (Produk vs Bahan Baku)
  /// nambah kolom `jenis_item` ke `produk_cache`. Fase 2 "Produk Ekstra"
  /// nambah kolom `ekstra_pilihan` (JSON array id produk EKSTRA, lihat
  /// [produkCacheResolveByIds]). Gap-closure "Foto Produk" nambah kolom
  /// `foto_urls` (JSON array URL foto, dipakai carousel kartu Kasir).
  /// `ALTER TABLE` dibungkus try/catch murni defensif thd kemungkinan state
  /// upgrade parsial (mis. proses sempat terhenti di tengah migrasi
  /// sebelumnya, kolom sudah terlanjur ada) -- padanan cara migrasi
  /// `local-db.js` versi Electron.
  Future<void> _upgradeSkema(Database db, int versiLama, int versiBaru) async {
    if (versiLama < 2) {
      try {
        await db.execute('ALTER TABLE produk_cache ADD COLUMN jenis_item TEXT');
      } catch (_) {
        // Kolom kemungkinan sudah ada -- aman diabaikan, bukan error fatal.
      }
    }
    if (versiLama < 3) {
      try {
        await db
            .execute('ALTER TABLE produk_cache ADD COLUMN ekstra_pilihan TEXT');
      } catch (_) {
        // Kolom kemungkinan sudah ada -- aman diabaikan, bukan error fatal.
      }
    }
    if (versiLama < 4) {
      // P7 varian Inventory & Sales: outbox TERPISAH dari transaksi_pending --
      // flush POS existing mengirim SEMUA baris pending ke aksi 'bayar', jadi
      // perintah si_* (kwitansi/biaya) tidak boleh menumpang tabel itu.
      try {
        await db.execute(_ddlOutboxIs);
      } catch (_) {
        // Tabel kemungkinan sudah ada (upgrade parsial) -- aman diabaikan.
      }
    }
    if (versiLama < 5) {
      // Gap-closure "Foto Produk" -- kolom `foto_urls` (JSON array URL, urut
      // lama->baru) dipakai kartu Kasir utk carousel otomatis tiap 3 detik
      // bila >1 foto (lihat Produk.fotoUrls di apps/ebisnis/lib/models.dart).
      try {
        await db.execute('ALTER TABLE produk_cache ADD COLUMN foto_urls TEXT');
      } catch (_) {
        // Kolom kemungkinan sudah ada -- aman diabaikan, bukan error fatal.
      }
    }
  }

  static const _ddlOutboxIs = '''
      CREATE TABLE outbox_is (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        aksi TEXT NOT NULL,
        kode_unik TEXT UNIQUE,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        pesan_error TEXT,
        percobaan INTEGER DEFAULT 0,
        dibuat_pada TEXT NOT NULL
      )
    ''';

  Future<void> _buatSkema(Database db, int versi) async {
    await db.execute('''
      CREATE TABLE produk_cache (
        id INTEGER PRIMARY KEY,
        kode TEXT,
        barcode TEXT,
        nama TEXT,
        harga_jual REAL,
        stok INTEGER,
        kategori_id INTEGER,
        kategori_nama TEXT,
        gambar_url TEXT,
        aktif INTEGER DEFAULT 1,
        jenis_item TEXT,
        ekstra_pilihan TEXT,
        foto_urls TEXT
      )
    ''');
    await db
        .execute('CREATE INDEX idx_produk_cache_kode ON produk_cache(kode)');
    await db.execute(
        'CREATE INDEX idx_produk_cache_barcode ON produk_cache(barcode)');

    await db.execute('''
      CREATE TABLE anggota_cache (
        id INTEGER PRIMARY KEY,
        kode TEXT,
        nama TEXT,
        kode_identitas TEXT,
        hp TEXT,
        jenis_nama TEXT,
        wajib_pin INTEGER DEFAULT 0,
        foto_url TEXT
      )
    ''');
    await db
        .execute('CREATE INDEX idx_anggota_cache_nama ON anggota_cache(nama)');

    await db.execute('''
      CREATE TABLE transaksi_pending (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kode_unik TEXT UNIQUE,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        pesan_error TEXT,
        dibuat_pada TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cache_referensi (
        kunci TEXT PRIMARY KEY,
        nilai_json TEXT NOT NULL,
        diperbarui_pada TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE error_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        waktu TEXT NOT NULL,
        sumber TEXT,
        tingkat TEXT,
        pesan TEXT,
        detail TEXT,
        disinkronkan INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sesi_kas_lokal (
        kode TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        modal_awal REAL,
        dibuka_pada TEXT,
        ditutup_pada TEXT,
        disinkronkan INTEGER DEFAULT 0
      )
    ''');

    await db.execute(_ddlOutboxIs);
  }

  // ============================== OUTBOX INVENTORY & SALES (P7) ==============================
  // Outbox TYPED utk perintah idempoten varian IS (si_collection_create,
  // si_expense_create, ...) -- tiap baris menyimpan NAMA AKSI + body JSON;
  // flush mengirim ke aksi aslinya (bukan 'bayar'), server aman dari duplikat
  // krn semua perintah ber-kode_unik idempoten.

  Future<int> outboxIsTambah(
      String aksi, String kodeUnik, String payloadJson) async {
    final database = await db;
    return database.insert('outbox_is', {
      'aksi': aksi,
      'kode_unik': kodeUnik,
      'payload_json': payloadJson,
      'status': 'PENDING',
      'dibuat_pada': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> outboxIsPending() async {
    final database = await db;
    return database.query('outbox_is',
        where: "status = 'PENDING'", orderBy: 'id ASC');
  }

  Future<void> outboxIsTandaiSukses(int id) async {
    final database = await db;
    await database.update(
        'outbox_is', {'status': 'SYNCED', 'pesan_error': null},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Penolakan bisnis server (bukan offline): status GAGAL permanen + pesan --
  /// tidak ikut retry berikutnya, tetap terlihat utk ditindak manual.
  Future<void> outboxIsTandaiGagal(int id, String pesan) async {
    final database = await db;
    await database.update(
        'outbox_is', {'status': 'GAGAL', 'pesan_error': pesan},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> outboxIsCatatPercobaan(int id, String pesan) async {
    final database = await db;
    await database.rawUpdate(
        'UPDATE outbox_is SET percobaan = COALESCE(percobaan,0) + 1,'
        ' pesan_error = ? WHERE id = ?',
        [pesan, id]);
  }

  Future<int> jumlahOutboxIsPending() async {
    final database = await db;
    final hasil = await database.rawQuery(
        "SELECT COUNT(*) AS n FROM outbox_is WHERE status = 'PENDING'");
    return (hasil.first['n'] as int?) ?? 0;
  }

  // ============================== PRODUK CACHE ==============================

  Future<void> replaceProdukCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('produk_cache');
      final batch = txn.batch();
      for (final b in baris) {
        batch.insert('produk_cache', b,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Dipakai semua konteks JUAL/penjualan (Kasir, Pesanan, picker pencarian
  /// produk) -- gap-closure "Jenis Item" mengecualikan baris `jenis_item IN
  /// ('BAHAN','EKSTRA')` (bahan baku hanya via resep, ekstra hanya via picker
  /// "Pilih Ekstra" produk dasar -- keduanya bukan baris yang bisa dijual
  /// mandiri). PENTING: `jenis_item != 'BAHAN'` SENDIRIAN tidak cukup krn
  /// SQLite `!=` tidak match NULL -- semua produk yang dibuat SEBELUM fitur
  /// ini (jenis_item masih NULL) akan ikut hilang diam-diam kalau klausanya
  /// bukan `(jenis_item IS NULL OR jenis_item NOT IN (...))`. Baris EKSTRA
  /// tetap ADA di tabel ini (lihat [produkCacheResolveByIds]) -- yang
  /// di-exclude cuma query ini, bukan sinkronisasinya.
  Future<List<Map<String, Object?>>> produkCache() async {
    final database = await db;
    return database.query(
      'produk_cache',
      where:
          "aktif = 1 AND (jenis_item IS NULL OR jenis_item NOT IN ('BAHAN','EKSTRA'))",
      orderBy: 'nama ASC',
    );
  }

  /// Resolusi id produk EKSTRA (dari [Produk.ekstraPilihan] produk dasar)
  /// jadi baris nama/harga siap tampil -- dipakai picker "Pilih Ekstra" Kasir
  /// SUPAYA TIDAK perlu round-trip server tiap kali produk dgn ekstra
  /// disentuh. SENGAJA TANPA filter `jenis_item` (beda dgn [produkCache]) --
  /// baris EKSTRA memang tetap disimpan lengkap di tabel ini oleh
  /// `replaceProdukCache`, hanya disembunyikan dari grid/pencarian umum.
  /// `ids` kosong -> query kosong (bukan error), aman dipanggil dgn
  /// `p.ekstraPilihan` produk yang belum/tak punya ekstra apa pun.
  Future<List<Map<String, Object?>>> produkCacheResolveByIds(
      List<int> ids) async {
    if (ids.isEmpty) return [];
    final database = await db;
    final placeholder = List.filled(ids.length, '?').join(',');
    return database.query(
      'produk_cache',
      where: 'id IN ($placeholder)',
      whereArgs: ids,
      orderBy: 'nama ASC',
    );
  }

  Future<int> jumlahProdukCache() async {
    final database = await db;
    final hasil =
        await database.rawQuery('SELECT COUNT(*) AS n FROM produk_cache');
    return (hasil.first['n'] as int?) ?? 0;
  }

  // ============================== ANGGOTA CACHE ==============================

  Future<void> upsertAnggotaCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    final batch = database.batch();
    for (final b in baris) {
      batch.insert('anggota_cache', b,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> cariAnggotaCache(String kataKunci,
      {int limit = 30}) async {
    final database = await db;
    if (kataKunci.trim().isEmpty) {
      return database.query('anggota_cache', orderBy: 'nama ASC', limit: limit);
    }
    final kw = '%$kataKunci%';
    return database.query(
      'anggota_cache',
      where: 'nama LIKE ? OR kode LIKE ? OR kode_identitas LIKE ?',
      whereArgs: [kw, kw, kw],
      orderBy: 'nama ASC',
      limit: limit,
    );
  }

  // ============================== TRANSAKSI PENDING ==============================

  Future<int> simpanTransaksiPending(
      String kodeUnik, String payloadJson) async {
    final database = await db;
    return database.insert('transaksi_pending', {
      'kode_unik': kodeUnik,
      'payload_json': payloadJson,
      'status': 'PENDING',
      'dibuat_pada': DateTime.now().toIso8601String(),
    });
  }

  Future<void> tandaiTransaksiSinkron(String kodeUnik) async {
    final database = await db;
    await database.update(
        'transaksi_pending', {'status': 'SYNCED', 'pesan_error': null},
        where: 'kode_unik = ?', whereArgs: [kodeUnik]);
  }

  Future<void> tandaiTransaksiGagal(String kodeUnik, String pesanError) async {
    final database = await db;
    await database.update('transaksi_pending', {'pesan_error': pesanError},
        where: 'kode_unik = ?', whereArgs: [kodeUnik]);
  }

  /// Dipakai saat server MENOLAK transaksi krn alasan bisnis (bukan jaringan
  /// offline, mis. saldo member kurang) -- baris pending dihapus supaya
  /// "Sinkronkan Sekarang" tidak terus mengirim ulang transaksi yang memang
  /// tidak pernah akan diterima server.
  Future<void> hapusTransaksiPending(String kodeUnik) async {
    final database = await db;
    await database.delete('transaksi_pending',
        where: 'kode_unik = ?', whereArgs: [kodeUnik]);
  }

  Future<List<Map<String, Object?>>> transaksiPendingBelumSinkron() async {
    final database = await db;
    return database.query('transaksi_pending',
        where: "status = 'PENDING'", orderBy: 'id ASC');
  }

  Future<int> jumlahTransaksiPending() async {
    Future<int> baca() async {
      final database = await db;
      final hasil = await database.query('transaksi_pending',
          columns: const ['COUNT(*) AS n'],
          where: 'status = ?',
          whereArgs: const ['PENDING']);
      return (hasil.first['n'] as num?)?.toInt() ?? 0;
    }

    try {
      return await baca();
    } catch (e) {
      // sqlite_error 21/API misuse biasanya berarti handle FFI lama sudah
      // tidak valid (mis. aplikasi sebelumnya ditutup paksa), bukan data
      // transaksi rusak. Buka ulang SATU kali tanpa menghapus/mencadangkan DB.
      final pesan = e.toString().toLowerCase();
      if (!pesan.contains('code 21') &&
          !pesan.contains('sqlite_error 21') &&
          !pesan.contains('api misuse')) {
        rethrow;
      }
      final lama = _db;
      _db = null;
      try {
        if (lama != null && lama.isOpen) await lama.close();
      } catch (_) {}
      return baca();
    }
  }

  // ============================== CACHE REFERENSI (generik) ==============================

  Future<void> simpanCacheReferensi(String kunci, String nilaiJson) async {
    final database = await db;
    await database.insert(
      'cache_referensi',
      {
        'kunci': kunci,
        'nilai_json': nilaiJson,
        'diperbarui_pada': DateTime.now().toIso8601String()
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> ambilCacheReferensi(String kunci) async {
    final database = await db;
    final hasil = await database
        .query('cache_referensi', where: 'kunci = ?', whereArgs: [kunci]);
    if (hasil.isEmpty) return null;
    return hasil.first['nilai_json'] as String?;
  }

  // ============================== ERROR LOG ==============================

  Future<void> catatErrorLog({
    required String sumber,
    required String tingkat,
    required String pesan,
    String? detail,
  }) async {
    final now = DateTime.now();
    final key = '$sumber|$tingkat|$pesan';
    final lastAt = _lastErrorLogAt;
    if (_lastErrorLogKey == key &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastErrorLogKey = key;
    _lastErrorLogAt = now;

    _errorLogTail =
        _errorLogTail.catchError((_) {}).then((_) => _catatErrorLogLangsung(
              waktu: now,
              sumber: sumber,
              tingkat: tingkat,
              pesan: pesan,
              detail: detail,
            ));
    return _errorLogTail;
  }

  Future<void> _catatErrorLogLangsung({
    required DateTime waktu,
    required String sumber,
    required String tingkat,
    required String pesan,
    String? detail,
  }) async {
    try {
      final database = await db;
      await database.insert('error_log', {
        'waktu': waktu.toIso8601String(),
        'sumber': sumber,
        'tingkat': tingkat,
        'pesan': pesan,
        'detail': detail,
        'disinkronkan': 0,
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Gagal mencatat error_log lokal: $e');
      }
    }
  }

  Future<List<Map<String, Object?>>> listErrorLog(
      {String? tingkat,
      String? sumber,
      String? kataKunci,
      int limit = 100,
      int offset = 0}) async {
    final database = await db;
    final klausa = <String>[];
    final args = <Object?>[];
    if (tingkat != null && tingkat.isNotEmpty) {
      klausa.add('tingkat = ?');
      args.add(tingkat);
    }
    if (sumber != null && sumber.isNotEmpty) {
      klausa.add('sumber = ?');
      args.add(sumber);
    }
    if (kataKunci != null && kataKunci.isNotEmpty) {
      klausa.add('pesan LIKE ?');
      args.add('%$kataKunci%');
    }
    return database.query(
      'error_log',
      where: klausa.isEmpty ? null : klausa.join(' AND '),
      whereArgs: klausa.isEmpty ? null : args,
      orderBy: 'waktu DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> jumlahErrorLog({String? tingkat}) async {
    final database = await db;
    final hasil = tingkat == null
        ? await database.rawQuery('SELECT COUNT(*) AS n FROM error_log')
        : await database.rawQuery(
            'SELECT COUNT(*) AS n FROM error_log WHERE tingkat = ?', [tingkat]);
    return (hasil.first['n'] as int?) ?? 0;
  }

  Future<void> hapusErrorLog(int id) async {
    final database = await db;
    await database.delete('error_log', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> bersihkanErrorLog() async {
    final database = await db;
    await database.delete('error_log');
  }

  // ============================== CACHE REFERENSI (generik) ==============================

  Future<List<Map<String, Object?>>> listCacheReferensi() async {
    final database = await db;
    return database.query('cache_referensi', orderBy: 'kunci ASC');
  }

  // ============================== TRANSAKSI PENDING (lanjutan) ==============================

  Future<({List<Map<String, Object?>> data, int total})> listTransaksiPending(
      {int limit = 20, int offset = 0, String? status}) async {
    final database = await db;
    final where = status == null ? null : 'status = ?';
    final whereArgs = status == null ? null : [status];
    final data = await database.query('transaksi_pending',
        where: where,
        whereArgs: whereArgs,
        orderBy: 'id DESC',
        limit: limit,
        offset: offset);
    final hasilTotal = status == null
        ? await database.rawQuery('SELECT COUNT(*) AS n FROM transaksi_pending')
        : await database.rawQuery(
            'SELECT COUNT(*) AS n FROM transaksi_pending WHERE status = ?',
            [status]);
    final total = (hasilTotal.first['n'] as int?) ?? 0;
    return (data: data, total: total);
  }

  // ============================== SESI KAS LOKAL ==============================

  Future<Map<String, Object?>?> sesiKasAktif() async {
    final database = await db;
    final hasil = await database.query('sesi_kas_lokal',
        where: "status = 'BUKA'", orderBy: 'dibuka_pada DESC', limit: 1);
    return hasil.isEmpty ? null : hasil.first;
  }

  /// [disinkronkan] = false (default) dipakai alur optimistic-open (tulis lokal DULU sebelum
  /// tahu hasil panggilan server, lihat `_bukaKas` di kasir_screen.dart) -- baris ditandai
  /// PENDING sampai server benar-benar mengonfirmasi. [disinkronkan] = true dipakai
  /// `_periksaSesiKas` saat menyalin status yg SUDAH terkonfirmasi server (`sesi_kas_status`),
  /// jadi tak perlu di-retry lagi. Lihat [sesiKasLokalBelumSinkron]/[tandaiSesiKasTersinkron]
  /// utk mekanisme retry-nya -- gap-closure bug "topbar Kas Terbuka vs checkout ditolak server"
  /// (kolom `disinkronkan` sudah ada di skema sejak awal tapi sebelumnya tidak pernah dipakai).
  Future<void> bukaSesiKasLokal(String kode, double modalAwal,
      {bool disinkronkan = false}) async {
    final database = await db;
    await database.insert(
      'sesi_kas_lokal',
      {
        'kode': kode,
        'status': 'BUKA',
        'modal_awal': modalAwal,
        'dibuka_pada': DateTime.now().toIso8601String(),
        'disinkronkan': disinkronkan ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sesiKasVersi.value++;
  }

  /// Baris sesi kas BUKA yang optimistic-write lokalnya belum terkonfirmasi server -- kandidat
  /// retry (lihat [bukaSesiKasLokal]).
  Future<List<Map<String, Object?>>> sesiKasLokalBelumSinkron() async {
    final database = await db;
    return database.query('sesi_kas_lokal',
        where: "status = 'BUKA' AND disinkronkan = 0");
  }

  Future<void> tandaiSesiKasTersinkron(String kode) async {
    final database = await db;
    await database.update('sesi_kas_lokal', {'disinkronkan': 1},
        where: 'kode = ?', whereArgs: [kode]);
  }

  Future<void> tutupSesiKasLokal(String kode) async {
    final database = await db;
    await database.update(
      'sesi_kas_lokal',
      {'status': 'TUTUP', 'ditutup_pada': DateTime.now().toIso8601String()},
      where: 'kode = ?',
      whereArgs: [kode],
    );
    sesiKasVersi.value++;
  }

  Future<void> tutupSemuaSesiKasLokal() async {
    final database = await db;
    final jumlah = await database.update(
      'sesi_kas_lokal',
      {'status': 'TUTUP', 'ditutup_pada': DateTime.now().toIso8601String()},
      where: "status = 'BUKA'",
    );
    if (jumlah > 0) sesiKasVersi.value++;
  }
}
