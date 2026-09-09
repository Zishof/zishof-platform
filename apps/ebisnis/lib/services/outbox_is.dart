import 'dart:convert';

import 'package:core_db/core_db.dart';

import '../api_client.dart';
import 'master_offline.dart';

/// <h3>Outbox typed varian Inventory &amp; Sales (P7).</h3>
///
/// Untuk perintah IDEMPOTEN (wajib ber-`kode_unik`): catat di perangkat lebih
/// dahulu, baru coba kirim ke server. Gangguan jaringan, timeout, HTTP 5xx,
/// atau jawaban gateway yang rusak mempertahankan baris PENDING di tabel
/// `outbox_is` (core_db v4, TERPISAH dari `transaksi_pending` POS -- flush POS
/// mengirim semua barisnya ke aksi 'bayar') dan dikirim ulang oleh [flush]
/// saat online. Penolakan bisnis server TIDAK diantre -- dilempar lagi ke
/// pemanggil supaya user melihat pesannya (baris antrean lama yang ditolak
/// server ditandai GAGAL permanen, tidak diretry membabi buta).
///
/// Server aman dari duplikat: retry memakai kode_unik yang sama -> replay
/// idempoten, bukan pencatatan kedua.
class OutboxIs {
  OutboxIs._();

  /// Aksi yang BOLEH diantre offline -- semuanya idempoten kode_unik di
  /// server, KECUALI si_print_log_create: register cetak append-only yang
  /// server-nya belum men-dedup kode_unik. Duplikat barisnya hanya mungkin
  /// bila aplikasi mati tepat di antara kirim dan tandai-sukses -- dapat
  /// diterima utk log; kode_unik tetap dikirim supaya dedup server bisa
  /// menyusul tanpa mengubah klien.
  static const aksiDidukung = {
    'si_collection_create',
    'si_expense_create',
    'si_print_log_create',
    'si_trip_purchase_link',
  };

  /// Catat [aksi] lebih dahulu; bila server belum siap, pertahankan antrean dan
  /// kembalikan `{offline: true}`. Urutan ini mencegah data hilang bila aplikasi
  /// berhenti tepat ketika permintaan jaringan sedang berlangsung.
  static Future<Map<String, dynamic>> kirimAtauAntre(
      String aksi, Map<String, dynamic> body) async {
    assert(aksiDidukung.contains(aksi),
        'Aksi $aksi tidak terdaftar sbg idempoten -- jangan diantre offline.');
    assert('${body['kode_unik'] ?? ''}'.isNotEmpty,
        'kode_unik wajib ada utk outbox idempoten.');
    final id = await CoreDb.instance
        .outboxIsTambah(aksi, '${body['kode_unik']}', jsonEncode(body));
    try {
      final hasil = await ApiClient.instance.aksi(aksi, body);
      await CoreDb.instance.outboxIsTandaiSukses(id);
      return hasil;
    } on ApiException catch (e) {
      if (!MasterOffline.dapatDicobaUlang(e)) {
        await CoreDb.instance.outboxIsTandaiGagal(id, e.pesan);
        rethrow; // penolakan bisnis -> tampilkan ke user, payload tetap ada.
      }
      await CoreDb.instance.outboxIsCatatPercobaan(id, e.pesan);
      return {'status': 'success', 'offline': true};
    }
  }

  /// Kirim ulang seluruh antrean PENDING. Aman dipanggil kapan pun (no-op saat
  /// kosong); berhenti diam-diam pada kegagalan jaringan pertama (masih
  /// offline). Return jumlah yang berhasil terkirim.
  static Future<int> flush() async {
    final pending = await CoreDb.instance.outboxIsPending();
    var terkirim = 0;
    for (final row in pending) {
      final id = (row['id'] as num).toInt();
      final aksi = '${row['aksi']}';
      Map<String, dynamic> body;
      try {
        body = Map<String, dynamic>.from(
            jsonDecode('${row['payload_json']}') as Map);
      } catch (e) {
        await CoreDb.instance.outboxIsTandaiGagal(id, 'Payload rusak: $e');
        continue;
      }
      try {
        await ApiClient.instance.aksi(aksi, body);
        await CoreDb.instance.outboxIsTandaiSukses(id);
        terkirim++;
      } on ApiException catch (e) {
        if (MasterOffline.dapatDicobaUlang(e)) {
          await CoreDb.instance.outboxIsCatatPercobaan(id, e.pesan);
          // Server/gateway belum dapat dipercaya. Baris tetap PENDING dan
          // sapuan berikutnya melanjutkan dengan kode unik yang sama.
          if (e.offline ||
              e.statusHttp == 408 ||
              e.statusHttp == 429 ||
              (e.statusHttp ?? 0) >= 500) {
            break;
          }
          continue;
        }
        // Server menolak scr bisnis -> permanen (terlihat, tidak diretry).
        await CoreDb.instance.outboxIsTandaiGagal(id, e.pesan);
      }
    }
    return terkirim;
  }
}
