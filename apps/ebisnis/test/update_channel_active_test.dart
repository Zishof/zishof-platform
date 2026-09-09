import 'package:ebisnis/app_variant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('varian aktif memakai kanal update yang tepat', () {
    if (AppVariant.kode == 'albahjah') {
      expect(AppVariant.updateAssetKeyword, 'albahjah');
      expect(AppVariant.updateTagPrefix, 'albahjah-');
    } else if (AppVariant.kode == 'nahl') {
      expect(AppVariant.updateAssetKeyword, 'nahl');
      expect(AppVariant.updateTagPrefix, 'nahl-');
    } else if (AppVariant.isEBisnis) {
      expect(AppVariant.updateAssetKeyword, 'ebisnis');
      expect(AppVariant.updateTagPrefix, 'v');
    } else {
      fail('Varian aktif belum memiliki kontrak kanal di tes ini.');
    }
  });
}
