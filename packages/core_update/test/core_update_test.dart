import 'package:flutter_test/flutter_test.dart';

import 'package:core_update/core_update.dart';

void main() {
  final assets = <dynamic>[
    {
      'name': 'eBisnis-Setup-1.33.22.exe',
      'browser_download_url': 'https://example.test/ebisnis.exe'
    },
    {
      'name': 'Al-Bahjah-POS-Setup-1.33.22.exe',
      'browser_download_url': 'https://example.test/albahjah.exe'
    },
    {
      'name': 'eBisnis-POS-1.33.22.apk',
      'browser_download_url': 'https://example.test/ebisnis.apk'
    },
    {
      'name': 'Al-Bahjah-POS-1.33.22.apk',
      'browser_download_url': 'https://example.test/albahjah.apk'
    },
    {
      'name': 'TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.30.exe',
      'browser_download_url': 'https://example.test/nahl.exe'
    },
  ];

  test('pemilih aset mempertahankan varian Al-Bahjah', () {
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.exe'], keyword: 'albahjah'),
        'https://example.test/albahjah.exe');
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.apk'], keyword: 'albahjah'),
        'https://example.test/albahjah.apk');
  });

  test('pemilih aset mempertahankan varian eBisnis', () {
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.exe'], keyword: 'ebisnis'),
        'https://example.test/ebisnis.exe');
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.apk'], keyword: 'ebisnis'),
        'https://example.test/ebisnis.apk');
  });

  test('tidak fallback ke eBisnis bila aset varian tidak tersedia', () {
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.exe'], keyword: 'apotik'),
        isNull);
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(assets,
            ekstensi: const ['.apk'], keyword: 'inventorysales'),
        isNull);
  });

  test('aset Nahl yang memuat kata Al-Bahjah ditolak kanal Al-Bahjah', () {
    final hanyaNahl = [assets.last];
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(hanyaNahl,
            ekstensi: const ['.exe'], keyword: 'albahjah'),
        isNull);
    expect(
        UpdateChecker.pilihAssetSesuaiVarian(hanyaNahl,
            ekstensi: const ['.exe'], keyword: 'nahl'),
        'https://example.test/nahl.exe');
  });

  test('rilis terbaru dipilih hanya di dalam kanal variannya', () {
    final releases = <dynamic>[
      {
        'tag_name': 'nahl-v1.34.30-uat',
        'draft': false,
      },
      {
        'tag_name': 'albahjah-v1.34.29-uat',
        'draft': false,
      },
      {
        'tag_name': 'albahjah-v1.34.28-uat',
        'draft': false,
      },
    ];
    expect(
        UpdateChecker.pilihRilisSesuaiKanal(releases, 'albahjah-')!['tag_name'],
        'albahjah-v1.34.29-uat');
    expect(UpdateChecker.pilihRilisSesuaiKanal(releases, 'nahl-')!['tag_name'],
        'nahl-v1.34.30-uat');
  });

  test('cekTerbaru mengembalikan null jika repo tak terjangkau', () async {
    final info = await UpdateChecker.cekTerbaru(
      repoOwner: 'tidak-ada-user-seperti-ini-xyz',
      repoName: 'tidak-ada-repo-seperti-ini-xyz',
      versiSaatIni: '1.0.0',
    );
    expect(info, isNull);
  });
}
