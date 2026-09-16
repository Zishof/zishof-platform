const kelompokTunaiTransferQris = 'Tunai/Transfer/QRIS';

/// Kelompok eksklusif: nota tidak dimasukkan ke dua kelompok sekaligus.
const metodeRincianProduk = <String>[
  'Voucher Santri',
  'Voucher Pejuang',
  kelompokTunaiTransferQris,
  'Campuran (split)',
  'Lainnya / belum diketahui',
];

String kelompokMetodeProduk(Object? nilai) {
  final nama = (nilai ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (nama.contains('+')) {
    final kelompok = nama.split('+').map(kelompokMetodeProduk).toSet();
    if (kelompok.length == 1 &&
        metodeRincianProduk.take(3).contains(kelompok.single)) {
      return kelompok.single;
    }
    return 'Campuran (split)';
  }
  if (RegExp(r'\bsplit\b').hasMatch(nama)) {
    return 'Campuran (split)';
  }
  final voucherPejuang = RegExp(r'\bvoucher[\s_-]+pejuang\b').hasMatch(nama);
  final voucherSantri = RegExp(r'\bvoucher[\s_-]+santri\b').hasMatch(nama);
  final transfer = RegExp(r'\b(transfer|tf|qris|qrs)\b').hasMatch(nama);
  final tunai = RegExp(r'^(tunai|cash)(\s+rp\b.*)?$').hasMatch(nama);
  final cocok = [voucherSantri, voucherPejuang, transfer || tunai];
  if (cocok.where((v) => v).length > 1) return 'Campuran (split)';
  for (var i = 0; i < cocok.length; i++) {
    if (cocok[i]) return metodeRincianProduk[i];
  }
  return 'Lainnya / belum diketahui';
}

List<Map<String, dynamic>> saringMetodeRincianProduk(
    List<Map<String, dynamic>> rows, String metode) {
  if (metode.isEmpty) return rows;
  return rows
      .where((r) => kelompokMetodeProduk(r['metode']) == metode)
      .toList();
}

/// Paginasi transaksi, bukan item: semua produk dalam satu nota tetap bersama.
Map<String, dynamic> halamanRincianProduk(
    List<Map<String, dynamic>> rows, int halaman, int ukuran) {
  final nota = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final id = r['idTransaksi'] ?? r['kodeNota'] ?? r['nomorNota'];
    final key = id == null || '$id'.trim().isEmpty ? 'baris:$i' : 'nota:$id';
    nota.putIfAbsent(key, () => []).add(r);
  }
  final size = ukuran > 0 ? ukuran : 10;
  final page = halaman > 0 ? halaman : 1;
  return {
    'total': nota.length,
    'data': nota.values
        .skip((page - 1) * size)
        .take(size)
        .expand((v) => v)
        .toList(),
  };
}
