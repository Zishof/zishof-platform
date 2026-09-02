import '../../../api_client.dart';

/// Satu pekerjaan konkret yang menunggu di dashboard (bukan sekadar angka).
class ApotikTugas {
  final String judul;
  final String keterangan;
  final ApotikTugasJenis jenis;

  /// Semakin kecil semakin mendesak (mis. sisa hari sampai kedaluwarsa).
  final int urutan;

  const ApotikTugas({
    required this.judul,
    required this.keterangan,
    required this.jenis,
    this.urutan = 0,
  });
}

enum ApotikTugasJenis { resep, expiry, stok }

/// Ringkasan prioritas dashboard apotik.
///
/// Setiap angka boleh `null` = **belum diketahui** (endpoint gagal/tidak
/// tersedia). Ini disengaja: dashboard tidak boleh menampilkan `0` untuk
/// sesuatu yang sebenarnya tidak terbaca — kasir bisa menyimpulkan "aman"
/// padahal datanya tidak pernah datang.
class ApotikRingkasan {
  final int? resepMenunggu;
  final int? batchNearExpiry;
  final int? stokHabis;
  final int? obatTerbaca;
  final List<ApotikTugas> tugas;

  /// Angka di atas berasal dari `apotik_metrik_operasional` (COUNT di basis
  /// data) atau — bila server belum punya aksi itu — dari daftar ber-halaman
  /// yang **terpotong pada 100**. Bedanya wajib terlihat: angka terpotong
  /// ditampilkan sebagai "100+", bukan sebagai fakta.
  final bool angkaPasti;

  /// Batch yang lotnya ditahan (karantina/recall/rusak). Hanya terisi bila
  /// server mengirim metrik.
  final int? batchDitahan;
  final int? transaksiHariIni;
  final double? nilaiHariIni;

  /// Waktu data ini benar-benar diterima dari server (untuk penanda basi).
  final DateTime? diperbaruiPada;

  /// Pesan galat per sumber; ditampilkan apa adanya, tidak ditelan UI.
  final Map<String, String> galat;

  const ApotikRingkasan({
    this.resepMenunggu,
    this.batchNearExpiry,
    this.stokHabis,
    this.obatTerbaca,
    this.tugas = const [],
    this.diperbaruiPada,
    this.galat = const {},
    this.angkaPasti = false,
    this.batchDitahan,
    this.transaksiHariIni,
    this.nilaiHariIni,
  });

  /// Label angka yang siap ditampilkan: menandai batas 100 saat angkanya
  /// berasal dari daftar terpotong.
  String label(int? nilai) {
    if (nilai == null) return '—';
    if (!angkaPasti && nilai >= 100) return '100+';
    return '$nilai';
  }
}

/// Pemuat data dashboard dari aksi yang BENAR-BENAR ada di server:
/// `apotik_metrik_operasional` (IR-10, angka pasti) dengan `apotik_resep_list`,
/// `apotik_batch_monitor`, dan `apotik_item_cari` untuk merakit daftar tugas.
/// Bila server belum punya aksi metrik, angka jatuh kembali ke daftar
/// ber-halaman dan ditandai TIDAK pasti (lihat [ApotikRingkasan.angkaPasti]).
///
/// Cold-chain, tugas shift, transaksi pending, dan SLA (ada di mockup 01)
/// TIDAK dipanggil karena backend belum menyediakannya — lihat IR-02/IR-06/
/// IR-10 pada `docs/apotik-uiux/02-api-action-map.md`. Kartu untuk metrik
/// tersebut sengaja tidak dibuat daripada menampilkan angka karangan.
class ApotikDashboardLoader {
  /// Ambang "mendekati kedaluwarsa" (hari) — dikirim ke server sebagai
  /// `hari_ke_depan` sehingga penyaringan terjadi di sisi data, bukan UI.
  static const int ambangNearExpiryHari = 90;

  final Future<Map<String, dynamic>> Function(String aksi,
      [Map<String, dynamic>? body]) _panggil;

  ApotikDashboardLoader({
    Future<Map<String, dynamic>> Function(String aksi,
            [Map<String, dynamic>? body])?
        panggil,
  }) : _panggil = panggil ?? _panggilDefault;

  static Future<Map<String, dynamic>> _panggilDefault(String aksi,
          [Map<String, dynamic>? body]) =>
      ApiClient.instance.aksi(aksi, body ?? const {});

  static bool _sukses(Map<String, dynamic> r) =>
      r['status'] == '00' || r['status'] == 'success';

  static List<Map<String, dynamic>> _data(Map<String, dynamic> r) =>
      ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  /// Sisa hari menuju [tanggal] format `yyyy-MM-dd`; null bila tak terbaca.
  static int? sisaHari(String? tanggal, {DateTime? sekarang}) {
    if (tanggal == null || tanggal.trim().isEmpty) return null;
    final t = DateTime.tryParse(tanggal.trim());
    if (t == null) return null;
    final kini = sekarang ?? DateTime.now();
    final awal = DateTime(kini.year, kini.month, kini.day);
    return DateTime(t.year, t.month, t.day).difference(awal).inDays;
  }

  Future<ApotikRingkasan> muat({DateTime? sekarang}) async {
    int? resepMenunggu;
    int? batchNearExpiry;
    int? stokHabis;
    int? obatTerbaca;
    int? batchDitahan;
    int? transaksiHariIni;
    double? nilaiHariIni;
    var angkaPasti = false;
    final tugas = <ApotikTugas>[];
    final galat = <String, String>{};

    // --- Metrik pasti (IR-10) -------------------------------------------
    // Dicoba LEBIH DULU: bila server mendukungnya, angka kartu berasal dari
    // COUNT atas seluruh baris, bukan dari daftar yang terpotong 100. Daftar
    // di bawah tetap dipanggil, tetapi hanya untuk merakit daftar tugas.
    try {
      final r = await _panggil('apotik_metrik_operasional', {
        'hari_ke_depan': ambangNearExpiryHari,
      });
      if (_sukses(r)) {
        angkaPasti = true;
        resepMenunggu = ((r['resepMenunggu'] as num?) ?? 0).toInt();
        batchNearExpiry = ((r['batchSegera'] as num?) ?? 0).toInt() +
            ((r['batchKedaluwarsa'] as num?) ?? 0).toInt();
        stokHabis = ((r['itemHabis'] as num?) ?? 0).toInt();
        batchDitahan = ((r['batchDitahan'] as num?) ?? 0).toInt();
        transaksiHariIni = ((r['transaksiHariIni'] as num?) ?? 0).toInt();
        nilaiHariIni = ((r['nilaiHariIni'] as num?) ?? 0).toDouble();
      }
    } catch (_) {
      // Server lama tanpa aksi ini: angka tetap diambil dari daftar di bawah,
      // dan ditandai tidak pasti lewat ApotikRingkasan.angkaPasti.
    }

    // --- Antrean resep -------------------------------------------------
    try {
      final r = await _panggil('apotik_resep_list', {'page_size': 100});
      if (_sukses(r)) {
        final semua = _data(r);
        // "Menunggu" = belum ditebus. Server mengirim `ditebus` (bool) dan
        // `status` (teks bebas); yang dipakai adalah `ditebus` karena itulah
        // penanda yang konsisten dari server.
        final menunggu = semua.where((e) => e['ditebus'] != true).toList();
        resepMenunggu ??= menunggu.length;
        for (final e in menunggu.take(5)) {
          tugas.add(ApotikTugas(
            judul: 'Resep ${e['kode'] ?? e['id'] ?? '-'}',
            keterangan: [
              if ('${e['diagnosa'] ?? ''}'.trim().isNotEmpty)
                '${e['diagnosa']}',
              if (e['jumlahBaris'] != null) '${e['jumlahBaris']} baris obat',
            ].join(' • '),
            jenis: ApotikTugasJenis.resep,
          ));
        }
      } else {
        galat['resep'] = '${r['description'] ?? 'Gagal memuat antrean resep.'}';
      }
    } catch (e) {
      galat['resep'] = '$e';
    }

    // --- Batch mendekati kedaluwarsa ------------------------------------
    try {
      final r = await _panggil('apotik_batch_monitor', {
        'hari_ke_depan': ambangNearExpiryHari,
        'page_size': 100,
      });
      if (_sukses(r)) {
        final batch = _data(r);
        batchNearExpiry ??= batch.length;
        final urut = [...batch];
        urut.sort((a, b) {
          final ha =
              sisaHari('${a['tanggalKadaluarsa'] ?? ''}', sekarang: sekarang) ??
                  99999;
          final hb =
              sisaHari('${b['tanggalKadaluarsa'] ?? ''}', sekarang: sekarang) ??
                  99999;
          return ha.compareTo(hb);
        });
        for (final e in urut.take(5)) {
          final hari =
              sisaHari('${e['tanggalKadaluarsa'] ?? ''}', sekarang: sekarang);
          tugas.add(ApotikTugas(
            judul: '${e['nama'] ?? e['kode'] ?? 'Batch'}',
            keterangan: hari == null
                ? 'Kedaluwarsa ${e['kedaluwarsa'] ?? '-'} • sisa ${e['sisa'] ?? 0}'
                : (hari < 0
                    ? 'SUDAH kedaluwarsa ${-hari} hari • sisa ${e['sisa'] ?? 0}'
                    : 'Kedaluwarsa dalam $hari hari • sisa ${e['sisa'] ?? 0}'),
            jenis: ApotikTugasJenis.expiry,
            urutan: hari ?? 99999,
          ));
        }
      } else {
        galat['batch'] = '${r['description'] ?? 'Gagal memuat monitor batch.'}';
      }
    } catch (e) {
      galat['batch'] = '$e';
    }

    // --- Stok habis ------------------------------------------------------
    try {
      final r = await _panggil('apotik_item_cari', {'page_size': 100});
      if (_sukses(r)) {
        final item = _data(r);
        obatTerbaca = item.length;
        final habis = item
            .where((e) => ((e['stok'] as num?)?.toDouble() ?? 0) <= 0)
            .toList();
        stokHabis ??= habis.length;
        for (final e in habis.take(5)) {
          tugas.add(ApotikTugas(
            judul: '${e['nama'] ?? '-'}',
            keterangan: 'Stok habis • ${e['kode'] ?? ''}',
            jenis: ApotikTugasJenis.stok,
            urutan: -1,
          ));
        }
      } else {
        galat['item'] = '${r['description'] ?? 'Gagal memuat daftar obat.'}';
      }
    } catch (e) {
      galat['item'] = '$e';
    }

    // Urutan tugas: expiry paling mendesak dulu (sisa hari terkecil/negatif),
    // lalu stok habis, lalu resep menunggu.
    tugas.sort((a, b) {
      int bobot(ApotikTugasJenis j) => switch (j) {
            ApotikTugasJenis.expiry => 0,
            ApotikTugasJenis.stok => 1,
            ApotikTugasJenis.resep => 2,
          };
      final w = bobot(a.jenis).compareTo(bobot(b.jenis));
      return w != 0 ? w : a.urutan.compareTo(b.urutan);
    });

    return ApotikRingkasan(
      resepMenunggu: resepMenunggu,
      batchNearExpiry: batchNearExpiry,
      stokHabis: stokHabis,
      obatTerbaca: obatTerbaca,
      tugas: tugas,
      diperbaruiPada: sekarang ?? DateTime.now(),
      galat: galat,
      angkaPasti: angkaPasti,
      batchDitahan: batchDitahan,
      transaksiHariIni: transaksiHariIni,
      nilaiHariIni: nilaiHariIni,
    );
  }
}
