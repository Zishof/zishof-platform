import 'dart:io';

import 'package:ebisnis/services/faktur_penjualan_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FakturPenjualanData contohData() => FakturPenjualanData.dariSumber(
        detail: {
          'kode': 'AB260914001',
          'waktu': '2026-09-14T10:25:00',
          'pembeli': 'Divisi Tafaqquh',
          'kasirNama': 'Ika',
          'totalDiskon': 10000,
          'pajak': 19000,
          'pajakPersen': 10,
          'totalBiaya': 214000,
          'statusPembayaran': 'LUNAS',
          'keterangan': 'Pengganti faktur POS lama',
        },
        ringkasan: const {},
        items: const [
          {
            'kode': '105612',
            'nama': 'Paket Al-Miftah',
            'qty': 2,
            'satuan': 'PCS',
            'harga': 50000,
            'diskon': 5000,
          },
          {
            'kodeProduk': '105614',
            'namaProduk': 'Fathul Qorib',
            'jumlah': 1,
            'namaSatuan': 'PCS',
            'hargaJual': 100000,
          },
        ],
        toko: 'Toko Al Bahjah',
        alamat: 'Kab. Cirebon, Jawa Barat',
        telepon: '081122220557',
        metodePembayaran: 'Kasbon Divisi',
      );

  test('normalisasi faktur merekonsiliasi total otoritatif transaksi', () {
    final data = contohData();

    expect(data.nomor, 'AB260914001');
    expect(data.tanggal, '14 Sep 2026 10:25');
    expect(data.subtotal, 200000);
    expect(data.diskon, 10000);
    expect(data.ppn, 19000);
    expect(data.biayaLain, 5000);
    expect(data.total, 214000);
    expect(data.items.last.kode, '105614');
    expect(data.items.last.total, 100000);
    expect(data.lunas, isTrue);
  });

  test('snapshot lokal jumlah dan diskon baris tetap dapat menjadi faktur', () {
    final data = FakturPenjualanData.dariSumber(
      detail: const {'kode': 'LOKAL-1', 'totalBiaya': 9000},
      ringkasan: const {'pembeli': 'Umum', 'totalDiskon': 0},
      items: const [
        {
          'kode': 'P1',
          'nama': 'Produk Lokal',
          'jumlah': 2,
          'harga': 5000,
          'diskon': 1000
        },
      ],
      toko: 'Toko Offline',
      alamat: 'Cirebon',
      telepon: '',
      metodePembayaran: 'Tunai',
    );

    expect(data.items.single.qty, 2);
    expect(data.subtotal, 10000);
    expect(data.diskon, 1000);
    expect(data.total, 9000);
    expect(data.biayaLain, 0);
  });

  test('terbilang rupiah menghasilkan kalimat faktur', () {
    expect(terbilangRupiah(0), 'Nol rupiah');
    expect(terbilangRupiah(268732302),
        'Dua ratus enam puluh delapan juta tujuh ratus tiga puluh dua ribu tiga ratus dua rupiah');
  });

  test('dokumen faktur yang dihasilkan adalah PDF A4 valid', () async {
    final bytes = await buatDokumenFakturPenjualan(contohData()).save();

    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('tabel faktur panjang dapat dilanjutkan ke halaman berikutnya',
      () async {
    final data = FakturPenjualanData.dariSumber(
      detail: const {
        'kode': 'FAKTUR-PANJANG',
        'waktu': '2026-09-14T10:25:00',
        'pembeli': 'Pelanggan UAT',
      },
      ringkasan: const {},
      items: List.generate(
        80,
        (index) => {
          'kode': 'P${index + 1}',
          'nama': 'Produk pengujian baris ${index + 1}',
          'qty': index % 4 + 1,
          'satuan': 'PCS',
          'harga': 1000 + index * 100,
        },
      ),
      toko: 'Toko UAT',
      alamat: 'Cirebon',
      telepon: '',
      metodePembayaran: 'Tunai',
    );

    final bytes = await buatDokumenFakturPenjualan(data).save();
    expect(bytes.length, greaterThan(6000));
  });

  test('jalur UAT dapat menyimpan contoh faktur tanpa dialog native', () async {
    const dirUji = String.fromEnvironment('POS_TEST_PDF_DIR');
    if (dirUji.isEmpty) return;

    final path = await simpanFakturPenjualanPdf(contohData());

    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(File(path).lengthSync(), greaterThan(2000));
  });

  test('riwayat penjualan menyediakan unduh dan pratinjau faktur', () {
    final source =
        File('lib/screens/riwayat_penjualan_screen.dart').readAsStringSync();

    expect(source, contains("label: const Text('Unduh Faktur PDF')"));
    expect(source, contains("label: const Text('Pratinjau & Cetak Faktur')"));
    expect(source, contains("label: 'Unduh faktur PDF'"));
    expect(source, contains("label: 'Pratinjau & cetak faktur'"));
    expect(source, contains('simpanFakturPenjualanPdf(data)'));
    expect(source, contains('tampilkanPratinjauPdf('));
  });
}
