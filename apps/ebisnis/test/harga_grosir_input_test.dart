import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/screens/harga_grosir_editor.dart';

/// Kontrak input editor Harga Grosir (umpan balik gambar 31-08).
///
/// Aturan yang "dibuat" pemilik tidak pernah muncul karena kolom ambang
/// menerima TEKS (nama produk) lalu server menolaknya diam-diam. Parser ini
/// jadi penjaga pertama: teks tanpa angka -> 0 (dialog menolak menyimpan),
/// sedangkan angka ber-pemisah ribuan Indonesia terbaca benar.
void main() {
  test('angka polos', () {
    expect(angkaRupiahGrosir('6'), 6);
    expect(angkaRupiahGrosir('1200000'), 1200000);
  });

  test('pemisah ribuan titik (Indonesia)', () {
    expect(angkaRupiahGrosir('1.200.000'), 1200000);
    expect(angkaRupiahGrosir('4.500.000'), 4500000);
    expect(angkaRupiahGrosir('1.200'), 1200);
  });

  test('desimal koma dan campuran', () {
    expect(angkaRupiahGrosir('1200,5'), 1200.5);
    expect(angkaRupiahGrosir('1.200.000,5'), 1200000.5);
    expect(angkaRupiahGrosir('1,200,000'), 1200000);
  });

  test('prefiks/spasi diabaikan', () {
    expect(angkaRupiahGrosir('Rp 65.000'), 65000);
    expect(angkaRupiahGrosir('  12000  '), 12000);
  });

  test('teks tanpa angka -> 0 sehingga dialog menolak menyimpan', () {
    expect(angkaRupiahGrosir('Kecap Manis 100g Per Dus'), 0);
    expect(angkaRupiahGrosir('Per Dus'), 0);
    expect(angkaRupiahGrosir(''), 0);
    expect(angkaRupiahGrosir('-'), 0);
  });
}
