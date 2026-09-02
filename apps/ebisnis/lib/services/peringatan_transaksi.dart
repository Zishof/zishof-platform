/// Pembaca **saluran peringatan pasca-transaksi** dari respons `bayar`.
///
/// Peringatan pasca-transaksi semuanya berbentuk sama: transaksi DITERIMA, tetapi
/// ada sesuatu yang perlu direkonsiliasi belakangan — stok minus, sesi kas yang
/// sudah ditutup, persetujuan limit yang gagal ditandai.
///
/// Dahulu masing-masing berupa field lepas pada respons, dan lima dari enam tidak
/// pernah dibaca kanal mana pun (docs/pos/79). Sebabnya struktural: setiap field
/// baru menuntut empat titik di aplikasi ini disentuh — bayar massal, bayar
/// tunggal, outbox, dan struk. Yang ketujuh pasti terlupa juga.
///
/// Server kini mengirim SATU daftar (`peringatanTransaksi`), dan kelas ini satu-
/// satunya tempat daftar itu dibaca. Peringatan berikutnya tidak menuntut satu
/// baris pun diubah di sini.
class PeringatanTransaksi {
  PeringatanTransaksi._();

  /// Kalimat peringatan dari sebuah respons `bayar`, siap ditampilkan apa adanya.
  ///
  /// Kosong berarti tidak ada yang perlu ditindaklanjuti.
  static List<String> dari(Map<String, dynamic>? respons) {
    if (respons == null) return const [];

    final daftar = respons['peringatanTransaksi'];
    if (daftar is List) {
      final hasil = <String>[];
      for (final e in daftar) {
        if (e is Map) {
          final pesan = '${e['pesan'] ?? ''}'.trim();
          if (pesan.isNotEmpty) hasil.add(pesan);
        } else {
          // Daftar berisi string polos juga diterima -- bentuk yang mungkin
          // dipakai versi server lain; menolaknya hanya membuang peringatan.
          final pesan = '$e'.trim();
          if (pesan.isNotEmpty) hasil.add(pesan);
        }
      }
      if (hasil.isNotEmpty) return hasil;
    }

    // Peladen yang BELUM mengirim saluran ini masih memakai field tunggal
    // `peringatanStok`. Dibaca sebagai cadangan supaya aplikasi yang diperbarui
    // lebih dulu daripada servernya tidak mendadak berhenti memperingatkan.
    final tunggal = '${respons['peringatanStok'] ?? ''}'.trim();
    return tunggal.isEmpty ? const [] : [tunggal];
  }

  /// Gabungan seluruh peringatan menjadi satu kalimat, untuk tempat yang hanya
  /// menyediakan satu baris (snackbar). Kosong bila tidak ada peringatan.
  static String gabung(Map<String, dynamic>? respons) => dari(respons).join(' ');
}
