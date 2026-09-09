/// Hasil pemeriksaan nominal pembayaran yang akan memotong saldo member.
///
/// Perhitungan ini sengaja dipisahkan dari layar Kasir supaya aturan batasnya
/// dapat diuji tanpa jaringan. Saldo yang dipakai oleh pemanggil tetap harus
/// berasal dari server tepat sebelum checkout; snapshot lokal hanya untuk
/// tampilan dan tidak pernah menjadi otorisasi pembayaran.
class HasilValidasiSaldoPembayaran {
  final double saldo;
  final double nominal;

  const HasilValidasiSaldoPembayaran({
    required this.saldo,
    required this.nominal,
  });

  bool get mencukupi => saldo + 0.0001 >= nominal;

  double get kekurangan {
    final selisih = nominal - saldo;
    return selisih > 0 ? selisih : 0;
  }
}

class ValidasiSaldoPembayaran {
  ValidasiSaldoPembayaran._();

  static HasilValidasiSaldoPembayaran evaluasi({
    required num saldo,
    required num nominal,
  }) {
    final saldoAman = saldo.toDouble();
    final nominalAman = nominal.toDouble();
    if (!saldoAman.isFinite || saldoAman < 0) {
      throw ArgumentError.value(
          saldo, 'saldo', 'harus berupa angka nonnegatif');
    }
    if (!nominalAman.isFinite || nominalAman <= 0) {
      throw ArgumentError.value(
          nominal, 'nominal', 'harus berupa angka positif');
    }
    return HasilValidasiSaldoPembayaran(
      saldo: saldoAman,
      nominal: nominalAman,
    );
  }
}
