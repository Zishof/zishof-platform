/// Pemeriksaan sebelum jawaban checkout boleh menandai jurnal lokal SYNCED.
/// Nomor yang sama saja bukan bukti bahwa barang dan pembayaran sudah diterima.
String? kendalaAckTransaksi(
    Map<String, dynamic> payload, Map<String, dynamic> hasil) {
  double? angka(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');
  final total = angka(hasil['total']);
  final diskon = angka(hasil['totalDiskon']);
  final baris = payload['transaksi'];
  if (total == null || diskon == null || baris is! List || baris.isEmpty) {
    return 'Jawaban server belum memuat total dan diskon yang dapat diverifikasi. '
        'Transaksi lokal tetap disimpan; periksa Riwayat Sinkronisasi.';
  }
  var subtotal = 0.0;
  for (final item in baris) {
    if (item is! Map) {
      return 'Rincian transaksi lokal tidak dapat diverifikasi.';
    }
    final harga = angka(item['harga']);
    final qty = angka(item['jumlah']);
    if (harga == null ||
        qty == null ||
        !harga.isFinite ||
        !qty.isFinite ||
        harga < 0 ||
        qty <= 0) {
      return 'Harga atau jumlah barang lokal tidak dapat diverifikasi.';
    }
    subtotal += harga * qty;
    final ekstra = item['ekstra'];
    if (ekstra is List) {
      for (final e in ekstra) {
        if (e is! Map) return 'Rincian ekstra tidak dapat diverifikasi.';
        final h = angka(e['harga']);
        final q = angka(e['jumlah']) ?? 1;
        if (h == null || !h.isFinite || !q.isFinite || h < 0 || q <= 0) {
          return 'Harga atau jumlah ekstra tidak dapat diverifikasi.';
        }
        subtotal += h * q * qty;
      }
    }
  }
  final pajak = angka(payload['pajak']) ?? 0;
  final seharusnya = (subtotal + pajak - diskon).clamp(0, double.infinity);
  if (!total.isFinite ||
      !diskon.isFinite ||
      diskon < 0 ||
      !pajak.isFinite ||
      (total - seharusnya).abs() >= 1) {
    return 'Total server berbeda dari rincian barang lokal. Cetak dan '
        'pengakuan sinkronisasi ditahan. Minta supervisor memeriksa nomor '
        '${payload['kodeUnik'] ?? ''} di Riwayat Sinkronisasi; '
        'jangan membuat transaksi pengganti.';
  }
  return null;
}
