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
    } else if (AppVariant.kode == 'abchicken') {
      expect(AppVariant.updateAssetKeyword, 'abchicken');
      expect(AppVariant.updateTagPrefix, 'abchicken-');
    } else {
      fail(
          'Tes ini harus dijalankan dengan varian albahjah, nahl, atau abchicken.');
    }
  });
}
