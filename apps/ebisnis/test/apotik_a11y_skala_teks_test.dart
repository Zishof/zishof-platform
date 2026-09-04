import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_batch_expiry_page.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_formularium_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pembayaran_sheet.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_state.dart';
import 'package:ebisnis/features/apotik/procurement/apotik_penerimaan_page.dart';
import 'package:ebisnis/features/apotik/reports/apotik_rekonsiliasi_page.dart';
import 'package:ebisnis/features/apotik/shared/widgets/apotik_status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _obat = {
  'id': 1,
  'kode': 'OBT-1',
  'nama': 'Amoxicillin Trihydrate 500 mg Kapsul',
  'stok': 4,
  'hargaJual': 3500,
  'lasa': true,
  'highAlert': true,
  'coldChain': true,
  'golonganObat': 'KERAS',
  'bentukSediaan': 'kapsul',
  'kekuatan': '500 mg',
};

Future<Map<String, dynamic>> _server(
    String aksi, Map<String, dynamic> body) async {
  switch (aksi) {
    case 'apotik_item_cari':
      return {
        'status': '00',
        'data': [_obat]
      };
    case 'apotik_batch_monitor':
      return {
        'status': '00',
        'data': [
          {
            'kadaluarsaId': 1,
            'itemNama': 'Amoxicillin Trihydrate 500 mg Kapsul',
            'tanggalKadaluarsa': '2026-10-01',
            'sisa': 12,
            'statusLot': 'QUARANTINE',
            'lotLayak': false,
            'alasanLot': 'Lot dikarantina menunggu pemeriksaan mutu',
          }
        ],
        'jumlahKedaluwarsa': 1,
        'jumlahSegera': 1,
      };
    case 'apotik_cara_bayar_list':
      return {
        'status': '00',
        'data': [
          {'id': 1, 'nama': 'Tunai Laci Depan', 'adaKembalian': true},
          {'id': 2, 'nama': 'QRIS Bank Daerah', 'adaKembalian': false},
        ]
      };
    case 'apotik_laporan_pembayaran':
      return {
        'status': '00',
        'perMetode': [
          {
            'nama': 'Tunai Laci Depan',
            'tunai': true,
            'jumlahTransaksi': 12,
            'nominal': 1250000
          },
        ],
        'totalTunai': 1250000,
        'totalNonTunai': 340000,
        'jumlahTransaksi': 16,
        'penjualanLedger': 1700000,
        'selisihTanpaMetode': 110000,
      };
  }
  return {'status': '00', 'data': const []};
}

/// Pemuat "lokal dulu" yang meneruskan ke [_server] palsu di atas, sehingga
/// layar master ikut diuji pada skala teks besar.
Future<void> _muatLokal(
  String aksi,
  Map<String, dynamic> body,
  String cacheKey, {
  required void Function(Map<String, dynamic> hasil) onData,
}) async {
  final r = await _server(aksi, body);
  onData({...r, 'dariServer': true});
}

/// Memasang layar pada skala teks tertentu. Overflow tata letak muncul sebagai
/// exception yang ditangkap [WidgetTester], sehingga pemeriksaannya nyata —
/// bukan sekadar "kelihatannya muat".
Future<Object?> _pumpSkala(
  WidgetTester tester,
  Widget child, {
  required double skala,
  required Size ukuran,
}) async {
  await tester.binding.setSurfaceSize(ukuran);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
        useMaterial3: true, extensions: const [ApotikDesignTokens.light]),
    home: MediaQuery(
      data: MediaQueryData(size: ukuran, textScaler: TextScaler.linear(skala)),
      child: SizedBox(width: ukuran.width, height: ukuran.height, child: child),
    ),
  ));
  await tester.pumpAndSettle();
  return tester.takeException();
}

void main() {
  // 1,3 dan 2,0 dipilih karena keduanya nyata dipakai: 1,3 setelan lansia yang
  // umum, 2,0 batas atas pengaturan aksesibilitas Android/iOS.
  const skalaUji = [1.0, 1.3, 2.0];

  group('Skala teks — layar tidak boleh meluber', () {
    for (final skala in skalaUji) {
      testWidgets('POS desktop pada skala ${skala}x', (tester) async {
        final pos = ApotikPosController()
          ..tambah(ApotikBarisKeranjang(item: _obat, qty: 2, harga: 3500));
        final galat = await _pumpSkala(
          tester,
          ApotikPosPage(controller: pos, panggil: _server),
          skala: skala,
          ukuran: const Size(1500, 950),
        );
        expect(galat, isNull);
      });

      testWidgets('POS ponsel pada skala ${skala}x', (tester) async {
        final pos = ApotikPosController()
          ..tambah(ApotikBarisKeranjang(item: _obat, qty: 2, harga: 3500));
        final galat = await _pumpSkala(
          tester,
          ApotikPosPage(controller: pos, panggil: _server),
          skala: skala,
          ukuran: const Size(390, 844),
        );
        expect(galat, isNull);
      });

      testWidgets('Formularium pada skala ${skala}x', (tester) async {
        final galat = await _pumpSkala(
          tester,
          const ApotikFormulariumPage(muatDaftar: _muatLokal),
          skala: skala,
          ukuran: const Size(1100, 900),
        );
        expect(galat, isNull);
      });

      testWidgets('Monitor kedaluwarsa pada skala ${skala}x', (tester) async {
        final galat = await _pumpSkala(
          tester,
          const ApotikBatchExpiryPage(muatDaftar: _muatLokal),
          skala: skala,
          ukuran: const Size(1100, 900),
        );
        expect(galat, isNull);
      });

      testWidgets('Penerimaan PBF pada skala ${skala}x', (tester) async {
        final galat = await _pumpSkala(
          tester,
          const ApotikPenerimaanPage(panggil: _server),
          skala: skala,
          ukuran: const Size(1200, 900),
        );
        expect(galat, isNull);
      });

      testWidgets('Rekonsiliasi kas pada skala ${skala}x', (tester) async {
        final galat = await _pumpSkala(
          tester,
          // Dipasang di dalam Scaffold seperti pemakaian nyatanya (tab di
          // dalam AppShell) -- TextField menuntut leluhur Material.
          const Scaffold(body: ApotikRekonsiliasiPage(panggil: _server)),
          skala: skala,
          ukuran: const Size(900, 900),
        );
        expect(galat, isNull);
      });

      testWidgets('Lembar pembayaran pada skala ${skala}x', (tester) async {
        final galat = await _pumpSkala(
          tester,
          const Scaffold(
            body: ApotikPembayaranSheet(
              total: 125000,
              metode: [
                MetodeBayar(
                    id: 1, nama: 'Tunai Laci Depan', adaKembalian: true),
                MetodeBayar(id: 2, nama: 'QRIS Bank Daerah'),
              ],
            ),
          ),
          skala: skala,
          ukuran: const Size(420, 900),
        );
        expect(galat, isNull);
      });
    }
  });

  group('Pill status pada skala besar', () {
    testWidgets('deretan pill tetap muat pada 2,0x', (tester) async {
      final galat = await _pumpSkala(
        tester,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              ApotikStatusPill(
                  teks: 'Kedaluwarsa',
                  nada: ApotikStatusNada.bahaya,
                  penjelasan: 'Tidak boleh dijual'),
              ApotikStatusPill(
                  teks: 'Segera kedaluwarsa',
                  nada: ApotikStatusNada.peringatan),
              ApotikStatusPill(teks: 'Layak', nada: ApotikStatusNada.sukses),
            ]),
          ),
        ),
        skala: 2.0,
        ukuran: const Size(360, 400),
      );
      expect(galat, isNull);
    });
  });
}
