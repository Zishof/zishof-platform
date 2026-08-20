import 'package:flutter_test/flutter_test.dart';
import 'package:zishof/models/aturan_diskon.dart';
import 'package:zishof/models/keranjang_item.dart';
import 'package:zishof/services/diskon_engine.dart';

/// Mengunci perilaku DiskonEngine terhadap `evaluateDiscount()` versi JSP.
/// Setiap kasus di bawah adalah aturan yang benar-benar ada di kode JSP.
void main() {
  AturanDiskon aturan({
    String id = 'R1',
    String? produk,
    String? toko,
    bool semuaMember = true,
    String? jenis,
    String? tipe,
    double persen = 0,
    double maks = 0,
    double nominal = 0,
    bool potonganLangsung = true,
    bool perHariPerToko = false,
    DateTime? mulai,
    DateTime? selesai,
    double terpakaiHariIni = 0,
  }) =>
      AturanDiskon(
        id: id,
        produk: produk,
        toko: toko,
        berlakuSemuaMember: semuaMember,
        jenisAnggota: jenis,
        tipeAnggota: tipe,
        persentase: persen,
        maksimalPotongan: maks,
        nominal: nominal,
        potonganLangsung: potonganLangsung,
        berlakuPerHariDanPerToko: perHariPerToko,
        tanggalMulai: mulai,
        tanggalSelesai: selesai,
        terpakaiHariIni: terpakaiHariIni,
      );

  KeranjangItem item({
    String id = 'P1',
    String toko = 'T1',
    double harga = 10000,
    int jumlah = 1,
  }) =>
      KeranjangItem(
        id: id,
        kode: 'K$id',
        nama: 'Produk $id',
        harga: harga,
        idToko: toko,
        namaToko: 'Toko $toko',
        jumlah: jumlah,
      );

  void hitung(List<KeranjangItem> keranjang, List<AturanDiskon> rules,
          {int? jenis, int? tipe}) =>
      DiskonEngine.hitungUlang(keranjang, rules,
          idJenisAnggota: jenis, idTipeAnggota: tipe);

  test('persentase dipakai lebih dulu daripada nominal', () {
    final it = item(harga: 10000, jumlah: 2);
    hitung([it], [aturan(persen: 10, nominal: 5000)]);
    // 20.000 x 10% = 2.000 -- nominal diabaikan karena persen > 0
    expect(it.diskon, 2000);
    expect(it.cashback, 0);
  });

  test('nominal dikalikan jumlah dan dibatasi subtotal baris', () {
    final it = item(harga: 3000, jumlah: 2);
    hitung([it], [aturan(nominal: 5000)]);
    // 5.000 x 2 = 10.000, tapi subtotal cuma 6.000
    expect(it.diskon, 6000);
  });

  test('maksimal potongan membatasi hasil persentase', () {
    final it = item(harga: 100000, jumlah: 1);
    hitung([it], [aturan(persen: 50, maks: 20000)]);
    expect(it.diskon, 20000);
  });

  test('potongan_langsung=false menjadi cashback, bukan diskon', () {
    final it = item(harga: 10000, jumlah: 1);
    hitung([it], [aturan(persen: 10, potonganLangsung: false)]);
    expect(it.diskon, 0);
    expect(it.cashback, 1000);
  });

  test('aturan produk spesifik tidak mengenai produk lain', () {
    final cocok = item(id: 'P1');
    final tidak = item(id: 'P2');
    hitung([cocok, tidak], [aturan(produk: 'P1', persen: 10)]);
    expect(cocok.diskon, 1000);
    expect(tidak.diskon, 0);
  });

  test('aturan toko spesifik tidak mengenai toko lain', () {
    final cocok = item(toko: 'T1');
    final tidak = item(id: 'P2', toko: 'T2');
    hitung([cocok, tidak], [aturan(toko: 'T1', persen: 10)]);
    expect(cocok.diskon, 1000);
    expect(tidak.diskon, 0);
  });

  test('aturan yang belum mulai atau sudah lewat dilewati', () {
    final besok = DateTime.now().add(const Duration(days: 1));
    final kemarin = DateTime.now().subtract(const Duration(days: 1));
    final a = item();
    hitung([a], [aturan(persen: 10, mulai: besok)]);
    expect(a.diskon, 0, reason: 'belum mulai');

    final b = item();
    hitung([b], [aturan(persen: 10, selesai: kemarin)]);
    expect(b.diskon, 0, reason: 'sudah lewat');
  });

  test('tanggal selesai berlaku sampai 23:59:59 hari itu', () {
    final hariIni = DateTime.now();
    final it = item();
    hitung([it], [aturan(persen: 10, selesai: hariIni)]);
    expect(it.diskon, 1000);
  });

  test('aturan khusus jenis/tipe anggota hanya untuk yang cocok', () {
    final it = item();
    hitung([it], [aturan(semuaMember: false, jenis: '7', persen: 10)],
        jenis: 7);
    expect(it.diskon, 1000);

    final lain = item();
    hitung([lain], [aturan(semuaMember: false, jenis: '7', persen: 10)],
        jenis: 9);
    expect(lain.diskon, 0);
  });

  test('aturan tanpa persen maupun nominal dilewati, aturan berikut dipakai',
      () {
    final it = item();
    hitung([it], [
      aturan(id: 'KOSONG'),
      aturan(id: 'ISI', persen: 10),
    ]);
    expect(it.aturanDiskon, 'ISI');
    expect(it.diskon, 1000);
  });

  test('aturan pertama yang cocok yang dipakai (bukan yang terbesar)', () {
    final it = item();
    hitung([it], [
      aturan(id: 'A', persen: 5),
      aturan(id: 'B', persen: 50),
    ]);
    expect(it.aturanDiskon, 'A');
    expect(it.diskon, 500);
  });

  test('pagu harian per aturan dibagi lintas baris keranjang', () {
    final a = item(id: 'P1', harga: 10000);
    final b = item(id: 'P2', harga: 10000);
    hitung([a, b], [
      aturan(persen: 100, maks: 15000, perHariPerToko: true),
    ]);
    // Baris pertama menyerap 10.000, sisa pagu 5.000 untuk baris kedua.
    expect(a.diskon, 10000);
    expect(b.diskon, 5000);
  });

  test('pagu harian memperhitungkan yang sudah terpakai hari ini', () {
    final it = item(harga: 10000);
    hitung([it], [
      aturan(persen: 100, maks: 15000, perHariPerToko: true, terpakaiHariIni: 12000),
    ]);
    expect(it.diskon, 3000);
  });

  test('pagu harian habis menghasilkan diskon nol', () {
    final it = item(harga: 10000);
    hitung([it], [
      aturan(persen: 100, maks: 15000, perHariPerToko: true, terpakaiHariIni: 15000),
    ]);
    expect(it.diskon, 0);
  });

  test('hitung ulang tidak menumpuk akumulator keranjang', () {
    final it = item(harga: 10000);
    final rules = [aturan(persen: 100, maks: 15000, perHariPerToko: true)];
    hitung([it], rules);
    final pertama = it.diskon;
    hitung([it], rules);
    final kedua = it.diskon;
    expect(kedua, pertama,
        reason: 'akumulator harus direset tiap kali hitung ulang');
  });

  test('parser boolean menerima true, "true", dan "t" dari Postgres', () {
    for (final nilai in [true, 'true', 't']) {
      final r = AturanDiskon.dariJson({
        'id': 'X',
        'berlaku_semua_member': nilai,
        'potongan_langsung': nilai,
        'persentase': 10,
      });
      expect(r.berlakuSemuaMember, isTrue, reason: 'nilai $nilai');
      expect(r.potonganLangsung, isTrue, reason: 'nilai $nilai');
    }
  });

  test('field kosong dari server dianggap tidak menyaring apa pun', () {
    final r = AturanDiskon.dariJson({
      'id': 'X',
      'produk': '',
      'toko': 'null',
      'persentase': '10',
      'berlaku_semua_member': 'true',
      'potongan_langsung': 'true',
    });
    expect(r.produk, isNull);
    expect(r.toko, isNull);
    final it = item();
    hitung([it], [r]);
    expect(it.diskon, 1000);
  });
}
