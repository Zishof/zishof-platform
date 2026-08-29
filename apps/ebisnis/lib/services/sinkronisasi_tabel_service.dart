import 'dart:async';

import 'package:core_db/core_db.dart';

import '../api_client.dart';
import '../models.dart';
import '../sesi.dart';
import 'master_offline.dart';
import 'outbox_is.dart';
import 'transaksi_outbox_service.dart';

class StatusSinkronTabel {
  const StatusSinkronTabel({
    required this.nama,
    required this.jumlahLokal,
    required this.jumlahKolom,
    required this.pending,
    required this.gagal,
    required this.terhapusLokal,
    required this.terbaruLokal,
    required this.adapter,
    required this.keterangan,
    this.jumlahServer,
    this.terbaruServer,
    this.kendala,
  });

  final String nama;
  final int jumlahLokal;
  final int jumlahKolom;
  final int pending;
  final int gagal;
  final int terhapusLokal;
  final String? terbaruLokal;
  final String? adapter;
  final String keterangan;
  final int? jumlahServer;
  final String? terbaruServer;
  final String? kendala;

  bool get dapatDisinkronkan => adapter != null;
  bool get berbeda => jumlahServer != null && jumlahServer != jumlahLokal;
  bool get belumValid =>
      pending > 0 || gagal > 0 || terhapusLokal > 0 || berbeda;

  StatusSinkronTabel salin({
    int? jumlahServer,
    String? terbaruServer,
    String? kendala,
  }) =>
      StatusSinkronTabel(
        nama: nama,
        jumlahLokal: jumlahLokal,
        jumlahKolom: jumlahKolom,
        pending: pending,
        gagal: gagal,
        terhapusLokal: terhapusLokal,
        terbaruLokal: terbaruLokal,
        adapter: adapter,
        keterangan: keterangan,
        jumlahServer: jumlahServer ?? this.jumlahServer,
        terbaruServer: terbaruServer ?? this.terbaruServer,
        kendala: kendala,
      );
}

/// Snapshot kemajuan satu rangkaian sinkronisasi seluruh tabel.
///
/// Persentase berasal dari jumlah adapter yang benar-benar telah selesai,
/// bukan timer semu. [sedangBerjalan] membedakan laporan sebelum dan sesudah
/// satu adapter diproses sehingga UI dapat menampilkan nama data yang aktif.
class KemajuanSinkronisasiTabel {
  const KemajuanSinkronisasiTabel({
    required this.nama,
    required this.label,
    required this.jumlahSelesai,
    required this.total,
    required this.sedangBerjalan,
    this.gagal = false,
    this.pesan,
    this.detail,
    this.fraksiTahap,
  });

  final String nama;
  final String label;
  final int jumlahSelesai;
  final int total;
  final bool sedangBerjalan;
  final bool gagal;
  final String? pesan;
  final String? detail;

  /// Kemajuan di dalam adapter aktif (0..1). Tanpa nilai ini persentase tetap
  /// dihitung dari jumlah tabel yang selesai, sehingga tidak pernah berpura-
  /// pura maju berdasarkan timer.
  final double? fraksiTahap;

  double get fraksi {
    if (total <= 0) return 0;
    final bagianAktif =
        sedangBerjalan ? (fraksiTahap ?? 0).clamp(0.0, 1.0).toDouble() : 0.0;
    return ((jumlahSelesai + bagianAktif) / total).clamp(0.0, 1.0).toDouble();
  }

  int get persen => (fraksi * 100).round();
}

typedef PelaporKemajuanSinkronisasi = void Function(
  KemajuanSinkronisasiTabel kemajuan,
);

typedef PelaporRincianSinkronisasi = void Function(
  String detail,
  int jumlahDiproses,
  int? total,
);

class SinkronisasiDibatalkan implements Exception {
  const SinkronisasiDibatalkan();

  @override
  String toString() =>
      'Dibatalkan pengguna. Data lokal yang sudah ada tetap dipertahankan.';
}

/// Token pembatalan kooperatif. Permintaan HTTP yang sudah berada di server
/// tidak diputus paksa; setelah respons/batas waktu kembali, proses berhenti
/// sebelum halaman berikutnya atau sebelum cache atomik diganti.
class PembatalanSinkronisasi {
  bool _dibatalkan = false;

  bool get dibatalkan => _dibatalkan;
  void batalkan() => _dibatalkan = true;

  void pastikanLanjut() {
    if (_dibatalkan) throw const SinkronisasiDibatalkan();
  }
}

/// Audit dan sinkron tabel lokal yang aman.
///
/// Inventaris tabel selalu dinamis dari SQLite. Hanya tabel pada registry ini
/// yang boleh menjalankan aksi sinkron, sebab nama tabel baru belum otomatis
/// mempunyai kontrak API, pemetaan kolom, lingkup toko, dan aturan konflik.
class SinkronisasiTabelService {
  SinkronisasiTabelService._();
  static final instance = SinkronisasiTabelService._();

  static const _adapter = <String, String>{
    'produk_cache': 'produk',
    'anggota_cache': 'anggota',
    'transaksi_pending': 'transaksi',
    'outbox_master': 'outbox_master',
    'outbox_is': 'outbox_is',
  };

  static String labelTabel(String nama) {
    switch (nama) {
      case 'produk_cache':
        return 'Katalog produk';
      case 'anggota_cache':
        return 'Data member';
      case 'transaksi_pending':
        return 'Transaksi lokal & pending';
      case 'outbox_master':
        return 'Perubahan data master';
      case 'outbox_is':
        return 'Perintah Inventory & Sales';
      default:
        return nama;
    }
  }

  static String _keterangan(String nama) {
    switch (nama) {
      case 'produk_cache':
        return 'Salinan katalog toko aktif; server menjadi sumber utama.';
      case 'anggota_cache':
        return 'Salinan member aktif; server menjadi sumber utama.';
      case 'transaksi_pending':
        return 'Jurnal transaksi lokal; hanya baris tertunda/gagal yang dikirim.';
      case 'outbox_master':
        return 'Antrean perubahan data master; tidak memiliki tabel cermin 1:1 di server.';
      case 'outbox_is':
        return 'Antrean perintah Inventory & Sales yang idempoten.';
      case 'cache_referensi':
        return 'Wadah snapshot beberapa API; sinkron dilakukan oleh menu pemilik datanya.';
      case 'error_log':
        return 'Log diagnostik perangkat, sengaja lokal.';
      case 'id_sementara':
        return 'Pemetaan ID offline ke ID server, sengaja lokal.';
      case 'pengikatan_tenant':
      case 'toko_aktif_akun':
        return 'Konfigurasi keamanan perangkat, sengaja lokal.';
      case 'sesi_kas_lokal':
        return 'Cadangan status kas; sinkron mengikuti alur buka/tutup kas.';
      default:
        return 'Tabel baru terdeteksi otomatis, tetapi belum memiliki adapter sinkronisasi.';
    }
  }

  /// Pemeriksaan ringan untuk menentukan apakah dialog sinkronisasi sesudah
  /// instalasi/update layak ditampilkan. Penolakan bisnis berarti server tetap
  /// terjangkau; hanya kegagalan jaringan yang menunda dialog sampai koneksi
  /// pulih.
  Future<bool> serverTerjangkau() async {
    if (!ApiClient.instance.sudahLogin) return false;
    try {
      await ApiClient.instance.aksi('katalog', {
        'page': 1,
        'page_size': 1,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
      });
      return true;
    } catch (e) {
      // Respons 401 membuang token. Walau jaringan hidup, jangan membuka
      // dialog sinkronisasi di atas layar dengan sesi yang sudah tidak sah.
      if (!ApiClient.instance.sudahLogin) return false;
      return e is! ApiException || !e.offline;
    }
  }

  Future<List<StatusSinkronTabel>> muat() async {
    final lokal = await CoreDb.instance.statistikSeluruhTabel();
    var hasil = lokal.map((row) {
      final nama = '${row['nama']}';
      return StatusSinkronTabel(
        nama: nama,
        jumlahLokal: (row['jumlah'] as num?)?.toInt() ?? 0,
        jumlahKolom: (row['jumlah_kolom'] as num?)?.toInt() ?? 0,
        pending: (row['pending'] as num?)?.toInt() ?? 0,
        gagal: (row['gagal'] as num?)?.toInt() ?? 0,
        terhapusLokal: (row['terhapus'] as num?)?.toInt() ?? 0,
        terbaruLokal: row['terbaru']?.toString(),
        adapter: _adapter[nama],
        keterangan: _keterangan(nama),
      );
    }).toList();

    if (!ApiClient.instance.sudahLogin) {
      return hasil
          .map((e) => e.dapatDisinkronkan
              ? e.salin(
                  kendala:
                      'Belum masuk ke server. Login dan pastikan koneksi aktif, lalu tekan Periksa Ulang.')
              : e)
          .toList();
    }

    int? totalProduk;
    int? totalAnggota;
    String? kendalaProduk;
    String? kendalaAnggota;
    try {
      final respons = await ApiClient.instance.aksi('katalog', {
        'page': 1,
        'page_size': 1,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
      });
      totalProduk = (respons['total'] as num?)?.toInt();
    } catch (e) {
      kendalaProduk = _pesanPeriksa(e);
    }
    try {
      final respons = await ApiClient.instance
          .aksi('anggota_list', {'page': 1, 'page_size': 1});
      totalAnggota = (respons['total'] as num?)?.toInt();
    } catch (e) {
      kendalaAnggota = _pesanPeriksa(e);
    }
    hasil = hasil.map((e) {
      if (e.nama == 'produk_cache') {
        return e.salin(jumlahServer: totalProduk, kendala: kendalaProduk);
      }
      if (e.nama == 'anggota_cache') {
        return e.salin(jumlahServer: totalAnggota, kendala: kendalaAnggota);
      }
      return e;
    }).toList();
    return hasil;
  }

  Future<String> sinkronkan(
    String nama, {
    PelaporRincianSinkronisasi? onDetail,
    PembatalanSinkronisasi? pembatalan,
    bool kirimMasterLebihDulu = true,
  }) async {
    pembatalan?.pastikanLanjut();
    switch (_adapter[nama]) {
      case 'produk':
        final jumlah = await _sinkronProduk(
          onDetail: onDetail,
          pembatalan: pembatalan,
          kirimMasterLebihDulu: kirimMasterLebihDulu,
        );
        return '$jumlah produk berhasil dicocokkan dengan server.';
      case 'anggota':
        final jumlah = await sinkronkanAnggota(
          onDetail: onDetail,
          pembatalan: pembatalan,
          kirimMasterLebihDulu: kirimMasterLebihDulu,
        );
        return '$jumlah member berhasil diunduh dari server.';
      case 'transaksi':
        final hasil = await TransaksiOutboxService.instance
            .sinkronkan(sertakanGagal: true);
        pembatalan?.pastikanLanjut();
        return '${hasil.berhasil} dari ${hasil.total} transaksi berhasil dikirim.';
      case 'outbox_master':
        final jumlah = await MasterOffline.flush();
        pembatalan?.pastikanLanjut();
        return '$jumlah perubahan data master berhasil dikirim.';
      case 'outbox_is':
        final jumlah = await OutboxIs.flush();
        pembatalan?.pastikanLanjut();
        return '$jumlah perintah Inventory & Sales berhasil dikirim.';
      default:
        throw StateError(
            'Tabel $nama belum memiliki adapter sinkronisasi. Data tidak diubah. Pengembang perlu menentukan API, kunci unik, aturan konflik, dan lingkup tokonya terlebih dahulu.');
    }
  }

  Future<List<String>> sinkronkanSemua({
    PelaporKemajuanSinkronisasi? onProgress,
    PembatalanSinkronisasi? pembatalan,
  }) async {
    final daftar = _adapter.keys.toList(growable: false);
    final pesanPerTabel = <String, String>{};
    var jumlahSelesai = 0;

    void lapor(
      String nama, {
      required bool sedangBerjalan,
      bool gagal = false,
      String? pesan,
      String? detail,
      double? fraksiTahap,
    }) {
      final label = labelTabel(nama);
      onProgress?.call(KemajuanSinkronisasiTabel(
        nama: nama,
        label: label,
        jumlahSelesai: jumlahSelesai,
        total: daftar.length,
        sedangBerjalan: sedangBerjalan,
        gagal: gagal,
        pesan: pesan,
        detail: detail,
        fraksiTahap: fraksiTahap,
      ));
    }

    Future<String> jalankan(
      String nama, {
      Future<int>? tungguMaster,
      bool hasilMaster = false,
    }) async {
      final label = labelTabel(nama);
      lapor(
        nama,
        sedangBerjalan: true,
        detail: tungguMaster == null
            ? 'Menyiapkan ${label.toLowerCase()}…'
            : 'Menunggu perubahan data master selesai agar cache tidak tertimpa…',
      );
      var gagal = false;
      late String hasil;
      try {
        if (tungguMaster != null) await tungguMaster;
        pembatalan?.pastikanLanjut();
        if (hasilMaster) {
          final jumlah = await (tungguMaster ?? Future<int>.value(0));
          hasil = '$jumlah perubahan data master berhasil dikirim.';
        } else {
          hasil = await sinkronkan(
            nama,
            pembatalan: pembatalan,
            kirimMasterLebihDulu: tungguMaster == null,
            onDetail: (detail, jumlahDiproses, totalData) {
              final fraksiTahap = totalData == null || totalData <= 0
                  ? null
                  : jumlahDiproses / totalData;
              lapor(
                nama,
                sedangBerjalan: true,
                detail: detail,
                fraksiTahap: fraksiTahap,
              );
            },
          );
        }
      } on SinkronisasiDibatalkan catch (e) {
        hasil = '$e';
      } catch (e) {
        gagal = true;
        hasil = _pesanPeriksa(e);
      }
      final pesanTabel = '$nama: $hasil';
      pesanPerTabel[nama] = pesanTabel;
      jumlahSelesai++;
      lapor(
        nama,
        sedangBerjalan: false,
        gagal: gagal,
        pesan: pesanTabel,
        detail: hasil,
      );
      return hasil;
    }

    // Satu flush master menjadi prasyarat bersama katalog+member. Future yang
    // sama mencegah tiga flush bersaing dan mencegah laporan "0 terkirim"
    // palsu ketika guard MasterOffline._sedangFlush aktif.
    final futureMaster = (() async {
      lapor(
        'outbox_master',
        sedangBerjalan: true,
        detail: 'Mengirim perubahan data master lokal…',
      );
      pembatalan?.pastikanLanjut();
      return MasterOffline.flush();
    })();

    await Future.wait<String>([
      jalankan('outbox_master', tungguMaster: futureMaster, hasilMaster: true),
      jalankan('produk_cache', tungguMaster: futureMaster),
      jalankan('anggota_cache', tungguMaster: futureMaster),
      jalankan('transaksi_pending'),
      jalankan('outbox_is'),
    ]);

    // Urutan hasil stabil sesuai grid, walaupun penyelesaiannya paralel.
    return daftar.map((nama) => pesanPerTabel[nama]!).toList(growable: false);
  }

  /// Unduh ulang seluruh member aktif dari server dan ganti cache lokal secara
  /// atomik. Dipublikasikan agar alur "Sinkronkan Semua Sivitas" dapat langsung
  /// menutup langkah kedua tanpa meminta pengguna menekan tombol lain.
  Future<int> sinkronkanAnggota({
    PelaporRincianSinkronisasi? onDetail,
    PembatalanSinkronisasi? pembatalan,
    bool kirimMasterLebihDulu = true,
  }) async {
    if (kirimMasterLebihDulu) {
      onDetail?.call(
          'Mengirim perubahan master lokal sebelum mengunduh member…', 0, null);
      await MasterOffline.flush();
    }
    pembatalan?.pastikanLanjut();
    var sejakId = 0;
    final perId = <int, Map<String, Object?>>{};
    while (true) {
      pembatalan?.pastikanLanjut();
      onDetail?.call(
          'Mengunduh data member setelah ID $sejakId…', perId.length, null);
      final hasil = await ApiClient.instance.aksi('anggota_sync_list', {
        'sejak_id': sejakId,
        'page_size': 500,
        'id_toko': Sesi.instance.idTokoTerpilih,
      });
      pembatalan?.pastikanLanjut();
      final data = (hasil['data'] as List?) ?? const [];
      for (final nilai in data.whereType<Map>()) {
        final row = Map<String, dynamic>.from(nilai);
        final id = (row['id'] as num?)?.toInt();
        if (id == null) {
          throw StateError(
              'Server mengirim member tanpa ID. Cache lama dipertahankan.');
        }
        perId[id] = Anggota.keCacheRow(row);
      }
      final berikutnya = (hasil['maksId'] as num?)?.toInt() ?? sejakId;
      if (hasil['adaLagi'] != true) break;
      if (berikutnya <= sejakId) {
        throw StateError(
            'Paging member tidak bergerak. Cache lama dipertahankan; periksa log server.');
      }
      sejakId = berikutnya;
    }
    onDetail?.call('Menyimpan ${perId.length} member ke database lokal…',
        perId.length, perId.length);
    pembatalan?.pastikanLanjut();
    await CoreDb.instance.replaceAnggotaCache(perId.values.toList());
    return perId.length;
  }

  Future<int> _sinkronProduk({
    PelaporRincianSinkronisasi? onDetail,
    PembatalanSinkronisasi? pembatalan,
    bool kirimMasterLebihDulu = true,
  }) async {
    if (kirimMasterLebihDulu) {
      onDetail?.call(
          'Mengirim perubahan master lokal sebelum mengunduh katalog…',
          0,
          null);
      await MasterOffline.flush();
    }
    pembatalan?.pastikanLanjut();
    const ukuran = 100;
    final perId = <int, Map<String, dynamic>>{};
    var halaman = 1;
    int? total;
    while (true) {
      pembatalan?.pastikanLanjut();
      onDetail?.call(
        total == null
            ? 'Mengunduh halaman $halaman katalog produk…'
            : 'Mengunduh halaman $halaman — ${perId.length} dari $total produk…',
        perId.length,
        total,
      );
      final hasil = await _ambilHalamanKatalogDenganRetry(
        halaman: halaman,
        ukuran: ukuran,
        onMencobaUlang: (percobaan) => onDetail?.call(
          'Server sempat sibuk di halaman $halaman. Mencoba ulang $percobaan dari 3 tanpa mengulang dari awal…',
          perId.length,
          total,
        ),
        pembatalan: pembatalan,
      );
      pembatalan?.pastikanLanjut();
      final data = ((hasil['produk'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      total ??= (hasil['total'] as num?)?.toInt();
      final sebelum = perId.length;
      for (final row in data) {
        final id = (row['id'] as num?)?.toInt();
        if (id == null) {
          throw StateError(
              'Server mengirim produk tanpa ID di halaman $halaman. Cache lama dipertahankan.');
        }
        perId[id] = row;
      }
      onDetail?.call(
        'Halaman $halaman selesai — ${perId.length} dari ${total ?? '?'} produk diterima.',
        perId.length,
        total,
      );
      if (data.length < ukuran || (total != null && perId.length >= total)) {
        break;
      }
      if (sebelum == perId.length) {
        throw StateError(
            'Paging katalog tidak bergerak. Cache lama dipertahankan; periksa log server.');
      }
      halaman++;
    }
    if (total != null && perId.length != total) {
      throw StateError(
          'Unduhan katalog belum lengkap (${perId.length}/$total). Cache lama dipertahankan dan aman dipakai.');
    }
    onDetail?.call(
      'Menyimpan ${perId.length} produk ke database lokal…',
      perId.length,
      total ?? perId.length,
    );
    pembatalan?.pastikanLanjut();
    await CoreDb.instance
        .replaceProdukCache(perId.values.map(Produk.baseKeCacheRow).toList());
    await MasterOffline.simpanDaftarLengkapDariServer(
        'master:produk_list', perId.values.toList());
    return perId.length;
  }

  /// Gateway produksi sesekali mengembalikan 502 ketika offset katalog sudah
  /// sangat dalam. Satu halaman boleh dicoba ulang tanpa membuang halaman yang
  /// telah diterima; cache aktif tetap baru diganti setelah katalog lengkap.
  Future<Map<String, dynamic>> _ambilHalamanKatalogDenganRetry({
    required int halaman,
    required int ukuran,
    void Function(int percobaan)? onMencobaUlang,
    PembatalanSinkronisasi? pembatalan,
  }) async {
    const jeda = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
    ];
    for (var percobaan = 1; percobaan <= 3; percobaan++) {
      pembatalan?.pastikanLanjut();
      try {
        return await ApiClient.instance.aksi('katalog', {
          'page': halaman,
          'page_size': ukuran,
          if (Sesi.instance.idTokoTerpilih != null)
            'toko_id': Sesi.instance.idTokoTerpilih,
          if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
        });
      } on ApiException catch (e) {
        final sementara = e.offline ||
            e.statusHttp == 502 ||
            e.statusHttp == 503 ||
            e.statusHttp == 504;
        if (!sementara || percobaan >= 3) {
          if (e.statusHttp == 502 ||
              e.statusHttp == 503 ||
              e.statusHttp == 504) {
            throw StateError(
              'Server masih sibuk pada halaman $halaman setelah 3 percobaan '
              '(HTTP ${e.statusHttp}, referensi ${e.kodeReferensi ?? '-'}). '
              'Cache lama tetap aman. Tunggu 2–5 menit, lalu tekan Sinkronkan '
              'Tabel pada produk_cache; bila berulang, admin server perlu '
              'memeriksa permintaan katalog halaman $halaman.',
            );
          }
          rethrow;
        }
        onMencobaUlang?.call(percobaan + 1);
        await _tungguDapatDibatalkan(jeda[percobaan - 1], pembatalan);
      }
    }
    throw StateError('Percobaan katalog berhenti tanpa hasil.');
  }

  static Future<void> _tungguDapatDibatalkan(
    Duration durasi,
    PembatalanSinkronisasi? pembatalan,
  ) async {
    const irisan = Duration(milliseconds: 200);
    var tersisa = durasi;
    while (tersisa > Duration.zero) {
      pembatalan?.pastikanLanjut();
      final tunggu = tersisa < irisan ? tersisa : irisan;
      await Future<void>.delayed(tunggu);
      tersisa -= tunggu;
    }
    pembatalan?.pastikanLanjut();
  }

  static String _pesanPeriksa(Object e) {
    if (e is ApiException && e.offline) {
      return 'Server belum dapat dihubungi. Periksa internet/alamat server, lalu tekan Periksa Ulang; data lokal tetap aman.';
    }
    return 'Pemeriksaan ditolak/gagal: $e. Buka Log Error untuk detail, perbaiki penyebabnya, lalu tekan Periksa Ulang.';
  }
}
