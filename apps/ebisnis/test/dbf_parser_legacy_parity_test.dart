import 'dart:io';
import 'dart:typed_data';

import 'package:ebisnis/screens/konfigurasi/dbf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PetaDbfLegacy mengenali seluruh berkas DBF 5-Inventory termasuk opname, akun, hutang, piutang', () {
    expect(PetaDbfLegacy.jenisDariNamaFile('account.dbf'), 'akun_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('SUPPLIER.DBF'), 'supplier');
    expect(PetaDbfLegacy.jenisDariNamaFile('CUSTOMER.DBF'), 'customer');
    expect(PetaDbfLegacy.jenisDariNamaFile('SALES.DBF'), 'sales');
    expect(PetaDbfLegacy.jenisDariNamaFile('STOK.DBF'), 'produk');
    expect(PetaDbfLegacy.jenisDariNamaFile('dataopn.dbf'), 'opname');
    expect(PetaDbfLegacy.jenisDariNamaFile('masterbl.DBF'), 'harga_beli');
    expect(PetaDbfLegacy.jenisDariNamaFile('masterjl.dbf'), 'harga_jual');
    expect(PetaDbfLegacy.jenisDariNamaFile('BELI.DBF'), 'pembelian_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('JUAL.DBF'), 'penjualan_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('Tran_Hut.DBF'), 'hutang_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('Tran_Piut.DBF'), 'piutang_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('PIUTSEMEN.DBF'), 'piutang_legacy');
  });

  test('normalisasi menjaga kontrak kunci backend Java (baris_ke, harga_jual_tunai null, diskon beli, piutang negatif)', () {
    final prod = PetaDbfLegacy.normalisasi('produk', {
      '_BARIS_KE': 7,
      'KODEBRG': '000301',
      'NAMABRG': 'OBAT A',
      'SATUAN': 'BOX',
      'HARGABELI': 10000,
      'HARGAJUAL': 12500,
      'HARGAJUAL2': 0,
      'TGLHARGA': '2026-01-15',
      'STOKMINIM': 5,
      'AWAL': 10,
      'MASUK': 20,
      'KELUAR': -4,
    })!;
    expect(prod['baris_ke'], '7');
    expect(prod['harga_jual_tunai'], isNull);
    expect(prod['tanggal_harga'], '2026-01-15');
    expect(prod['stok_legacy'], 26.0);

    final beli = PetaDbfLegacy.normalisasi('pembelian_legacy', {
      '_BARIS_KE': 12,
      'NOFAKTUR': 'FB-001',
      'KODESUPPL': 'S01',
      'KODEBRG': '000301',
      'NAMABRG': 'OBAT A',
      'TANGGAL': '2026-02-01',
      'JUMLAH': 5,
      'HARGABELI': 9500,
      'HARGAASLI': 10000,
      'DISCOUNT': 5,
      'DISCOUNT2': 0,
      'NOBATCH': 'B1',
      'TGLEXP': '2028-01-01',
    })!;
    expect(beli['baris_ke'], '12');
    expect(beli['harga_bruto'], 10000.0);
    expect(beli['diskon_persen'], 5.0);
    expect(beli['diskon_nilai'], 0.0);

    final bayarPiut = PetaDbfLegacy.normalisasi('pembayaran_piutang_legacy', {
      '_BARIS_KE': 99,
      '_NAMA_FILE': 'Tran_Piut.DBF',
      'NOFAKTUR': '2601-000001',
      'KODECUST': '00001',
      'KODESALES': '01',
      'TANGGAL': '2026-01-10',
      'TGLBAYAR': '2026-01-25',
      'JUMLAH': -150000,
      'KETBAYAR': 'TUN',
      'NOMERBG': '',
      'NAMABANK': '',
      'TANGGALBG': null,
    })!;
    expect(bayarPiut['nilai'], 150000.0);
    expect(bayarPiut['baris_ke'], '99');
    expect(bayarPiut['sumber'], 'Tran_Piut.DBF');
  });

  test('DbfParser membaca arsip nyata 5-Inventory bila tersedia di mesin pengembangan', () async {
    const stokPath = r'C:\Users\USER\Documents\5-Inventory--\5-Inventory\STOK.DBF';
    if (!await File(stokPath).exists()) return;
    final bytes = Uint8List.fromList(await File(stokPath).readAsBytes());
    final tbl = DbfParser.parse('STOK.DBF', bytes);
    expect(tbl.rows.length, 627);
    expect(tbl.rows.first['_BARIS_KE'], 1);
  });
}
