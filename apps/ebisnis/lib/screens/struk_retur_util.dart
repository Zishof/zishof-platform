import 'package:flutter/material.dart';

import 'struk_screen.dart';

/// Faktur/struk **Retur Penjualan**.
///
/// Sengaja memakai ulang [StrukScreen] milik kasir, bukan membuat layar cetak sendiri, supaya
/// bentuk struknya (kop toko, kolom No/Tanggal/Kasir/Pelanggan, daftar barang, total, pengaturan
/// lebar kertas, dan jalur cetak langsung ke printer default) persis sama dengan struk penjualan.
/// Yang membedakan hanya dua hal: judul dokumen dicetak di bawah kop toko, dan barisnya diberi
/// label status RETUR PENJUALAN sehingga tidak mungkin tertukar dengan struk jual.
///
/// Nilai yang ditampilkan adalah nilai yang DIKEMBALIKAN kepada pembeli (positif), bukan angka
/// minus — mengikuti kebiasaan nota retur manual yang selama ini dipegang toko.
Future<void> bukaStrukRetur(
  BuildContext context, {
  required String kode,
  required String waktu,
  required List<Map<String, dynamic>> item,
  required double total,
  required String metode,
  String? pelanggan,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => StrukScreen(
        kode: kode,
        waktu: waktu,
        item: item,
        total: total,
        metode: metode.trim().isEmpty ? 'Tunai' : metode,
        pelanggan: pelanggan,
        statusLabel: 'RETUR PENJUALAN',
        jenisDokumen: 'Faktur Retur Penjualan',
        // Retur bukan transaksi kasir baru: tombol "Transaksi Baru" dan "Buka Laci"
        // tidak relevan di sini, jadi layar dibuka dalam mode cetak ulang.
        modeCetakUlang: true,
      ),
    ),
  );
}

/// Ubah baris retur (dari form Buat Retur maupun dari tabel Riwayat) menjadi item struk.
///
/// Kunci yang dibaca sengaja longgar karena kedua sumber memakai nama field berbeda:
/// form memakai `nama`/`hargaSatuan`, sedangkan riwayat memakai `namaProduk`/`hargaSatuan`.
Map<String, dynamic> itemStrukRetur({
  required String nama,
  required num qty,
  required num harga,
}) {
  return {
    'nama': nama.trim().isEmpty ? '-' : nama.trim(),
    'qty': qty,
    'harga': harga,
  };
}
