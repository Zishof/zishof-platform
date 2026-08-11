import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/product_profile.dart';

/// Uji guard varian (LANGKAH 2.2 perintah POS Apotik): kombinasi build yang
/// SALAH (entrypoint vs --dart-define) harus TERTANGKAP `cocokDenganDartDefine`
/// -- build salah kombinasi menghasilkan aplikasi yang TAMPAK benar tapi
/// berperilaku varian lain, karena itu guard ini wajib punya uji yang bisa
/// gagal. Suite ini sah dijalankan dengan --dart-define apa pun: ekspektasi
/// dihitung dari profil dart-define aktual, bukan hardcode satu varian.
void main() {
  final dariDefine = AppProductProfile.dariDartDefine();

  test('profil yang SESUAI dart-define lolos guard', () {
    expect(dariDefine.cocokDenganDartDefine(), isTrue,
        reason: 'Profil hasil dariDartDefine() wajib selalu konsisten dgn '
            'dart-define build ini (kode=${dariDefine.kode}).');
  });

  test('profil yang TIDAK sesuai dart-define TERTANGKAP guard', () {
    final salah = dariDefine.kode == 'apotik'
        ? const AppProductProfile.ebisnis()
        : const AppProductProfile.apotik();
    expect(salah.cocokDenganDartDefine(), isFalse,
        reason: 'Entrypoint "${salah.kode}" pada build ber-dart-define '
            '"${dariDefine.kode}" adalah kombinasi salah dan guard harus '
            'berteriak (bootstrap menulis error_log).');
  });

  test('profil apotik terdefinisi utuh (branding + fitur grup)', () {
    const apotik = AppProductProfile.apotik();
    expect(apotik.kode, 'apotik');
    expect(apotik.namaAplikasi, 'eBisnis POS Apotik');
    expect(apotik.updateAssetKeyword, 'apotik');
    expect(apotik.logoAsset, 'assets/images/apotik/icon.png');
    expect(apotik.isApotik, isTrue);
    expect(apotik.isInventorySales, isFalse,
        reason: 'Apotik BUKAN varian inventory_sales -- menu si_ tidak boleh '
            'ikut dirakit.');
    expect(apotik.bolehMenuVarian(FiturGrup.apotik), isTrue);
    expect(const AppProductProfile.ebisnis().bolehMenuVarian(FiturGrup.apotik),
        isFalse,
        reason: 'Menu apotik tidak pernah dirakit ke varian POS lama.');
  });

  test('profil emedik memuat apotik SEKALIGUS emedik (beda via Tbmrole)', () {
    const emedik = AppProductProfile.emedik();
    expect(emedik.kode, 'emedik');
    expect(emedik.namaAplikasi, 'eBisnis POS eMedik');
    expect(emedik.updateAssetKeyword, 'emedik');
    expect(emedik.logoAsset, 'assets/images/emedik/icon.png');
    expect(emedik.isEmedik, isTrue);
    expect(emedik.isApotik, isTrue,
        reason: 'Satu build eMedik WAJIB memuat fitur apotik -- yang '
            'membedakan pengguna adalah Tbmrole di server.');
    expect(emedik.bolehMenuVarian(FiturGrup.apotik), isTrue);
    expect(emedik.bolehMenuVarian(FiturGrup.emedik), isTrue);
    expect(const AppProductProfile.apotik().bolehMenuVarian(FiturGrup.emedik),
        isFalse,
        reason: 'Varian apotik murni tidak merakit grup emedik.');
    // Adaptif thd dart-define build test ini: cocok HANYA bila define = emedik.
    expect(emedik.cocokDenganDartDefine(),
        AppProductProfile.dariDartDefine().kode == 'emedik',
        reason: 'Guard harus true tepat ketika dart-define build = emedik, '
            'false utk kombinasi lain.');
  });
}
