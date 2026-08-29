import 'package:ebisnis/widgets/penawaran_sinkronisasi_versi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('penawaran sinkronisasi setelah instalasi/update', () {
    test('instalasi baru ditawarkan karena belum ada versi tersimpan', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+161',
          versiTerakhirDitawarkan: null,
        ),
        isTrue,
      );
    });

    test('versi/build yang sama tidak ditawarkan berulang', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+161',
          versiTerakhirDitawarkan: '1.34.03+161',
        ),
        isFalse,
      );
    });

    test('perubahan build maupun versi memicu penawaran baru', () {
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.03+162',
          versiTerakhirDitawarkan: '1.34.03+161',
        ),
        isTrue,
      );
      expect(
        PenawaranSinkronisasiVersi.perluDitawarkan(
          versiSaatIni: '1.34.04+163',
          versiTerakhirDitawarkan: '1.34.03+162',
        ),
        isTrue,
      );
    });

    test('kunci dipisahkan per tenant agar data usaha tidak tertukar', () {
      expect(
        PenawaranSinkronisasiVersi.kunciPenyimpanan(tenantId: 1),
        isNot(equals(PenawaranSinkronisasiVersi.kunciPenyimpanan(tenantId: 2))),
      );
    });
  });
}
