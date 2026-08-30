import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/services/url_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfig.instance.simpan(
      host: 'an-nahl.santri.info',
      contextPath: 'nahl',
      https: true,
    );
  });

  test('URL media proxy memakai origin server aktif', () {
    expect(
      normalisasiUrlMedia(
          'http://127.0.0.1:8080/nahl/AmbilMediaProduk?fotoId=17'),
      'https://an-nahl.santri.info/nahl/AmbilMediaProduk?fotoId=17',
    );
  });

  test('URL relatif media dilengkapi origin server aktif', () {
    expect(
      normalisasiUrlMedia('/nahl/AmbilMediaProduk?fotoId=18'),
      'https://an-nahl.santri.info/nahl/AmbilMediaProduk?fotoId=18',
    );
  });

  test('URL media tanpa context dipasang ke context server aktif', () {
    expect(
      normalisasiUrlMedia('http://127.0.0.1:8080/AmbilMediaProduk?fotoId=18'),
      'https://an-nahl.santri.info/nahl/AmbilMediaProduk?fotoId=18',
    );
  });

  test('foto profil eCampus mengikuti origin server aktif', () {
    expect(
      normalisasiUrlMedia(
          'http://server-internal:8080/nahl/AmbilMedia?clazz=FotoPegawai&id=7'),
      'https://an-nahl.santri.info/nahl/AmbilMedia?clazz=FotoPegawai&id=7',
    );
  });

  test('URL eksternal non-media tidak diubah', () {
    expect(
      normalisasiUrlMedia('https://cdn.example.org/foto.jpg'),
      'https://cdn.example.org/foto.jpg',
    );
  });

  test('fallback id foto membentuk URL servlet pada context aktif', () {
    expect(
      urlFotoProdukDariId(19),
      'https://an-nahl.santri.info/nahl/AmbilMediaProduk?fotoId=19',
    );
  });
}
