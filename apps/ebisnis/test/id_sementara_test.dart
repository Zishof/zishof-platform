import 'package:ebisnis/services/master_offline.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mekanisme id sementara untuk baris master yang dibuat saat OFFLINE.
///
/// Baris baru mendapat id NEGATIF dari klien; setiap rujukan ke id itu ditukar dengan
/// id server sebelum antrean dikirim, dan baris yang induknya belum terkirim DITAHAN.
/// Yang diuji di sini bagian murni logikanya (penukaran rujukan), tanpa SQLite.
void main() {
  test('id sementara selalu negatif dan tidak berulang', () {
    final a = MasterOffline.idSementaraBaru();
    final b = MasterOffline.idSementaraBaru();
    expect(a, lessThan(0), reason: 'id server selalu positif; sementara harus negatif');
    expect(b, lessThan(0));
    expect(a, isNot(equals(b)));
  });

  test('rujukan id ditukar dengan id server yang sudah diketahui', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'workspaceId': -17, 'nama': 'Belanja ATK', 'nilai': 250000},
      {-17: 4021},
    );
    expect(hasil, isNotNull);
    expect(hasil!['workspaceId'], 4021);
    expect(hasil['nama'], 'Belanja ATK');
  });

  test('nilai negatif yang BUKAN kolom id tidak ikut ditukar', () async {
    // Nominal jurnal boleh negatif (koreksi/pembalikan). Menukar semua bilangan
    // negatif akan merusak angkanya -- inilah alasan penukaran dibatasi kolom id.
    final hasil = await MasterOffline.tukarIdSementara(
      {'akunId': -17, 'debet': -5000, 'kredit': 0},
      {-17: 99},
    );
    expect(hasil, isNotNull);
    expect(hasil!['akunId'], 99);
    expect(hasil['debet'], -5000, reason: 'nominal tidak boleh ikut ditukar');
  });

  test('rujukan yang induknya belum terkirim menahan pengiriman', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'workspaceId': -21, 'nama': 'Menunggu induk'},
      const {}, // belum ada pemetaan sama sekali
    );
    expect(hasil, isNull,
        reason: 'baris tidak boleh dikirim menggantung ke id yang belum ada di server');
  });

  test('id_lokal milik baris itu sendiri tidak dianggap rujukan menggantung',
      () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {'id_lokal': -31, 'kode': '111.999', 'nama': 'Kas Baru'},
      const {},
    );
    expect(hasil, isNotNull,
        reason: 'id_lokal memang menyimpan id sementaranya sendiri, bukan rujukan');
    expect(hasil!['id_lokal'], -31);
  });

  test('rujukan bersarang di dalam daftar ikut ditukar', () async {
    final hasil = await MasterOffline.tukarIdSementara(
      {
        'baris': [
          {'akunId': -5, 'nilai': 1000},
          {'akunId': -6, 'nilai': 2000},
        ]
      },
      {-5: 11, -6: 12},
    );
    expect(hasil, isNotNull);
    final baris = hasil!['baris'] as List;
    expect((baris[0] as Map)['akunId'], 11);
    expect((baris[1] as Map)['akunId'], 12);
  });
}
