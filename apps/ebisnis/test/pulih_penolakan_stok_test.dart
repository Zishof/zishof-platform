import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/transaksi_outbox_service.dart';

/// Pemulihan transaksi yang terparkir GAGAL oleh penolakan stok yang KELIRU.
///
/// Latar: `STOK_TIDAK_CUKUP` termasuk [TransaksiOutboxService.kodePenolakanPermanen],
/// dan retry otomatis hanya membaca baris PENDING. Jadi transaksi luring yang
/// ditolak gerbang stok langsung diparkir GAGAL dan tidak pernah dicoba lagi.
///
/// Itu benar untuk penolakan yang sah. Tetapi sejak r77493 (16-08-2026) sampai
/// perbaikannya 02-09-2026, gerbang itu menolak produk yang tidak pernah dikunci
/// admin -- nilai `null` ("Ikut Pengaturan Toko") diperlakukan sebagai "Wajib
/// Diblokir" (docs/pos/73). Transaksi yang diparkir karenanya adalah penjualan
/// SAH: uang sudah diterima kasir, struk sudah tercetak.
///
/// Yang diuji di sini adalah PENCOCOKAN TEKS-nya, karena di situlah kesalahan
/// paling mudah lolos tanpa terlihat:
///
/// * terlalu longgar -> membangunkan penolakan yang sah (produk kadaluarsa,
///   data tidak lengkap), yang lalu gagal lagi dan membuang permintaan;
/// * terlalu ketat  -> tidak membangunkan apa pun, dan penjualannya tetap
///   hilang dari omzet server tanpa seorang pun tahu.
void main() {
  final svc = TransaksiOutboxService.instance;

  group('dibangunkan -- penolakan stok versi lama', () {
    // Bunyi persis yang tercatat pada perangkat kasir selama masa regresi.
    const contohNyata = 'Stok tidak mencukupi utk produk yang dikunci admin '
        '(tidak boleh dijual minus): Nasi Koloke (sisa -2.0, diminta 1.0)';

    test('pesan penolakan produksi 01-09-2026 dikenali', () {
      expect(svc.terparkirPenolakanStokKeliru(contohNyata), isTrue);
    });

    test('bunyi pesan versi BARU juga dikenali', () {
      // Perbaikannya mengubah kalimat penolakan (docs/pos/73 bagian 1.6). Baris
      // yang terparkir SESUDAH pembaruan server tetapi SEBELUM aplikasi kasir
      // ikut diperbarui akan menyimpan bunyi yang baru ini.
      expect(
          svc.terparkirPenolakanStokKeliru(
              'Stok tidak mencukupi untuk produk yang disetel "Wajib Diblokir '
              'Jika Stok Tidak Cukup" pada master Produk: Nasi Koloke'),
          isTrue);
    });

    test('pencocokan tidak peduli besar-kecil huruf', () {
      expect(svc.terparkirPenolakanStokKeliru(contohNyata.toUpperCase()),
          isTrue);
      expect(svc.terparkirPenolakanStokKeliru(contohNyata.toLowerCase()),
          isTrue);
    });
  });

  group('TIDAK dibangunkan -- penolakan yang memang sah', () {
    const penolakanLain = <String, String>{
      'produk kadaluarsa':
          'Produk berikut sudah melewati tanggal kadaluarsa dan tidak boleh '
              'dijual: Susu UHT (kadaluarsa 01-08-2026). Segera pisahkan dari stok jual.',
      'stok batch FEFO':
          'Stok batch aktif yang belum kedaluwarsa tidak mencukupi: Roti Tawar. '
              'Periksa stok fisik atau aktifkan izin transaksi stok habis pada toko ini.',
      'sesi kas':
          'Transaksi berasal dari sesi kas yang berbeda dan bukan transaksi '
              'tertahan milik kasir yang sedang login.',
      'data tidak lengkap': 'Pesanan tidak dibayar otomatis karena data '
          'pembeli/member pada draft belum tersedia.',
      'kelipatan grosir':
          'Jumlah pembelian harus kelipatan 6 untuk produk Air Mineral Dus.',
    };

    penolakanLain.forEach((nama, pesan) {
      test('$nama tetap diparkir', () {
        expect(svc.terparkirPenolakanStokKeliru(pesan), isFalse,
            reason: 'penolakan ini SAH -- membangunkannya hanya menghasilkan '
                'kegagalan yang sama sekali lagi');
      });
    });

    test('pesan kosong / null tidak dibangunkan', () {
      expect(svc.terparkirPenolakanStokKeliru(null), isFalse);
      expect(svc.terparkirPenolakanStokKeliru(''), isFalse);
      expect(svc.terparkirPenolakanStokKeliru('   '), isFalse);
    });
  });

  group('kontrak yang menjadikan pemulihan ini perlu', () {
    test('STOK_TIDAK_CUKUP memang penolakan permanen', () {
      // Bila suatu hari kode ini dikeluarkan dari daftar permanen, retry biasa
      // sudah menjemputnya sendiri dan pemulihan sekali-jalan ini tidak lagi
      // punya alasan untuk ada. Uji ini yang akan mengingatkan.
      expect(TransaksiOutboxService.kodePenolakanPermanen,
          contains('STOK_TIDAK_CUKUP'));
      expect(svc.dapatDicobaUlang(_galat('STOK_TIDAK_CUKUP')), isFalse,
          reason: 'inilah sebabnya baris terparkir butuh dibangunkan manual');
    });

    test('kadaluarsa juga permanen, dan memang tidak ikut dibangunkan', () {
      expect(TransaksiOutboxService.kodePenolakanPermanen,
          contains('PRODUK_KADALUARSA'));
    });
  });
}

/// ApiException yang SUNGGUHAN, bukan tiruan: `dapatDicobaUlang` memeriksa
/// tipenya lebih dulu (`if (error is! ApiException) return true`), sehingga
/// tiruan apa pun akan lolos sebagai "boleh dicoba ulang" dan membuat uji ini
/// mengiyakan hal yang tidak diujinya. (Terjadi saat uji ini pertama ditulis.)
ApiException _galat(String kode) =>
    ApiException('galat uji', kode: kode, statusHttp: 200);
