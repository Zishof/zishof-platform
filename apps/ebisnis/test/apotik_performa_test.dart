import 'package:ebisnis/features/apotik/core/apotik_design_tokens.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_batch_expiry_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/prescription/apotik_resep_page.dart';
import 'package:ebisnis/features/apotik/shared/widgets/medication_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// <h3>Penjaga performa daftar (Fase 8).</h3>
///
/// Bukan pengukuran milidetik — angka begitu tidak stabil di mesin CI/uji dan
/// gampang jadi klaim kosong. Yang dijaga di sini adalah SIFAT yang benar-benar
/// menentukan performa daftar panjang:
///
/// 1. daftar yang jumlah barisnya mengikuti data server harus **malas**
///    (hanya membangun baris yang terlihat);
/// 2. permintaan katalog harus tetap **berhalaman** — begitu ada yang menaikkan
///    `page_size` menjadi "semua", layar akan membangun ratusan kartu sekaligus.
List<Map<String, dynamic>> _batchBanyak(int n) => List.generate(
      n,
      (i) => {
        'kadaluarsaId': i + 1,
        'nama': 'Obat Uji Nomor ${i + 1}',
        'tanggalKadaluarsa': '2026-12-31',
        'sisa': 10 + i,
        'statusLot': 'ELIGIBLE',
        'lotLayak': true,
      },
    );

List<Map<String, dynamic>> _resepBanyak(int n) => List.generate(
      n,
      (i) => {
        'id': i + 1,
        'kode': 'RSP-${i + 1}',
        'namaPasien': 'Pasien ${i + 1}',
        'namaDokter': 'dr. Uji',
        'status': 'MENUNGGU',
        'tanggal': '2026-09-02',
        'jumlahBaris': 3,
      },
    );

Future<void> _pump(WidgetTester tester, Widget child,
    {Size ukuran = const Size(1100, 800)}) async {
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
  group('Daftar panjang tetap malas', () {
    testWidgets('monitor kedaluwarsa 100 baris tidak dibangun sekaligus',
        (tester) async {
      await _pump(
        tester,
        ApotikBatchExpiryPage(
            muatDaftar: (aksi, body, cacheKey, {required onData}) async {
          onData({
            'data': aksi == 'apotik_batch_monitor'
                ? _batchBanyak(100)
                : const <Map<String, dynamic>>[],
            'dariServer': true,
          });
        }),
      );
      final terbangun =
          tester.widgetList(find.textContaining('Obat Uji Nomor ')).length;
      expect(terbangun, greaterThan(0), reason: 'daftar harus terisi');
      expect(terbangun, lessThan(100),
          reason: 'ListView.builder hanya boleh membangun baris yang terlihat');
    });

    testWidgets('antrean resep 100 baris tidak dibangun sekaligus',
        (tester) async {
      await _pump(
        tester,
        ApotikResepPage(
            panggil: (aksi, body) async => {'status': '00', 'data': const []},
            muatDaftar: (aksi, body, cacheKey, {required onData}) async {
              onData({
                'data': aksi == 'apotik_resep_list'
                    ? _resepBanyak(100)
                    : const <Map<String, dynamic>>[],
                'dariServer': true,
              });
            }),
      );
      final terbangun = tester.widgetList(find.textContaining('RSP-')).length;
      expect(terbangun, greaterThan(0));
      expect(terbangun, lessThan(100));
    });
  });

  group('Katalog POS tetap berhalaman', () {
    testWidgets('permintaan pencarian membawa page_size yang wajar',
        (tester) async {
      final permintaan = <Map<String, dynamic>>[];
      await _pump(
        tester,
        ApotikPosPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_item_cari') {
            permintaan.add(Map<String, dynamic>.from(body));
            return {
              'status': '00',
              'data': [
                {'id': 1, 'kode': 'A', 'nama': 'Obat A', 'stok': 3}
              ]
            };
          }
          return {'status': '00', 'data': const []};
        }),
        ukuran: const Size(1500, 900),
      );
      expect(permintaan, isNotEmpty);
      final ukuranHalaman = (permintaan.first['page_size'] as num?)?.toInt();
      expect(ukuranHalaman, isNotNull,
          reason: 'katalog TIDAK boleh meminta seluruh formularium');
      // Kartu obat cukup berat (badge, pill, harga); 60 kartu sekali bangun
      // sudah terasa pada mesin kasir kelas rendah.
      expect(ukuranHalaman, lessThanOrEqualTo(100));
    });

    testWidgets('kartu yang dibangun sebanyak hasil, bukan seluruh katalog',
        (tester) async {
      await _pump(
        tester,
        ApotikPosPage(panggil: (aksi, body) async {
          if (aksi == 'apotik_item_cari') {
            return {
              'status': '00',
              'data': List.generate(
                  8,
                  (i) => {
                        'id': i,
                        'kode': 'K$i',
                        'nama': 'Obat $i',
                        'stok': 5,
                        'hargaJual': 1000
                      })
            };
          }
          return {'status': '00', 'data': const []};
        }),
        ukuran: const Size(1500, 900),
      );
      expect(find.byType(MedicationCard), findsNWidgets(8));
    });
  });
}
