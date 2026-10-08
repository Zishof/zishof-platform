/// Menyiapkan payload finalisasi agar ID draft tidak disalahartikan server
/// sebagai ID header pembayaran yang sudah ada.
Map<String, dynamic> payloadBayarAman(
  Map<String, dynamic> payload, {
  required bool melanjutkanDraft,
}) {
  final hasil = Map<String, dynamic>.from(payload);
  if (melanjutkanDraft) {
    // Pada action `bayar`, `id` adalah ID PembelianAnggotaKoperasi. ID draft
    // dikirim lewat `draftPembelianAnggotaKoperasi` dan aliasnya. Mengirim ID
    // draft sebagai `id` melewati pencarian idempotensi berdasarkan kode nota,
    // sehingga retry draft yang sudah pernah tercatat bisa memotong saldo lagi.
    hasil.remove('id');
  }
  return hasil;
}
