import 'package:core_auth/core_auth.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('token tersimpan memulihkan tenant dan pengguna untuk local-first',
      () async {
    SharedPreferences.setMockInitialValues({
      'token': 'token-uji',
      'tenant_id': 41,
      'tenant_kode': 'abchicken',
      'tenant_nama': 'AB Chicken',
    });
    await VerifikatorSandiLokal.instance
        .simpan('abchicken@gmail.com', 'sandi-uji-yang-tidak-disimpan');
    Sesi.instance.reset();

    await ApiClient.instance.muatTokenTersimpan();

    expect(ApiClient.instance.sudahLogin, isTrue);
    expect(Sesi.instance.tenantId, 41);
    expect(Sesi.instance.tenantKode, 'abchicken');
    expect(Sesi.instance.userId, 'abchicken@gmail.com');

    await ApiClient.instance.hapusToken();
  });
}
