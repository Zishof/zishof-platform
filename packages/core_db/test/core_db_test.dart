import 'package:flutter_test/flutter_test.dart';

import 'package:core_db/core_db.dart';

void main() {
  test('CoreDb.instance singleton stabil', () {
    expect(CoreDb.instance, same(CoreDb.instance));
  });
}
