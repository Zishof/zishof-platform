import 'package:ebisnis/services/master_offline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rantai dokumen modul Keuangan saat dibuat OFFLINE.
///
/// Pertanggungjawaban (PJ) menunjuk dokumen induknya lewat `uangMukaId` /
/// `kasBesarId`. Bila induknya juga baru dibuat offline, id-nya masih SEMENTARA
/// (negatif) sehingga PJ tidak boleh dikirim apa adanya. Yang diuji di sini: nama
/// kolom rujukan itu memang dikenali penukar id, dan PJ ditahan selama induknya
/// belum terkirim.
///
/// Uji ini melengkapi keuangan_lokal_dulu_test yang mengunci JALUR simpannya;
/// yang dikunci di sini adalah keutuhan RUJUKAN antar dokumennya.
void main() {
  test('rujukan uangMukaId ikut ditukar saat induknya sudah terkirim', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'uangMukaId': -91, 'nominal': 750000, 'keterangan': 'PJ perjalanan'},
      {-91: 3307},
    );
    expect(hasil, isNotNull);
    expect(hasil!['uangMukaId'], 3307);
    expect(hasil['nominal'], 750000, reason: 'nominal tidak boleh ikut ditukar');
  });

  test('rujukan kasBesarId ikut ditukar saat induknya sudah terkirim', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'kasBesarId': -92, 'nominal': 1250000},
      {-92: 4410},
    );
    expect(hasil, isNotNull);
    expect(hasil!['kasBesarId'], 4410);
  });

  test('PJ ditahan selama dokumen induknya belum terkirim', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'uangMukaId': -93, 'nominal': 500000},
      const {},
    );
    expect(hasil, isNull,
        reason: 'PJ tidak boleh menggantung ke uang muka yang belum ada di server');
  });

  test('rincian bersarang milik PJ ikut ditukar', () async {
    // Baris rincian PJ membawa rujukannya sendiri; penukaran harus menembus
    // daftar, bukan hanya kolom di tingkat teratas.
    final hasil = await MasterOffline.tukarIdSementara(
      {
        'kasBesarId': -94,
        'rincian': [
          {'akunId': -95, 'nominal': 100000},
          {'akunId': 77, 'nominal': 200000},
        ],
      },
      {-94: 5501, -95: 6602},
    );
    expect(hasil, isNotNull);
    expect(hasil!['kasBesarId'], 5501);
    final rincian = hasil['rincian'] as List;
    expect((rincian[0] as Map)['akunId'], 6602);
    expect((rincian[1] as Map)['akunId'], 77,
        reason: 'id server yang sudah benar tidak boleh ikut diubah');
  });
}
