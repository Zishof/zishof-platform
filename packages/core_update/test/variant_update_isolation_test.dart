import 'dart:convert';
import 'dart:io';

import 'package:core_update/core_update.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/nahl_1_34_37_update.dart' as installed;

Map<String, dynamic> release(String variant, String version,
        {bool prerelease = false, String? assetVariant}) =>
    {
      'tag_name': '$variant-v$version',
      'draft': false,
      'prerelease': prerelease,
      'html_url': 'https://example.test/$variant-v$version',
      'assets': [
        for (final suffix in ['.apk', '-Setup.exe', '-update.zip'])
          {
            'name': '${assetVariant ?? variant}-$version$suffix',
            'browser_download_url':
                'https://example.test/${assetVariant ?? variant}-$version$suffix',
            'digest': 'sha256:${List.filled(64, 'a').join()}',
          },
      ],
    };

Future<InfoUpdate?> check(String variant, List<dynamic> releases,
    {String current = '1.34.37', bool legacyLatest = false}) async {
  final client = MockClient((request) async {
    expect(request.url.host, 'api.github.com');
    if (legacyLatest) {
      expect(request.url.path, endsWith('/releases/latest'));
      return http.Response(jsonEncode(releases.first), 200);
    }
    expect(request.url.path, endsWith('/releases'));
    return http.Response(jsonEncode(releases), 200);
  });
  try {
    return await UpdateChecker.cekTerbaru(
      repoOwner: 'test',
      repoName: 'pos',
      versiSaatIni: current,
      assetKeyword: variant,
      tagPrefix: legacyLatest ? null : '$variant-',
      client: client,
    );
  } finally {
    client.close();
  }
}

void main() {
  test('unduhan versi sama tidak berbagi berkas sementara antarinstalasi',
      () async {
    final body = utf8.encode('test-package');
    final digest = sha256.convert(body).toString();
    final packages = await http.runWithClient(
      () => Future.wait([
        for (final variant in ['albahjah', 'nahl'])
          WindowsUpdatePackage.unduhDanVerifikasi(
            url: 'https://example.test/$variant.zip',
            sha256Diharapkan: digest,
            versi: '1.34.39',
          ),
      ]),
      () => MockClient((request) async => http.Response.bytes(body, 200)),
    );
    try {
      expect(packages[0].path, isNot(packages[1].path));
      for (final file in packages) {
        expect(await file.readAsBytes(), body);
        expect(file.parent.parent.path, Directory.systemTemp.path);
      }
    } finally {
      for (final file in packages) {
        await file.delete();
        await file.parent.delete();
      }
    }
  });

  test('updater Nahl 1.34.37 asli mengabaikan publikasi baru Al-Bahjah',
      () async {
    final info = await http.runWithClient(
      () => installed.UpdateChecker.cekTerbaru(
        repoOwner: 'test',
        repoName: 'pos',
        versiSaatIni: '1.34.37',
        assetKeyword: 'nahl',
        tagPrefix: 'nahl-',
      ),
      () => MockClient((request) async {
        expect(request.url.path, endsWith('/releases'));
        return http.Response(
            jsonEncode([
              release('albahjah', '9.0.0'),
              release('nahl', '1.34.37'),
            ]),
            200);
      }),
    );
    expect(info, isNull);
  });

  test('updater Nahl terpasang tetap hanya memperoleh paket Nahl', () async {
    final info = await http.runWithClient(
      () => installed.UpdateChecker.cekTerbaru(
        repoOwner: 'test',
        repoName: 'pos',
        versiSaatIni: '1.34.37',
        assetKeyword: 'nahl',
        tagPrefix: 'nahl-',
      ),
      () => MockClient((request) async => http.Response(
          jsonEncode([
            release('albahjah', '9.0.0'),
            release('nahl', '1.34.38'),
          ]),
          200)),
    );
    expect(info!.versi, '1.34.38');
    expect(info.urlApk, contains('nahl-'));
    expect(info.urlExe, contains('nahl-'));
    expect(info.urlPaketWindows, contains('nahl-'));
  });

  test('publikasi Al-Bahjah tidak menjadi update Nahl terpasang', () async {
    final releases = [
      release('albahjah', '1.34.99'),
      release('nahl', '1.34.37')
    ];
    expect(await check('nahl', releases), isNull);
    final albahjah = await check('albahjah', releases);
    expect(albahjah!.versi, '1.34.99');
    expect(albahjah.urlApk, contains('albahjah-'));
    expect(albahjah.urlExe, contains('albahjah-'));
    expect(albahjah.urlPaketWindows, contains('albahjah-'));
  });

  test('kanal Nahl hanya memperoleh ketiga jenis aset Nahl', () async {
    final info = await check('nahl', [
      release('albahjah', '9.0.0'),
      release('nahl', '1.34.38'),
    ]);
    expect(info!.versi, '1.34.38');
    expect(info.urlApk, contains('nahl-'));
    expect(info.urlExe, contains('nahl-'));
    expect(info.urlPaketWindows, contains('nahl-'));
  });

  test('aset Al-Bahjah pada tag Nahl yang salah tidak ditawarkan', () async {
    expect(
      await check(
          'nahl', [release('nahl', '1.34.99', assetVariant: 'albahjah')]),
      isNull,
    );
  });

  test('ZIP Al-Bahjah An Nahl ditolak bersama APK dan EXE oleh Al-Bahjah',
      () async {
    expect(
      await check('albahjah', [
        release('albahjah', '1.34.99',
            assetVariant: 'TokoQu-Al-Bahjah-An-Nahl'),
      ]),
      isNull,
    );
  });

  test('fallback latest tanpa awalan tag tetap tidak memasang varian lain',
      () async {
    expect(
      await check('nahl', [release('albahjah', '9.0.0')], legacyLatest: true),
      isNull,
    );
  });

  test('prerelease dan draft lebih baru tidak masuk pembaruan otomatis',
      () async {
    final info = await check('albahjah', [
      release('albahjah', '1.34.99', prerelease: true),
      {...release('albahjah', '1.34.98'), 'draft': true},
      release('albahjah', '1.34.38'),
    ]);
    expect(info!.versi, '1.34.38');
    expect(
      await check(
          'albahjah', [release('albahjah', '1.34.99', prerelease: true)],
          legacyLatest: true),
      isNull,
    );
  });
}
