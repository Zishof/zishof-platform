import 'package:flutter/foundation.dart';

import '../models/aturan_diskon.dart';
import '../models/keranjang_item.dart';
import 'diskon_engine.dart';
import 'sesi.dart';

/// Keranjang belanja member. Boleh memuat produk dari BEBERAPA toko sekaligus;
/// saat checkout isinya dipecah per toko menjadi satu transaksi per toko --
/// sama seperti versi JSP.
class Keranjang extends ChangeNotifier {
  Keranjang._();
  static final Keranjang instance = Keranjang._();

  final List<KeranjangItem> items = [];
  List<AturanDiskon> aturan = [];

  /// Meja kantin hasil scan QR. Null berarti belum memilih.
  String? idMeja;
  String? namaMeja;
  bool bawaPulang = false;

  int get jumlahItem =>
      items.fold(0, (sebelum, item) => sebelum + item.jumlah);

  double get subtotal =>
      items.fold(0.0, (sebelum, item) => sebelum + item.subtotal);

  double get totalDiskon =>
      items.fold(0.0, (sebelum, item) => sebelum + item.diskon);

  double get totalCashback =>
      items.fold(0.0, (sebelum, item) => sebelum + item.cashback);

  /// Yang benar-benar dibayar: cashback TIDAK mengurangi tagihan.
  double get grandTotal => subtotal - totalDiskon;

  void setAturan(List<AturanDiskon> nilai) {
    aturan = nilai;
    hitungUlang();
  }

  void tambah(KeranjangItem baru) {
    final adaIndex = items.indexWhere(
        (e) => e.id == baru.id && e.idToko == baru.idToko);
    if (adaIndex >= 0) {
      items[adaIndex].jumlah += baru.jumlah;
    } else {
      items.add(baru);
    }
    hitungUlang();
  }

  void ubahJumlah(int index, int delta) {
    if (index < 0 || index >= items.length) return;
    items[index].jumlah += delta;
    if (items[index].jumlah <= 0) {
      items.removeAt(index);
    }
    hitungUlang();
  }

  void setJumlah(int index, int nilai) {
    if (index < 0 || index >= items.length) return;
    if (nilai <= 0) {
      items.removeAt(index);
    } else {
      items[index].jumlah = nilai;
    }
    hitungUlang();
  }

  void hapus(int index) {
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    hitungUlang();
  }

  void kosongkan() {
    items.clear();
    idMeja = null;
    namaMeja = null;
    bawaPulang = false;
    notifyListeners();
  }

  void pilihMeja(String id, String nama) {
    idMeja = id;
    namaMeja = nama;
    bawaPulang = false;
    notifyListeners();
  }

  void hapusMeja() {
    idMeja = null;
    namaMeja = null;
    notifyListeners();
  }

  void setBawaPulang(bool nilai) {
    bawaPulang = nilai;
    if (nilai) {
      idMeja = null;
      namaMeja = null;
    }
    notifyListeners();
  }

  void hitungUlang() {
    DiskonEngine.hitungUlang(
      items,
      aturan,
      idJenisAnggota: Sesi.instance.idJenisAnggota,
      idTipeAnggota: Sesi.instance.idTipeAnggota,
    );
    notifyListeners();
  }

  /// Kelompokkan isi keranjang per toko utk checkout.
  Map<String, List<KeranjangItem>> kelompokPerToko() {
    final peta = <String, List<KeranjangItem>>{};
    for (final item in items) {
      peta.putIfAbsent(item.idToko, () => []).add(item);
    }
    return peta;
  }
}
