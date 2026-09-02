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

  group('entri massal Kulakan', () {
    late String bulk;

    setUpAll(() {
      bulk = File('lib/screens/kulakan_bulk_entry_screen.dart').readAsStringSync();
    });

    test('persetujuan diminta SEBELUM baris diantrekan', () {
      // Bentuk pra-kirim, bukan tangkap-lalu-ulang: penolakan bisnis di layar
      // ini melempar dari dalam loop yang sudah menaruh baris di antrean
      // offline dengan id sementara, dan seluruh posting mati
      // (`if (!e.offline) rethrow;`). Mencoba ulang di tengahnya menyentuh
      // penukaran id dan urutan flush.
      final iKonfirmasi = bulk.indexOf('_konfirmasiHargaModalTinggi(hargaModalTinggi)');
      final iAntre = bulk.indexOf('MasterOffline.antreLokal');
      expect(iKonfirmasi, greaterThan(0));
      expect(iAntre, greaterThan(0));
      expect(iKonfirmasi, lessThan(iAntre),
          reason: 'persetujuan harus diminta sebelum antreLokal dipanggil');
    });

    test('syaratnya mencerminkan gerbang server persis', () {
      // Server: hargaJualFinal > 0.0 && hargaModalFinal > hargaJualFinal * 10.0
      expect(bulk, contains('row.hargaJualNilai > 0'));
      expect(bulk, contains('row.hppUnit > row.hargaJualNilai * 10'));
      expect(bulk, contains('row.produkId == null'),
          reason: 'hanya produk baru yang melewati produk_simpan');
    });

    test('penandanya benar-benar ikut terkirim', () {
      expect(bulk,
          contains("if (izinHargaModalTinggi) 'izin_harga_modal_tinggi': true,"));
    });

    test('dialognya menyebut baris mana yang bermasalah', () {
      // Persetujuan tanpa menyebut barisnya adalah persetujuan buta atas
      // seluruh batch -- gerbangnya mati tanpa pengguna tahu apa yang disetujui.
      expect(bulk, contains('row.namaBersih'));
      expect(bulk, contains('_bulkRp.format(row.hppUnit)'));
    });
  });
}
