import 'package:flutter_test/flutter_test.dart';

import 'package:core_update/core_update.dart';

void main() {
  test('cekTerbaru mengembalikan null jika repo tak terjangkau', () async {
    final info = await UpdateChecker.cekTerbaru(
      repoOwner: 'tidak-ada-user-seperti-ini-xyz',
      repoName: 'tidak-ada-repo-seperti-ini-xyz',
      versiSaatIni: '1.0.0',
    );
    expect(info, isNull);
  });
}
