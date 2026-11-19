import 'dart:io';
import 'dart:typed_data';

import 'package:ebisnis/screens/konfigurasi/dbf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PetaDbfLegacy mengenali seluruh berkas DBF 5-Inventory termasuk batchno, opname, akun, hutang, piutang', () {
    expect(PetaDbfLegacy.jenisDariNamaFile('account.dbf'), 'akun_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('SUPPLIER.DBF'), 'supplier');
    expect(PetaDbfLegacy.jenisDariNamaFile('CUSTOMER.DBF'), 'customer');
    expect(PetaDbfLegacy.jenisDariNamaFile('SALES.DBF'), 'sales');
    expect(PetaDbfLegacy.jenisDariNamaFile('STOK.DBF'), 'produk');
    expect(PetaDbfLegacy.jenisDariNamaFile('batchno.dbf'), 'batch_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('dataopn.dbf'), 'opname');
    expect(PetaDbfLegacy.jenisDariNamaFile('masterbl.DBF'), 'harga_beli');
    expect(PetaDbfLegacy.jenisDariNamaFile('masterjl.dbf'), 'harga_jual');
    expect(PetaDbfLegacy.jenisDariNamaFile('BELI.DBF'), 'pembelian_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('JUAL.DBF'), 'penjualan_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('Tran_Hut.DBF'), 'hutang_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('Tran_Piut.DBF'), 'piutang_legacy');
    expect(PetaDbfLegacy.jenisDariNamaFile('PIUTSEMEN.DBF'), 'piutang_legacy');
  });

  test('normalisasi menjaga kontrak kunci backend Java (baris_ke, batch_legacy, harga_jual_tunai null, diskon beli, bayar hutang & piutang negatif)', () {
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

    final batch = PetaDbfLegacy.normalisasi('batch_legacy', {
      '_BARIS_KE': 3,
      'KODEBRG': '000301',
      'NOBATCH': 'LOT-2026A',
      'TGLEXP': '2028-06-30',
      'JUMLAH': 12,
    })!;
    expect(batch['baris_ke'], '3');
    expect(batch['kode_produk'], '000301');
    expect(batch['nomor_batch'], 'LOT-2026A');
    expect(batch['tanggal_expired'], '2028-06-30');

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

    final bayarHut = PetaDbfLegacy.normalisasi('pembayaran_hutang_legacy', {
      '_BARIS_KE': 45,
      'NOFAKTUR': 'FH-009',
      'KODESUPPL': 'S01',
      'TANGGAL': '2026-01-05',
      'TGLBAYAR': '',
      'JUMLAH': -250000,
      'KETBAYAR': 'RET',
      'NOMERBG': '',
      'NAMABANK': '',
      'TANGGALBG': null,
    })!;
    expect(bayarHut['nilai'], 250000.0);
    expect(bayarHut['tanggal_bayar'], '2026-01-05');

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

  test('DbfParser membaca arsip nyata 5-Inventory termasuk mode sertakanTerhapus untuk histori lunas', () async {
    const base = r'C:\Users\USER\Documents\5-Inventory--\5-Inventory';
    if (!await Directory(base).exists()) return;

    final stokBytes = Uint8List.fromList(await File('$base\\STOK.DBF').readAsBytes());
    final stokTbl = DbfParser.parse('STOK.DBF', stokBytes);
    expect(stokTbl.rows.length, 627);
    expect(stokTbl.rows.first['_BARIS_KE'], 1);

    final batchBytes = Uint8List.fromList(await File('$base\\batchno.dbf').readAsBytes());
    final batchTbl = DbfParser.parse('batchno.dbf', batchBytes);
    expect(batchTbl.rows.length, 1257);

    final hutBytes = Uint8List.fromList(await File('$base\\Tran_Hut.DBF').readAsBytes());
    final hutAktif = DbfParser.parse('Tran_Hut.DBF', hutBytes);
    final hutSemua = DbfParser.parse('Tran_Hut.DBF', hutBytes, sertakanTerhapus: true);
    expect(hutAktif.rows.length, 68);
    expect(hutSemua.rows.length, 8865);
  });
}
