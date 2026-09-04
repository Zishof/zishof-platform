import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pembayaran_sheet.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pembayaran_tertunda.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:ebisnis/features/apotik/pos/apotik_struk_teks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tunai = MetodeBayar(id: 1, nama: 'Tunai', adaKembalian: true);
const _qris = MetodeBayar(id: 2, nama: 'QRIS', adaKembalian: false);

const _obat = {'id': 9, 'kode': 'OBT-9', 'nama': 'Paracetamol', 'stok': 20};

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1500, 950)}) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: SizedBox(width: ukuran.width, height: ukuran.height, child: child),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Membuka lembar pembayaran lewat tombol supaya Navigator.pop punya rute.
Future<HasilPembayaran?> _bukaSheet(
  WidgetTester tester, {
  required double total,
  required List<MetodeBayar> metode,
  bool laciTersedia = false,
}) async {
  HasilPembayaran? hasil;
  await _pump(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async {
            hasil = await showModalBottomSheet<HasilPembayaran>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ApotikPembayaranSheet(
                  total: total, metode: metode, laciTersedia: laciTersedia),
            );
          },
          child: const Text('buka'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return hasil;
}

void main() {
  group('Pagar pembayaran (fungsi murni)', () {
    test('tunai kurang dari total MENAHAN pembayaran', () {
      final p = ApotikPembayaranSheet.periksa(
          total: 50000, metode: _tunai, tunai: 20000, referensi: '');
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('Uang diterima kurang'));
    });

    test('tunai pas lolos', () {
      final p = ApotikPembayaranSheet.periksa(
          total: 50000, metode: _tunai, tunai: 50000, referensi: '');
      expect(p.boleh, isTrue);
      expect(p.alasan, isEmpty);
    });

    test('non-tunai tanpa referensi MEMPERINGATKAN, tidak menahan', () {
      // Server menerima referensi kosong; menahannya berarti mengarang aturan.
      final p = ApotikPembayaranSheet.periksa(
          total: 50000, metode: _qris, tunai: 0, referensi: '');
      expect(p.boleh, isTrue);
      expect(p.peringatan.join(), contains('sulit dicocokkan'));
    });

    test('non-tunai berisi referensi tidak memperingatkan apa pun', () {
      final p = ApotikPembayaranSheet.periksa(
          total: 50000, metode: _qris, tunai: 0, referensi: 'APV-771');
      expect(p.boleh, isTrue);
      expect(p.peringatan, isEmpty);
    });

    test('total nol ditahan', () {
      final p = ApotikPembayaranSheet.periksa(
          total: 0, metode: _tunai, tunai: 0, referensi: '');
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('Total transaksi 0'));
    });

    test('saran tunai selalu >= total, urut, dan tidak berlebihan', () {
      final saran = ApotikPembayaranSheet.saranTunai(37500);
      expect(saran.first, 37500);
      expect(saran.length, lessThanOrEqualTo(5));
      expect(saran.every((s) => s >= 37500), isTrue);
      final urut = [...saran]..sort();
      expect(saran, urut);
    });
  });

  group('Lembar pembayaran', () {
    testWidgets('metode tunai menampilkan uang diterima dan kembalian',
        (tester) async {
      await _bukaSheet(tester, total: 50000, metode: const [_tunai, _qris]);
      expect(find.widgetWithText(TextField, 'Uang diterima'), findsOneWidget);
      expect(find.text('Kembalian'), findsOneWidget);
    });

    testWidgets('metode non-tunai meminta referensi, bukan uang diterima',
        (tester) async {
      await _bukaSheet(tester, total: 50000, metode: const [_qris]);
      expect(find.widgetWithText(TextField, 'Uang diterima'), findsNothing);
      expect(find.widgetWithText(TextField, 'Nomor referensi / approval'),
          findsOneWidget);
    });

    testWidgets('menyatakan bahwa uang diterima & kembalian ikut dibukukan',
        (tester) async {
      await _bukaSheet(tester, total: 50000, metode: const [_tunai]);
      expect(find.textContaining('ikut dibukukan'), findsOneWidget);
    });

    testWidgets('server tanpa daftar metode dikatakan apa adanya',
        (tester) async {
      await _bukaSheet(tester, total: 50000, metode: const []);
      expect(
          find.textContaining('belum mengirim daftar metode'), findsOneWidget);
    });

    testWidgets('tombol bayar terkunci selama uang diterima kurang',
        (tester) async {
      await _bukaSheet(tester, total: 50000, metode: const [_tunai]);
      final tombolAwal = tester.widget<FilledButton>(
          find.byWidgetPredicate((w) => w is FilledButton));
      expect(tombolAwal.onPressed, isNull);

      await tester.enterText(
          find.widgetWithText(TextField, 'Uang diterima'), '100000');
      await tester.pumpAndSettle();
      final tombol = tester.widget<FilledButton>(
          find.byWidgetPredicate((w) => w is FilledButton));
      expect(tombol.onPressed, isNotNull);
      expect(find.textContaining('kembali Rp 50.000'), findsOneWidget);
    });

    testWidgets('hasil membawa metode, tunai, dan kembalian', (tester) async {
      HasilPembayaran? hasil;
      await _pump(
        tester,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                hasil = await showModalBottomSheet<HasilPembayaran>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ApotikPembayaranSheet(
                      total: 45000, metode: [_tunai, _qris]),
                );
              },
              child: const Text('buka'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Uang diterima'), '50000');
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((w) => w is FilledButton));
      await tester.pumpAndSettle();
      expect(hasil, isNotNull);
      expect(hasil!.caraBayarId, 1);
      expect(hasil!.tunai, 50000);
      expect(hasil!.kembalian, 5000);
    });
  });

  group('Pembayaran terpisah (IR-11)', () {
    BarisBayar baris(MetodeBayar m, double nominal, {double tunai = 0}) =>
        BarisBayar(metode: m, nominal: nominal, tunai: tunai);

    test('jumlah baris harus sama dengan total', () {
      final p = ApotikPembayaranSheet.periksaSplit(total: 100000, baris: [
        baris(_tunai, 40000, tunai: 40000),
        baris(_qris, 50000),
      ]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('kurang Rp 10.000'));
    });

    test('kelebihan juga ditahan dan dijelaskan sebagai kembalian', () {
      final p = ApotikPembayaranSheet.periksaSplit(total: 100000, baris: [
        baris(_tunai, 70000, tunai: 70000),
        baris(_qris, 50000),
      ]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('KEMBALIAN'));
    });

    test('pembagian pas lolos', () {
      final p = ApotikPembayaranSheet.periksaSplit(total: 100000, baris: [
        baris(_tunai, 40000, tunai: 50000),
        BarisBayar(metode: _qris, nominal: 60000, referensi: 'APV-9'),
      ]);
      expect(p.boleh, isTrue);
      expect(p.alasan, isEmpty);
      expect(p.peringatan, isEmpty);
    });

    test('baris tunai dengan uang diterima kurang ditahan', () {
      final p = ApotikPembayaranSheet.periksaSplit(total: 100000, baris: [
        baris(_tunai, 60000, tunai: 50000),
        BarisBayar(metode: _qris, nominal: 40000, referensi: 'APV-9'),
      ]);
      expect(p.boleh, isFalse);
      expect(p.alasan.join(), contains('uang diterima kurang'));
    });

    test('kembalian dihitung per baris tunai saja', () {
      final b1 = baris(_tunai, 40000, tunai: 50000);
      final b2 = baris(_qris, 60000, tunai: 99999);
      expect(b1.kembalian, 10000);
      expect(b2.kembalian, 0, reason: 'metode non-tunai tak punya kembalian');
    });

    test('payload baris memuat nominal dan hanya kirim tunai bila relevan', () {
      final tunaiPayload = baris(_tunai, 40000, tunai: 50000).toPayload();
      expect(tunaiPayload['cara_bayar_id'], 1);
      expect(tunaiPayload['nominal'], 40000);
      expect(tunaiPayload['tunai'], 50000);
      expect(tunaiPayload['kembalian'], 10000);

      final qrisPayload =
          BarisBayar(metode: _qris, nominal: 60000, referensi: 'APV-9')
              .toPayload();
      expect(qrisPayload.containsKey('tunai'), isFalse);
      expect(qrisPayload['referensi'], 'APV-9');
    });

    testWidgets('kasir dapat memecah pembayaran dan sisanya terbaca',
        (tester) async {
      await _bukaSheet(tester, total: 100000, metode: const [_tunai, _qris]);
      await tester.tap(find.text('Bayar terpisah'));
      await tester.pumpAndSettle();
      // Baris pertama mewarisi seluruh total, jadi belum ada sisa.
      expect(find.text('Seluruh total sudah terbagi.'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Nominal dibukukan').first,
          '40000');
      await tester.pumpAndSettle();
      expect(
          find.textContaining('Sisa belum terbagi Rp 60.000'), findsOneWidget);
    });

    testWidgets('POS mengirim larik pembayaran DAN cara_bayar_id tunggal',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 1, harga: 100000));
      await _pump(
        tester,
        ApotikPosPage(
          controller: pos,
          panggil: (aksi, body) async {
            if (aksi == 'apotik_cara_bayar_list') {
              return {
                'status': '00',
                'data': [
                  {'id': 1, 'nama': 'Tunai', 'adaKembalian': true},
                  {'id': 2, 'nama': 'QRIS', 'adaKembalian': false},
                ],
              };
            }
            if (aksi == 'apotik_bayar') {
              terkirim.add(Map<String, dynamic>.from(body));
              return {'status': '00', 'kode': 'TRX-1', 'total': 100000};
            }
            return {'status': '00', 'data': const []};
          },
        ),
      );
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Uang diterima'), '100000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bayar').last);
      await tester.pumpAndSettle();

      expect(terkirim.length, 1);
      final rincian = terkirim.first['pembayaran'] as List;
      expect(rincian.length, 1);
      expect((rincian.first as Map)['nominal'], 100000);
      expect((rincian.first as Map)['tunai'], 100000);
      // Kompatibilitas server lama: metode tunggal tetap ikut dikirim.
      expect(terkirim.first['cara_bayar_id'], 1);
    });
  });

  group('Antrean pembayaran belum dipastikan', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    PembayaranTertunda contoh([String kode = 'APT1']) => PembayaranTertunda(
          kode: kode,
          payload: {'kode': kode, 'items': const []},
          total: 15000,
          waktu: DateTime(2026, 9, 2, 10),
        );

    test('tercatat dan selamat dibaca ulang', () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      final daftar = await store.muat();
      expect(daftar.length, 1);
      expect(daftar.first.kode, 'APT1');
      expect(daftar.first.payload['kode'], 'APT1');
    });

    test('endpoint racikan ikut tersimpan dan dipakai saat pemeriksaan ulang',
        () async {
      final store = ApotikPembayaranTertundaStore.instance;
      final tertunda = PembayaranTertunda(
        kode: 'RAC-1',
        aksi: 'apotik_bayar_racikan',
        payload: const {'kode': 'RAC-1', 'items': []},
        total: 10000,
        waktu: DateTime(2026, 9, 5),
      );
      await store.catat(tertunda);
      final terbaca = (await store.muat()).single;
      String? aksiTerkirim;
      await store.periksaUlang(terbaca, (aksi, body) async {
        aksiTerkirim = aksi;
        return {'status': '00', 'kode': 'RAC-1', 'idempoten': true};
      });
      expect(aksiTerkirim, 'apotik_bayar_racikan');
    });

    test('kode yang sama tidak menggandakan antrean', () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      await store.catat(contoh());
      expect((await store.muat()).length, 1);
    });

    test('idempoten:true berarti SUDAH terbukukan sejak kiriman pertama',
        () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      final h = await store.periksaUlang(
          contoh(),
          (aksi, body) async => {
                'status': '00',
                'kode': 'TRX-9',
                'idempoten': true,
              });
      expect(h.status, StatusPeriksaUlang.sudahTerbukukan);
      expect(h.pesan, contains('SUDAH terbukukan'));
      expect(await store.muat(), isEmpty);
    });

    test('sukses tanpa flag berarti baru terbukukan sekarang', () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      final h = await store.periksaUlang(
          contoh(), (aksi, body) async => {'status': '00', 'kode': 'TRX-9'});
      expect(h.status, StatusPeriksaUlang.baruTerbukukan);
      expect(await store.muat(), isEmpty);
    });

    test('penolakan bisnis membuktikan transaksi TIDAK pernah terbukukan',
        () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      final h = await store.periksaUlang(
          contoh(),
          (aksi, body) async =>
              {'status': '91', 'description': 'Stok tidak cukup.'});
      expect(h.status, StatusPeriksaUlang.ditolak);
      expect(h.pesan, contains('Stok tidak cukup'));
      expect(await store.muat(), isEmpty);
    });

    test('masih offline: tetap mengantre, tidak diklaim apa pun', () async {
      final store = ApotikPembayaranTertundaStore.instance;
      await store.catat(contoh());
      final h = await store.periksaUlang(contoh(), (aksi, body) async {
        throw ApiException('Koneksi terputus', offline: true);
      });
      expect(h.status, StatusPeriksaUlang.masihTidakPasti);
      expect(h.selesai, isFalse);
      expect((await store.muat()).length, 1);
    });
  });

  group('POS: kegagalan jaringan TIDAK disebut gagal', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('menjadi paidUnsynced, mengantre, dan memunculkan bilah',
        (tester) async {
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 2, harga: 3000));
      await _pump(
        tester,
        ApotikPosPage(
          controller: pos,
          panggil: (aksi, body) async {
            if (aksi == 'apotik_bayar') {
              throw ApiException('Waktu tunggu habis', offline: true);
            }
            return {'status': '00', 'data': const []};
          },
        ),
      );
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();

      expect(find.text('Belum Dapat Dipastikan'), findsOneWidget);
      expect(find.textContaining('BELUM'), findsOneWidget);
      await tester.tap(find.text('Mengerti'));
      await tester.pumpAndSettle();

      expect(pos.status, ApotikStatusTransaksi.paidUnsynced);
      // Keranjang TIDAK dikosongkan: menganggapnya selesai sama saja
      // mengklaim sesuatu yang belum diketahui.
      expect(pos.keranjang.length, 1);
      expect(
          find.textContaining('belum dipastikan terbukukan'), findsOneWidget);
      expect((await ApotikPembayaranTertundaStore.instance.muat()).length, 1);
    });
  });

  group('POS: lembar pembayaran menyatu dengan pengiriman', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('metode dan referensi ikut terkirim ke apotik_bayar',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 2, harga: 3000));
      await _pump(
        tester,
        ApotikPosPage(
          controller: pos,
          panggil: (aksi, body) async {
            if (aksi == 'apotik_cara_bayar_list') {
              return {
                'status': '00',
                'data': [
                  {'id': 2, 'nama': 'QRIS', 'adaKembalian': false},
                ],
              };
            }
            if (aksi == 'apotik_bayar') {
              terkirim.add(Map<String, dynamic>.from(body));
              return {'status': '00', 'kode': 'TRX-7', 'total': 6000};
            }
            return {'status': '00', 'data': const []};
          },
        ),
      );
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      // Lembar pembayaran terbuka karena server MEMANG mengirim metode.
      expect(find.text('Pembayaran'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Nomor referensi / approval'),
          'APV-42');
      await tester.pumpAndSettle();
      // Tombol bayar lembar ini FilledButton.icon (subclass) dan judulnya
      // sama dengan tombol di panel keranjang di belakangnya -- ambil yang
      // terakhir dipasang, yaitu milik lembar.
      await tester.tap(find.text('Bayar').last);
      await tester.pumpAndSettle();

      expect(terkirim.length, 1);
      expect(terkirim.first['cara_bayar_id'], 2);
      expect(terkirim.first['referensi_bayar'], 'APV-42');
      expect(find.text('Transaksi Berhasil'), findsOneWidget);
    });

    testWidgets('membatalkan lembar TIDAK mengirim apa pun', (tester) async {
      final terkirim = <String>[];
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 1, harga: 3000));
      await _pump(
        tester,
        ApotikPosPage(
          controller: pos,
          panggil: (aksi, body) async {
            if (aksi == 'apotik_cara_bayar_list') {
              return {
                'status': '00',
                'data': [
                  {'id': 1, 'nama': 'Tunai', 'adaKembalian': true},
                ],
              };
            }
            terkirim.add(aksi);
            return {'status': '00', 'data': const []};
          },
        ),
      );
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Batal'));
      await tester.pumpAndSettle();
      expect(terkirim.contains('apotik_bayar'), isFalse);
      expect(pos.keranjang.length, 1);
      expect(pos.status, isNot(ApotikStatusTransaksi.paymentPending));
    });
  });

  group('Struk teks', () {
    DataStruk data({bool cetakUlang = false, double tunai = 0}) => DataStruk(
          namaApotek: 'Apotek Sehat',
          kodeTransaksi: 'TRX-1',
          waktu: DateTime(2026, 9, 2, 14, 5),
          kasir: 'kasir1',
          baris: const [
            BarisStruk(nama: 'Paracetamol 500 mg', qty: 2, harga: 3000),
          ],
          total: 6000,
          metode: 'Tunai',
          tunai: tunai,
          kembalian: tunai > 0 ? tunai - 6000 : 0,
          cetakUlang: cetakUlang,
        );

    test('lebar kertas menentukan jumlah kolom', () {
      expect(ApotikStrukTeks.kolomUntukKertas(58), 32);
      expect(ApotikStrukTeks.kolomUntukKertas(72), 42);
      expect(ApotikStrukTeks.kolomUntukKertas(80), 48);
    });

    test('setiap baris tepat selebar kertas atau kurang', () {
      final baris = ApotikStrukTeks.susun(data(tunai: 10000), kolom: 32);
      expect(baris.every((b) => b.length <= 32), isTrue);
    });

    test('memuat identitas, item, dan total', () {
      final teks = ApotikStrukTeks.susun(data(), kolom: 32).join('\n');
      expect(teks, contains('APOTEK SEHAT'));
      expect(teks, contains('TRX-1'));
      expect(teks, contains('Paracetamol 500 mg'));
      expect(teks, contains('6.000'));
      expect(teks, contains('Tunai'));
    });

    test('tunai & kembalian dicetak hanya bila memang tunai', () {
      expect(
          ApotikStrukTeks.susun(data()).join('\n'), isNot(contains('Kembali')));
      expect(ApotikStrukTeks.susun(data(tunai: 10000)).join('\n'),
          contains('Kembali'));
    });

    test('cetak ulang ditandai supaya tidak dikira transaksi kedua', () {
      final teks = ApotikStrukTeks.susun(data(cetakUlang: true)).join('\n');
      expect(teks, contains('CETAK ULANG'));
    });

    test('byte ESC/POS diawali reset dan diakhiri perintah potong', () {
      final b = ApotikStrukTeks.keEscPos(['halo']);
      expect(b.sublist(0, 2), [0x1B, 0x40]);
      expect(b.sublist(b.length - 4), [0x1D, 0x56, 0x42, 0x00]);
    });
  });
}
