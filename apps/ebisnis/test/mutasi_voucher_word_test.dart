import 'dart:io';

import 'package:ebisnis/screens/anggota/tab_mutasi_tabungan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Unduh Word di Mutasi Voucher aplikasi (POS Desktop/Android).
///
/// Permintaan An Nahl 17-09-2026 -- "mutasi voucher mohon bisa di download Word
/// untuk rincian mutasi & sisa saldonya" -- semula hanya dikerjakan di kanal
/// web (ais docs/pos/131), sementara kasir memakai aplikasi (docs/pos/135).
///
/// Diuji PERILAKUNYA: fungsi perakitnya murni, jadi dokumen yang dihasilkan
/// diperiksa langsung -- angka, isi, dan escape -- bukan dicocokkan teksnya.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
  });

  final baris = <Map<String, dynamic>>[
    {
      'namaAnggota': '242507141 - Malihah Rendi Ardian',
      'waktu': '2026-09-10T08:00:00',
      'jenisMutasi': 'Topup',
      'keterangan': 'Topup',
      'masuk': 100000,
      'keluar': 0,
      'saldoPerPenabung': 100000,
    },
    {
      'namaAnggota': '242507141 - Malihah Rendi Ardian',
      'waktu': '2026-09-13T10:00:00',
      'jenisMutasi': 'Pembelian/Belanja',
      'keterangan': 'ROTI BAKAR x4, diskon 4.000 (KTN-A)',
      'masuk': 0,
      'keluar': 24000,
      'saldoPerPenabung': 76000,
    },
  ];
  final rekap = <Map<String, dynamic>>[
    {
      'namaAnggota': '242507141 - Malihah Rendi Ardian',
      'saldoAwal': 0.0,
      'masuk': 100000.0,
      'keluar': 24000.0,
      'saldoAkhir': 76000.0,
    },
  ];

  test('ringkasan memakai rumus kartu di layar', () {
    final r = ringkasMutasiVoucher(baris, rekap);
    expect(r.totalMasuk, 100000);
    expect(r.totalKeluar, 24000);
    expect(r.saldoAwal, 0);
    expect(r.saldoAkhir, 76000);
  });

  test('dokumen memuat ringkasan, rekap, dan rincian dengan sisa saldo', () {
    final html = dokumenWordMutasiVoucher(
        baris: baris,
        rekap: rekap,
        dari: DateTime(2026, 9, 1),
        sampai: DateTime(2026, 9, 17));
    expect(html, contains('Total Masuk'));
    expect(html, contains('Total Keluar'));
    expect(html, contains('Sisa Saldo'));
    expect(html, contains('Rekap per Anggota'));
    expect(html, contains('Periode 01/09/2026 s/d 17/09/2026'));
    // Keterangan nama produk dari server (dok. 135) ikut terbawa apa adanya.
    expect(html, contains('ROTI BAKAR x4, diskon 4.000 (KTN-A)'));
    // Sisa saldo yang sama dengan kartu "Saldo Akhir" di layar.
    expect(html, contains('<b>Rp 76.000</b>'));
  });

  test('satu baris tabel rincian per mutasi', () {
    final html = dokumenWordMutasiVoucher(
        baris: baris,
        rekap: rekap,
        dari: DateTime(2026, 9, 1),
        sampai: DateTime(2026, 9, 17));
    final rincian = html.substring(html.indexOf('Rincian Mutasi'));
    // 1 baris judul + 2 baris mutasi.
    expect('<tr>'.allMatches(rincian).length, 3);
  });

  test('teks dari data di-escape -- nama dan keterangan adalah input pengguna', () {
    final html = dokumenWordMutasiVoucher(
      baris: [
        {...baris[1], 'keterangan': '<script>alert(1)</script> & Co'}
      ],
      rekap: rekap,
      dari: DateTime(2026, 9, 1),
      sampai: DateTime(2026, 9, 17),
      namaAnggota: 'A <b>',
    );
    expect(html, isNot(contains('<script>')));
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt; &amp; Co'));
    expect(html, contains('A &lt;b&gt;'));
  });

  test('layar: tombol Word ada, dan kartu memakai ringkasan yang sama', () {
    final layar =
        File('lib/screens/anggota/tab_mutasi_tabungan.dart').readAsStringSync();
    expect(layar, contains("label: const Text('Word')"));
    expect(layar, contains('onPressed: _unduhWord'));
    // Kartu dan Word wajib satu sumber angka -- kalau kartu kembali menghitung
    // sendiri, keduanya bisa bercerita berbeda tentang uang yang sama.
    expect(layar,
        contains('final ringkas = ringkasMutasiVoucher(_data, _rekapPerAnggota);'));
  });
}
