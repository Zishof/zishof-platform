import 'package:ebisnis/screens/konfigurasi/dbf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BELI dan JUAL dikenali setelah seluruh master', () {
    expect(PetaDbfLegacy.jenisDariNamaFile(r'C:\legacy\BELI.DBF'),
        'pembelian_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile(r'C:\legacy\JUAL.DBF'),
        'penjualan_legacy');
    expect(PetaDbfLegacy.urutanImpor.indexOf('pembelian_legacy'),
        greaterThan(PetaDbfLegacy.urutanImpor.indexOf('produk')));
    expect(PetaDbfLegacy.urutanImpor.indexOf('penjualan_legacy'),
        greaterThan(PetaDbfLegacy.urutanImpor.indexOf('customer')));
  });

  test('normalisasi transaksi mempertahankan kunci rekonsiliasi dan nilai', () {
    final beli = PetaDbfLegacy.normalisasi('pembelian_legacy', {
      'NOFAKTUR': 'B-001',
      'KODESUPPL': 'S01',
      'KODEBRG': '000123',
      'NAMABRG': 'Barang Uji',
      'TANGGAL': '2026-08-16',
      'JUMLAH': 3.0,
      'HARGABELI': 1200.0,
      'NOBATCH': 'LOT-1',
      'TGLEXP': '2027-08-16',
    });
    expect(beli?['nomor_faktur'], 'B-001');
    expect(beli?['kode_produk'], '000123');
    expect(beli?['qty'], 3.0);

    final jual = PetaDbfLegacy.normalisasi('penjualan_legacy', {
      'NOFAKTUR': 'J-001',
      'KODECUST': 'C01',
      'KODESALES': '01',
      'KODEBRG': '000123',
      'TANGGAL': '2026-08-16',
      'JUMLAH': 2.0,
      'HARGABELI': 1200.0,
      'HARGAJUAL': 1800.0,
    });
    expect(jual?['nomor_faktur'], 'J-001');
    expect(jual?['kode_customer'], 'C01');
    expect(jual?['harga_jual'], 1800.0);
  });
}
