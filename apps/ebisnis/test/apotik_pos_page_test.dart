import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/pos/apotik_batch_sheet.dart';
import 'package:ebisnis/features/apotik/pos/apotik_cart_panel.dart';
import 'package:ebisnis/features/apotik/pos/apotik_mode_switcher.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Server tiruan dengan kontrak NYATA apotik.
PanggilAksi _server({
  List<Map<String, dynamic>>? item,
  List<Map<String, dynamic>>? batch,
  List<Map<String, dynamic>>? caraBayar,
  Map<String, dynamic>? hasilBayar,
  List<String> dicatat = const [],
}) {
  return (aksi, body) async {
    dicatat.add(aksi);
    switch (aksi) {
      case 'apotik_item_cari':
        return {'status': '00', 'data': item ?? const []};
      case 'apotik_item_batch':
        return {'status': '00', 'data': batch ?? const []};
      case 'apotik_cara_bayar_list':
        return {'status': '00', 'data': caraBayar ?? const []};
      case 'apotik_bayar':
        return hasilBayar ?? {'status': '00', 'kode': 'APT1', 'total': 6000};
      case 'apotik_resep_list':
        return {'status': '00', 'data': const []};
      default:
        return {'status': '91', 'description': 'Aksi tidak dikenal'};
    }
  };
}

Widget _bungkus(Widget child, Size ukuran) {
  return MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran),
      child: SizedBox(width: ukuran.width, height: ukuran.height, child: child),
    ),
  );
}

/// Surface test default 800x600 akan MEMANGKAS SizedBox yang lebih lebar,
/// sehingga layout tiga area tidak pernah terbentuk. Atur ukuran surface
/// sungguhan lalu kembalikan setelah test selesai.
Future<void> _pump(WidgetTester tester, Widget child, Size ukuran) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_bungkus(child, ukuran));
  await tester.pumpAndSettle();
}

final _obat = <String, dynamic>{
  'id': 1,
  'kode': 'OBT-1',
  'nama': 'Paracetamol 500 mg',
  'satuan': 'tablet',
  'stok': 20,
  'hargaJual': 3000,
  'kekuatan': '500 mg',
  'bentukSediaan': 'tablet',
};

void main() {
  group('Tata letak responsif', () {
    testWidgets('desktop lebar merakit TIGA area sekaligus', (tester) async {
      await _pump(
          tester,
          ApotikPosPage(panggil: _server(item: [_obat], dicatat: [])),
          const Size(1500, 900));
      // Area konteks (mode switcher) + katalog + keranjang tampil bersamaan.
      expect(find.byType(ApotikModeSwitcher), findsOneWidget);
      expect(find.byType(MedicationCard), findsOneWidget);
      expect(find.byType(ApotikCartPanel), findsOneWidget);
      expect(find.text('Keranjang kosong'), findsOneWidget);
    });

    testWidgets(
        'mobile memakai satu kolom + aksi melekat, tanpa panel keranjang',
        (tester) async {
      await _pump(
          tester,
          ApotikPosPage(panggil: _server(item: [_obat], dicatat: [])),
          const Size(420, 850));
      expect(find.byType(MedicationCard), findsOneWidget);
      // Keranjang TIDAK dirakit sebagai panel; hanya tombol ringkasan melekat.
      expect(find.byType(ApotikCartPanel), findsNothing);
      expect(find.text('Keranjang'), findsOneWidget);
      expect(find.text('0 item'), findsOneWidget);
    });
  });

  group('Katalog', () {
    testWidgets('menampilkan atribut IR-01 pada kartu obat', (tester) async {
      await _pump(
          tester,
          ApotikPosPage(
              panggil: _server(item: [
            {..._obat, 'golonganObat': 'KERAS', 'highAlert': true}
          ], dicatat: [])),
          const Size(1500, 900));
      expect(find.text('500 mg • tablet'), findsOneWidget);
      expect(find.text('Keras (Rx)'), findsOneWidget);
      expect(find.text('High-alert'), findsOneWidget);
    });

    testWidgets('katalog kosong memberi petunjuk tindakan', (tester) async {
      await _pump(tester, ApotikPosPage(panggil: _server(dicatat: [])),
          const Size(1500, 900));
      expect(find.text('Obat tidak ditemukan'), findsOneWidget);
      // Muncul dua kali dan itu memang benar: hint kolom cari + empty state.
      expect(find.textContaining('pindai barcode'), findsNWidgets(2));
    });

    testWidgets('galat server ditampilkan apa adanya dengan tombol coba lagi',
        (tester) async {
      await _pump(tester, ApotikPosPage(panggil: (aksi, body) async {
        if (aksi == 'apotik_item_cari') {
          return {'status': '91', 'description': 'Katalog sedang dikunci.'};
        }
        return {'status': '00', 'data': const []};
      }), const Size(1500, 900));
      // Kini dibungkus Exception oleh jalur lokal-dulu; pesan servernya tetap
      // tampil apa adanya di dalamnya.
      expect(find.textContaining('Katalog sedang dikunci.'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });
  });

  group('Menambah obat ke keranjang', () {
    testWidgets('obat tanpa batch langsung masuk keranjang', (tester) async {
      await _pump(
          tester,
          ApotikPosPage(panggil: _server(item: [_obat], dicatat: [])),
          const Size(1500, 900));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      expect(find.text('Keranjang kosong'), findsNothing);
      expect(find.text('1 item'), findsOneWidget);
    });

    testWidgets('obat ber-batch membuka pemilih FEFO lebih dulu',
        (tester) async {
      await _pump(
          tester,
          ApotikPosPage(
              panggil: _server(item: [
            _obat
          ], batch: [
            {
              'kadaluarsaId': 9,
              'tanggalKadaluarsa': '2027-06-30',
              'sisa': 50,
              'kedaluwarsa': false,
              'lotLayak': true,
            }
          ], dicatat: [])),
          const Size(1500, 900));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      expect(find.byType(ApotikBatchSheet), findsOneWidget);
      expect(find.textContaining('Pilih Batch'), findsOneWidget);
    });
  });

  group('Pemilih batch FEFO (IR-02)', () {
    testWidgets('lot dikarantina terkunci dan tidak ikut prefill FEFO',
        (tester) async {
      final batches = <Map<String, dynamic>>[
        {
          'kadaluarsaId': 1,
          'tanggalKadaluarsa': '2027-01-31',
          'sisa': 10,
          'kedaluwarsa': false,
          'lotLayak': false,
          'alasanLot': 'Lot dikarantina',
        },
        {
          'kadaluarsaId': 2,
          'tanggalKadaluarsa': '2027-12-31',
          'sisa': 10,
          'kedaluwarsa': false,
          'lotLayak': true,
        },
      ];
      await _pump(
          tester,
          Scaffold(
              body: ApotikBatchSheet(
                  namaItem: 'Obat X', batches: batches, qtyDiminta: 4)),
          const Size(600, 900));

      expect(find.text('Lot dikarantina'), findsOneWidget);
      // Field qty lot karantina dinonaktifkan.
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields[0].enabled, isFalse);
      expect(fields[1].enabled, isTrue);
      // Prefill FEFO melompati lot karantina -> qty jatuh ke lot layak.
      expect(fields[0].controller!.text, isEmpty);
      expect(fields[1].controller!.text, '4');
    });

    testWidgets('batch kedaluwarsa tetap terkunci (pagar lama dipertahankan)',
        (tester) async {
      await _pump(
          tester,
          Scaffold(
              body:
                  ApotikBatchSheet(namaItem: 'Obat X', qtyDiminta: 2, batches: [
            {
              'kadaluarsaId': 3,
              'tanggalKadaluarsa': '2020-01-01',
              'sisa': 5,
              'kedaluwarsa': true,
              'lotLayak': true,
            }
          ])),
          const Size(600, 900));
      expect(find.text('Kedaluwarsa'), findsOneWidget);
      final f = tester.widget<TextField>(find.byType(TextField));
      expect(f.enabled, isFalse);
    });

    test('helper terkunci/alasan konsisten dengan aturan server', () {
      expect(ApotikBatchSheet.terkunci({'kedaluwarsa': true, 'lotLayak': true}),
          isTrue);
      expect(
          ApotikBatchSheet.terkunci({'kedaluwarsa': false, 'lotLayak': false}),
          isTrue);
      expect(
          ApotikBatchSheet.terkunci({'kedaluwarsa': false, 'lotLayak': true}),
          isFalse);
      expect(
          ApotikBatchSheet.alasanTerkunci(
              {'lotLayak': false, 'alasanLot': 'Lot ditarik (recall)'}),
          'Lot ditarik (recall)');
      expect(ApotikBatchSheet.alasanTerkunci({'lotLayak': true}), isNull);
    });
  });

  group('Pembayaran (IR-07 + anti double-submit)', () {
    testWidgets('metode pembayaran hanya dari daftar server', (tester) async {
      await _pump(
          tester,
          ApotikPosPage(
              panggil: _server(item: [
            _obat
          ], caraBayar: [
            {'id': 1, 'nama': 'Tunai'},
            {'id': 2, 'nama': 'QRIS'},
          ], dicatat: [])),
          const Size(1500, 900));
      expect(find.text('Metode pembayaran'), findsOneWidget);
      expect(find.text('Tunai'), findsOneWidget);
    });

    testWidgets('server tanpa daftar metode: dropdown tidak dirakit',
        (tester) async {
      await _pump(
          tester,
          ApotikPosPage(panggil: _server(item: [_obat], dicatat: [])),
          const Size(1500, 900));
      expect(find.text('Metode pembayaran'), findsNothing);
    });

    testWidgets('bayar sukses mengosongkan keranjang', (tester) async {
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 2, harga: 3000));
      await _pump(
          tester,
          ApotikPosPage(
              controller: pos, panggil: _server(item: [_obat], dicatat: [])),
          const Size(1500, 900));
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      expect(find.text('Transaksi Berhasil'), findsOneWidget);
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(pos.keranjang, isEmpty);
    });

    testWidgets('penolakan server ditampilkan apa adanya, keranjang utuh',
        (tester) async {
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 1, harga: 3000));
      await _pump(
          tester,
          ApotikPosPage(
              controller: pos,
              panggil: _server(item: [
                _obat
              ], hasilBayar: {
                'status': '91',
                'description': 'DITOLAK: Lot dikarantina pada batch "X".'
              }, dicatat: [])),
          const Size(1500, 900));
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lot dikarantina'), findsOneWidget);
      expect(pos.keranjang.length, 1);
    });

    testWidgets('kode idempoten SAMA pada percobaan ulang setelah gagal',
        (tester) async {
      final kodeTerkirim = <String>[];
      final pos = ApotikPosController()
        ..tambah(ApotikBarisKeranjang(item: _obat, qty: 1, harga: 3000));
      await _pump(
          tester,
          ApotikPosPage(
            controller: pos,
            panggil: (aksi, body) async {
              if (aksi == 'apotik_bayar') {
                kodeTerkirim.add('${body['kode']}');
                return {'status': '91', 'description': 'Jaringan bermasalah.'};
              }
              return {'status': '00', 'data': const []};
            },
          ),
          const Size(1500, 900));
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bayar'));
      await tester.pumpAndSettle();
      expect(kodeTerkirim.length, 2);
      expect(kodeTerkirim[0], kodeTerkirim[1]);
    });
  });

  group('Katalog lokal-dulu', () {
    testWidgets('katalog dari cache ditandai dan stoknya tidak diklaim baru',
        (tester) async {
      await _pump(
        tester,
        ApotikPosPage(
          muatKatalog: (aksi, body, cacheKey, {required onData}) async {
            onData({
              'data': [_obat],
              'dariServer': false
            });
          },
        ),
        const Size(1500, 900),
      );
      expect(find.textContaining('Katalog dari data terakhir'), findsOneWidget);
      expect(find.textContaining('stok belum tentu mutakhir'), findsOneWidget);
      // Pagar keselamatan tetap: pembayaran butuh server.
      expect(find.textContaining('Pembayaran tetap memerlukan server'),
          findsOneWidget);
    });

    testWidgets('emisi server menghapus penanda cache', (tester) async {
      await _pump(
        tester,
        ApotikPosPage(
          muatKatalog: (aksi, body, cacheKey, {required onData}) async {
            onData({
              'data': [_obat],
              'dariServer': false
            });
            onData({
              'data': [_obat],
              'dariServer': true
            });
          },
        ),
        const Size(1500, 900),
      );
      expect(find.textContaining('Katalog dari data terakhir'), findsNothing);
    });

    testWidgets('hasil cache DISARING menurut kata kunci yang diketik',
        (tester) async {
      // Cache menyimpan hasil kueri terakhir. Tanpa penyaringan, mengetik
      // kata kunci baru saat offline akan memunculkan obat yang salah.
      await _pump(
        tester,
        ApotikPosPage(
          muatKatalog: (aksi, body, cacheKey, {required onData}) async {
            onData({
              'data': [
                _obat,
                {..._obat, 'id': 99, 'kode': 'OBT-99', 'nama': 'Vitamin C'},
              ],
              'dariServer': false,
            });
          },
        ),
        const Size(1500, 900),
      );
      expect(find.text('Vitamin C'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(
              TextField, 'Cari nama obat, kode, atau pindai barcode…'),
          'vitamin');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Vitamin C'), findsOneWidget);
      expect(find.text('Paracetamol 500 mg'), findsNothing);
    });

    testWidgets('server gagal TIDAK menghapus katalog dari cache',
        (tester) async {
      await _pump(
        tester,
        ApotikPosPage(
          muatKatalog: (aksi, body, cacheKey, {required onData}) async {
            onData({
              'data': [_obat],
              'dariServer': false
            });
            throw Exception('Koneksi terputus');
          },
        ),
        const Size(1500, 900),
      );
      expect(find.byType(MedicationCard), findsWidgets);
      expect(find.textContaining('Koneksi terputus'), findsNothing);
    });
  });
}
