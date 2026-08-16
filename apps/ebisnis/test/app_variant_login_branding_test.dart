import 'package:ebisnis/app_variant.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identitas login mengikuti build varian dan aset latar tersedia',
      () async {
    expect(AppVariant.subJudulLogin, isNot('Masuk sebagai Kasir'));
    expect(
      AppVariant.loginBackgroundAsset,
      contains(
          'assets/images/${AppVariant.kode == 'default' ? 'ebisnis' : AppVariant.kode}/'),
    );

    final data = await rootBundle.load(AppVariant.loginBackgroundAsset);
    expect(data.lengthInBytes, greaterThan(0));
  });
}
