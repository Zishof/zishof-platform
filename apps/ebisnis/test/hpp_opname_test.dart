import 'package:ebisnis/services/hpp_opname.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HPP nol sah, data kosong/salah produk tidak menjadi nol', () {
    expect(HppOpname.nilai({'produkId': 1, 'hargaBeli': 0}, 1), 0);
    expect(HppOpname.nilai({'produkId': 1, 'hargaBeli': 1250.5}, 1), 1250.5);
    expect(HppOpname.nilai({'produkId': 1, 'hargaJual': 5000}, 1), isNull);
    expect(HppOpname.nilai({'produkId': 2, 'hargaBeli': 1250}, 1), isNull);
    expect(
        HppOpname.nilai({'produkId': 1, 'hargaBeli': double.nan}, 1), isNull);
    expect(HppOpname.nilai({'produkId': 1, 'hargaBeli': -1}, 1), isNull);
  });
  test('cache terpisah menurut server tenant kasir toko dan produk', () {
    final row = {'produkId': 1, 'kode': 'A'};
    final dasar = ['api', 1, 'kasir', 1];
    final key = HppOpname.kunci(dasar, row);
    for (var i = 0; i < dasar.length; i++) {
      final beda = List<Object>.from(dasar)..[i] = 'beda';
      expect(HppOpname.kunci(beda, row), isNot(key));
    }
    expect(HppOpname.kunci(dasar, {'produkId': 2, 'kode': 'A'}), isNot(key));
  });
  test('cache tampil sebelum server; kegagalan tidak menghapus HPP tersimpan',
      () async {
    final hasil = <double?>[];
    final cache = <bool>[];
    await HppOpname.muat([
      {'produkId': 1, 'kode': 'A'}
    ],
        aktif: () => true,
        baca: (row, emit) async {
          emit({'produkId': 1, 'hargaBeli': 1500, 'offline': true});
          expect(hasil, [1500]);
          throw Exception('offline');
        },
        onData: (id, nilai, lokal) {
          hasil.add(nilai);
          cache.add(lokal);
        });
    expect(hasil, [1500]);
    expect(cache, [true]);
  });
  test('produk dideduplikasi dan pembacaan maksimal tiga bersamaan', () async {
    var berjalan = 0, maksimum = 0, jumlah = 0;
    final rows = List.generate(
        12, (i) => <String, dynamic>{'produkId': i % 6, 'kode': 'P${i % 6}'});
    await HppOpname.muat(rows,
        aktif: () => true,
        baca: (row, emit) async {
          berjalan++;
          jumlah++;
          if (berjalan > maksimum) maksimum = berjalan;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          berjalan--;
        },
        onData: (_, __, ___) {});
    expect(jumlah, 6);
    expect(maksimum, 3);
  });
  test('respons terlambat setelah konteks berubah diabaikan', () async {
    var aktif = true, emisi = 0;
    await HppOpname.muat([
      {'produkId': 1, 'kode': 'A'}
    ],
        aktif: () => aktif,
        baca: (row, emit) async {
          aktif = false;
          emit({'produkId': 1, 'hargaBeli': 1});
        },
        onData: (_, __, ___) {
          emisi++;
        });
    expect(emisi, 0);
  });
}
