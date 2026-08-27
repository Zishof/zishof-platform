import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('penolakan pembayaran mempertahankan pesan aman dari server', () {
    final gagal = ApiException(
      'Stok TELUR AYAM tidak mencukupi untuk jumlah yang diminta.',
      aktivitas: 'bayar',
      kodeReferensi: 'REQ-BAYAR-1',
      teknis: 'Exception server: contoh detail teknis',
    );

    expect(gagal.info.judul, 'Stok belum mencukupi');
    expect(gagal.info.pesan,
        'Stok TELUR AYAM tidak mencukupi untuk jumlah yang diminta.');
    expect(gagal.info.teknis, contains('detail teknis'));
    expect(gagal.info.solusi, isNotEmpty);
  });

  test('ketidaksamaan rincian pesanan diterjemahkan untuk kasir', () {
    final gagal = ApiException(
      'Rincian pesanan tersimpan berjumlah 2, sedangkan keranjang pembayaran berjumlah 4. Muat ulang pesanan sebelum mencoba kembali.',
      aktivitas: 'bayar',
      teknis:
          'java.lang.IllegalStateException: Rincian pesanan tersimpan berjumlah 2',
    );

    expect(gagal.info.judul, 'Pesanan perlu dimuat ulang');
    expect(gagal.info.pesan, contains('Pembayaran dihentikan'));
    expect(gagal.info.pesan, isNot(contains('IllegalStateException')));
    expect(gagal.info.teknis, contains('IllegalStateException'));
    expect(gagal.info.solusi.join(' '), contains('muat ulang'));
  });

  test('batas hutang memberi langkah mandiri dan jalur klik yang lengkap', () {
    final gagal = ApiException(
      'Transaksi ditolak: batas maksimal hutang anggota ini (500.000) akan terlampaui. Hutang berjalan saat ini 0, transaksi ini menambah 2.601.968.',
      aktivitas: 'bayar',
      kode: 'PERMINTAAN_DITOLAK',
      judul: 'Belum dapat diproses',
      solusi: const [
        'Perbaiki data sesuai penjelasan di atas, lalu simpan kembali.',
        'Bila penjelasannya menyangkut hak akses atau pengaturan, hubungi admin/supervisor.',
      ],
    );

    expect(gagal.info.judul, 'Batas hutang member terlampaui');
    expect(gagal.info.solusi.join(' '), contains('Pelanggan > Tipe Member'));
    expect(
        gagal.info.solusi.join(' '), contains('Pesanan > Transaksi Pending'));
    expect(gagal.info.solusi.join(' '), contains('jangan mengubah jurnal'));
  });

  test('toko kosong menjelaskan tombol, urutan, dan batas eskalasi', () {
    final gagal = ApiException(
      'Toko tidak diketahui.',
      aktivitas: 'produk_statistik',
      kode: 'PERMINTAAN_DITOLAK',
      solusi: const ['Perbaiki data sesuai penjelasan di atas.'],
    );

    expect(gagal.info.judul, 'Toko aktif belum dipilih');
    expect(gagal.info.solusi.first, contains('bilah atas'));
    expect(gagal.info.solusi.join(' '), contains('Muat Ulang'));
    expect(gagal.info.solusi.join(' '), contains('minta admin'));
  });

  test('solusi spesifik server tidak ditimpa panduan fallback', () {
    final gagal = ApiException(
      'Dokumen belum disetujui.',
      aktivitas: 'pengadaan_bayar',
      solusi: const [
        'Buka Pengadaan > Persetujuan lalu minta pejabat yang ditunjuk menyetujui dokumen ini.',
      ],
    );

    expect(gagal.info.solusi, hasLength(1));
    expect(gagal.info.solusi.first, contains('Pengadaan > Persetujuan'));
  });

  testWidgets('informasi teknis error selalu dapat dibuka', (tester) async {
    String? teksTersalin;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        teksTersalin = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const info = AppErrorInfo(
      judul: 'Proses belum berhasil',
      pesan: 'Pesan yang mudah dipahami pengguna.',
      solusi: ['Coba kembali.'],
      teknis: 'java.lang.IllegalStateException: contoh stack trace',
      kodeReferensi: 'REQ-123',
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AppErrorPanel(info: info, ringkas: true)),
    ));

    expect(find.text('Informasi Teknis'), findsOneWidget);
    expect(
        find.textContaining('java.lang.IllegalStateException'), findsNothing);

    await tester.tap(find.text('Informasi Teknis'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kode referensi: REQ-123'), findsOneWidget);
    expect(
        find.textContaining('java.lang.IllegalStateException'), findsOneWidget);

    await tester.tap(find.text('Salin Informasi Teknis'));
    await tester.pumpAndSettle();

    expect(teksTersalin, contains('Kode referensi: REQ-123'));
    expect(teksTersalin, contains('java.lang.IllegalStateException'));
  });
}
