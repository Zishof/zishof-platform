import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/core/apotik_lokal_dulu.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_batch_expiry_page.dart';
import 'package:ebisnis/widgets/kilau_perubahan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Meniru urutan nyata `MasterOffline.daftarCacheDulu`: cache dulu, server
/// menyusul beserta diff.
MuatDaftarApotik _server({
  List<Map<String, dynamic>>? batch,
  List<Map<String, dynamic>>? cache,
  Set<String> idBerubah = const {},
  int jumlahHapus = 0,
  Object? galat,
  List<Map<String, dynamic>>? terkirim,
}) {
  return (aksi, body, cacheKey, {required onData}) async {
    terkirim?.add({'aksi': aksi, 'cacheKey': cacheKey, ...body});
    if (cache != null) onData({'data': cache, 'dariServer': false});
    if (galat != null) throw galat;
    onData({
      'data': batch ?? const [],
      'dariServer': true,
      'idBerubah': idBerubah,
      'jumlahHapus': jumlahHapus,
    });
  };
}

SimpanMasterApotik _penyimpan({
  List<Map<String, dynamic>>? terkirim,
  Map<String, dynamic>? hasil,
  Object? lempar,
}) {
  return (context,
      {required aksi, required body, kunci, cacheKey, rowLokal}) async {
    terkirim?.add({
      'aksi': aksi,
      'kunci': kunci ?? '',
      'cacheKey': cacheKey ?? '',
      'rowLokal': rowLokal ?? const <String, dynamic>{},
      ...body,
    });
    if (lempar != null) throw lempar;
    return hasil ?? {'status': '00'};
  };
}

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1400, 900)}) async {
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

String _tanggalDalam(int hari) {
  final d = DateTime.now().add(Duration(days: hari));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

void main() {
  testWidgets('menampilkan lot beserta sisa hari menuju kedaluwarsa',
      (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            muatDaftar: _server(batch: [
          {
            'kadaluarsaId': 1,
            'kode': 'OBT-1',
            'nama': 'Amoxicillin 500 mg',
            'tanggalKadaluarsa': _tanggalDalam(20),
            'sisa': 40,
            'kedaluwarsa': false,
            'lotLayak': true,
          }
        ])));
    expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
    expect(find.textContaining('sisa 40'), findsOneWidget);
    expect(find.textContaining('Near-expiry — 20 hari'), findsOneWidget);
  });

  testWidgets('lot yang sudah lewat ditandai kedaluwarsa', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            muatDaftar: _server(batch: [
          {
            'kadaluarsaId': 2,
            'nama': 'Obat Basi',
            'tanggalKadaluarsa': _tanggalDalam(-5),
            'sisa': 3,
            'kedaluwarsa': true,
            'lotLayak': true,
          }
        ])));
    expect(find.text('Kedaluwarsa'), findsOneWidget);
  });

  testWidgets('lot ditahan menampilkan alasan dari server', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            muatDaftar: _server(batch: [
          {
            'kadaluarsaId': 3,
            'nama': 'Obat Karantina',
            'tanggalKadaluarsa': _tanggalDalam(60),
            'sisa': 10,
            'kedaluwarsa': false,
            'lotLayak': false,
            'alasanLot': 'Lot dikarantina',
          }
        ])));
    expect(find.text('Lot dikarantina'), findsOneWidget);
  });

  testWidgets('kosong memberi kalimat menenangkan yang menyebut ambang hari',
      (tester) async {
    await _pump(tester, ApotikBatchExpiryPage(muatDaftar: _server()));
    expect(find.text('Tidak ada batch mendekati kedaluwarsa'), findsOneWidget);
    expect(find.textContaining('365 hari ke depan'), findsOneWidget);
  });

  testWidgets('mengubah ambang hari memuat ulang dengan parameter baru',
      (tester) async {
    final terkirim = <Map<String, dynamic>>[];
    await _pump(
        tester, ApotikBatchExpiryPage(muatDaftar: _server(terkirim: terkirim)));
    await tester.tap(find.text('30 hari'));
    await tester.pumpAndSettle();
    expect(terkirim.last['hari_ke_depan'], 30);
  });

  testWidgets('galat server ditampilkan apa adanya', (tester) async {
    await _pump(
        tester,
        ApotikBatchExpiryPage(
            muatDaftar:
                _server(galat: Exception('Monitor batch dinonaktifkan.'))));
    expect(find.textContaining('Monitor batch dinonaktifkan.'), findsOneWidget);
  });

  group('Ubah status lot (IR-02 sisi tulis)', () {
    testWidgets('mengirim status dan alasan ke server', (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikBatchExpiryPage(
              muatDaftar: _server(batch: [
                {
                  'kadaluarsaId': 9,
                  'nama': 'Obat X',
                  'tanggalKadaluarsa': _tanggalDalam(40),
                  'sisa': 12,
                  'kedaluwarsa': false,
                  'lotLayak': true,
                }
              ]),
              simpan: _penyimpan(terkirim: terkirim)));
      await tester.tap(find.text('Ubah status'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kemasan penyok');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final kirim =
          terkirim.lastWhere((e) => e['aksi'] == 'apotik_batch_status_ubah');
      expect(kirim['kadaluarsa_id'], 9);
      expect(kirim['alasan'], 'Kemasan penyok');
    });

    testWidgets('penolakan dari server ditampilkan apa adanya', (tester) async {
      await _pump(
          tester,
          ApotikBatchExpiryPage(
            muatDaftar: _server(batch: [
              {
                'kadaluarsaId': 9,
                'nama': 'Obat X',
                'tanggalKadaluarsa': _tanggalDalam(40),
                'sisa': 12,
                'kedaluwarsa': false,
                'lotLayak': true,
              }
            ]),
            simpan: _penyimpan(
                lempar: Exception('Alasan wajib diisi saat menahan lot.')),
          ));
      await tester.tap(find.text('Ubah status'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Alasan wajib diisi'), findsOneWidget);
    });
  });

  group('Local-first', () {
    testWidgets('memakai kunci cache monitor batch', (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(tester,
          ApotikBatchExpiryPage(muatDaftar: _server(terkirim: terkirim)));
      expect(terkirim.first['cacheKey'], kunciCacheBatchApotik);
    });

    testWidgets('isi cache tetap terbaca saat server tidak terjangkau',
        (tester) async {
      await _pump(
        tester,
        ApotikBatchExpiryPage(
          muatDaftar: _server(
            cache: [
              {
                'kadaluarsaId': 9,
                'nama': 'Obat Dari Cache',
                'tanggalKadaluarsa': _tanggalDalam(10),
                'sisa': 5,
                'kedaluwarsa': false,
                'lotLayak': true,
              }
            ],
            galat: Exception('Koneksi terputus'),
          ),
        ),
      );
      // Justru saat jaringan mati, petugas perlu tahu lot mana yang tidak
      // boleh dijual.
      expect(find.text('Obat Dari Cache'), findsOneWidget);
      expect(find.textContaining('Koneksi terputus'), findsNothing);
    });

    testWidgets('lot yang diubah petugas lain diberitahukan + dianimasikan',
        (tester) async {
      await _pump(
        tester,
        ApotikBatchExpiryPage(
          muatDaftar: _server(
            batch: [
              {
                'kadaluarsaId': 9,
                'nama': 'Obat X',
                'tanggalKadaluarsa': _tanggalDalam(40),
                'sisa': 12,
                'kedaluwarsa': false,
                'lotLayak': false,
                'statusLot': 'QUARANTINE',
              }
            ],
            idBerubah: {'9'},
          ),
        ),
      );
      expect(find.textContaining('Pembaruan dari server'), findsOneWidget);
      expect(find.byType(KilauBaris), findsWidgets);
    });

    testWidgets('perubahan status diantre dengan kunci + baris lokal',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikBatchExpiryPage(
            muatDaftar: _server(batch: [
              {
                'kadaluarsaId': 9,
                'nama': 'Obat X',
                'tanggalKadaluarsa': _tanggalDalam(40),
                'sisa': 12,
                'kedaluwarsa': false,
                'lotLayak': true,
              }
            ]),
            simpan: _penyimpan(terkirim: terkirim),
          ));
      await tester.tap(find.text('Ubah status'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Kemasan penyok');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final kirim = terkirim.single;
      expect(kirim['kunci'], 'apotik_batch_status:9');
      expect(kirim['cacheKey'], kunciCacheBatchApotik);
      final row = kirim['rowLokal'] as Map<String, dynamic>;
      expect(row['statusLot'], isNotNull);
      expect(row['lotLayak'], isNotNull,
          reason: 'baris cache harus ikut menandai lot tak layak');
    });

    testWidgets('tiap lot punya tombol riwayat AuditTrails', (tester) async {
      await _pump(
        tester,
        ApotikBatchExpiryPage(
          muatDaftar: _server(batch: [
            {
              'kadaluarsaId': 9,
              'nama': 'Obat X',
              'tanggalKadaluarsa': _tanggalDalam(40),
              'sisa': 12,
              'kedaluwarsa': false,
              'lotLayak': true,
            }
          ]),
        ),
      );
      expect(find.byTooltip('Riwayat data ini (AuditTrails)'), findsOneWidget);
    });
  });
}
