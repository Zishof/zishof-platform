import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart';
import '../api_client.dart';
import '../sesi.dart';
import 'master_offline.dart';

/// Menjaga stok hasil opname konsisten pada seluruh perangkat kasir tanpa
/// mengunduh ulang seluruh katalog produk. Server mengirim jurnal perubahan
/// setelah cursor terakhir; perangkat hanya menambal kolom stok di SQLite.
class SinkronStokOpname {
  SinkronStokOpname._();

  static Timer? _timer;
  static bool _berjalan = false;
  static const interval = Duration(seconds: 15);

  static void mulai() {
    _timer ??= Timer.periodic(interval, (_) => jalankan());
    unawaited(jalankan());
  }

  static void berhenti() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> jalankan({bool lemparGalat = false}) async {
    if (_berjalan) return;
    final tokoId = Sesi.instance.idTokoTerpilih;
    if (tokoId == null) return;
    _berjalan = true;
    try {
      final kunciVersi = 'sinkron:stok-opname:versi:$tokoId';
      final mentah = await CoreDb.instance.ambilCacheReferensi(kunciVersi);
      var versi = 0;
      if (mentah != null && mentah.isNotEmpty) {
        try {
          final nilai = jsonDecode(mentah);
          versi = nilai is num ? nilai.toInt() : int.tryParse('$nilai') ?? 0;
        } catch (_) {
          versi = int.tryParse(mentah) ?? 0;
        }
      }
      final hasil = await ApiClient.instance.aksi('so_perubahan_stok', {
        'setelah_id': versi,
        'limit': 500,
      });
      final data = (hasil['data'] as List?) ?? const [];
      var berubah = 0;
      for (final item in data) {
        if (item is! Map) continue;
        final produkId = (item['produkId'] as num?)?.toInt();
        final stok = item['stok'] as num?;
        if (produkId == null || stok == null) continue;
        await CoreDb.instance.produkCachePerbaruiStok(produkId, stok);
        berubah++;
      }
      final versiBaru = (hasil['versiTerakhir'] as num?)?.toInt() ?? versi;
      if (versiBaru >= versi) {
        await CoreDb.instance
            .simpanCacheReferensi(kunciVersi, jsonEncode(versiBaru));
      }
      if (berubah > 0) MasterOffline.revisiBaris.value++;
    } catch (_) {
      if (lemparGalat) rethrow;
      // Sinkron periodik tidak mengganggu transaksi kasir. Tick berikutnya
      // mencoba kembali memakai cursor lama sehingga tidak ada perubahan hilang.
    } finally {
      _berjalan = false;
    }
  }
}
