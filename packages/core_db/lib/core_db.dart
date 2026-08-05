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
    if (currentDb != null) return currentDb;

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
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
      final dir = await getApplicationSupportDirectory();
      path = p.join(dir.path, 'ebisnis.db');
    } else {
      factory = databaseFactory;
      path = p.join(await getDatabasesPath(), 'ebisnis.db');
    }
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: _konfigurasiDb,
        onCreate: _buatSkema,
      ),
    );
  }

  Future<void> _konfigurasiDb(Database db) async {
    await db.execute('PRAGMA busy_timeout = 5000');
    await db.execute('PRAGMA journal_mode = WAL');
  }

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
        aktif INTEGER DEFAULT 1
      )
    ''');
    await db.execute('CREATE INDEX idx_produk_cache_kode ON produk_cache(kode)');
    await db.execute('CREATE INDEX idx_produk_cache_barcode ON produk_cache(barcode)');

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
    await db.execute('CREATE INDEX idx_anggota_cache_nama ON anggota_cache(nama)');

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
  }

  // ============================== PRODUK CACHE ==============================

  Future<void> replaceProdukCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('produk_cache');
      final batch = txn.batch();
      for (final b in baris) {
        batch.insert('produk_cache', b, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, Object?>>> produkCache() async {
    final database = await db;
    return database.query('produk_cache', where: 'aktif = 1', orderBy: 'nama ASC');
  }

  Future<int> jumlahProdukCache() async {
    final database = await db;
    final hasil = await database.rawQuery('SELECT COUNT(*) AS n FROM produk_cache');
    return (hasil.first['n'] as int?) ?? 0;
  }

  // ============================== ANGGOTA CACHE ==============================

  Future<void> upsertAnggotaCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    final batch = database.batch();
    for (final b in baris) {
      batch.insert('anggota_cache', b, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> cariAnggotaCache(String kataKunci, {int limit = 30}) async {
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

  Future<int> simpanTransaksiPending(String kodeUnik, String payloadJson) async {
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
    await database.update('transaksi_pending', {'status': 'SYNCED', 'pesan_error': null},
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
    await database.delete('transaksi_pending', where: 'kode_unik = ?', whereArgs: [kodeUnik]);
  }

  Future<List<Map<String, Object?>>> transaksiPendingBelumSinkron() async {
    final database = await db;
    return database.query('transaksi_pending', where: "status = 'PENDING'", orderBy: 'id ASC');
  }

  Future<int> jumlahTransaksiPending() async {
    final database = await db;
    final hasil = await database
        .rawQuery("SELECT COUNT(*) AS n FROM transaksi_pending WHERE status = 'PENDING'");
    return (hasil.first['n'] as int?) ?? 0;
  }

  // ============================== CACHE REFERENSI (generik) ==============================

  Future<void> simpanCacheReferensi(String kunci, String nilaiJson) async {
    final database = await db;
    await database.insert(
      'cache_referensi',
      {'kunci': kunci, 'nilai_json': nilaiJson, 'diperbarui_pada': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> ambilCacheReferensi(String kunci) async {
    final database = await db;
    final hasil = await database.query('cache_referensi', where: 'kunci = ?', whereArgs: [kunci]);
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

    _errorLogTail = _errorLogTail
        .catchError((_) {})
        .then((_) => _catatErrorLogLangsung(
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

  Future<List<Map<String, Object?>>> listErrorLog({String? tingkat, String? sumber, String? kataKunci, int limit = 100, int offset = 0}) async {
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
        : await database.rawQuery('SELECT COUNT(*) AS n FROM error_log WHERE tingkat = ?', [tingkat]);
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

  Future<({List<Map<String, Object?>> data, int total})> listTransaksiPending({int limit = 20, int offset = 0, String? status}) async {
    final database = await db;
    final where = status == null ? null : 'status = ?';
    final whereArgs = status == null ? null : [status];
    final data = await database.query('transaksi_pending', where: where, whereArgs: whereArgs, orderBy: 'id DESC', limit: limit, offset: offset);
    final hasilTotal = status == null
        ? await database.rawQuery('SELECT COUNT(*) AS n FROM transaksi_pending')
        : await database.rawQuery('SELECT COUNT(*) AS n FROM transaksi_pending WHERE status = ?', [status]);
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

  Future<void> bukaSesiKasLokal(String kode, double modalAwal) async {
    final database = await db;
    await database.insert(
      'sesi_kas_lokal',
      {
        'kode': kode,
        'status': 'BUKA',
        'modal_awal': modalAwal,
        'dibuka_pada': DateTime.now().toIso8601String(),
        'disinkronkan': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sesiKasVersi.value++;
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
