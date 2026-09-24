import 'dart:convert';

/// HPP master per satuan dasar, bukan snapshot harga pada waktu opname.
class HppOpname {
  static double? nilai(Map<String, dynamic> produk, Object? produkId) {
    if (produkId == null || '${produk['produkId']}' != '$produkId') return null;
    final raw = produk['hargaBeli'];
    final nilai = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return nilai != null && nilai.isFinite && nilai >= 0 ? nilai : null;
  }

  static String kunci(List<Object?> konteks, Map<String, dynamic> row) =>
      'so:hpp:v1:${jsonEncode([...konteks, row['produkId'], row['kode']])}';

  /// Maksimal tiga pembacaan bersamaan; setiap produk hanya dibaca sekali.
  /// Pembaca menyajikan cache dahulu, kemudian respons server. Tidak ada mutasi.
  static Future<void> muat(
    List<Map<String, dynamic>> rows, {
    required bool Function() aktif,
    required Future<void> Function(
            Map<String, dynamic>, void Function(Map<String, dynamic>))
        baca,
    required void Function(Object, double?, bool) onData,
  }) async {
    final unik = <Object, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['produkId'];
      if (id != null && '${row['kode'] ?? ''}'.trim().isNotEmpty) {
        unik[id] = row;
      }
    }
    final antrean = unik.values.toList();
    var indeks = 0;
    Future<void> pekerja() async {
      while (aktif() && indeks < antrean.length) {
        final row = antrean[indeks++];
        try {
          await baca(row, (produk) {
            if (aktif()) {
              onData(row['produkId'], nilai(produk, row['produkId']),
                  produk['offline'] == true);
            }
          });
        } catch (_) {
          // Cache yang telah tampil dipertahankan ketika jaringan gagal.
          // Tanpa cache, UI tetap menunjukkan belum tersedia, bukan Rp 0.
        }
      }
    }

    await Future.wait(List.generate(3, (_) => pekerja()));
  }
}
