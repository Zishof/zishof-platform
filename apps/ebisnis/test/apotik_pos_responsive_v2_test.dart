import 'package:ebisnis/features/apotik/core/apotik_breakpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('capability POS berdasarkan inner width', () {
    const sempit = [560.0, 760.0, 960.0];
    const duaArea = [980.0, 1040.0, 1120.0, 1280.0, 1520.0];

    for (final lebar in sempit) {
      test('$lebar memakai sheet dan bottom cart capability', () {
        final hasil = ApotikBreakpoints.kemampuanPos(lebar);
        expect(hasil.bolehKeranjangTetap, isFalse);
        expect(hasil.bolehPanelKonteksTetap, isFalse);
        expect(hasil.tampilkanBottomCart, isTrue);
      });
    }

    for (final lebar in duaArea) {
      test('$lebar mempertahankan keranjang tanpa panel konteks', () {
        final hasil = ApotikBreakpoints.kemampuanPos(lebar);
        expect(hasil.bolehKeranjangTetap, isTrue);
        expect(hasil.bolehPanelKonteksTetap, isFalse);
        expect(hasil.tampilkanBottomCart, isFalse);
      });
    }

    test('1680 memberi ruang untuk tiga area', () {
      final hasil = ApotikBreakpoints.kemampuanPos(1680);
      expect(hasil.bolehKeranjangTetap, isTrue);
      expect(hasil.bolehPanelKonteksTetap, isTrue);
      expect(hasil.tampilkanBottomCart, isFalse);
    });
  });
}
