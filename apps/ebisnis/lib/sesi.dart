import 'models.dart';

/// Data toko/kasir yang sedang login -- diisi sekali sesudah aksi "konfigurasi"
/// dipanggil (lihat KasirScreen.initState), dipakai layar-layar berikutnya
/// tanpa perlu meminta ulang ke server (pajak, nama toko, daftar cara bayar).
class Sesi {
  Sesi._();
  static final Sesi instance = Sesi._();

  String tokoNama = '';
  int? tokoId;
  String userId = '';
  double pajakPersen = 0;
  List<CaraBayar> caraBayar = [];
  String pesanTerimaKasih = '';

  void reset() {
    tokoNama = '';
    tokoId = null;
    userId = '';
    pajakPersen = 0;
    caraBayar = [];
    pesanTerimaKasih = '';
  }
}
