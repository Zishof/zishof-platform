import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebisnis/services/pengikatan_tenant.dart';
import 'package:ebisnis/widgets/pemilih_tenant.dart';

/// Penjaga pemilih usaha.
///
/// Layar ini menentukan pengguna bekerja pada perusahaan yang mana. Salah
/// pilih tidak menimbulkan galat apa pun — datanya benar, perusahaannya yang
/// keliru — jadi perilakunya harus dikunci uji.
void main() {
  const daftar = <RingkasanTenant>[
    RingkasanTenant(
      id: 11,
      kode: 'TEN-11',
      nama: 'Caruban Medika Nusantara',
      peran: 'OWNER',
      status: 'ACTIVE',
      modul: <String>['INVENTORY_SALES'],
    ),
    RingkasanTenant(
      id: 22,
      kode: 'TEN-22',
      nama: 'Distributor Uji B',
      peran: 'ADMIN_TENANT',
      status: 'SUSPENDED',
      modul: <String>[],
    ),
    RingkasanTenant(
      id: 33,
      kode: 'TEN-33',
      nama: 'Apotek Sedang Disiapkan',
      peran: 'OWNER',
      status: 'PROVISIONING',
      modul: <String>[],
    ),
  ];

  Future<int?> bukaPemilih(WidgetTester tester,
      {List<RingkasanTenant> isi = daftar}) async {
    int? hasil;
    var selesai = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            hasil = await PemilihTenant.pilih(context, isi);
            selesai = true;
          },
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    return selesai ? hasil : null;
  }

  testWidgets('menampilkan seluruh usaha, termasuk yang tidak dapat dipakai',
      (tester) async {
    await bukaPemilih(tester);

    expect(find.text('Caruban Medika Nusantara'), findsOneWidget);
    expect(find.text('Distributor Uji B'), findsOneWidget,
        reason: 'usaha SUSPENDED tetap ditampilkan -- daftar yang '
            'menyembunyikannya tampak seperti kehilangan data');
    expect(find.text('Apotek Sedang Disiapkan'), findsOneWidget);

    // Alasannya terlihat, bukan hanya tidak bisa diklik.
    expect(find.textContaining('dihentikan sementara'), findsOneWidget);
    expect(find.textContaining('disiapkan'), findsOneWidget);

    // Kode dan peran ikut tampil supaya nama yang mirip dapat dibedakan.
    expect(find.textContaining('TEN-11'), findsOneWidget);
    expect(find.textContaining('OWNER'), findsWidgets);
  });

  testWidgets('memilih usaha aktif mengembalikan id-nya', (tester) async {
    int? terpilih;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            terpilih = await PemilihTenant.pilih(context, daftar);
          },
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Caruban Medika Nusantara'));
    await tester.pumpAndSettle();

    expect(terpilih, 11);
  });

  testWidgets('usaha yang tidak dapat dipakai TIDAK dapat dipilih',
      (tester) async {
    int? terpilih;
    var selesai = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            terpilih = await PemilihTenant.pilih(context, daftar);
            selesai = true;
          },
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Distributor Uji B'));
    await tester.pumpAndSettle();

    expect(selesai, isFalse,
        reason: 'mengetuk usaha SUSPENDED tidak boleh menutup dialog');
    expect(terpilih, isNull);

    // Dialognya masih berdiri, dan yang aktif tetap dapat dipilih.
    await tester.tap(find.text('Caruban Medika Nusantara'));
    await tester.pumpAndSettle();
    expect(terpilih, 11);
  });

  testWidgets('tombol Keluar mengembalikan null, bukan menebak satu usaha',
      (tester) async {
    int? terpilih = -1;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            terpilih = await PemilihTenant.pilih(context, daftar);
          },
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(terpilih, isNull,
        reason: 'membatalkan berarti membatalkan login -- menebak salah satu '
            'usaha berarti pengguna bekerja pada perusahaan yang keliru');
  });

  test('status menentukan dapat-tidaknya dipakai, dan alasannya terbaca', () {
    const aktif = RingkasanTenant(
        id: 1, kode: 'A', nama: 'A', peran: 'OWNER', status: 'ACTIVE', modul: []);
    const siap = RingkasanTenant(
        id: 2, kode: 'B', nama: 'B', peran: 'OWNER', status: 'READY', modul: []);
    const henti = RingkasanTenant(
        id: 3, kode: 'C', nama: 'C', peran: 'OWNER', status: 'SUSPENDED', modul: []);
    const asing = RingkasanTenant(
        id: 4, kode: 'D', nama: 'D', peran: 'OWNER', status: 'ENTAH', modul: []);

    expect(aktif.dapatDipakai, isTrue);
    expect(siap.dapatDipakai, isTrue);
    expect(henti.dapatDipakai, isFalse);
    expect(asing.dapatDipakai, isFalse,
        reason: 'status yang tidak dikenal harus ditolak, bukan diterima');
    expect(asing.alasanTidakDapat, contains('ENTAH'),
        reason: 'status asing tetap ditampilkan apa adanya supaya dapat dilacak');
  });

  test('parser daftar menolak baris yang tidak sah', () {
    expect(RingkasanTenant.dariJson(null), isNull);
    expect(RingkasanTenant.dariJson('bukan map'), isNull);
    expect(RingkasanTenant.dariJson(<String, Object?>{'tenantId': 0}), isNull,
        reason: 'tenantId nol bukan tenant');
    expect(RingkasanTenant.dariJson(<String, Object?>{'tenantId': '11'}), isNull,
        reason: 'tenantId harus angka, bukan teks');

    final sah = RingkasanTenant.dariJson(<String, Object?>{
      'tenantId': 11,
      'tenantCode': 'TEN-11',
      'nama': 'Caruban',
      'role': 'OWNER',
      'status': 'ACTIVE',
      'modules': <String>['INVENTORY_SALES'],
    });
    expect(sah, isNotNull);
    expect(sah!.id, 11);
    expect(sah.modul, <String>['INVENTORY_SALES']);
  });
}
