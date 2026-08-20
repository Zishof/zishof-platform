/// Satu baris di keranjang belanja.
///
/// [diskon] dan [cashback] TIDAK diisi pengguna: keduanya hasil evaluasi
/// aturan diskon (lihat DiskonEngine) dan dikirim apa adanya ke server, sama
/// seperti versi JSP. Server tetap menghitung ulang saat finalisasi.
class KeranjangItem {
  final String id;
  final String kode;
  final String nama;
  final double harga;
  final String idToko;
  final String namaToko;

  int jumlah;
  double diskon;
  double cashback;
  String? aturanDiskon;
  bool berlakuPerHariDanPerToko;

  KeranjangItem({
    required this.id,
    required this.kode,
    required this.nama,
    required this.harga,
    required this.idToko,
    required this.namaToko,
    this.jumlah = 1,
    this.diskon = 0,
    this.cashback = 0,
    this.aturanDiskon,
    this.berlakuPerHariDanPerToko = false,
  });

  double get subtotal => harga * jumlah;
  double get totalSetelahDiskon => subtotal - diskon;

  /// Bentuk yang diterima aksi `kantin_bayar` / `kantin_draft_bayar`.
  Map<String, dynamic> keJsonTransaksi() => {
        'id': id,
        'kode': kode,
        'nama': nama,
        'harga': harga,
        'jumlah': jumlah,
        'diskon': diskon,
        'aturanDiskon': aturanDiskon,
        'cashback': cashback,
        'berlakuPerHariDanPerToko': berlakuPerHariDanPerToko,
      };
}
