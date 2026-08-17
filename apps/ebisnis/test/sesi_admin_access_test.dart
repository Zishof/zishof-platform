import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    Sesi.instance.reset();
  });

  test('administrator melewati pembatasan seluruh menu POS dan varian', () {
    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': true,
      'aksesMenu': <String, dynamic>{
        'produk': false,
        'apotik_formularium': false,
      },
    });

    expect(Sesi.instance.bolehMenu('produk'), isTrue);
    expect(Sesi.instance.bolehMenuVarianBaru('apotik_formularium'), isTrue);
    expect(Sesi.instance.bolehAksiPos('produk', 'update'), isTrue);
  });

  test('pengguna biasa tetap mengikuti matriks hak akses', () {
    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': false,
      'aksesMenu': <String, dynamic>{
        'produk': false,
        'apotik_formularium': false,
      },
    });

    expect(Sesi.instance.bolehMenu('produk'), isFalse);
    expect(Sesi.instance.bolehMenuVarianBaru('apotik_formularium'), isFalse);
  });

  test('aksi pemulihan transaksi hanya tersedia untuk supervisor atau admin',
      () {
    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': false,
      'supervisorPedagang': false,
    });
    expect(Sesi.instance.bolehKelola, isFalse);

    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': false,
      'supervisorPedagang': true,
    });
    expect(Sesi.instance.bolehKelola, isTrue);
  });

  test('data sample wajib admin, toko demo, dan konfigurasi aktif sekaligus',
      () {
    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': true,
      'tokoDemo': true,
      'dataSampleEbisnis': true,
    });
    expect(Sesi.instance.bolehDataSample, isTrue);

    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': true,
      'tokoDemo': false,
      'dataSampleEbisnis': true,
    });
    expect(Sesi.instance.bolehDataSample, isFalse);

    Sesi.instance.terapkanKonfig(<String, dynamic>{
      'isAdmin': false,
      'tokoDemo': true,
      'dataSampleEbisnis': true,
    });
    expect(Sesi.instance.bolehDataSample, isFalse);
  });
}
