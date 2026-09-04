import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/core/apotik_lokal_dulu.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_formularium_page.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:ebisnis/widgets/kilau_perubahan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _obat = <String, dynamic>{
  'id': 11,
  'kode': 'OBT-11',
  'nama': 'Amoxicillin 500 mg',
  'satuan': 'tablet',
  'stok': 25,
  'hargaJual': 2500,
  'golonganObat': 'BEBAS',
  'lasa': false,
  'highAlert': false,
  'coldChain': false,
};

/// Pemuat palsu yang meniru urutan NYATA `MasterOffline.daftarCacheDulu`:
/// emisi cache lebih dulu (`dariServer: false`), lalu emisi server dengan
/// diff. Jalur UI yang diuji sama persis dengan produksi.
MuatDaftarApotik _pemuat({
  List<Map<String, dynamic>>? cache,
  List<Map<String, dynamic>>? server,
  Set<String> idBaru = const {},
  Set<String> idBerubah = const {},
  int jumlahHapus = 0,
  Object? galat,
  List<Map<String, dynamic>>? permintaan,
}) {
  return (aksi, body, cacheKey, {required onData}) async {
    permintaan?.add({'aksi': aksi, 'cacheKey': cacheKey, ...body});
    if (cache != null) {
      onData({'data': cache, 'dariServer': false});
    }
    if (galat != null) throw galat;
    if (server != null) {
      onData({
        'data': server,
        'dariServer': true,
        'idBaru': idBaru,
        'idBerubah': idBerubah,
        'jumlahHapus': jumlahHapus,
      });
    }
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

void main() {
  testWidgets('menampilkan katalog memakai kartu yang SAMA dengan POS',
      (tester) async {
    await _pump(
        tester, ApotikFormulariumPage(muatDaftar: _pemuat(server: [_obat])));
    expect(find.byType(MedicationCard), findsOneWidget);
    expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
  });

  testWidgets('kosong memberi petunjuk asal obat baru', (tester) async {
    await _pump(
        tester, ApotikFormulariumPage(muatDaftar: _pemuat(server: const [])));
    expect(find.text('Obat tidak ditemukan'), findsOneWidget);
    expect(find.textContaining('modul persediaan/penerimaan'), findsOneWidget);
  });

  group('Local-first', () {
    testWidgets('memakai kunci cache yang sama dengan layar persediaan lama',
        (tester) async {
      final permintaan = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
              muatDaftar: _pemuat(server: [_obat], permintaan: permintaan)));
      expect(permintaan.first['cacheKey'], kunciCacheItemApotik);
      expect(permintaan.first['aksi'], 'apotik_item_cari');
    });

    testWidgets('isi cache tampil walau server GAGAL dijangkau',
        (tester) async {
      await _pump(
        tester,
        ApotikFormulariumPage(
          muatDaftar:
              _pemuat(cache: [_obat], galat: Exception('Koneksi terputus')),
        ),
      );
      // Daftar terakhir tetap terbaca; layar tidak jatuh ke keadaan galat.
      expect(find.text('Amoxicillin 500 mg'), findsOneWidget);
      expect(find.textContaining('Koneksi terputus'), findsNothing);
    });

    testWidgets('cache kosong DAN server gagal: galat ditampilkan apa adanya',
        (tester) async {
      await _pump(
        tester,
        ApotikFormulariumPage(
            muatDaftar: _pemuat(galat: Exception('Koneksi terputus'))),
      );
      expect(find.textContaining('Koneksi terputus'), findsOneWidget);
    });

    testWidgets('perubahan dari petugas lain diberitahukan dan dianimasikan',
        (tester) async {
      await _pump(
        tester,
        ApotikFormulariumPage(
          muatDaftar: _pemuat(
            cache: [_obat],
            server: [_obat],
            idBerubah: {'11'},
            jumlahHapus: 2,
          ),
        ),
      );
      expect(find.textContaining('Pembaruan dari server'), findsOneWidget);
      expect(find.textContaining('1 berubah'), findsOneWidget);
      expect(find.textContaining('2 dihapus'), findsOneWidget);
      expect(find.byType(KilauBaris), findsWidgets);
    });

    testWidgets('emisi cache TIDAK dianggap perubahan server', (tester) async {
      await _pump(
        tester,
        ApotikFormulariumPage(muatDaftar: _pemuat(cache: [_obat])),
      );
      expect(find.textContaining('Pembaruan dari server'), findsNothing);
    });

    testWidgets('tiap baris punya tombol riwayat AuditTrails', (tester) async {
      await _pump(
          tester, ApotikFormulariumPage(muatDaftar: _pemuat(server: [_obat])));
      expect(find.byTooltip('Riwayat data ini (AuditTrails)'), findsOneWidget);
    });
  });

  group('Editor profil IR-01 — melengkapi lingkaran baca/tulis', () {
    testWidgets('form memuat nilai yang sudah ada', (tester) async {
      await _pump(
          tester,
          ApotikFormulariumPage(
              muatDaftar: _pemuat(server: [
            {
              ..._obat,
              'golonganObat': 'KERAS',
              'kekuatan': '500 mg',
              'bentukSediaan': 'kaplet',
              'highAlert': true,
            }
          ])));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      expect(find.text('500 mg'), findsWidgets);
      expect(find.text('kaplet'), findsOneWidget);
      expect(find.text('Keras (Rx)'), findsWidgets);
    });

    testWidgets('menyimpan lewat antrean master, bukan panggilan langsung',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
            muatDaftar: _pemuat(server: [_obat]),
            simpan: _penyimpan(terkirim: terkirim),
          ));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Kekuatan'), '250 mg');
      await tester.enterText(
          find.widgetWithText(TextField, 'Bentuk sediaan'), 'sirup');
      await tester.tap(find.text('High-alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      expect(terkirim.length, 1);
      final kirim = terkirim.single;
      expect(kirim['aksi'], 'apotik_item_profil_simpan');
      expect(kirim['item_id'], 11);
      expect(kirim['kekuatan'], '250 mg');
      expect(kirim['bentuk_sediaan'], 'sirup');
      expect(kirim['high_alert'], isTrue);
      expect(kirim.containsKey('golongan_obat'), isTrue);
      expect(kirim.containsKey('lasa'), isTrue);
      expect(kirim.containsKey('cold_chain'), isTrue);
      // Wajib untuk offline-first: kunci antrean + cache yang harus diperbarui.
      expect(kirim['kunci'], 'apotik_item_profil:11');
      expect(kirim['cacheKey'], kunciCacheItemApotik);
    });

    testWidgets('baris lokal dikirim dalam bentuk yang dibaca kartu obat',
        (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
            muatDaftar: _pemuat(server: [_obat]),
            simpan: _penyimpan(terkirim: terkirim),
          ));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Kekuatan'), '250 mg');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      final row = terkirim.single['rowLokal'] as Map<String, dynamic>;
      // camelCase seperti yang dikirim server, bukan snake_case milik payload:
      // kalau salah, kartu di cache akan kehilangan badge-nya saat offline.
      expect(row['kekuatan'], '250 mg');
      expect(row.containsKey('golonganObat'), isTrue);
      expect(row.containsKey('highAlert'), isTrue);
      expect(row['id'], 11, reason: 'baris lokal harus tetap dikenali');
    });

    testWidgets('membatalkan dialog TIDAK mengirim apa pun', (tester) async {
      final terkirim = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
            muatDaftar: _pemuat(server: [_obat]),
            simpan: _penyimpan(terkirim: terkirim),
          ));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(terkirim, isEmpty);
    });

    testWidgets('offline: daftar TIDAK dimuat ulang dari server',
        (tester) async {
      final permintaan = <Map<String, dynamic>>[];
      await _pump(
          tester,
          ApotikFormulariumPage(
            muatDaftar: _pemuat(server: [_obat], permintaan: permintaan),
            simpan: _penyimpan(hasil: {'status': '00', 'offline': true}),
          ));
      final sebelum = permintaan.length;
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      // Cache lokal sudah diperbarui oleh alur simpan; memuat ulang saat
      // offline hanya akan gagal dan menakut-nakuti apoteker.
      expect(permintaan.length, sebelum);
    });

    testWidgets('kegagalan simpan ditampilkan apa adanya', (tester) async {
      await _pump(
          tester,
          ApotikFormulariumPage(
            muatDaftar: _pemuat(server: [_obat]),
            simpan: _penyimpan(lempar: Exception('Golongan tidak dikenal')),
          ));
      await tester.tap(find.byType(MedicationCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Golongan tidak dikenal'), findsOneWidget);
    });
  });
}
