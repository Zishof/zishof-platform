/// Kebijakan murni untuk menjaga checkout POS tetap dapat dipakai ketika
/// penyegaran metode pembayaran gagal atau masih menunggu server.
///
/// Snapshot hanya boleh dipakai bila berasal dari konteks yang sama. Konteks
/// dibedakan sampai tenant, pengguna, toko, dan member agar izin pembayaran
/// milik satu kasir/member tidak pernah bocor ke transaksi lain.
class KebijakanOfflinePembayaran {
  KebijakanOfflinePembayaran._();

  static String kunciCache({
    required String varian,
    required int? tenantId,
    required String userId,
    required int? tokoId,
    required int? memberId,
  }) {
    final pengguna = Uri.encodeComponent(
        userId.trim().isEmpty ? 'tanpa-pengguna' : userId.trim());
    return 'pos:cara_bayar:$varian:'
        'tenant-${tenantId ?? 0}:'
        'pengguna-$pengguna:'
        'toko-${tokoId ?? 0}:'
        'member-${memberId ?? 'umum'}';
  }

  static bool snapshotSesuai({
    required bool konteksSiap,
    required int? konteksSnapshotMemberId,
    required int? memberAktifId,
  }) =>
      konteksSiap && konteksSnapshotMemberId == memberAktifId;

  /// Picker boleh dibuka saat penyegaran berlangsung bila snapshot yang aman
  /// sudah ada. Tanpa snapshot, ketukan ditahan agar permintaan tidak rangkap.
  static bool bolehBukaPemilih({
    required bool terkunci,
    required bool sedangMemuat,
    required bool punyaSnapshot,
    required bool konteksSesuai,
  }) =>
      !terkunci && (!sedangMemuat || (punyaSnapshot && konteksSesuai));

  /// Penyegaran server bukan syarat pembayaran. Yang menjadi syarat adalah
  /// pilihan dari snapshot berkonteks sama; validasi saldo, PIN, dan otorisasi
  /// sensitif tetap dijalankan oleh alur checkout masing-masing.
  static bool bolehBayar({
    required bool sedangMemproses,
    required bool punyaPilihan,
    required bool adaKeranjang,
    required bool uangTunaiKurang,
    required bool konteksSesuai,
  }) =>
      !sedangMemproses &&
      punyaPilihan &&
      adaKeranjang &&
      !uangTunaiKurang &&
      konteksSesuai;
}
