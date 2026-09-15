import 'package:core_device/core_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pemuatan bersamaan dan pemuatan ulang mempertahankan satu ID',
      () async {
    SharedPreferences.setMockInitialValues({});
    final mesin = IdentitasMesin.instance;
    await Future.wait(List.generate(20, (_) => mesin.muat()));
    final pertama = mesin.idMesin;
    expect(pertama, isNotEmpty);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('identitas_mesin_id'), pertama);
    await mesin.muat();
    expect(mesin.idMesin, pertama);
  });

  test('ID instalasi lama tidak diganti saat update', () async {
    SharedPreferences.setMockInitialValues(
        {'identitas_mesin_id': 'MESIN-LAMA'});
    await IdentitasMesin.instance.muat();
    expect(IdentitasMesin.instance.idMesin, 'MESIN-LAMA');
  });
}
