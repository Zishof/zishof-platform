import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Verifikasi Item Request Pengguna (18-19 September 2026)', () {
    test('1. Rincian penerimaan per kasir memisahkan porsi metode dari total nota', () {
      final file = File('lib/screens/laporan_transaksi_screen.dart');
      final content = file.readAsStringSync();

      expect(content.contains('barisEksporRincianPenerimaan'), isTrue);
      expect(content.contains('nominalMetode'), isTrue);
      expect(content.contains('Total nota:'), isTrue);
      expect(content.contains('Kategori'), isTrue);
    });

    test('2. Retur pembelian memiliki pencarian nomor faktur dan supplier', () {
      final file = File('lib/screens/retur_pembelian_screen.dart');
      final content = file.readAsStringSync();

      expect(content.contains('Cari nomor faktur atau supplier...'), isTrue);
      expect(content.contains('nomorFaktur'), isTrue);
      expect(content.contains('namaSupplier'), isTrue);
    });

    test('3. Tabel dan kartu Produk menampilkan Satuan dan Supplier', () {
      final file = File('lib/screens/produk_screen.dart');
      final content = file.readAsStringSync();

      expect(content.contains("'SATUAN'"), isTrue);
      expect(content.contains("'SUPPLIER'"), isTrue);
      expect(content.contains('produk.satuanNama'), isTrue);
      expect(content.contains('produk.pemasokNama'), isTrue);
    });

    test('4. Query LaporanKantinUtil.java di AIS memiliki kolom Kategori untuk pnj_per_barang', () {
      final file = File('C:/opt/AIS/ais/src/main/src/ais/action/master/koperasi/helper/LaporanKantinUtil.java');
      final content = file.readAsStringSync();

      expect(content.contains('left join koperasi.jenis_produk jp on jp.id=pr.jenis_produk'), isTrue);
      expect(content.contains('coalesce(nullif(trim(jp.nama),\'\'),\'Umum\')'), isTrue);
      expect(content.contains('new Kolom("Kategori","text")'), isTrue);
    });
  });
}
