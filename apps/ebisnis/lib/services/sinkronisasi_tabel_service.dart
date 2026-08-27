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

  Future<String> sinkronkan(String nama) async {
    switch (_adapter[nama]) {
      case 'produk':
        final jumlah = await _sinkronProduk();
        return '$jumlah produk berhasil dicocokkan dengan server.';
      case 'anggota':
        final jumlah = await sinkronkanAnggota();
        return '$jumlah member berhasil diunduh dari server.';
      case 'transaksi':
        final hasil = await TransaksiOutboxService.instance
            .sinkronkan(sertakanGagal: true);
        return '${hasil.berhasil} dari ${hasil.total} transaksi berhasil dikirim.';
      case 'outbox_master':
        final jumlah = await MasterOffline.flush();
        return '$jumlah perubahan data master berhasil dikirim.';
      case 'outbox_is':
        final jumlah = await OutboxIs.flush();
        return '$jumlah perintah Inventory & Sales berhasil dikirim.';
      default:
        throw StateError(
            'Tabel $nama belum memiliki adapter sinkronisasi. Data tidak diubah. Pengembang perlu menentukan API, kunci unik, aturan konflik, dan lingkup tokonya terlebih dahulu.');
    }
  }

  Future<List<String>> sinkronkanSemua() async {
    final pesan = <String>[];
    for (final nama in _adapter.keys) {
      try {
        pesan.add('$nama: ${await sinkronkan(nama)}');
      } catch (e) {
        pesan.add('$nama: ${_pesanPeriksa(e)}');
      }
    }
    return pesan;
  }

  /// Unduh ulang seluruh member aktif dari server dan ganti cache lokal secara
  /// atomik. Dipublikasikan agar alur "Sinkronkan Semua Sivitas" dapat langsung
  /// menutup langkah kedua tanpa meminta pengguna menekan tombol lain.
  Future<int> sinkronkanAnggota() async {
    await MasterOffline.flush();
    var sejakId = 0;
    final perId = <int, Map<String, Object?>>{};
    while (true) {
      final hasil = await ApiClient.instance
          .aksi('anggota_sync_list', {'sejak_id': sejakId, 'page_size': 500});
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
    await CoreDb.instance.replaceAnggotaCache(perId.values.toList());
    return perId.length;
  }

  Future<int> _sinkronProduk() async {
    await MasterOffline.flush();
    const ukuran = 100;
    final perId = <int, Map<String, dynamic>>{};
    var halaman = 1;
    int? total;
    while (true) {
      final hasil = await ApiClient.instance.aksi('katalog', {
        'page': halaman,
        'page_size': ukuran,
        if (Sesi.instance.idTokoTerpilih != null)
          'toko_id': Sesi.instance.idTokoTerpilih,
        if (Sesi.instance.idTokoTerpilih == null) 'semuaToko': true,
      });
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
    await CoreDb.instance
        .replaceProdukCache(perId.values.map(Produk.baseKeCacheRow).toList());
    await MasterOffline.simpanDaftarLengkapDariServer(
        'master:produk_list', perId.values.toList());
    return perId.length;
  }

  static String _pesanPeriksa(Object e) {
    if (e is ApiException && e.offline) {
      return 'Server belum dapat dihubungi. Periksa internet/alamat server, lalu tekan Periksa Ulang; data lokal tetap aman.';
    }
    return 'Pemeriksaan ditolak/gagal: $e. Buka Log Error untuk detail, perbaiki penyebabnya, lalu tekan Periksa Ulang.';
  }
}
