import 'package:core_device/core_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pembangkit nomor antrean yang tetap bekerja tanpa jaringan.
///
/// Nomor dipisahkan per toko, perangkat, dan tanggal. Awalan perangkat
/// mencegah dua kasir offline menghasilkan nomor yang sama pada outlet yang
/// sama, sedangkan urutan harian membuat nomor tetap singkat untuk dipanggil.
class PengaturanNomorAntrian {
  PengaturanNomorAntrian._();

  static final instance = PengaturanNomorAntrian._();

  Future<String> buat({required int tokoId}) async {
    await IdentitasMesin.instance.muat();
    final perangkat = IdentitasMesin.instance.idMesin
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .padRight(2, '0')
        .substring(0, 2);
    final sekarang = DateTime.now();
    final tanggal =
        '${sekarang.year}${sekarang.month.toString().padLeft(2, '0')}${sekarang.day.toString().padLeft(2, '0')}';
    final dasar = 'nomor_antrian_${tokoId}_${perangkat}_$tanggal';
    final prefs = await SharedPreferences.getInstance();
    final urutan = (prefs.getInt(dasar) ?? 0) + 1;
    await prefs.setInt(dasar, urutan);
    return '$perangkat-${urutan.toString().padLeft(3, '0')}';
  }
}
