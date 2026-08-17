import 'package:ebisnis/services/pengaturan_koreksi_transaksi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default edit aktif untuk mempertahankan fungsi lama', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PengaturanKoreksiTransaksi.instance.muat();
    expect(PengaturanKoreksiTransaksi.instance.izinkanEdit, isTrue);
  });

  test('pilihan edit tersimpan dan dimuat kembali', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await PengaturanKoreksiTransaksi.instance.simpan(false);
    PengaturanKoreksiTransaksi.instance.izinkanEdit = true;
    await PengaturanKoreksiTransaksi.instance.muat();
    expect(PengaturanKoreksiTransaksi.instance.izinkanEdit, isFalse);
  });
}
