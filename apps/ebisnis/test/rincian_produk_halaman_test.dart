import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/screens/laporan_transaksi_screen.dart';

/// Aturan berhenti pengambilan halaman pada ekspor "Rincian Produk Terjual".
///
/// Laporan ini memaginasi TRANSAKSI sementara barisnya adalah ITEM, sehingga
/// batas berhentinya tidak boleh memakai jumlah baris (helper laporan lain).
/// Salah menghitung di sini membuat PDF/Excel berhenti sebelum halaman terakhir
/// dan hasilnya tampak berhasil padahal terpotong.
void main() {
  test('periode kosong tetap satu halaman', () {
    expect(totalHalamanRincian(0, 100), 1);
  });

  test('satu transaksi = satu halaman', () {
    expect(totalHalamanRincian(1, 100), 1);
  });

  test('tepat satu halaman penuh tidak menambah halaman', () {
    expect(totalHalamanRincian(100, 100), 1);
  });

  test('lebih satu transaksi dari sehalaman = dua halaman', () {
    expect(totalHalamanRincian(101, 100), 2);
  });

  test('250 transaksi = tiga halaman (halaman terakhir tidak hilang)', () {
    expect(totalHalamanRincian(250, 100), 3);
  });

  test('ukuran halaman tidak sah tidak membuat pembagian nol', () {
    expect(totalHalamanRincian(250, 0), 1);
  });
}
