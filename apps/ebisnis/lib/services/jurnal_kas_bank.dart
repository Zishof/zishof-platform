/// Pembentuk dua baris jurnal kas/bank dari satu nominal dan dua akun.
///
/// Posting tetap dilakukan oleh layanan jurnal yang sama; helper ini hanya
/// menyusun baris yang dikirim bersama draf dan tidak mengirim perubahan sendiri.
class JurnalKasBankDraft {
  JurnalKasBankDraft._();

  static List<Map<String, dynamic>> buat({
    required bool pengeluaran,
    required int akunKasBank,
    required int akunPasangan,
    required double nominal,
    required String keterangan,
  }) {
    if (akunKasBank <= 0 || akunPasangan <= 0) {
      throw ArgumentError('Rekening kas/bank dan akun pasangan wajib dipilih.');
    }
    if (akunKasBank == akunPasangan) {
      throw ArgumentError('Rekening kas/bank dan akun pasangan harus berbeda.');
    }
    if (!nominal.isFinite || nominal <= 0) {
      throw ArgumentError('Nominal harus lebih besar dari nol.');
    }

    final uraian = keterangan.trim();
    if (uraian.isEmpty) {
      throw ArgumentError('Keterangan jurnal wajib diisi.');
    }

    final barisKasBank = <String, dynamic>{
      'akunId': akunKasBank,
      'debet': pengeluaran ? 0.0 : nominal,
      'kredit': pengeluaran ? nominal : 0.0,
      'keterangan': uraian,
    };
    final barisPasangan = <String, dynamic>{
      'akunId': akunPasangan,
      'debet': pengeluaran ? nominal : 0.0,
      'kredit': pengeluaran ? 0.0 : nominal,
      'keterangan': uraian,
    };

    return pengeluaran
        ? <Map<String, dynamic>>[barisPasangan, barisKasBank]
        : <Map<String, dynamic>>[barisKasBank, barisPasangan];
  }
}
