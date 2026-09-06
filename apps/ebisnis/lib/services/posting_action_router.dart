/// Menentukan endpoint posting berdasarkan varian aplikasi.
///
/// Apotik/eMedic mempunyai sumber transaksi dan tabel penanda posting sendiri.
/// Mengirim layar Apotik ke endpoint toko generik akan membaca transaksi Kantin,
/// sehingga pemilihan endpoint harus eksplisit dan mudah dikunci oleh unit test.
String aksiPostingKeuangan({
  required bool apotik,
  required String jenis,
  required bool terapkan,
}) {
  if (!apotik) return 'laporan_keuangan_pendukung';
  return 'apotik_posting_${jenis}_${terapkan ? 'terapkan' : 'draft'}';
}

/// Endpoint rantai pengadaan Apotik yang sudah mempunyai jurnal khusus.
///
/// Proses Apotik yang belum mempunyai endpoint khusus ditolak fail-closed agar
/// layar tidak pernah membaca atau memposting transaksi Kantin secara keliru.
String aksiPostingToko({
  required bool apotik,
  required String jenis,
  required bool terapkan,
}) {
  if (apotik && jenis == 'kulakan') {
    return 'apotik_posting_pbf_${terapkan ? 'terapkan' : 'draft'}';
  }
  if (apotik && jenis == 'bayar_hutang') {
    return 'apotik_posting_bayar_hutang_pbf_${terapkan ? 'terapkan' : 'draft'}';
  }
  if (apotik) {
    throw UnsupportedError(
        'Posting $jenis belum mempunyai endpoint khusus Apotik.');
  }
  return 'posting_${jenis}_${terapkan ? 'terapkan' : 'draft'}';
}
