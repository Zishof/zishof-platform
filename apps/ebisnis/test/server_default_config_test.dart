import 'package:ebisnis/app_setting.dart';
import 'package:ebisnis/app_variant.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('server bawaan sesuai varian build', () {
    if (AppVariant.isAlBahjah) {
      expect(AppSetting.baseUrlHost, 'ecampus.staialbahjah.ac.id');
      expect(AppSetting.baseUrlContextPath, 'albahjah');
    } else if (AppVariant.isNahl) {
      expect(AppSetting.baseUrlHost, 'an-nahl.santri.info');
      expect(AppSetting.baseUrlContextPath, 'nahl');
    } else {
      expect(AppSetting.baseUrlHost, 'ebisnis.id');
      expect(AppSetting.baseUrlContextPath, 'ebisnis');
    }
    expect(AppSetting.baseUrlHttps, isTrue);
  });

  test('instalasi baru langsung memakai server bawaan varian', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await ServerConfig.instance.muat();

    expect(ServerConfig.instance.host, AppSetting.baseUrlHost);
    expect(
      ServerConfig.instance.contextPath,
      AppSetting.baseUrlContextPath,
    );
    expect(ServerConfig.instance.https, isTrue);
  });

  test('alamat bawaan pilot lama dimigrasikan tanpa menyentuh Al-Bahjah',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_host': 'dev.ecampus.id',
      'server_context_path': 'ecampus',
      'server_https': true,
    });

    await ServerConfig.instance.muat();

    if (AppVariant.isAlBahjah) {
      expect(ServerConfig.instance.host, 'dev.ecampus.id');
      expect(ServerConfig.instance.contextPath, 'ecampus');
    } else if (AppVariant.isNahl) {
      expect(ServerConfig.instance.host, 'an-nahl.santri.info');
      expect(ServerConfig.instance.contextPath, 'nahl');
    } else {
      expect(ServerConfig.instance.host, 'ebisnis.id');
      expect(ServerConfig.instance.contextPath, 'ebisnis');
    }
  });

  test('konfigurasi Al-Bahjah lama tidak bocor ke build eBisnis', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'server_host': 'ecampus.staialbahjah.ac.id',
      'server_context_path': 'albahjah',
      'server_https': true,
    });

    await ServerConfig.instance.muat();

    if (AppVariant.isAlBahjah) {
      expect(ServerConfig.instance.host, 'ecampus.staialbahjah.ac.id');
      expect(ServerConfig.instance.contextPath, 'albahjah');
    } else if (AppVariant.isNahl) {
      expect(ServerConfig.instance.host, 'an-nahl.santri.info');
      expect(ServerConfig.instance.contextPath, 'nahl');
    } else {
      expect(ServerConfig.instance.host, 'ebisnis.id');
      expect(ServerConfig.instance.contextPath, 'ebisnis');
    }
  });

  test('kunci server tersimpan memakai namespace varian', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfig.instance.simpan(
      host: AppSetting.baseUrlHost,
      contextPath: AppSetting.baseUrlContextPath,
      https: true,
    );
    final sp = await SharedPreferences.getInstance();

    expect(
      sp.getString('${AppVariant.storageNamespace}_server_host'),
      AppSetting.baseUrlHost,
    );
    expect(sp.getString('server_host'), isNull);
  });
}
