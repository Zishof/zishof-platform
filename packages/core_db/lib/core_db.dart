import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database offline-first eBisnis -- satu file SQLite per varian instalasi
/// (`ebisnis_<namespace>.db`),
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

  static String _storageNamespace = 'ebisnis';

  /// Wajib dipanggil saat bootstrap, sebelum akses DB pertama. Meskipun
  /// path_provider biasanya sudah memisahkan folder per ProductName/package,
  /// nama file dan backup juga diberi namespace sebagai lapisan pengaman saat
  /// beberapa varian terpasang pada satu mesin.
  static void configureStorage(String namespace) {
    final normalized =
        namespace.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    if (normalized.isEmpty) {
      throw ArgumentError.value(namespace, 'namespace', 'Tidak boleh kosong');
    }
    if (instance._db != null || instance._openingDb != null) {
      if (_storageNamespace != normalized) {
        throw StateError(
            'Namespace CoreDb tidak boleh diubah setelah DB dibuka.');
      }
      return;
    }
    _storageNamespace = normalized;
  }

  static String get storageNamespace => _storageNamespace;

  /// Naik setiap status sesi kas lokal berubah. UI seperti topbar memakai ini
  /// untuk refresh chip "Kas Terbuka/Tertutup" tanpa menunggu rebuild layar.
  final ValueNotifier<int> sesiKasVersi = ValueNotifier<int>(0);

  Database? _db;
  String? _pathDb;
  Future<Database>? _openingDb;
  Future<void> _errorLogTail = Future.value();
  String? _lastErrorLogKey;
  DateTime? _lastErrorLogAt;

  static const MethodChannel _backupChannel =
      MethodChannel('id.zishof.ebisnis/persistent_transaction_backup');
  static String get _namaFileBackup =>
      'transaksi-pos-${_storageNamespace}-backup.jsonl';

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
      path = p.join(dir.path, 'ebisnis_${_storageNamespace}.db');
      _pathDb = path;
    } else {
      factory = databaseFactory;
      path =
          p.join(await getDatabasesPath(), 'ebisnis_${_storageNamespace}.db');
      _pathDb = path;
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
        version: 19,
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
    await _pulihkanArsipTransaksiPersisten(database);
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

  /// Menulis snapshot append-only di lokasi kedua di luar database utama.
  /// Pada Android 10+ native side memakai MediaStore/Downloads/eBisnis,
  /// sehingga file tetap ada setelah aplikasi diperbarui maupun dihapus.
  /// Pada desktop file berada di Documents/eBisnis/<varian>/Backup. Snapshot tidak
  /// memuat token/sandi; isinya hanya payload transaksi operasional yang
  /// memang diperlukan untuk membangun ulang arsip lokal.
  Future<void> _cadangkanTransaksiPersisten(
      Map<String, Object?> snapshot) async {
    try {
      final line = jsonEncode(<String, Object?>{
        'versi': 1,
        'dicatat_pada': DateTime.now().toIso8601String(),
        ...snapshot,
      });
      if (!kIsWeb && Platform.isAndroid) {
        await _backupChannel.invokeMethod<void>('append', <String, Object?>{
          'fileName': _namaFileBackup,
          'line': line,
        });
        return;
      }
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final documents = await getApplicationDocumentsDirectory();
        final directory = Directory(
            p.join(documents.path, 'eBisnis', _storageNamespace, 'Backup'));
        await directory.create(recursive: true);
        await File(p.join(directory.path, _namaFileBackup))
            .writeAsString('$line\n', mode: FileMode.append, flush: true);
      }
    } catch (e) {
      // Salinan utama SQLite sudah committed sebelum metode ini dipanggil.
      // Gangguan media sekunder tidak boleh membatalkan penjualan kasir.
      if (kDebugMode) debugPrint('Backup transaksi sekunder gagal: $e');
    }
  }

  Future<String?> _bacaBackupTransaksiPersisten() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        return await _backupChannel.invokeMethod<String>(
            'read', <String, Object?>{'fileName': _namaFileBackup});
      }
      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        final documents = await getApplicationDocumentsDirectory();
        final file = File(p.join(documents.path, 'eBisnis', _storageNamespace,
            'Backup', _namaFileBackup));
        return await file.exists() ? await file.readAsString() : null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Backup transaksi sekunder gagal dibaca: $e');
    }
    return null;
  }

  /// Mengembalikan snapshot terakhir setiap kode ke SQLite. INSERT OR IGNORE
  /// sengaja dipakai agar data yang masih ada di DB utama selalu menang.
  Future<void> _pulihkanArsipTransaksiPersisten(Database database) async {
    final isi = await _bacaBackupTransaksiPersisten();
    if (isi == null || isi.trim().isEmpty) return;
    final terbaru = <String, Map<String, Object?>>{};
    for (final line in const LineSplitter().convert(isi)) {
      try {
        final parsed = jsonDecode(line);
        if (parsed is! Map) continue;
        final row = Map<String, Object?>.from(parsed);
        final kode = '${row['kode_unik'] ?? ''}'.trim();
        // Baris terakhir boleh berupa tombstone. Tanpa tombstone, transaksi
        // yang sengaja dibuang dari SQLite akan hidup kembali ketika database
        // dipulihkan dari backup append-only.
        if (kode.isNotEmpty) terbaru[kode] = row;
      } catch (_) {
        // Satu baris terputus (mis. perangkat mati saat append) tidak merusak
        // snapshot-snapshot lengkap lain di file append-only.
      }
    }
    if (terbaru.isEmpty) return;
    final batch = database.batch();
    for (final row in terbaru.values) {
      if (row['dihapus'] == true) continue;
      if (row['payload_json'] == null) continue;
      batch.insert(
        'transaksi_pending',
        <String, Object?>{
          'kode_unik': row['kode_unik'],
          'payload_json': row['payload_json'],
          'status': row['status'] ?? 'PENDING',
          'pesan_error': row['pesan_error'],
          'dibuat_pada': row['dibuat_pada'] ?? DateTime.now().toIso8601String(),
          'akun_kunci': row['akun_kunci'],
          'toko_id': row['toko_id'],
          'id_perangkat': row['id_perangkat'],
          'percobaan': row['percobaan'] ?? 0,
          'terakhir_dicoba': row['terakhir_dicoba'],
          'disinkronkan_pada': row['disinkronkan_pada'],
          'diperbarui_pada': row['diperbarui_pada'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> _cadangkanBarisTransaksi(String kodeUnik) async {
    final database = await db;
    final rows = await database.query('transaksi_pending',
        where: 'kode_unik = ?', whereArgs: <Object?>[kodeUnik], limit: 1);
    if (rows.isNotEmpty) {
      await _cadangkanTransaksiPersisten(rows.first);
    }
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
    if (versiLama < 6) {
      try {
        await db.execute(_ddlTokoAktifAkun);
      } catch (_) {
        // Tabel kemungkinan sudah ada akibat upgrade parsial.
      }
      for (final kolom in const ['telp', 'email']) {
        try {
          await db.execute('ALTER TABLE anggota_cache ADD COLUMN $kolom TEXT');
        } catch (_) {
          // Kolom kemungkinan sudah ada akibat upgrade parsial.
        }
      }
    }
    if (versiLama < 19) {
      await _buatIndeksBarisCacheReferensi(db);
    }
    if (versiLama < 18) {
      try {
        await db.execute('ALTER TABLE produk_cache ADD COLUMN kemasan TEXT');
      } catch (_) {
        // Kolom kemungkinan sudah ada -- aman diabaikan.
      }
    }
    if (versiLama < 7) {
      // Kepemilikan outbox harus eksplisit. Tanpa ini, transaksi offline Udin
      // dapat terkirim memakai token Susi bila akun berganti sebelum retry.
      for (final definisi in const [
        'akun_kunci TEXT',
        'toko_id INTEGER',
        'id_perangkat TEXT',
        'percobaan INTEGER NOT NULL DEFAULT 0',
        'terakhir_dicoba TEXT',
      ]) {
        try {
          await db
              .execute('ALTER TABLE transaksi_pending ADD COLUMN $definisi');
        } catch (_) {
          // Upgrade parsial: kolom yang sudah ada aman dilewati.
        }
      }
      try {
        await db.execute(
            'CREATE INDEX idx_transaksi_pending_pemilik ON transaksi_pending(status, akun_kunci, toko_id)');
      } catch (_) {
        // Index kemungkinan sudah dibuat pada percobaan upgrade sebelumnya.
      }
    }
    if (versiLama < 8) {
      for (final definisi in const [
        'disinkronkan_pada TEXT',
        'diperbarui_pada TEXT',
      ]) {
        try {
          await db
              .execute('ALTER TABLE transaksi_pending ADD COLUMN $definisi');
        } catch (_) {
          // Upgrade parsial: kolom yang sudah ada aman dilewati.
        }
      }
      try {
        await db.execute(
            'CREATE INDEX idx_transaksi_arsip_waktu ON transaksi_pending(dibuat_pada DESC)');
      } catch (_) {
        // Index kemungkinan sudah dibuat pada percobaan upgrade sebelumnya.
      }
    }
    if (versiLama < 9) {
      try {
        await db.execute(
            'CREATE INDEX idx_transaksi_toko_waktu_status ON transaksi_pending(toko_id, dibuat_pada DESC, status)');
      } catch (_) {
        // Index kemungkinan sudah dibuat pada percobaan upgrade sebelumnya.
      }
    }
    if (versiLama < 10) {
      // Offline-first CRUD MASTER (anggota/produk/jenis produk/dst) -- lihat
      // komentar _ddlOutboxMaster utk alasan tabel terpisah & semantik kunci.
      try {
        await db.execute(_ddlOutboxMaster);
      } catch (_) {
        // Tabel kemungkinan sudah ada (upgrade parsial) -- aman diabaikan.
      }
    }
    if (versiLama < 11) {
      // Pemetaan id sementara -> id server utk baris master yang dibuat offline.
      try {
        await db.execute(_ddlIdSementara);
      } catch (_) {
        // Tabel kemungkinan sudah ada (upgrade parsial) -- aman diabaikan.
      }
    }
    if (versiLama < 12) {
      // Angka OTORITATIF dari server disimpan apa adanya supaya struk dapat
      // dikoreksi setelah sinkron (lihat simpanHasilServerTransaksi).
      try {
        await db.execute(
            'ALTER TABLE transaksi_pending ADD COLUMN hasil_server_json TEXT');
      } catch (_) {
        // Kolom kemungkinan sudah ada (upgrade parsial) -- aman dilewati.
      }
    }
    if (versiLama < 13) {
      // Pengikatan tenant (P6/P7). Basis data lama TIDAK ditandai tenant apa pun
      // -- tabelnya sengaja dibiarkan KOSONG, bukan diisi tebakan. Menebak bahwa
      // data lama milik tenant yang pertama kali login akan mengadopsi diam-diam
      // data yang mungkin bukan miliknya; dokumen master 15.4 melarangnya.
      try {
        await db.execute(_ddlPengikatanTenant);
      } catch (_) {
        // Tabel kemungkinan sudah ada (upgrade parsial) -- aman dilewati.
      }
    }
    if (versiLama < 14) {
      // Kebijakan biometrik ikut snapshot member agar picker offline tidak
      // menurunkan aturan keamanan menjadi false hanya karena jaringan putus.
      for (final kolom in const [
        'wajib_biometric_wajah',
        'wajib_biometric_fingerprint',
      ]) {
        try {
          await db.execute(
              'ALTER TABLE anggota_cache ADD COLUMN $kolom INTEGER DEFAULT 0');
        } catch (_) {
          // Kolom mungkin sudah dibuat oleh upgrade parsial.
        }
      }
    }
    if (versiLama < 15) {
      // Izin stok minus per-produk harus ikut katalog lokal. Tanpa kolom ini,
      // aplikasi offline menganggap semua produk stok nol selalu terblokir.
      try {
        await db.execute(
            'ALTER TABLE produk_cache ADD COLUMN izinkan_jual_minus_stok INTEGER DEFAULT 0');
      } catch (_) {
        // Kolom mungkin sudah dibuat oleh upgrade parsial.
      }
    }
    if (versiLama < 16) {
      // Hanya STATUS keberadaan PIN yang dicache. PIN/hash/salt tidak pernah
      // disalin ke perangkat; metadata ini cukup untuk UI supervisor tetap
      // informatif saat local-first/offline.
      try {
        await db.execute(
            'ALTER TABLE anggota_cache ADD COLUMN pin_sudah_diatur INTEGER DEFAULT 0');
      } catch (_) {
        // Kolom mungkin sudah dibuat oleh upgrade parsial.
      }
    }
    if (versiLama < 17) {
      // Limit tipe member ikut snapshot local-first. Checkout yang mempunyai
      // limit harus menunggu keputusan server agar pengajuan supervisor tidak
      // baru diketahui setelah kasir menutup transaksi.
      for (final kolom in const [
        'maksimal_transaksi_harian REAL DEFAULT 0',
        'maksimal_transaksi_mingguan REAL DEFAULT 0',
        'maksimal_transaksi_bulanan REAL DEFAULT 0',
      ]) {
        try {
          await db.execute('ALTER TABLE anggota_cache ADD COLUMN $kolom');
        } catch (_) {
          // Kolom mungkin sudah dibuat oleh upgrade parsial.
        }
      }
    }
  }

  /// Pemetaan id sementara (negatif, dibuat klien saat offline) -> id server.
  ///
  /// Kuncinya HANYA nilai id lokalnya, tanpa nama entitas: id sementara dibuat dari
  /// pencacah waktu sehingga unik lintas entitas, dan tanpa entitas penukaran nilai di
  /// dalam payload menjadi sederhana -- setiap bilangan negatif yang dikenal ditukar,
  /// apa pun nama kolomnya.
  static const _ddlIdSementara = '''
      CREATE TABLE id_sementara (
        id_lokal INTEGER PRIMARY KEY,
        entitas TEXT,
        id_server INTEGER,
        dibuat_pada TEXT NOT NULL,
        dipetakan_pada TEXT
      )
    ''';

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

  /// Outbox CRUD MASTER offline-first (anggota/produk/jenis produk/dst).
  /// TERPISAH dari `outbox_is` (khusus perintah idempoten ber-kode_unik) dan
  /// `transaksi_pending` (flush-nya mengirim semua baris ke aksi 'bayar').
  /// `kunci` = identitas baris master ("produk:123", "jenis_produk:baru:xyz")
  /// dipakai COALESCE: edit berulang pada baris yang sama saat offline hanya
  /// menyisakan payload TERAKHIR, sehingga replay tidak mengirim draf usang.
  static const _ddlOutboxMaster = '''
      CREATE TABLE outbox_master (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        aksi TEXT NOT NULL,
        kunci TEXT,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        pesan_error TEXT,
        percobaan INTEGER DEFAULT 0,
        dibuat_pada TEXT NOT NULL
      )
    ''';

  static const _ddlTokoAktifAkun = '''
      CREATE TABLE toko_aktif_akun (
        akun_kunci TEXT PRIMARY KEY,
        toko_id INTEGER NOT NULL,
        diperbarui_pada TEXT NOT NULL
      )
    ''';

  /// Penanda tenant yang MEMILIKI data lokal pada perangkat ini.
  ///
  /// Satu perangkat melayani satu tenant (keputusan 2026-08-23), jadi tabel ini
  /// selalu berisi paling banyak satu baris -- dipaksa lewat `CHECK (id = 1)`.
  /// Gunanya bukan memilih tenant, melainkan MENOLAK percampuran: perangkat yang
  /// dialihkan ke tenant lain akan ketahuan di sini sebelum satu baris pun
  /// tertulis atau terkirim atas nama tenant yang keliru.
  static const _ddlPengikatanTenant = '''
      CREATE TABLE pengikatan_tenant (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        tenant_id INTEGER NOT NULL,
        tenant_kode TEXT,
        server_sidik TEXT,
        akun_sidik TEXT,
        terikat_pada TEXT NOT NULL
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
        foto_urls TEXT,
        kemasan TEXT,
        izinkan_jual_minus_stok INTEGER DEFAULT 0
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
        telp TEXT,
        email TEXT,
        jenis_nama TEXT,
        wajib_pin INTEGER DEFAULT 0,
        pin_sudah_diatur INTEGER DEFAULT 0,
        wajib_biometric_wajah INTEGER DEFAULT 0,
        wajib_biometric_fingerprint INTEGER DEFAULT 0,
        maksimal_transaksi_harian REAL DEFAULT 0,
        maksimal_transaksi_mingguan REAL DEFAULT 0,
        maksimal_transaksi_bulanan REAL DEFAULT 0,
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
        dibuat_pada TEXT NOT NULL,
        akun_kunci TEXT,
        toko_id INTEGER,
        id_perangkat TEXT,
        percobaan INTEGER NOT NULL DEFAULT 0,
        terakhir_dicoba TEXT,
        disinkronkan_pada TEXT,
        diperbarui_pada TEXT,
        hasil_server_json TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_transaksi_pending_pemilik ON transaksi_pending(status, akun_kunci, toko_id)');
    await db.execute(
        'CREATE INDEX idx_transaksi_arsip_waktu ON transaksi_pending(dibuat_pada DESC)');
    await db.execute(
        'CREATE INDEX idx_transaksi_toko_waktu_status ON transaksi_pending(toko_id, dibuat_pada DESC, status)');

    await db.execute('''
      CREATE TABLE cache_referensi (
        kunci TEXT PRIMARY KEY,
        nilai_json TEXT NOT NULL,
        diperbarui_pada TEXT NOT NULL
      )
    ''');
    await _buatIndeksBarisCacheReferensi(db);

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
    await db.execute(_ddlTokoAktifAkun);
    await db.execute(_ddlOutboxMaster);
    await db.execute(_ddlIdSementara);
    await db.execute(_ddlPengikatanTenant);
  }

  /// Pilihan toko terakhir per kombinasi server+akun. Penyimpanan ini sengaja
  /// berada di SQLite (bukan preferences global) agar dua akun pada perangkat
  /// yang sama tidak saling menimpa toko aktif.
  Future<int?> tokoAktifAkunBaca(String akunKunci) async {
    final database = await db;
    final rows = await database.query('toko_aktif_akun',
        columns: ['toko_id'],
        where: 'akun_kunci = ?',
        whereArgs: [akunKunci],
        limit: 1);
    if (rows.isEmpty) return null;
    return (rows.first['toko_id'] as num?)?.toInt();
  }

  Future<void> tokoAktifAkunSimpan(String akunKunci, int tokoId) async {
    final database = await db;
    await database.insert(
        'toko_aktif_akun',
        {
          'akun_kunci': akunKunci,
          'toko_id': tokoId,
          'diperbarui_pada': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> tokoAktifAkunHapus(String akunKunci) async {
    final database = await db;
    await database.delete('toko_aktif_akun',
        where: 'akun_kunci = ?', whereArgs: [akunKunci]);
  }

  // ============================== PENGIKATAN TENANT (P6/P7) ==============================
  // Satu perangkat melayani SATU tenant. Tidak ada perpindahan tenant saat
  // aplikasi berjalan -- yang dijaga di sini adalah perangkat yang DIALIHKAN:
  // pegawai pindah cabang, perangkat dipakai ulang, atau salah login. Tanpa
  // penjagaan, antrean milik tenant lama akan terkirim memakai token tenant
  // baru, dan cache lama tampil sebagai data tenant baru.

  /// Keadaan pengikatan perangkat terhadap tenant yang sedang login.
  Future<StatusPengikatan> periksaPengikatan(int tenantId) async {
    final sekarang = await pengikatanSekarang();
    if (sekarang == null) return StatusPengikatan.belumTerikat;
    final terikat = sekarang['tenant_id'];
    if (terikat is int && terikat == tenantId) return StatusPengikatan.cocok;
    return StatusPengikatan.beda;
  }

  /// Baris pengikatan, atau null bila perangkat belum pernah diikat.
  Future<Map<String, Object?>?> pengikatanSekarang() async {
    final database = await db;
    final rows = await database.query('pengikatan_tenant', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Ikat perangkat ini pada satu tenant. Menimpa pengikatan lama bila ada —
  /// pemanggil WAJIB memastikan antreannya kosong lebih dulu lewat
  /// [hitungAntreanTertunda], sebab data lama tidak dibersihkan oleh metode ini.
  Future<void> ikatTenant({
    required int tenantId,
    String? tenantKode,
    String? serverSidik,
    String? akunSidik,
  }) async {
    final database = await db;
    await database.insert(
      'pengikatan_tenant',
      {
        'id': 1,
        'tenant_id': tenantId,
        'tenant_kode': tenantKode,
        'server_sidik': serverSidik,
        'akun_sidik': akunSidik,
        'terikat_pada': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Jumlah pekerjaan yang BELUM sampai ke server: antrean master, antrean
  /// Inventory & Sales, dan transaksi kasir.
  ///
  /// Dipakai sebagai syarat sebelum perangkat dialihkan ke tenant lain.
  /// Melepaskan pengikatan saat antrean masih berisi berarti membuang pekerjaan
  /// yang belum terkirim — atau lebih buruk, mengirimkannya atas nama tenant
  /// yang salah.
  Future<int> hitungAntreanTertunda() async {
    final database = await db;
    var jumlah = 0;
    for (final tabel in const [
      'outbox_master',
      'outbox_is',
      'transaksi_pending'
    ]) {
      try {
        final r = await database.rawQuery(
            'SELECT COUNT(*) AS n FROM $tabel WHERE status = ?', ['PENDING']);
        final n = r.isEmpty ? null : r.first['n'];
        if (n is int) jumlah += n;
      } catch (_) {
        // Tabel belum ada pada basis data yang sangat lama -- hitung nol.
      }
    }
    return jumlah;
  }

  /// Tutup basis data tanpa mengarsipkan apa pun — dipakai saat keluar akun.
  ///
  /// Berbeda dari [lepaskanDanArsipkan]: berkasnya **tetap di tempatnya**. Keluar akun bukan
  /// pengalihan tenant; antrean yang belum terkirim harus tetap ada ketika pemiliknya masuk
  /// kembali. Yang dilepas hanyalah pegangan di memori.
  ///
  /// Pembukaan berikutnya terjadi dengan sendirinya pada akses pertama.
  Future<void> tutup() async {
    final terbuka = _db;
    _db = null;
    _openingDb = null;
    if (terbuka != null && terbuka.isOpen) {
      try {
        await terbuka.close();
      } catch (_) {
        // Gagal menutup (mis. masih ada operasi berjalan) tidak boleh menggagalkan keluar
        // akun. Pegangannya sudah dilepas; sisanya urusan garbage collector.
      }
    }
  }

  /// Tutup basis data tenant lama, arsipkan berkasnya dengan cap waktu, lalu
  /// biarkan pembukaan berikutnya membuatnya dari nol.
  ///
  /// Berkasnya **diarsipkan, bukan dihapus** (dokumen master §15.4): kalau
  /// ternyata ada yang salah, datanya masih dapat diperiksa. Mengembalikan
  /// jalur arsipnya, atau null bila tidak ada yang perlu diarsipkan.
  Future<String?> lepaskanDanArsipkan() async {
    final path = _pathDb;
    final terbuka = _db;
    if (terbuka != null && terbuka.isOpen) {
      await terbuka.close();
    }
    _db = null;
    _openingDb = null;
    if (path == null) return null;
    final cap = DateTime.now().millisecondsSinceEpoch;
    String? arsip;
    for (final akhiran in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$akhiran');
      if (!file.existsSync()) continue;
      final tujuan = '$path$akhiran.tenant-$cap';
      try {
        file.renameSync(tujuan);
        if (akhiran.isEmpty) arsip = tujuan;
      } catch (_) {
        // Rename gagal (berkas terkunci) -- jangan hapus. Lebih baik gagal
        // terang-terangan daripada menghilangkan data tenant lama diam-diam.
      }
    }
    return arsip;
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

  // ============================ OUTBOX MASTER ============================
  // CRUD master offline-first (lihat _ddlOutboxMaster). Dipakai
  // services/master_offline.dart di app; helper di sini sengaja bodoh
  // (tanpa kebijakan retry) supaya kebijakan tetap satu tempat di service.

  /// Antre satu mutasi master. Bila [kunci] terisi, baris PENDING lama dengan
  /// kunci sama DIGANTI (coalesce) -- edit terakhir yang menang saat replay.
  /// Return id baris antrean yang baru dibuat -- dipakai alur "simpan lokal
  /// dulu" utk mencoba mengirim baris ITU saja segera setelah antre.
  Future<int> outboxMasterTambah(
      String aksi, String? kunci, String payloadJson) async {
    final database = await db;
    return database.transaction<int>((txn) async {
      if (kunci != null && kunci.isNotEmpty) {
        await txn.delete('outbox_master',
            // Koreksi user atas validasi GAGAL menggantikan payload lama juga;
            // satu objek hanya boleh mempunyai satu versi lokal yang aktif.
            where: "status IN ('PENDING','GAGAL') AND kunci = ?",
            whereArgs: [kunci]);
      }
      return txn.insert('outbox_master', {
        'aksi': aksi,
        'kunci': kunci,
        'payload_json': payloadJson,
        'status': 'PENDING',
        'dibuat_pada': DateTime.now().toIso8601String(),
      });
    });
  }

  /// Hapus satu baris antrean hanya untuk pembatalan/pemulihan eksplisit.
  /// Penolakan server tidak boleh memakai ini: gangguan teknis tetap PENDING,
  /// sedangkan validasi bisnis menjadi GAGAL agar payload lokal tidak hilang.
  /// Buang antrean PENDING milik satu kunci. Dipakai saat penghapusan lokal
  /// DIPULIHKAN: barisnya kembali tampil, jadi perintah hapus yang masih
  /// mengantre TIDAK boleh ikut terkirim -- kalau tetap terkirim, datanya
  /// lenyap di server justru setelah pengguna membatalkan penghapusannya.
  Future<int> outboxMasterHapusKunci(String kunci) async {
    final database = await db;
    return database.delete('outbox_master',
        where: "status = 'PENDING' AND kunci = ?", whereArgs: [kunci]);
  }

  Future<void> outboxMasterHapus(int id) async {
    final database = await db;
    await database.delete('outbox_master', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> outboxMasterPending() async {
    final database = await db;
    return database.query('outbox_master',
        where: "status = 'PENDING'", orderBy: 'id ASC');
  }

  /// Antrean aktif untuk satu jenis data/kunci tertentu.
  ///
  /// Selain proses sinkronisasi, payload lokal juga merupakan sumber tampilan
  /// local-first. Foto yang belum diterima server harus tetap bisa dipulihkan
  /// ketika form ditutup lalu dibuka kembali. Status GAGAL ikut dibaca karena
  /// penolakan server tidak boleh menghilangkan media yang sudah disimpan di
  /// perangkat.
  Future<List<Map<String, Object?>>> outboxMasterAktif({
    required String aksi,
    required String awalanKunci,
  }) async {
    final database = await db;
    return database.query(
      'outbox_master',
      where: "status IN ('PENDING','GAGAL') AND aksi = ? AND kunci LIKE ?",
      whereArgs: [aksi, '$awalanKunci%'],
      orderBy: 'id ASC',
    );
  }

  /// Salinan mutasi media untuk preview, termasuk yang sudah tersinkron.
  /// Pemanggil wajib membatasi aksi+kunci supaya payload CRUD biasa tidak
  /// ikut dimuat ke memori.
  Future<List<Map<String, Object?>>> outboxMasterUntukPreview({
    required String aksi,
    required String awalanKunci,
  }) async {
    final database = await db;
    return database.query(
      'outbox_master',
      where:
          "status IN ('PENDING','GAGAL','SYNCED') AND aksi = ? AND kunci LIKE ?",
      whereArgs: [aksi, '$awalanKunci%'],
      orderBy: 'id ASC',
    );
  }

  /// Simpan hasil minimal server pada jurnal mutasi yang sama. Media memakai
  /// pasangan id server dengan bytes lokal sebagai fallback preview.
  Future<void> outboxMasterSimpanHasilServer(
      int id, Map<String, Object?> hasilServer) async {
    final database = await db;
    final baris = await database.query('outbox_master',
        columns: ['payload_json'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (baris.isEmpty) return;
    try {
      final payload = Map<String, dynamic>.from(
          jsonDecode('${baris.first['payload_json'] ?? '{}'}') as Map);
      payload['_hasil_server'] = hasilServer;
      await database.update(
          'outbox_master', {'payload_json': jsonEncode(payload)},
          where: 'id = ?', whereArgs: [id]);
    } catch (_) {
      // Payload lama/rusak dipertahankan untuk diagnosis.
    }
  }

  Future<void> outboxMasterTandaiSukses(int id) async {
    final database = await db;
    await database.update(
        'outbox_master', {'status': 'SYNCED', 'pesan_error': null},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Penolakan bisnis server (bukan offline): GAGAL permanen + pesan --
  /// tidak ikut retry berikutnya, tetap terlihat utk ditindak manual.
  Future<void> outboxMasterTandaiGagal(int id, String pesan) async {
    final database = await db;
    await database.update(
        'outbox_master', {'status': 'GAGAL', 'pesan_error': pesan},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> outboxMasterCatatPercobaan(int id, String pesan) async {
    final database = await db;
    await database.rawUpdate(
        'UPDATE outbox_master SET percobaan = COALESCE(percobaan,0) + 1,'
        ' pesan_error = ? WHERE id = ?',
        [pesan, id]);
  }

  // ======================== ID SEMENTARA (OFFLINE) ========================
  // Lihat _ddlIdSementara. Alurnya: catat() saat baris dibuat offline ->
  // petakan() begitu server memberi id sungguhan -> cari()/belumDipetakan()
  // dipakai MasterOffline saat menukar rujukan sebelum mengirim antrean.

  /// Catat id sementara yang baru dipakai satu baris master offline.
  Future<void> idSementaraCatat(int idLokal, String entitas) async {
    final database = await db;
    await database.insert(
      'id_sementara',
      {
        'id_lokal': idLokal,
        'entitas': entitas,
        'dibuat_pada': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Simpan hasil penukaran setelah baris pembuatnya berhasil terkirim.
  Future<void> idSementaraPetakan(int idLokal, int idServer) async {
    final database = await db;
    await database.update(
      'id_sementara',
      {
        'id_server': idServer,
        'dipetakan_pada': DateTime.now().toIso8601String(),
      },
      where: 'id_lokal = ?',
      whereArgs: [idLokal],
    );
  }

  /// Id server untuk satu id sementara, atau null bila baris pembuatnya belum
  /// terkirim (rujukan yang memakainya HARUS ditahan dulu).
  Future<int?> idSementaraCari(int idLokal) async {
    final database = await db;
    final hasil = await database.query('id_sementara',
        columns: ['id_server'],
        where: 'id_lokal = ?',
        whereArgs: [idLokal],
        limit: 1);
    if (hasil.isEmpty) return null;
    return (hasil.first['id_server'] as num?)?.toInt();
  }

  /// Seluruh pemetaan yang sudah selesai -- dipakai menukar rujukan secara borongan.
  Future<Map<int, int>> idSementaraTerpetakan() async {
    final database = await db;
    final hasil = await database.query('id_sementara',
        columns: ['id_lokal', 'id_server'], where: 'id_server IS NOT NULL');
    return {
      for (final r in hasil)
        (r['id_lokal'] as num).toInt(): (r['id_server'] as num).toInt(),
    };
  }

  /// Berapa baris yang masih menunggu id server (indikator + pagar pengiriman).
  Future<int> jumlahIdSementaraTertunda() async {
    final database = await db;
    final hasil = await database.rawQuery(
        'SELECT COUNT(*) AS n FROM id_sementara WHERE id_server IS NULL');
    return (hasil.first['n'] as int?) ?? 0;
  }

  /// Bersihkan pemetaan lama yang sudah tidak dirujuk siapa pun.
  Future<void> idSementaraBersihkan({int simpanHari = 30}) async {
    final database = await db;
    final batas =
        DateTime.now().subtract(Duration(days: simpanHari)).toIso8601String();
    await database.delete('id_sementara',
        where: 'id_server IS NOT NULL AND dipetakan_pada < ?',
        whereArgs: [batas]);
  }

  Future<int> jumlahOutboxMasterPending() async {
    final database = await db;
    final hasil = await database.rawQuery(
        "SELECT COUNT(*) AS n FROM outbox_master WHERE status = 'PENDING'");
    return (hasil.first['n'] as int?) ?? 0;
  }

  /// Baris GAGAL permanen terakhir -- bahan tampilan "perlu perhatian" di UI.
  Future<List<Map<String, Object?>>> outboxMasterGagal({int batas = 20}) async {
    final database = await db;
    return database.query('outbox_master',
        where: "status = 'GAGAL'", orderBy: 'id DESC', limit: batas);
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

      // Snapshot server tidak boleh menghapus edit produk yang sudah sah
      // tersimpan lokal tetapi belum diterima server. Terapkan kembali payload
      // outbox sebagai lapisan paling baru setelah replace penuh. Baris create
      // belum ikut di sini karena belum memiliki id server/primary key cache.
      final mutasiLokal = await txn.query(
        'outbox_master',
        columns: ['payload_json'],
        where: "aksi = 'produk_simpan' AND status IN ('PENDING','GAGAL')",
        orderBy: 'id ASC',
      );
      for (final antrean in mutasiLokal) {
        try {
          final payload = Map<String, dynamic>.from(
            jsonDecode(antrean['payload_json'] as String) as Map,
          );
          final id = (payload['id'] as num?)?.toInt();
          if (id == null) continue;
          final hasil = await txn.query(
            'produk_cache',
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          if (hasil.isEmpty) continue;
          final lokal = Map<String, Object?>.from(hasil.single);
          void salin(String payloadKey, String cacheKey) {
            if (payload.containsKey(payloadKey)) {
              lokal[cacheKey] = payload[payloadKey];
            }
          }

          salin('kode', 'kode');
          salin('barcode', 'barcode');
          salin('nama', 'nama');
          salin('harga_jual', 'harga_jual');
          salin('stok', 'stok');
          salin('kategori_id', 'kategori_id');
          salin('jenis_item', 'jenis_item');
          if (payload.containsKey('aktif')) {
            lokal['aktif'] = payload['aktif'] == false ? 0 : 1;
          }
          if (payload.containsKey('izinkan_jual_minus_stok')) {
            lokal['izinkan_jual_minus_stok'] =
                payload['izinkan_jual_minus_stok'] == true ? 1 : 0;
          }
          if (payload.containsKey('ekstra_pilihan')) {
            lokal['ekstra_pilihan'] =
                jsonEncode(payload['ekstra_pilihan'] ?? const []);
          }
          if (payload.containsKey('kemasan')) {
            lokal['kemasan'] = jsonEncode(payload['kemasan'] ?? const []);
          }
          await txn.insert(
            'produk_cache',
            lokal,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {
          // Payload rusak tetap dipertahankan di outbox untuk diagnosis; satu
          // baris tidak boleh menggagalkan refresh katalog lainnya.
        }
      }
    });
  }

  /// Menambahkan/memperbarui sebagian katalog tanpa menghapus halaman lain.
  /// Jalur ini dipakai POS yang memuat katalog per halaman/kata kunci.
  Future<void> upsertProdukCache(List<Map<String, Object?>> baris) async {
    if (baris.isEmpty) return;
    final database = await db;
    final batch = database.batch();
    for (final b in baris) {
      batch.insert('produk_cache', b,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
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
  Future<List<Map<String, Object?>>> produkCache({
    String keyword = '',
    int? limit,
    int offset = 0,
  }) async {
    final database = await db;
    final kata = keyword.trim().toLowerCase();
    var where =
        "aktif = 1 AND (jenis_item IS NULL OR jenis_item NOT IN ('BAHAN','EKSTRA'))";
    final whereArgs = <Object?>[];
    if (kata.isNotEmpty) {
      where +=
          " AND (LOWER(COALESCE(nama,'')) LIKE ? OR LOWER(COALESCE(kode,'')) LIKE ? OR LOWER(COALESCE(barcode,'')) LIKE ?)";
      final pola = '%$kata%';
      whereArgs.addAll([pola, pola, pola]);
    }
    return database.query(
      'produk_cache',
      where: where,
      whereArgs: whereArgs,
      // Pembukaan POS tanpa kata kunci memakai primary key sehingga SQLite
      // dapat berhenti segera sesudah [limit] baris, tanpa menyortir seluruh
      // cache katalog yang dapat berisi puluhan ribu produk.
      orderBy: kata.isEmpty ? 'id ASC' : 'nama ASC',
      limit: limit,
      offset: offset,
    );
  }

  /// Daftar produk untuk layar MASTER Produk, dibaca langsung dari SQLite dan
  /// dipaginasi di database. Berbeda dari [produkCache] milik Kasir, daftar
  /// ini tetap menyertakan produk nonaktif, BAHAN, dan EKSTRA agar admin dapat
  /// mengelola seluruh master tanpa mengurai snapshot JSON puluhan ribu baris
  /// di thread UI.
  Future<List<Map<String, Object?>>> produkCacheMaster({
    String keyword = '',
    int? kategoriId,
    String jenisItem = 'SEMUA',
    int limit = 15,
    int offset = 0,
  }) async {
    final database = await db;
    final syarat = <String>[];
    final argumen = <Object?>[];
    final kata = keyword.trim().toLowerCase();
    if (kata.isNotEmpty) {
      syarat.add(
          "(LOWER(COALESCE(nama,'')) LIKE ? OR LOWER(COALESCE(kode,'')) LIKE ? OR LOWER(COALESCE(barcode,'')) LIKE ?)");
      final pola = '%$kata%';
      argumen.addAll([pola, pola, pola]);
    }
    if (kategoriId != null) {
      syarat.add('kategori_id = ?');
      argumen.add(kategoriId);
    }
    final jenis = jenisItem.trim().toUpperCase();
    if (jenis != 'SEMUA') {
      if (jenis == 'JUAL') {
        // Produk lama sebelum fitur Jenis Item bernilai NULL dan secara
        // kontrak diperlakukan sebagai produk jual biasa.
        syarat.add("(jenis_item IS NULL OR jenis_item = '' OR jenis_item = ?)");
        argumen.add('JUAL');
      } else {
        syarat.add('jenis_item = ?');
        argumen.add(jenis);
      }
    }
    return database.query(
      'produk_cache',
      where: syarat.isEmpty ? null : syarat.join(' AND '),
      whereArgs: argumen.isEmpty ? null : argumen,
      orderBy: 'nama COLLATE NOCASE ASC, id ASC',
      limit: limit,
      offset: offset,
    );
  }

  /// Jumlah pasangan filter [produkCacheMaster], dipisah dari pengambilan
  /// halaman agar kontrol pagination tidak perlu memuat semua produk.
  Future<int> jumlahProdukCacheMaster({
    String keyword = '',
    int? kategoriId,
    String jenisItem = 'SEMUA',
  }) async {
    final database = await db;
    final syarat = <String>[];
    final argumen = <Object?>[];
    final kata = keyword.trim().toLowerCase();
    if (kata.isNotEmpty) {
      syarat.add(
          "(LOWER(COALESCE(nama,'')) LIKE ? OR LOWER(COALESCE(kode,'')) LIKE ? OR LOWER(COALESCE(barcode,'')) LIKE ?)");
      final pola = '%$kata%';
      argumen.addAll([pola, pola, pola]);
    }
    if (kategoriId != null) {
      syarat.add('kategori_id = ?');
      argumen.add(kategoriId);
    }
    final jenis = jenisItem.trim().toUpperCase();
    if (jenis != 'SEMUA') {
      if (jenis == 'JUAL') {
        syarat.add("(jenis_item IS NULL OR jenis_item = '' OR jenis_item = ?)");
        argumen.add('JUAL');
      } else {
        syarat.add('jenis_item = ?');
        argumen.add(jenis);
      }
    }
    final hasil = await database.rawQuery(
      'SELECT COUNT(*) AS n FROM produk_cache${syarat.isEmpty ? '' : ' WHERE ${syarat.join(' AND ')}'}',
      argumen,
    );
    return (hasil.first['n'] as num?)?.toInt() ?? 0;
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

  /// Ganti cache member secara atomik setelah seluruh halaman server berhasil
  /// diunduh. Baris yang sudah hilang/nonaktif di server ikut dibersihkan,
  /// sementara kegagalan unduh tidak menyentuh cache lama.
  Future<void> replaceAnggotaCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('anggota_cache');
      final batch = txn.batch();
      for (final b in baris) {
        batch.insert('anggota_cache', b,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsertAnggotaCache(List<Map<String, Object?>> baris) async {
    final database = await db;
    final batch = database.batch();
    for (final b in baris) {
      batch.insert('anggota_cache', b,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Jumlah member di cache offline (opsional berfilter kata kunci, filter
  /// SAMA dgn [cariAnggotaCache]) -- 0 tanpa filter berarti belum pernah
  /// sinkron awal (pemicu progress bar hidrasi pertama di layar Pelanggan);
  /// dgn filter dipakai sbg total paginasi lokal daftar member.
  Future<int> jumlahAnggotaCache({String kataKunci = ''}) async {
    final database = await db;
    if (kataKunci.trim().isEmpty) {
      final hasil =
          await database.rawQuery('SELECT COUNT(*) AS n FROM anggota_cache');
      return (hasil.first['n'] as int?) ?? 0;
    }
    final kw = '%$kataKunci%';
    final hasil = await database.rawQuery(
        'SELECT COUNT(*) AS n FROM anggota_cache '
        'WHERE nama LIKE ? OR kode LIKE ? OR kode_identitas LIKE ? '
        'OR hp LIKE ? OR telp LIKE ? OR email LIKE ?',
        [kw, kw, kw, kw, kw, kw]);
    return (hasil.first['n'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> cariAnggotaCache(String kataKunci,
      {int limit = 30, int offset = 0}) async {
    final database = await db;
    if (kataKunci.trim().isEmpty) {
      return database.query('anggota_cache',
          orderBy: 'nama ASC', limit: limit, offset: offset);
    }
    final kw = '%$kataKunci%';
    return database.query(
      'anggota_cache',
      where: 'nama LIKE ? OR kode LIKE ? OR kode_identitas LIKE ? '
          'OR hp LIKE ? OR telp LIKE ? OR email LIKE ?',
      whereArgs: [kw, kw, kw, kw, kw, kw],
      orderBy: 'nama ASC',
      limit: limit,
      offset: offset,
    );
  }

  // ============================== TRANSAKSI PENDING ==============================

  Future<int> simpanTransaksiPending(String kodeUnik, String payloadJson,
      {String? akunKunci, int? tokoId, String? idPerangkat}) async {
    final database = await db;
    // `kode_unik` juga menjadi idempotency key server. Saat kasir memuat
    // kembali pesanan tertahan, kode draft yang sama memang WAJIB dipakai
    // kembali agar server memperbarui draft, bukan membuat transaksi baru.
    // Karena itu penyimpanan outbox lokal harus idempotent pula: INSERT biasa
    // akan melempar UNIQUE constraint bila kode tersebut pernah dicoba dari
    // perangkat ini dan membuat tombol Bayar tampak tidak bereaksi sebelum
    // request sempat dikirim. REPLACE aman di sini karena satu kode hanya boleh
    // mempunyai satu payload/status outbox terbaru.
    final sekarang = DateTime.now().toIso8601String();
    final id = await database.insert(
      'transaksi_pending',
      {
        'kode_unik': kodeUnik,
        'payload_json': payloadJson,
        'status': 'PENDING',
        'pesan_error': null,
        'dibuat_pada': sekarang,
        'akun_kunci': akunKunci,
        'toko_id': tokoId,
        'id_perangkat': idPerangkat,
        'percobaan': 0,
        'terakhir_dicoba': null,
        'disinkronkan_pada': null,
        'diperbarui_pada': sekarang,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // DB utama sudah committed. Buat salinan kedua sebelum request server.
    await _cadangkanBarisTransaksi(kodeUnik);
    return id;
  }

  /// Menyimpan angka OTORITATIF balasan server untuk satu transaksi.
  ///
  /// Server SELALU menghitung ulang promo saat menyimpan dan menimpa diskon
  /// kiriman kasir (lihat `terapkanEvaluasiDiskonServer` di KantinHelper), jadi
  /// total yang tercatat bisa berbeda dari total yang dipakai struk -- struk
  /// dicetak dari keranjang lokal sesaat setelah commit SQLite, tanpa menunggu
  /// balasan server. Balasannya disimpan apa adanya di sini supaya layar struk
  /// (yang sudah memantau baris ini tiap detik) dapat mengoreksi angkanya
  /// SEBELUM dicetak, dan memperingatkan kasir bila ternyata berbeda.
  Future<void> simpanHasilServerTransaksi(
      String kodeUnik, Map<String, dynamic> hasil) async {
    final database = await db;
    await database.update(
        'transaksi_pending',
        {
          'hasil_server_json': jsonEncode(hasil),
          'diperbarui_pada': DateTime.now().toIso8601String(),
        },
        where: 'kode_unik = ?',
        whereArgs: [kodeUnik]);
  }

  Future<void> tandaiTransaksiSinkron(String kodeUnik) async {
    final database = await db;
    final sekarang = DateTime.now().toIso8601String();
    await database.update(
        'transaksi_pending',
        {
          'status': 'SYNCED',
          'pesan_error': null,
          'disinkronkan_pada': sekarang,
          'diperbarui_pada': sekarang,
        },
        where: 'kode_unik = ?',
        whereArgs: [kodeUnik]);
    await _cadangkanBarisTransaksi(kodeUnik);
  }

  /// Menyimpan transaksi yang ditemukan di server sebagai salinan lokal.
  /// Baris PENDING/GAGAL tidak ditimpa agar payload pemulihan yang belum
  /// terkirim tetap utuh; kode_unik adalah kunci deduplikasi dua arah.
  Future<bool> simpanTransaksiDariServer(String kodeUnik, String payloadJson,
      {String? akunKunci, int? tokoId, String? idPerangkat}) async {
    final database = await db;
    final lama = await database.query('transaksi_pending',
        where: 'kode_unik = ?', whereArgs: [kodeUnik], limit: 1);
    if (lama.isNotEmpty && '${lama.first['status']}' != 'SYNCED') {
      return false;
    }
    final sekarang = DateTime.now().toIso8601String();
    await database.insert(
      'transaksi_pending',
      {
        'kode_unik': kodeUnik,
        'payload_json': payloadJson,
        'status': 'SYNCED',
        'pesan_error': null,
        'dibuat_pada': lama.isEmpty
            ? sekarang
            : '${lama.first['dibuat_pada'] ?? sekarang}',
        'akun_kunci': akunKunci,
        'toko_id': tokoId,
        'id_perangkat': idPerangkat,
        'percobaan': lama.isEmpty ? 0 : (lama.first['percobaan'] ?? 0),
        'terakhir_dicoba': lama.isEmpty ? null : lama.first['terakhir_dicoba'],
        'disinkronkan_pada': sekarang,
        'diperbarui_pada': sekarang,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _cadangkanBarisTransaksi(kodeUnik);
    return true;
  }

  Future<Map<String, Object?>?> transaksiLokalDenganKode(
      String kodeUnik) async {
    final database = await db;
    final rows = await database.query('transaksi_pending',
        where: 'kode_unik = ?', whereArgs: [kodeUnik], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> tandaiTransaksiGagal(String kodeUnik, String pesanError) async {
    final database = await db;
    await database.rawUpdate(
      'UPDATE transaksi_pending SET pesan_error = ?, '
      'percobaan = COALESCE(percobaan, 0) + 1, terakhir_dicoba = ?, '
      'diperbarui_pada = ? '
      'WHERE kode_unik = ?',
      [
        pesanError,
        DateTime.now().toIso8601String(),
        DateTime.now().toIso8601String(),
        kodeUnik
      ],
    );
    await _cadangkanBarisTransaksi(kodeUnik);
  }

  /// Penolakan permanen dari server atau payload lokal rusak. Dipisahkan dari
  /// PENDING supaya retry otomatis tidak mengirim ulang kesalahan bisnis tanpa
  /// akhir, tetapi baris dan pesan teknis tetap tersedia di Riwayat Sinkronisasi.
  Future<void> tandaiTransaksiDitolak(
      String kodeUnik, String pesanError) async {
    final database = await db;
    await database.update(
      'transaksi_pending',
      {
        'status': 'GAGAL',
        'pesan_error': pesanError,
        'diperbarui_pada': DateTime.now().toIso8601String(),
      },
      where: 'kode_unik = ?',
      whereArgs: [kodeUnik],
    );
    await _cadangkanBarisTransaksi(kodeUnik);
  }

  /// Transaksi yang pernah divonis GAGAL dan MASIH belum ada di server.
  ///
  /// Dipakai layar Riwayat Sinkronisasi dan tombol Sinkronkan manual: nota yang
  /// terlanjur ditandai GAGAL tidak pernah lagi diambil retry otomatis (retry
  /// hanya membaca status PENDING), sehingga tanpa jalur ini nilainya hilang
  /// dari omzet server selamanya.
  Future<List<Map<String, Object?>>> transaksiGagalBelumSinkron({
    String? akunKunci,
    int? tokoId,
    int limit = 200,
  }) async {
    final database = await db;
    final klausa = <String>["status = 'GAGAL'"];
    final args = <Object?>[];
    if (akunKunci != null && akunKunci.isNotEmpty) {
      klausa.add('(akun_kunci = ? OR akun_kunci IS NULL)');
      args.add(akunKunci);
    }
    if (tokoId != null) {
      klausa.add('(toko_id = ? OR toko_id IS NULL)');
      args.add(tokoId);
    }
    return database.query(
      'transaksi_pending',
      where: klausa.join(' AND '),
      whereArgs: args,
      orderBy: 'dibuat_pada ASC',
      limit: limit,
    );
  }

  /// Kembalikan transaksi GAGAL ke antrean kirim (PENDING) supaya siklus
  /// sinkronisasi mengambilnya lagi. Hitungan percobaan direset agar jeda retry
  /// tidak langsung menahannya, dan pesan error lama dibersihkan supaya riwayat
  /// tidak menampilkan sebab yang sudah tidak berlaku.
  ///
  /// Aman terhadap transaksi ganda: pengiriman ulang memakai `kode_unik` asli,
  /// dan server menolak duplikat lewat DUPLIKAT_KODE_TRANSAKSI yang oleh
  /// pengirim diperlakukan sebagai "sudah ada di server".
  Future<int> kembalikanTransaksiKeAntrean(List<String> kodeUnik) async {
    if (kodeUnik.isEmpty) return 0;
    final database = await db;
    final tanda = List.filled(kodeUnik.length, '?').join(',');
    return database.rawUpdate(
      'UPDATE transaksi_pending SET status = ?, percobaan = 0, '
      'terakhir_dicoba = NULL, pesan_error = NULL, diperbarui_pada = ? '
      'WHERE kode_unik IN ($tanda) AND status = ?',
      ['PENDING', DateTime.now().toIso8601String(), ...kodeUnik, 'GAGAL'],
    );
  }

  /// Arsip transaksi milik akun/toko aktif, termasuk yang sudah tersinkron.
  /// Halaman Riwayat Penjualan memakai sumber ini untuk langsung menampilkan
  /// struk yang baru tercetak tanpa menunggu round-trip laporan server.
  /// Hanya `kode_unik` seluruh transaksi lokal satu toko.
  ///
  /// Dipakai replikasi cadangan untuk memeriksa "transaksi ini sudah ada di
  /// perangkat?". [transaksiArsipLokal] melakukan SELECT * sehingga ikut
  /// memuat `payload_json` SETIAP transaksi -- pada toko ramai itu puluhan MB
  /// JSON yang dibaca lalu langsung dibuang, tiap kali sinkronisasi berjalan.
  /// Kueri ini hanya mengambil satu kolom yang benar-benar dipakai.
  Future<Set<String>> kodeTransaksiLokalToko(int tokoId) async {
    final database = await db;
    final rows = await database.query(
      'transaksi_pending',
      columns: ['kode_unik'],
      where: '(toko_id = ? OR toko_id IS NULL)',
      whereArgs: [tokoId],
    );
    final hasil = <String>{};
    for (final row in rows) {
      final kode = '${row['kode_unik'] ?? ''}'.trim().toLowerCase();
      if (kode.isNotEmpty) hasil.add(kode);
    }
    return hasil;
  }

  Future<List<Map<String, Object?>>> transaksiArsipLokal({
    String? akunKunci,
    int? tokoId,
    int limit = 500,
  }) async {
    final database = await db;
    final klausa = <String>[];
    final args = <Object?>[];
    if (akunKunci != null && akunKunci.isNotEmpty) {
      klausa.add('(akun_kunci = ? OR akun_kunci IS NULL)');
      args.add(akunKunci);
    }
    if (tokoId != null) {
      klausa.add('(toko_id = ? OR toko_id IS NULL)');
      args.add(tokoId);
    }
    return database.query(
      'transaksi_pending',
      where: klausa.isEmpty ? null : klausa.join(' AND '),
      whereArgs: klausa.isEmpty ? null : args,
      orderBy: 'dibuat_pada DESC',
      limit: limit,
    );
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

  /// Menghapus transaksi yang telah dipastikan tidak ada pada arsip server.
  ///
  /// Pemanggil wajib memberikan hasil perbandingan server lengkap. Metode ini
  /// hanya menghapus kode yang diminta, lalu menulis tombstone ke backup
  /// append-only agar transaksi tidak dipulihkan kembali saat DB direcovery.
  Future<int> hapusTransaksiLokalTidakAdaDiServer(
      Iterable<String> kodeUnik) async {
    final kode = kodeUnik
        .map((nilai) => nilai.trim().toLowerCase())
        .where((nilai) => nilai.isNotEmpty)
        .toSet()
        .toList();
    if (kode.isEmpty) return 0;

    final database = await db;
    final tanda = List.filled(kode.length, '?').join(',');
    final terhapus = await database.transaction((txn) async {
      final rows = await txn.query(
        'transaksi_pending',
        columns: const ['kode_unik'],
        where: 'LOWER(kode_unik) IN ($tanda)',
        whereArgs: kode,
      );
      if (rows.isEmpty) return <String>[];
      final kodeAsli = rows
          .map((row) => '${row['kode_unik'] ?? ''}'.trim())
          .where((nilai) => nilai.isNotEmpty)
          .toList();
      final tandaAsli = List.filled(kodeAsli.length, '?').join(',');
      await txn.delete(
        'transaksi_pending',
        where: 'kode_unik IN ($tandaAsli)',
        whereArgs: kodeAsli,
      );
      return kodeAsli;
    });

    for (final nilai in terhapus) {
      await _cadangkanTransaksiPersisten(<String, Object?>{
        'kode_unik': nilai,
        'dihapus': true,
        'alasan': 'TIDAK_ADA_DI_SERVER',
      });
    }
    return terhapus.length;
  }

  Future<List<Map<String, Object?>>> transaksiPendingBelumSinkron(
      {String? akunKunci,
      int? tokoId,
      String? idPerangkat,
      Duration jedaRetry = const Duration(minutes: 10)}) async {
    final database = await db;
    final batasRetry = DateTime.now().subtract(jedaRetry).toIso8601String();
    final klausa = <String>[
      "status = 'PENDING'",
      '(terakhir_dicoba IS NULL OR terakhir_dicoba <= ?)'
    ];
    final args = <Object?>[batasRetry];
    if (akunKunci != null && akunKunci.isNotEmpty) {
      // NULL adalah baris versi lama; service memeriksa field `kasir` di
      // payload sebelum mengirim agar migrasi tidak kehilangan transaksi.
      klausa.add('(akun_kunci = ? OR akun_kunci IS NULL)');
      args.add(akunKunci);
    }
    if (tokoId != null) {
      klausa.add('(toko_id = ? OR toko_id IS NULL)');
      args.add(tokoId);
    }
    if (idPerangkat != null && idPerangkat.isNotEmpty) {
      klausa.add('(id_perangkat = ? OR id_perangkat IS NULL)');
      args.add(idPerangkat);
    }
    return database.query(
      'transaksi_pending',
      where: klausa.join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
    );
  }

  /// Jumlah transaksi lokal yang masih menjadi tanggung jawab akun, toko, dan
  /// perangkat ini. Dipakai sebagai gerbang Tutup Kas agar transaksi offline
  /// tidak tertinggal tanpa sesi asal yang masih terbuka.
  Future<int> jumlahTransaksiPendingPemilik({
    required String akunKunci,
    required int tokoId,
    required String idPerangkat,
  }) async {
    final database = await db;
    final hasil = await database.rawQuery(
      "SELECT COUNT(*) AS n FROM transaksi_pending "
      "WHERE status = 'PENDING' "
      'AND (akun_kunci = ? OR akun_kunci IS NULL) '
      'AND (toko_id = ? OR toko_id IS NULL) '
      'AND (id_perangkat = ? OR id_perangkat IS NULL)',
      [akunKunci, tokoId, idPerangkat],
    );
    return (hasil.first['n'] as num?)?.toInt() ?? 0;
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

  static Future<void> _buatIndeksBarisCacheReferensi(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_referensi_baris (
        kunci TEXT NOT NULL,
        urutan INTEGER NOT NULL,
        nilai_json TEXT NOT NULL,
        dihapus INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (kunci, urutan)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cache_referensi_baris_halaman
      ON cache_referensi_baris(kunci, dihapus, urutan)
    ''');
  }

  Future<List<dynamic>?> _uraiDaftarReferensi(String nilaiJson) async {
    // Snapshot besar harus diurai di isolate pekerja; kalau dilakukan pada
    // isolate UI, migrasi pertama cache lama justru kembali membuat layar
    // terlihat mandek sebelum LIMIT/OFFSET dapat dipakai.
    if (nilaiJson.length >= 64 * 1024) {
      return compute(_uraiDaftarReferensiDiIsolate, nilaiJson);
    }
    return _uraiDaftarReferensiDiIsolate(nilaiJson);
  }

  Future<void> _indeksDaftarReferensi(
      DatabaseExecutor database, String kunci, List<dynamic>? daftar) async {
    await database.delete('cache_referensi_baris',
        where: 'kunci = ?', whereArgs: [kunci]);
    if (daftar == null || daftar.isEmpty) return;
    final batch = database.batch();
    for (var i = 0; i < daftar.length; i++) {
      final baris = daftar[i];
      batch.insert('cache_referensi_baris', {
        'kunci': kunci,
        'urutan': i,
        'nilai_json': jsonEncode(baris),
        'dihapus': baris is Map && baris['_dihapus'] == true ? 1 : 0,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> simpanCacheReferensi(String kunci, String nilaiJson) async {
    final database = await db;
    final daftar = await _uraiDaftarReferensi(nilaiJson);
    await database.transaction((txn) async {
      await txn.insert(
        'cache_referensi',
        {
          'kunci': kunci,
          'nilai_json': nilaiJson,
          'diperbarui_pada': DateTime.now().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _indeksDaftarReferensi(txn, kunci, daftar);
    });
  }

  Future<String?> ambilCacheReferensi(String kunci) async {
    final database = await db;
    final hasil = await database
        .query('cache_referensi', where: 'kunci = ?', whereArgs: [kunci]);
    if (hasil.isEmpty) return null;
    return hasil.first['nilai_json'] as String?;
  }

  /// Membaca snapshot daftar generik memakai LIMIT/OFFSET SQLite. Snapshot
  /// instalasi versi lama diindeks otomatis satu kali saat pertama diakses;
  /// setelah itu perpindahan halaman tidak lagi mengurai puluhan ribu baris.
  Future<HalamanCacheReferensi?> ambilCacheReferensiHalaman(
    String kunci, {
    required int limit,
    required int offset,
  }) async {
    if (limit <= 0 || offset < 0) return null;
    final database = await db;
    final hitungIndeks = await database.rawQuery(
        'SELECT COUNT(*) AS jumlah FROM cache_referensi_baris WHERE kunci = ?',
        [kunci]);
    final jumlah = hitungIndeks.isEmpty
        ? 0
        : (hitungIndeks.first['jumlah'] as num).toInt();
    if (jumlah == 0) {
      final nilai = await ambilCacheReferensi(kunci);
      if (nilai == null) return null;
      final daftar = await _uraiDaftarReferensi(nilai);
      if (daftar == null) return null;
      await database
          .transaction((txn) => _indeksDaftarReferensi(txn, kunci, daftar));
    }
    final hitungAktif = await database.rawQuery('''
          SELECT COUNT(*) AS jumlah FROM cache_referensi_baris
          WHERE kunci = ? AND dihapus = 0
        ''', [kunci]);
    final total =
        hitungAktif.isEmpty ? 0 : (hitungAktif.first['jumlah'] as num).toInt();
    final rows = await database.query(
      'cache_referensi_baris',
      columns: ['nilai_json'],
      where: 'kunci = ? AND dihapus = 0',
      whereArgs: [kunci],
      orderBy: 'urutan ASC',
      limit: limit,
      offset: offset,
    );
    final data = <dynamic>[];
    for (final row in rows) {
      try {
        data.add(jsonDecode(row['nilai_json'] as String));
      } catch (_) {
        // Satu baris rusak tidak boleh menggagalkan seluruh halaman.
      }
    }
    return HalamanCacheReferensi(data, total);
  }

  /// GENERIK utk semua modul CRUD: true bila cache daftar [kunci] sudah ada
  /// dan tidak kosong -- pemeriksaan murah (tanpa parse JSON penuh) sebagai
  /// pemicu "perlu sinkron awal ber-progress" saat cache lokal masih kosong.
  Future<bool> adaCacheReferensiList(String kunci) async {
    final nilai = await ambilCacheReferensi(kunci);
    if (nilai == null) return false;
    final ringkas = nilai.trim();
    return ringkas.length > 2 && ringkas != '[]';
  }

  /// GENERIK: jumlah baris pada cache daftar [kunci] (0 bila belum ada/rusak).
  Future<int> jumlahCacheReferensiList(String kunci) async {
    final nilai = await ambilCacheReferensi(kunci);
    if (nilai == null) return 0;
    try {
      final data = jsonDecode(nilai);
      return data is List ? data.length : 0;
    } catch (_) {
      return 0;
    }
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

  /// Inventaris seluruh tabel SQLite milik aplikasi secara dinamis.
  ///
  /// Tidak ada daftar nama tabel yang di-hardcode di sini: tabel baru yang
  /// ditambahkan lewat migrasi otomatis ikut tampil pada pusat audit sinkron.
  /// Nilai ini hanya diagnostik/read-only; keputusan apakah sebuah tabel aman
  /// disinkronkan tetap berada pada adapter aplikasi (jangan pernah mengirim
  /// SQL/nama tabel bebas ke server).
  Future<List<Map<String, Object?>>> statistikSeluruhTabel() async {
    final database = await db;
    final tabel = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
      ORDER BY name COLLATE NOCASE
    ''');
    final hasil = <Map<String, Object?>>[];
    for (final item in tabel) {
      final nama = '${item['name'] ?? ''}';
      if (nama.isEmpty) continue;
      final aman = '"${nama.replaceAll('"', '""')}"';
      final info = await database.rawQuery('PRAGMA table_info($aman)');
      final kolom = info.map((e) => '${e['name'] ?? ''}').toList();
      final count = await database.rawQuery('SELECT COUNT(*) AS n FROM $aman');
      var pending = 0;
      var gagal = 0;
      var terhapus = 0;
      if (kolom.contains('status')) {
        final status = await database.rawQuery('''
          SELECT UPPER(COALESCE(status, '')) AS status, COUNT(*) AS n
          FROM $aman GROUP BY UPPER(COALESCE(status, ''))
        ''');
        for (final row in status) {
          final nilai = '${row['status'] ?? ''}';
          final jumlah = (row['n'] as num?)?.toInt() ?? 0;
          if (nilai == 'PENDING') pending += jumlah;
          if (nilai == 'GAGAL' || nilai == 'FAILED') gagal += jumlah;
        }
      }
      if (nama == 'cache_referensi') {
        final cache =
            await database.query('cache_referensi', columns: ['nilai_json']);
        for (final row in cache) {
          try {
            final nilai = jsonDecode('${row['nilai_json']}');
            if (nilai is List) {
              terhapus += nilai
                  .whereType<Map>()
                  .where((e) => e['_dihapus'] == true)
                  .length;
            }
          } catch (_) {
            // Cache lama/korup dihitung sebagai satu kegagalan audit; satu
            // nilai rusak tidak boleh menggagalkan inventaris tabel lain.
            gagal++;
          }
        }
      }
      final kolomWaktu = [
        'diperbarui_pada',
        'terakhir_dicoba',
        'dibuat_pada',
        'waktu',
        'dibuka_pada'
      ].where(kolom.contains).toList();
      String? terbaru;
      if (kolomWaktu.isNotEmpty) {
        final waktu = kolomWaktu.first;
        final qWaktu = '"${waktu.replaceAll('"', '""')}"';
        final max = await database
            .rawQuery('SELECT MAX($qWaktu) AS terbaru FROM $aman');
        terbaru = max.first['terbaru']?.toString();
      }
      hasil.add({
        'nama': nama,
        'jumlah': (count.first['n'] as num?)?.toInt() ?? 0,
        'pending': pending,
        'gagal': gagal,
        'terhapus': terhapus,
        'terbaru': terbaru,
        'kolom': kolom,
        'jumlah_kolom': kolom.length,
      });
    }
    return hasil;
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

/// Hasil pemeriksaan pengikatan perangkat terhadap tenant.
enum StatusPengikatan {
  /// Perangkat belum pernah diikat -- pemasangan baru, atau basis data lama
  /// yang naik dari versi sebelum v13.
  belumTerikat,

  /// Perangkat sudah terikat pada tenant yang sama. Jalan terus.
  cocok,

  /// Perangkat terikat pada tenant LAIN. Data lokalnya bukan milik tenant yang
  /// sedang login, dan antreannya tidak boleh terkirim atas namanya.
  beda,
}

/// Satu halaman snapshot referensi generik yang dibaca langsung dari SQLite.
/// [total] adalah jumlah seluruh baris aktif pada snapshot, bukan hanya jumlah
/// [data], sehingga layar tetap dapat membentuk paginator tanpa memuat semua
/// JSON ke thread UI.
class HalamanCacheReferensi {
  final List<dynamic> data;
  final int total;

  const HalamanCacheReferensi(this.data, this.total);
}

List<dynamic>? _uraiDaftarReferensiDiIsolate(String nilaiJson) {
  try {
    final hasil = jsonDecode(nilaiJson);
    return hasil is List ? hasil : null;
  } catch (_) {
    return null;
  }
}
