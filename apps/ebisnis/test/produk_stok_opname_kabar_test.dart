import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Form produk harus memberi tahu bila angka Stok-nya dicatat sebagai stok opname.
///
/// `produk_simpan` TIDAK pernah menimpa `produk.stok` langsung. Angka Stok dari
/// form dicatat sebagai stok opname atomik
/// (`StokOpnameScanUtil.sinkronkanStokFisikJikaBerbeda`) supaya Hitung Ulang
/// Stok -- yang bersumber dari ledger -- tidak menghapusnya. Server lalu
/// melapor `stokDisesuaikan` dan `stokOpnameId`.
///
/// Sebelum ini klien membuang keduanya: form tertutup diam-diam, dan pengguna
/// tidak pernah tahu satu dokumen stok opname baru saja tercipta atas namanya.
/// Auditor kelak menemukan opname yang "tidak dibuat siapa pun". Ditemukan oleh
/// `alat/field-tanpa-pembaca.py` (ais docs/pos/133).
///
/// Diikat di sini karena ini kelas cacat yang paling sering berulang di repo
/// ini: satu sisi mengirim, sisi lain tidak membaca, dan tidak ada yang gagal.
void main() {
  late String layar;
  late String simpan;

  setUpAll(() {
    layar = File('lib/screens/produk_screen.dart').readAsStringSync();
    // Berkas ini punya DUA `_simpan()` -- form kebijakan retur dan form
    // produk. Mengiris yang pertama menguji layar yang salah, jadi irisan
    // dijangkarkan pada pemanggilan `produk_simpan` itu sendiri.
    final iAksi = layar.indexOf("aksi: 'produk_simpan'");
    expect(iAksi, greaterThan(0), reason: 'pemanggilan produk_simpan hilang');
    final awal = layar.lastIndexOf('Future<void> _simpan() async {', iAksi);
    final akhir = layar.indexOf('Widget build(BuildContext context)', iAksi);
    expect(awal, greaterThan(0), reason: '_simpan milik form produk hilang');
    expect(akhir, greaterThan(iAksi));
    simpan = layar.substring(awal, akhir);
  });

  test('kabar penyesuaian stok dibaca dari respons', () {
    expect(simpan, contains("hasil['stokDisesuaikan']"),
        reason: 'field server tanpa pembaca = opname yang tak pernah dikabarkan');
  });

  test('nomor opname ikut dibaca supaya dokumennya bisa ditemukan', () {
    expect(simpan, contains("hasil['stokOpnameId']"));
  });

  test('pengguna benar-benar diberi tahu, bukan sekadar dibaca', () {
    expect(simpan, contains('stok opname'),
        reason: 'dibaca tanpa ditampilkan sama dengan tidak dibaca');
    expect(simpan, contains('showSnackBar'));
  });

  test('messenger diambil SEBELUM form ditutup', () {
    // Sesudah pop, context form sudah dilepas dari pohon widget; mencari
    // ScaffoldMessenger lewat context itu tidak lagi sahih. Pesan yang
    // dijadwalkan dari sana bisa hilang tanpa galat.
    final iMessenger = simpan.indexOf('ScaffoldMessenger.maybeOf(context)');
    final iPop = simpan.indexOf('Navigator.of(context).pop(true)');
    expect(iMessenger, greaterThan(0));
    expect(iPop, greaterThan(0));
    expect(iMessenger, lessThan(iPop));
  });

  test('pesan hanya muncul bila server benar-benar membuat opname', () {
    // Stok yang tidak berubah tidak membuat opname; pesan yang selalu muncul
    // akan cepat diabaikan dan kehilangan artinya.
    expect(simpan, contains('if (stokDisesuaikan && messenger != null)'));
  });
}
