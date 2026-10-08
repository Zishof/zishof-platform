import 'package:ebisnis/screens/riwayat_penjualan_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mulai = DateTime(2026, 10, 8);
  final sampai = DateTime(2026, 10, 9);

  test('rentang tanggal transaksi mencakup tanggal awal dan akhir', () {
    expect(
      tanggalTransaksiDalamRentang(
        DateTime(2026, 10, 8, 0, 1),
        mulai: mulai,
        sampai: sampai,
      ),
      isTrue,
    );
    expect(
      tanggalTransaksiDalamRentang(
        DateTime(2026, 10, 9, 23, 59),
        mulai: mulai,
        sampai: sampai,
      ),
      isTrue,
    );
  });

  test('rentang tanggal transaksi mengecualikan tanggal di luar pilihan', () {
    expect(
      tanggalTransaksiDalamRentang(
        DateTime(2026, 10, 7, 23, 59),
        mulai: mulai,
        sampai: sampai,
      ),
      isFalse,
    );
    expect(
      tanggalTransaksiDalamRentang(
        DateTime(2026, 10, 10),
        mulai: mulai,
        sampai: sampai,
      ),
      isFalse,
    );
  });

  test('tanpa batas tanggal menerima waktu apa pun, termasuk waktu kosong', () {
    expect(tanggalTransaksiDalamRentang(null), isTrue);
    expect(
      tanggalTransaksiDalamRentang(DateTime(2020), sampai: sampai),
      isTrue,
    );
  });

  test('waktu kosong ditolak saat filter tanggal sedang dipakai', () {
    expect(
      tanggalTransaksiDalamRentang(null, mulai: mulai, sampai: sampai),
      isFalse,
    );
  });
}
