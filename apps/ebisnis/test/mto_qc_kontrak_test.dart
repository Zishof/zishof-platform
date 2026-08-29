import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';

/// Kontrak Fase E (dok. 48 P5/P6): rute MTO dan tanda QC pada Produk.
///
/// Klien hanya menyunting konfigurasi -- pemicunya di server (konfirmasi
/// SalesOrderLapangan utk MTO_*, OUTPUT POSTED utk QC). Uji ini menjaga
/// pemetaan JSON dan nilai bawaan: katalog lama tanpa kedua field tetap
/// terbaca sebagai perilaku hari ini (BELI, tanpa QC).
void main() {
  Map<String, dynamic> katalog({String? rute, bool? perluQc}) => {
        'id': 1,
        'kode': 'P1',
        'barcode': '',
        'nama': 'Roti',
        'hargaJual': 1000,
        'stok': 5,
        'kategoriId': null,
        'kategoriNama': '',
        'gambarUrl': null,
        if (rute != null) 'rute': rute,
        if (perluQc != null) 'perluQc': perluQc,
      };

  test('katalog lama: rute kosong dan perluQc false', () {
    final p = Produk.fromJson(katalog());
    expect(p.rute, '');
    expect(p.perluQc, isFalse);
  });

  test('rute MTO_BELI / MTO_PRODUKSI terbaca apa adanya', () {
    expect(Produk.fromJson(katalog(rute: 'MTO_BELI')).rute, 'MTO_BELI');
    expect(
        Produk.fromJson(katalog(rute: 'MTO_PRODUKSI')).rute, 'MTO_PRODUKSI');
  });

  test('perluQc true dari server terbaca', () {
    expect(Produk.fromJson(katalog(perluQc: true)).perluQc, isTrue);
  });
}
