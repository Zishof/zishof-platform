import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../api_client.dart';

/// Kontrak pemanggilan server (sama dengan POS) supaya dapat diuji tanpa
/// jaringan.
typedef PanggilBayar = Future<Map<String, dynamic>> Function(
    String aksi, Map<String, dynamic> body);

/// Satu pembayaran yang nasibnya BELUM DIKETAHUI.
class PembayaranTertunda {
  /// Kode idempoten yang dikirim ke server (`payload['kode']`).
  final String kode;
  final Map<String, dynamic> payload;
  final double total;
  final DateTime waktu;

  const PembayaranTertunda({
    required this.kode,
    required this.payload,
    required this.total,
    required this.waktu,
  });

  Map<String, dynamic> toJson() => {
        'kode': kode,
        'payload': payload,
        'total': total,
        'waktu': waktu.toIso8601String(),
      };

  static PembayaranTertunda? dariJson(Object? j) {
    if (j is! Map) return null;
    final kode = '${j['kode'] ?? ''}';
    final payload = j['payload'];
    if (kode.isEmpty || payload is! Map) return null;
    return PembayaranTertunda(
      kode: kode,
      payload: Map<String, dynamic>.from(payload),
      total: ((j['total'] as num?) ?? 0).toDouble(),
      waktu: DateTime.tryParse('${j['waktu'] ?? ''}') ?? DateTime.now(),
    );
  }
}

/// Apa yang terjadi setelah satu pembayaran tertunda diperiksa ulang.
enum StatusPeriksaUlang {
  /// Server mengenali kode ini — transaksi SUDAH terbukukan sebelumnya.
  sudahTerbukukan,

  /// Kiriman pertama ternyata tidak pernah sampai; kiriman ulang ini yang
  /// membukukannya.
  baruTerbukukan,

  /// Server menolak secara bisnis. Karena kode yang sama tidak dikenali,
  /// transaksi ini TIDAK pernah terbukukan.
  ditolak,

  /// Masih tidak dapat dihubungi — nasibnya tetap belum diketahui.
  masihTidakPasti,
}

class HasilPeriksaUlang {
  final StatusPeriksaUlang status;
  final String pesan;
  final String kodeTransaksi;
  const HasilPeriksaUlang(this.status, this.pesan, {this.kodeTransaksi = ''});

  bool get selesai => status != StatusPeriksaUlang.masihTidakPasti;
}

/// <h3>Pembayaran yang belum dipastikan (Fase 6 — sinkronisasi).</h3>
///
/// **Masalah yang diselesaikan.** Ketika `apotik_bayar` gagal karena jaringan
/// (timeout / koneksi putus), kasir TIDAK tahu apakah server sempat
/// membukukan transaksi atau tidak. Alur lama menandainya "gagal" begitu saja
/// — klaim yang belum tentu benar, dan kasir yang menekan Bayar lagi berisiko
/// membuat penjualan kedua. Status `paidUnsynced` pada state machine memang
/// disediakan untuk keadaan ini, tetapi sebelumnya tidak pernah dipakai.
///
/// **Cara memastikannya.** Server sudah idempoten terhadap `kode`: bila kode
/// yang sama dikirim lagi, ia mengembalikan transaksi yang sudah ada beserta
/// `idempoten: true`, bukan membukukan ulang (lihat `ApotikApiHelper.bayar`).
/// Jadi cara paling aman untuk MENGETAHUI nasib transaksi adalah mengirim
/// ulang payload yang PERSIS SAMA:
///
/// * `idempoten: true` → transaksi sudah terbukukan sejak kiriman pertama;
/// * sukses tanpa flag → baru terbukukan oleh kiriman ulang ini;
/// * penolakan bisnis → kode tidak dikenal server, jadi tidak pernah
///   terbukukan;
/// * gagal jaringan lagi → tetap tidak pasti, biarkan mengantre.
///
/// Antrean disimpan di `shared_preferences` supaya **selamat dari aplikasi
/// ditutup atau mati listrik** — justru saat itulah kasir paling butuh tahu.
/// Yang disimpan hanya payload yang sudah dikirim; tidak ada penjualan yang
/// "diciptakan" secara offline. Menerima pembayaran saat server benar-benar
/// tidak terjangkau memerlukan reservasi stok di sisi server dan BUKAN bagian
/// dari kelas ini.
class ApotikPembayaranTertundaStore {
  ApotikPembayaranTertundaStore._();
  static final ApotikPembayaranTertundaStore instance =
      ApotikPembayaranTertundaStore._();

  static const String kunciPrefs = 'apotik_bayar_tertunda';

  /// Penyimpanan lokal tidak selalu ada (mis. test widget tanpa plugin).
  /// Ketiadaannya tidak boleh menggagalkan apa pun -- pemanggil di jalur kritis
  /// karenanya TIDAK menunggu tulisan/pembacaan ini selesai.
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<List<PembayaranTertunda>> muat() async {
    final prefs = await _prefs();
    if (prefs == null) return <PembayaranTertunda>[];
    final mentah = prefs.getString(kunciPrefs);
    if (mentah == null || mentah.isEmpty) return <PembayaranTertunda>[];
    try {
      final list = jsonDecode(mentah);
      if (list is! List) return <PembayaranTertunda>[];
      return list
          .map(PembayaranTertunda.dariJson)
          .whereType<PembayaranTertunda>()
          .toList();
    } catch (_) {
      // Data rusak tidak boleh mengunci kasir; perlakukan sebagai kosong.
      return <PembayaranTertunda>[];
    }
  }

  Future<void> _tulis(List<PembayaranTertunda> daftar) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setString(
        kunciPrefs, jsonEncode(daftar.map((e) => e.toJson()).toList()));
  }

  /// Catat satu pembayaran yang nasibnya tidak diketahui. Idempoten terhadap
  /// [PembayaranTertunda.kode] — percobaan ulang tidak menggandakan antrean.
  Future<void> catat(PembayaranTertunda p) async {
    final daftar = await muat();
    if (daftar.any((e) => e.kode == p.kode)) return;
    daftar.add(p);
    await _tulis(daftar);
  }

  Future<void> hapus(String kode) async {
    final daftar = await muat();
    daftar.removeWhere((e) => e.kode == kode);
    await _tulis(daftar);
  }

  /// Kirim ulang payload yang sama untuk mengetahui nasib [p].
  ///
  /// Baris antrean dihapus begitu nasibnya pasti — termasuk saat ditolak,
  /// karena penolakan membuktikan transaksi tidak pernah terbukukan.
  Future<HasilPeriksaUlang> periksaUlang(
      PembayaranTertunda p, PanggilBayar panggil) async {
    Map<String, dynamic> r;
    try {
      r = await panggil('apotik_bayar', p.payload);
    } on ApiException catch (e) {
      if (e.offline) {
        return HasilPeriksaUlang(StatusPeriksaUlang.masihTidakPasti,
            'Server masih belum dapat dihubungi: ${e.pesan}');
      }
      // Penolakan bisnis lewat exception: kode tidak dikenali server, jadi
      // transaksi tidak terbukukan.
      await hapus(p.kode);
      return HasilPeriksaUlang(StatusPeriksaUlang.ditolak, e.pesan);
    } catch (e) {
      return HasilPeriksaUlang(
          StatusPeriksaUlang.masihTidakPasti, 'Belum dapat dipastikan: $e');
    }

    final sukses = r['status'] == '00' || r['status'] == 'success';
    if (!sukses) {
      await hapus(p.kode);
      return HasilPeriksaUlang(StatusPeriksaUlang.ditolak,
          '${r['description'] ?? 'Ditolak server.'}');
    }
    await hapus(p.kode);
    final kodeTrx = '${r['kode'] ?? ''}';
    if (r['idempoten'] == true) {
      return HasilPeriksaUlang(StatusPeriksaUlang.sudahTerbukukan,
          'Transaksi $kodeTrx ternyata SUDAH terbukukan sejak kiriman pertama.',
          kodeTransaksi: kodeTrx);
    }
    return HasilPeriksaUlang(StatusPeriksaUlang.baruTerbukukan,
        'Transaksi $kodeTrx baru terbukukan oleh kiriman ulang ini.',
        kodeTransaksi: kodeTrx);
  }
}
