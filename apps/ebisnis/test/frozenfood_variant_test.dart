import 'package:ebisnis/product_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Profil frozenfood memiliki identitas dan fitur yang sesuai', () {
    const profile = AppProductProfile.frozenFood();
    expect(profile.kode, 'frozenfood');
    expect(profile.namaAplikasi, 'Sarimpi Jaya Frozen POS');
    expect(profile.namaSidebar, 'Sarimpi Jaya Frozen');
    expect(profile.logoAsset, 'assets/images/frozenfood/icon.png');
    expect(profile.fiturGrup, contains(FiturGrup.pos));
    expect(profile.tagRilisPrefix, 'frozenfood-');
    expect(profile.isFrozenFood, isTrue);
  });
}
