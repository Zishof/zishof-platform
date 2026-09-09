import 'package:ebisnis/services/kebijakan_offline_pembayaran.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot konteks sama tetap dapat dipakai saat refresh server', () {
    final sesuai = KebijakanOfflinePembayaran.snapshotSesuai(
      konteksSiap: true,
      konteksSnapshotMemberId: 17,
      memberAktifId: 17,
    );

    expect(
      KebijakanOfflinePembayaran.bolehBukaPemilih(
        terkunci: false,
        sedangMemuat: true,
        punyaSnapshot: true,
        konteksSesuai: sesuai,
      ),
      isTrue,
    );
    expect(
      KebijakanOfflinePembayaran.bolehBayar(
        sedangMemproses: false,
        punyaPilihan: true,
        adaKeranjang: true,
        uangTunaiKurang: false,
        konteksSesuai: sesuai,
      ),
      isTrue,
    );
  });

  test('snapshot member lain ditolak meskipun ada metode terpilih', () {
    final sesuai = KebijakanOfflinePembayaran.snapshotSesuai(
      konteksSiap: true,
      konteksSnapshotMemberId: 16,
      memberAktifId: 17,
    );

    expect(sesuai, isFalse);
    expect(
      KebijakanOfflinePembayaran.bolehBayar(
        sedangMemproses: false,
        punyaPilihan: true,
        adaKeranjang: true,
        uangTunaiKurang: false,
        konteksSesuai: sesuai,
      ),
      isFalse,
    );
  });

  test('tanpa snapshot, picker menahan ketukan rangkap selama loading', () {
    expect(
      KebijakanOfflinePembayaran.bolehBukaPemilih(
        terkunci: false,
        sedangMemuat: true,
        punyaSnapshot: false,
        konteksSesuai: false,
      ),
      isFalse,
    );
    expect(
      KebijakanOfflinePembayaran.bolehBukaPemilih(
        terkunci: false,
        sedangMemuat: false,
        punyaSnapshot: false,
        konteksSesuai: false,
      ),
      isTrue,
    );
  });

  test('kunci cache terisolasi per varian tenant pengguna toko dan member', () {
    String key({String varian = 'albahjah', int? memberId = 10}) =>
        KebijakanOfflinePembayaran.kunciCache(
          varian: varian,
          tenantId: 2,
          userId: 'kasir cabang',
          tokoId: 7,
          memberId: memberId,
        );

    expect(key(), contains('pengguna-kasir%20cabang'));
    expect(key(), isNot(key(varian: 'nahl')));
    expect(key(), isNot(key(memberId: 11)));
    expect(key(memberId: null), contains('member-umum'));
  });
}
