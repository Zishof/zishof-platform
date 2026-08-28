import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/uom_konversi.dart';

void main() {
  group('Kontrak UOM produk', () {
    test('membaca relasi UOM dasar dan pembelian dari katalog', () {
      final produk = Produk.fromJson(<String, dynamic>{
        'id': 10,
        'kode': 'AIR-330',
        'nama': 'Air Mineral 330 ml',
        'satuanId': 1,
        'satuanNama': 'Pcs',
        'satuanPembelianId': 2,
        'satuanPembelianNama': 'Dus 24',
      });

      expect(produk.satuanId, 1);
      expect(produk.satuanNama, 'Pcs');
      expect(produk.satuanPembelianId, 2);
      expect(produk.satuanPembelianNama, 'Dus 24');
    });

    test('katalog lama tanpa Purchase UOM tetap kompatibel', () {
      final produk = Produk.fromJson(<String, dynamic>{
        'id': 11,
        'kode': 'LEGACY',
        'nama': 'Produk Lama',
      });

      expect(produk.satuanId, isNull);
      expect(produk.satuanPembelianId, isNull);
      expect(produk.satuanPembelianNama, isEmpty);
    });

    test('preset kemasan dipisahkan dari UOM akuntansi', () {
      final produk = Produk.fromJson(<String, dynamic>{
        'id': 12,
        'kode': 'AIR-600',
        'nama': 'Air Mineral 600 ml',
        'satuanId': 1,
        'satuanNama': 'Pcs',
        'kemasan': [
          {
            'nama': 'Dus 24',
            'barcode': '899000024',
            'qtyDasar': 24,
            'aktif': true,
          }
        ],
      });

      expect(produk.satuanNama, 'Pcs');
      expect(produk.kemasan.single['qtyDasar'], 24);
      expect(produk.kemasan.single['barcode'], '899000024');
    });
  });

  group('Perhitungan konversi UOM', () {
    final pcs = <String, dynamic>{
      'nama': 'Pcs',
      'kategori': 'UNIT',
      'tipeKonversi': 'REFERENCE',
      'rasio': 1,
    };
    final dus = <String, dynamic>{
      'nama': 'Dus 24',
      'kategori': 'UNIT',
      'tipeKonversi': 'BIGGER',
      'rasio': 24,
    };
    final kg = <String, dynamic>{
      'nama': 'Kg',
      'kategori': 'BERAT',
      'tipeKonversi': 'REFERENCE',
      'rasio': 1,
    };
    final gram = <String, dynamic>{
      'nama': 'Gram',
      'kategori': 'BERAT',
      'tipeKonversi': 'SMALLER',
      'rasio': 1000,
    };

    test('10 Dus 24 menjadi 240 Pcs', () {
      expect(UomKonversi.konversi(jumlah: 10, dari: dus, ke: pcs), 240);
    });

    test('500 Gram menjadi 0.5 Kg', () {
      expect(UomKonversi.konversi(jumlah: 500, dari: gram, ke: kg), 0.5);
    });

    test('menolak konversi lintas kategori', () {
      expect(
        () => UomKonversi.konversi(jumlah: 1, dari: pcs, ke: kg),
        throwsFormatException,
      );
    });
  });
}
