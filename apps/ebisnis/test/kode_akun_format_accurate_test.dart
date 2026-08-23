import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak **format Accurate** pada unduh/unggah bagan akun, dan tombol
/// **Bersihkan Akun** yang hanya untuk administrator.
///
/// Permintaan pemilik produk: berkas unduh/unggah harus berbentuk sama persis
/// dengan ekspor Accurate ("akun-perkiraan.xlsx"), supaya bagan akun dapat
/// bolak-balik tanpa disusun ulang. Urutan kolomnya adalah kontrak: geser satu
/// kolom saja dan seluruh berkas milik pengguna salah terbaca tanpa satu pun
/// pesan galat -- itulah kenapa dikunci di sini.
void main() {
  final layar = File('lib/screens/kode_akun_screen.dart').readAsStringSync();

  test('kolom unduh mengikuti urutan berkas Accurate', () {
    // Judul & urutannya sama persis dengan baris pertama berkas Accurate.
    const urutan = [
      "'No. '",
      "'Tipe Akun'",
      "'Kode Perkiraan'",
      "'Nama'",
      "'Akun Induk'",
      "'Mata Uang'",
      "'Saldo Awal'",
      "'per Tgl'",
      "'Kurs Saldo (Jika Asing)'",
      "'Cabang Saldo'",
      "'Catatan'",
    ];
    var posisi = -1;
    for (final judul in urutan) {
      final k = layar.indexOf(judul, posisi + 1);
      expect(k, greaterThan(posisi),
          reason: 'kolom $judul hilang atau urutannya berubah');
      posisi = k;
    }
  });

  test('unggah membaca kolom pada indeks Accurate, bukan indeks lama', () {
    // B=1 Tipe Akun, C=2 Kode Perkiraan, D=3 Nama, E=4 Akun Induk, K=10 Catatan.
    expect(layar, contains("'tipeAkun': k(1)"));
    expect(layar, contains("'kode': k(2)"));
    expect(layar, contains("'nama': k(3)"));
    expect(layar, contains("'kodeParent': k(4)"));
    expect(layar, contains("'keterangan': k(10)"));
  });

  test('kolom saldo awal TIDAK ikut dikirim saat unggah', () {
    // Saldo awal dibukukan lewat layar "Saldo Awal (Neraca Awal)" yang
    // menjurnalnya; mengirimkannya dari berkas bagan akun akan membuat dua
    // sumber angka untuk hal yang sama.
    expect(layar.contains("'saldoAwal':"), isFalse);
    expect(layar.contains("'perTanggal':"), isFalse);
  });

  test('Bersihkan Akun hanya tampil untuk administrator', () {
    // Cari TOMBOLnya, bukan judul dialognya -- keduanya bertulisan sama.
    final i = layar.indexOf("label: const Text('Bersihkan Akun')");
    expect(i, greaterThan(-1), reason: 'tombol Bersihkan Akun belum ada');
    // Penjaganya harus berada SEBELUM tombolnya, pada blok if yang sama.
    final sebelum = layar.substring((i - 400).clamp(0, i), i);
    expect(sebelum, contains('Sesi.instance.isAdmin'),
        reason: 'tombol harus digerbangi Sesi.isAdmin (Common.getApakahAdminLain di server)');
  });

  test('Bersihkan Akun selalu pratinjau dulu, baru menghapus', () {
    expect(layar, contains("'kode_akun_bersihkan', {'praTinjau': true}"),
        reason: 'langkah pratinjau hilang -- penghapusan massal tidak boleh '
            'terjadi karena salah klik');
    expect(layar, contains("aksi('kode_akun_bersihkan', {})"),
        reason: 'langkah hapus sesungguhnya hilang');
    // Dialog konfirmasi di antara keduanya.
    final iPratinjau = layar.indexOf("'praTinjau': true");
    final iDialog = layar.indexOf('showDialog<bool>', iPratinjau);
    final iHapus = layar.indexOf("aksi('kode_akun_bersihkan', {})");
    expect(iDialog, greaterThan(iPratinjau));
    expect(iHapus, greaterThan(iDialog),
        reason: 'hapus harus SESUDAH pengguna menyetujui dialog');
  });
}
