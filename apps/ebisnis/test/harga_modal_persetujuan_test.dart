import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gerbang harga modal (>10x harga jual) punya jalan keluar yang sah: barang
/// promo rugi dan klaim garansi. Pesan penolakan server menyuruh pengguna
/// "simpan ulang dengan persetujuan harga modal tinggi".
///
/// Selama berbulan-bulan perintah itu MUSTAHIL dijalankan: tidak ada satu pun
/// klien yang mengirim `izin_harga_modal_tinggi`, sehingga menyimpan ulang
/// hanya menghasilkan penolakan yang sama, dan barisnya terparkir GAGAL di
/// outbox. Ditemukan lewat pemindaian arah "dibaca server, tidak pernah
/// dikirim klien" (ais docs/pos/86).
///
/// Uji ini berbasis sumber -- layar Produk tidak punya harness widget yang
/// dapat menjalankan alur simpan sampai ke server. Ia sengaja mengikat pada
/// hal yang bisa PATAH: kode penolakan, penanda yang dikirim, dan penawaran
/// persetujuannya. Menegaskan sebuah nama sekadar "muncul" di berkas tidak
/// cukup -- pelajaran docs/pos/85, tempat uji semacam itu tetap hijau selama
/// cacatnya hidup.
void main() {
  late String sumber;

  setUpAll(() {
    sumber = File('lib/screens/produk_screen.dart').readAsStringSync();
  });

  test('penanda persetujuan ikut terkirim pada payload simpan', () {
    expect(
      sumber,
      contains("if (_izinHargaModalTinggi) 'izin_harga_modal_tinggi': true,"),
      reason: 'tanpa baris ini persetujuan tidak pernah sampai ke server',
    );
  });

  test('penolakan dikenali lewat KODE, bukan teks pesan', () {
    expect(sumber, contains("e.kode == 'HARGA_MODAL_TINGGI'"));
    // Teks pesan server memuat angka harga dan boleh berubah; mencocokkannya
    // akan mematahkan alur ini diam-diam pada perubahan kata-kata pertama.
    expect(
      sumber.contains("contains('lebih dari 10 kali harga jual')"),
      isFalse,
      reason: 'jangan mencocokkan teks pesan server',
    );
  });

  test('persetujuan ditawarkan lalu dicoba ulang, bukan sekadar dicatat', () {
    expect(sumber, contains('Simpan dengan persetujuan'));
    expect(sumber, contains('_izinHargaModalTinggi = true;'));
    expect(sumber, contains('await _simpan();'));
  });

  test('persetujuan berlaku sekali pakai', () {
    // Bila penandanya tidak direset, satu persetujuan diam-diam mengizinkan
    // seluruh penyimpanan berikutnya di form yang sama -- gerbangnya mati
    // tanpa ada yang menyadarinya.
    expect(sumber, contains('_izinHargaModalTinggi = false;'));
    expect(sumber, contains('!_izinHargaModalTinggi &&'));
  });
}
