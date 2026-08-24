import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak **cakupan "Layani Semua"** pada Dasbor &gt; Ringkasan Umum.
///
/// Aksi ini menandai TERLAYANI banyak baris sekaligus dan tidak punya pembatalan.
/// Cakupannya karena itu wajib sama persis dengan tabel Data Pembelian yang sedang
/// dilihat pengguna: menyaring "QRIS BMT", melihat 12 baris, lalu menekan tombolnya
/// harus menandai 12 baris itu -- bukan seluruh transaksi pada rentang tanggalnya.
///
/// Dulu tombol ini hanya mengirim `_payloadRentangTanggal()`. Penyaring lain
/// diabaikan diam-diam: `payload.optString(...)` di sisi server memang dirancang
/// tidak mengeluh, jadi tidak ada satu pun tanda bahwa yang dikerjakan berbeda dari
/// yang disetujui. Uji ini mengunci bentuk kodenya supaya jalur itu tidak terbuka
/// lagi tanpa ada yang menyadarinya.
void main() {
  final sumber =
      File('lib/screens/ringkasan/tab_umum.dart').readAsStringSync();

  /// Potongan literal payload sesudah [penanda], sampai kurung penutupnya.
  ///
  /// Sengaja melempar, bukan memakai `expect`: fungsi ini dipanggil di luar badan
  /// test (agar hasilnya dipakai bersama), dan `expect` di luar test gagal sebagai
  /// OutsideTestException -- yang menyembunyikan sebab sesungguhnya.
  String potongPayload(String penanda) {
    final mulai = sumber.indexOf(penanda);
    if (mulai < 0) throw StateError('penanda tidak ketemu: $penanda');
    final kandidat = [sumber.indexOf('});', mulai), sumber.indexOf('};', mulai)]
        .where((i) => i > -1);
    if (kandidat.isEmpty) throw StateError('akhir payload tidak ketemu: $penanda');
    return sumber.substring(mulai, kandidat.reduce((a, b) => a < b ? a : b));
  }

  final payloadTabel = potongPayload('Map<String, dynamic> _payloadDashboardUmum()');
  final payloadLayani = potongPayload("aksi('layani_semua_transaksi'");

  // Penyaring yang MENENTUKAN baris mana yang tampil. Yang lain (periodeTren,
  // page, tanggalAcuan) hanya soal tampilan, jadi tidak diwajibkan di sini.
  const penyaring = ['cariPembeli', 'kodeTransaksi', 'metodeBayar'];

  test('Layani Semua mengirim penyaring yang SAMA dengan tabel Data Pembelian',
      () {
    for (final kunci in penyaring) {
      expect(payloadTabel, contains("'$kunci'"),
          reason: 'tabel Data Pembelian kehilangan penyaring $kunci');
      expect(payloadLayani, contains("'$kunci'"),
          reason: 'layani_semua_transaksi TIDAK mengirim $kunci -- aksi massal '
              'akan menyapu lebih luas daripada yang dilihat pengguna');
    }
    // Rentang tanggal tetap wajib ada di keduanya.
    expect(payloadTabel, contains('_payloadRentangTanggal()'));
    expect(payloadLayani, contains('_payloadRentangTanggal()'));
  });

  test('kunci kode transaksi dikirim dalam dua ejaan yang sama di kedua payload',
      () {
    // Server menerima `kodeTransaksi` maupun `kode`; keduanya dikirim supaya
    // tidak bergantung pada ejaan mana yang dibaca lebih dulu.
    for (final payload in [payloadTabel, payloadLayani]) {
      expect(payload, contains("'kodeTransaksi': _kodeTransaksi"));
      expect(payload, contains("'kode': _kodeTransaksi"));
    }
  });

  test('dialog konfirmasi mengeja penyaring aktif, bukan "rentang filter ini"',
      () {
    expect(sumber, contains('_ringkasanPenyaringAktif()'),
        reason: 'cakupan aksi massal harus dapat dibaca sebelum disetujui');

    final mulai = sumber.indexOf('Future<void> _layaniSemua()');
    expect(mulai, greaterThan(-1));
    final blokDialog = sumber.substring(mulai, sumber.indexOf('konfirmasi != true', mulai));
    expect(blokDialog, contains('penyaring'),
        reason: 'dialog harus menampilkan daftar penyaring yang sedang aktif');
    expect(blokDialog.contains('Semua transaksi pada rentang filter ini'), isFalse,
        reason: 'kalimat lama tidak dapat diperiksa pengguna: ia tidak menyebut '
            'penyaring apa yang sedang berlaku');

    // Tanpa penyaring, kalimatnya harus mengaku apa adanya.
    expect(blokDialog, contains('SELURUH transaksi'),
        reason: 'tanpa penyaring, cakupan sesungguhnya harus disebut terus terang');
  });
}
