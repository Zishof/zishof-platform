import 'package:ebisnis/services/abchicken_feature_contract.dart';
import 'package:ebisnis/services/platform_parity_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seluruh 58 kebutuhan DKB terdaftar satu kali', () {
    expect(AbChickenFeatureContract.features, hasLength(58));
    final ids = AbChickenFeatureContract.features.map((e) => e.id).toSet();
    expect(ids, hasLength(58));
    for (var number = 1; number <= 58; number++) {
      expect(ids, contains('DKB-${number.toString().padLeft(2, '0')}'));
    }
  });

  test('setiap fitur punya menu dan aksi yang jelas', () {
    for (final feature in AbChickenFeatureContract.features) {
      expect(feature.department.trim(), isNotEmpty, reason: feature.id);
      expect(feature.menuPath, contains('>'), reason: feature.id);
      expect(feature.actions, isNotEmpty, reason: feature.id);
    }
  });

  test('Windows dan Android mendukung kontrak bisnis yang sama', () {
    for (final feature in AbChickenFeatureContract.features) {
      expect(feature.supports(EbisnisPlatform.desktop), isTrue,
          reason: feature.id);
      expect(feature.supports(EbisnisPlatform.android), isTrue,
          reason: feature.id);
      expect(feature.desktopMode.trim(), isNotEmpty, reason: feature.id);
      expect(feature.androidMode.trim(), isNotEmpty, reason: feature.id);
    }
  });

  test('platform lain bukan target build resmi ABChicken', () {
    expect(AbChickenFeatureContract.officialPlatforms,
        {EbisnisPlatform.desktop, EbisnisPlatform.android});
    expect(AbChickenFeatureContract.byId('DKB-29').androidMode,
        'device-camera-biometric');
    expect(AbChickenFeatureContract.byId('DKB-07').desktopMode, 'qr-publisher');
  });
}
