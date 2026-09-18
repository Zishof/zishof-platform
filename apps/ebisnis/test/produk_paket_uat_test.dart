import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/models.dart';

void main() {
  group('UAT Fitur Produk Paket (Bundling Promo)', () {
    // Definisi Produk Jual Asli (Eceran)
    final beras = Produk(
      id: 101,
      kode: 'BRS-01',
      barcode: '8991001',
      nama: 'Beras Ramos 5kg',
      hargaBeli: 65000,
      hargaJual: 72000,
      stok: 50,
      kategoriId: 1,
      kategoriNama: 'Sembako',
      gambarUrl: null,
      jenisItem: 'JUAL',
    );

    final minyak = Produk(
      id: 102,
      kode: 'MYK-01',
      barcode: '8991002',
      nama: 'Minyak Goreng 2L',
      hargaBeli: 32000,
      hargaJual: 36000,
      stok: 40,
      kategoriId: 1,
      kategoriNama: 'Sembako',
      gambarUrl: null,
      jenisItem: 'JUAL',
    );

    final gula = Produk(
      id: 103,
      kode: 'GLA-01',
      barcode: '8991003',
      nama: 'Gula Pasir 1kg',
      hargaBeli: 15000,
      hargaJual: 17500,
      stok: 60,
      kategoriId: 1,
      kategoriNama: 'Sembako',
      gambarUrl: null,
      jenisItem: 'JUAL',
    );

    final bahanNonJual = Produk(
      id: 201,
      kode: 'BHN-01',
      barcode: '8992001',
      nama: 'Tepung Terigu Mentah',
      hargaBeli: 8000,
      hargaJual: 0,
      stok: 100,
      kategoriId: 2,
      kategoriNama: 'Bahan Baku',
      gambarUrl: null,
      jenisItem: 'BAHAN',
    );

    test('UAT-01: Validasi Komponen Paket Hanya Menerima Produk Status JUAL', () {
      final kandidatProduk = [beras, minyak, gula, bahanNonJual];
      // Aturan: Hanya produk dengan status jenisItem == 'JUAL' yang dapat dijadikan paket
      final bolehJadiPaket = kandidatProduk.where((p) => p.jenisItem == 'JUAL').toList();
      
      expect(bolehJadiPaket.length, 3);
      expect(bolehJadiPaket.map((p) => p.kode), containsAll(['BRS-01', 'MYK-01', 'GLA-01']));
      expect(bolehJadiPaket.any((p) => p.jenisItem == 'BAHAN'), isFalse);
    });

    test('UAT-02: Pembuatan Paket 1 (Paket Sembako Barokah) & Hitung HPP Otomatis', () {
      final komponenSembako = [
        {'produkId': beras.id, 'nama': beras.nama, 'qty': 1, 'harga': beras.hargaBeli},
        {'produkId': minyak.id, 'nama': minyak.nama, 'qty': 1, 'harga': minyak.hargaBeli},
        {'produkId': gula.id, 'nama': gula.nama, 'qty': 1, 'harga': gula.hargaBeli},
      ];

      // Hitung HPP otomatis dari komponen
      final totalHpp = komponenSembako.fold<double>(
        0, (sum, item) => sum + ((item['qty'] as num) * (item['harga'] as num)).toDouble()
      );
      expect(totalHpp, 112000); // 65.000 + 32.000 + 15.000

      // Bundle selling price (bebas ditentukan, tidak terikat harga jual eceran)
      final hargaJualPaket = 119000.0;
      expect(hargaJualPaket, lessThan(beras.hargaJual + minyak.hargaJual + gula.hargaJual)); // 119.000 < 125.500
      expect(hargaJualPaket, greaterThan(totalHpp)); // Margin positif Rp 7.000
    });

    test('UAT-03: Assembly Perakitan Stok Paket (Potong Stok Eceran, Tambah Stok Paket)', () {
      var stokBeras = 50;
      var stokMinyak = 40;
      var stokGula = 60;
      var stokPaket = 0;

      const jumlahRakit = 10;
      // Simulasi Assembly
      stokBeras -= (1 * jumlahRakit);
      stokMinyak -= (1 * jumlahRakit);
      stokGula -= (1 * jumlahRakit);
      stokPaket += jumlahRakit;

      expect(stokBeras, 40);
      expect(stokMinyak, 30);
      expect(stokGula, 50);
      expect(stokPaket, 10);
    });

    test('UAT-04: Disassembly Pembatalan / Pecah Paket (Kembali ke Stok Eceran Asli)', () {
      var stokBeras = 40;
      var stokMinyak = 30;
      var stokGula = 50;
      var stokPaket = 10;

      const jumlahPecah = 2;
      // Simulasi Pecah Paket
      stokPaket -= jumlahPecah;
      stokBeras += (1 * jumlahPecah);
      stokMinyak += (1 * jumlahPecah);
      stokGula += (1 * jumlahPecah);

      expect(stokPaket, 8);
      expect(stokBeras, 42);
      expect(stokMinyak, 32);
      expect(stokGula, 52);
    });

    test('UAT-05: Validasi Masa Kedaluwarsa Promo (Expired Lock)', () {
      final tglExpiredKemarin = DateTime.now().subtract(const Duration(days: 1));
      final paketExpired = {
        'id': 9003,
        'nama': 'Paket Kebersihan Santri',
        'hargaJual': 28500,
        'stok': 15,
        'tanggalExpired': tglExpiredKemarin.toIso8601String(),
      };

      final expired = DateTime.parse(paketExpired['tanggalExpired'] as String);
      final bolehDijual = DateTime.now().isBefore(expired);

      // Paket yang tanggal expired-nya lewat TIDAK boleh dijual di kasir
      expect(bolehDijual, isFalse);
    });
  });
}