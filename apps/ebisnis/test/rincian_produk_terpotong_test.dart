import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';

/// Penanda "hasil tidak lengkap" pada pengambilan rincian produk.
///
/// Ekspor yang diam-diam terpotong lebih berbahaya daripada ekspor yang gagal:
/// angkanya terlihat wajar dan tetap dipakai untuk mengambil keputusan. Karena
/// itu hasil pengambilan membawa penanda tersendiri, bukan sekadar daftar baris.
void main() {
  test('hasil lengkap tidak ditandai terpotong', () {
    const hasil = HasilBarisRincian(<Map<String, dynamic>>[], false);
    expect(hasil.terpotong, isFalse);
    expect(hasil.baris, isEmpty);
  });

  test('hasil yang menyentuh batas halaman ditandai terpotong', () {
    const hasil = HasilBarisRincian(<Map<String, dynamic>>[], true);
    expect(hasil.terpotong, isTrue);
  });

  test('baris yang dibawa tetap dapat dirangkum menjadi rekap', () {
    final hasil = HasilBarisRincian([
      {'idTransaksi': 1, 'produkKode': 'A', 'produkNama': 'Kopi', 'qty': 2, 'total': 4000},
    ], true);
    final rekap = rekapProdukDariRincian(hasil.baris);
    expect(rekap.length, 1);
    expect(rekap.first['qty'], 2);
    // Penanda terpotong TIDAK boleh hilang hanya karena rekapnya berhasil dibuat.
    expect(hasil.terpotong, isTrue);
  });
}
