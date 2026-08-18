/// Kebijakan kontak per Tipe Member (cermin server
/// `TipeAnggotaKoperasi.defaultWajibHp`): dipakai sbg fallback saat server
/// lama belum mengirim field `wajibHp`/`wajibEmail`, dan sbg nilai awal form
/// Tipe Member baru. Sumber kebenaran tetap nilai eksplisit dari server.
library;

/// Default "Wajib Memasukkan No. HP" berdasarkan NAMA tipe: Pegawai, Dosen,
/// Guru, dan Umum wajib; Mahasiswa/Siswa (dan lainnya) tidak.
bool defaultWajibHpTipe(String? nama) {
  final n = (nama ?? '').trim().toLowerCase();
  if (n.isEmpty) return false;
  return n.contains('pegawai') ||
      n.contains('dosen') ||
      n.contains('guru') ||
      n.contains('umum');
}

/// Ambil kebijakan wajib-HP dari satu baris tipe (respons server), dgn
/// fallback default per nama utk server yang belum mengirim field-nya.
bool wajibHpDariTipe(Map<String, dynamic>? tipe) {
  if (tipe == null) return false;
  final eksplisit = tipe['wajibHp'];
  if (eksplisit is bool) return eksplisit;
  return defaultWajibHpTipe('${tipe['nama'] ?? ''}');
}

/// Email tidak wajib utk semua tipe kecuali disetel eksplisit oleh admin.
bool wajibEmailDariTipe(Map<String, dynamic>? tipe) {
  if (tipe == null) return false;
  final eksplisit = tipe['wajibEmail'];
  return eksplisit is bool && eksplisit;
}
