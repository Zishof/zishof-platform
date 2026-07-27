import 'package:flutter_test/flutter_test.dart';

import 'package:core_device/core_device.dart';

void main() {
  test('IdentitasMesin.instance singleton stabil', () {
    expect(IdentitasMesin.instance, same(IdentitasMesin.instance));
  });
}
