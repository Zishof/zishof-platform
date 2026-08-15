import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_device/core_device.dart';

import '../api_client.dart';
import '../sesi.dart';
import 'pelayanan_transaksi.dart';

/// Pengirim ulang transaksi POS yang sudah ditulis ke SQLite sebelum request
/// pertama dilakukan. Satu instance hidup selama aplikasi berjalan sehingga
/// retry tidak bergantung pada layar Kasir sedang terbuka atau tombol Sinkron
/// ditekan pengguna.
///
/// Hanya kegagalan jaringan/timeout yang terus dicoba. Penolakan bisnis yang
/// pasti (stok/saldo/hak akses/payload tidak valid) ditandai GAGAL agar tidak
/// membanjiri server setiap sepuluh menit. Semua retry memakai `kode_unik`
/// asli, sehingga aman terhadap respons yang hilang setelah server sempat
/// menyimpan transaksi.
class TransaksiOutboxService {
  TransaksiOutboxService._();

  static final TransaksiOutboxService instance = TransaksiOutboxService._();
  static const intervalRetry = Duration(minutes: 10);

  Timer? _timer;
  Future<HasilSinkronisasiTransaksi>? _prosesAktif;

  void mulai() {
    if (_timer != null) return;
    unawaited(sinkronkan());
    _timer = Timer.periodic(intervalRetry, (_) => unawaited(sinkronkan()));
  }

  Future<HasilSinkronisasiTransaksi> sinkronkan() {
    final aktif = _prosesAktif;
    if (aktif != null) return aktif;
    final proses = _sinkronkanInternal();
    _prosesAktif = proses;
    return proses.whenComplete(() => _prosesAktif = null);
  }

  Future<HasilSinkronisasiTransaksi> _sinkronkanInternal() async {
    if (!ApiClient.instance.sudahLogin) {
      return const HasilSinkronisasiTransaksi(total: 0, berhasil: 0);
    }

    final pending = await CoreDb.instance.transaksiPendingBelumSinkron(
      akunKunci: Sesi.instance.userId,
      tokoId: Sesi.instance.tokoId,
      idPerangkat: IdentitasMesin.instance.idMesin,
    );
    var berhasil = 0;
    for (final row in pending) {
      final kodeUnik = '${row['kode_unik'] ?? ''}';
      Map<String, dynamic> payload;
      try {
        payload = Map<String, dynamic>.from(
            jsonDecode('${row['payload_json']}') as Map);
      } catch (e) {
        await CoreDb.instance.tandaiTransaksiDitolak(
            kodeUnik, 'Payload lokal rusak dan tidak dapat dikirim: $e');
        continue;
      }

      // Proteksi migrasi utk baris lama yang belum memiliki akun_kunci.
      // Jangan pernah kirim transaksi milik akun/toko lain memakai token
      // pengguna yang sedang login sekarang.
      final kasirPayload = '${payload['kasir'] ?? ''}'.trim();
      final tokoPayload = (payload['tokoId'] ?? payload['idToko']) as Object?;
      final tokoPayloadInt = tokoPayload is num
          ? tokoPayload.toInt()
          : int.tryParse('$tokoPayload');
      if ((kasirPayload.isNotEmpty && kasirPayload != Sesi.instance.userId) ||
          (tokoPayloadInt != null && tokoPayloadInt != Sesi.instance.tokoId) ||
          ('${payload['id_perangkat'] ?? ''}'.trim().isNotEmpty &&
              '${payload['id_perangkat']}'.trim() !=
                  IdentitasMesin.instance.idMesin)) {
        continue;
      }

      try {
        final hasilBayar = await ApiClient.instance.aksi('bayar', payload);
        await PelayananTransaksi.tandaiJikaPerlu(
          payload: payload,
          hasilBayar: hasilBayar,
          percobaanCari: 1,
        );
        await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
        berhasil++;
      } catch (e) {
        final pesan = e.toString();
        if (pesan.toLowerCase().contains('sudah tercatat')) {
          await CoreDb.instance.tandaiTransaksiSinkron(kodeUnik);
          berhasil++;
          continue;
        }
        await CoreDb.instance.tandaiTransaksiGagal(kodeUnik, pesan);
        if (e is ApiException && e.offline) {
          // Koneksi masih putus. Berhenti agar baris berikutnya tidak ikut
          // menghasilkan error yang sama; timer akan mencoba lagi 10 menit.
          break;
        }
        await CoreDb.instance.tandaiTransaksiDitolak(kodeUnik, pesan);
      }
    }
    return HasilSinkronisasiTransaksi(
        total: pending.length, berhasil: berhasil);
  }
}

class HasilSinkronisasiTransaksi {
  final int total;
  final int berhasil;

  const HasilSinkronisasiTransaksi(
      {required this.total, required this.berhasil});
}
