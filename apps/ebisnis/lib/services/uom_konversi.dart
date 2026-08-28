/// Kalkulator pratinjau UOM. Mutasi stok server tetap wajib menyimpan snapshot
/// qty input, faktor, dan qty dasar dengan presisi database.
class UomKonversi {
  const UomKonversi._();

  static double faktorKeAcuan(Map<String, dynamic>? uom) {
    if (uom == null) return 1;
    final langsung = (uom['faktorKeAcuan'] as num?)?.toDouble();
    if (langsung != null && langsung > 0) return langsung;
    final rasio = (uom['rasio'] as num?)?.toDouble() ?? 1;
    if (rasio <= 0) {
      throw const FormatException('Rasio UOM harus lebih dari 0.');
    }
    return '${uom['tipeKonversi'] ?? 'REFERENCE'}'.toUpperCase() == 'SMALLER'
        ? 1 / rasio
        : rasio;
  }

  static double konversi({
    required double jumlah,
    required Map<String, dynamic> dari,
    required Map<String, dynamic> ke,
  }) {
    final kategoriDari = '${dari['kategori'] ?? 'UNIT'}'.toUpperCase();
    final kategoriKe = '${ke['kategori'] ?? 'UNIT'}'.toUpperCase();
    if (kategoriDari != kategoriKe) {
      throw FormatException(
          'UOM $kategoriDari tidak dapat dikonversi ke $kategoriKe.');
    }
    return jumlah * faktorKeAcuan(dari) / faktorKeAcuan(ke);
  }
}
