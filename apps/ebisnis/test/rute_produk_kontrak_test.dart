import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/models.dart';

/// Kontrak Fase C (dok. 48 P3): rute pemenuhan ulang stok pada Produk.
///
/// Klien hanya menyunting konfigurasi; penjadwal SERVER yang membacanya
/// (BELI -> pengajuan pembelian, PRODUKSI -> draf Work Order). Uji ini
/// menjaga pemetaan JSON dan nilai bawaan: katalog lama tanpa `rute` harus
/// tetap terbaca sebagai BELI (string kosong), bukan error.
void main() {
  Map<String, dynamic> katalog({String? rute}) => {
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
      };

  test('katalog lama tanpa rute -> kosong (= BELI, perilaku hari ini)', () {
    expect(Produk.fromJson(katalog()).rute, '');
  });

  test('rute PRODUKSI dari server terbaca apa adanya', () {
    expect(Produk.fromJson(katalog(rute: 'PRODUKSI')).rute, 'PRODUKSI');
  });
}
