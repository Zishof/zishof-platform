import 'package:ebisnis/services/pengaturan_nomor_struk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('format tanggal urut menyertakan nonce anti bentrok', () async {
    await PengaturanNomorStruk.instance
        .simpanFormat(FormatNomorStruk.tanggalUrut);

    final pertama = await PengaturanNomorStruk.instance.buatNomor();
    final kedua = await PengaturanNomorStruk.instance.buatNomor();

    expect(pertama, matches(RegExp(r'^\d{13}-[A-Z0-9]{6}$')));
    expect(kedua, matches(RegExp(r'^\d{13}-[A-Z0-9]{6}$')));
    expect(pertama, isNot(equals(kedua)));
  });
}
