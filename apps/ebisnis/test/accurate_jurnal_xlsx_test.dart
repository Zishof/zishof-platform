import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ebisnis/services/accurate_jurnal_xlsx.dart';

void main() {
  group('AccurateJurnalXlsx', () {
    test('Generate Accurate XLSX and parse it back', () {
      final tglMulai = DateTime(2026, 7, 1);
      final tglSampai = DateTime(2026, 7, 31);

      final jurnalDummy = [
        {
          'kode': 'JV.2026.07.0001',
          'tanggal': '2026-07-01',
          'keterangan': 'Setoran Tunai Toko',
          'jenisTransaksi': 'Jurnal Umum',
          'totalDebet': 500000.0,
          'totalKredit': 500000.0,
          'baris': [
            {
              'kodeAkun': '110101',
              'namaAkun': 'Kas Toko',
              'keterangan': 'Setoran Tunai Toko',
              'debet': 500000.0,
              'kredit': 0.0,
            },
            {
              'kodeAkun': '110201',
              'namaAkun': 'Bank BSI',
              'keterangan': 'Setoran Tunai Toko',
              'debet': 0.0,
              'kredit': 500000.0,
            },
          ],
        },
      ];

      final bytes = buildAccurateJurnalXlsx(
        namaToko: 'Toko Al Bahjah',
        mulai: tglMulai,
        sampai: tglSampai,
        daftarJurnal: jurnalDummy,
      );

      expect(bytes.isNotEmpty, isTrue);

      final daftarAkun = [
        {'id': 101, 'kode': '110101', 'nama': 'Kas Toko'},
        {'id': 102, 'kode': '110201', 'nama': 'Bank BSI'},
      ];

      final hasil = parseAccurateJurnalXlsx(bytes, daftarAkun: daftarAkun);

      expect(hasil.daftarJurnal.length, equals(1));
      final j = hasil.daftarJurnal.first;
      expect(j.noBukti, equals('JV.2026.07.0001'));
      expect(j.tanggal, equals('2026-07-01'));
      expect(j.rincian.length, equals(2));
      expect(j.totalDebet, equals(500000.0));
      expect(j.totalKredit, equals(500000.0));
      expect(j.isSeimbang, isTrue);
      expect(j.rincian[0].akunId, equals(101));
      expect(j.rincian[1].akunId, equals(102));
      expect(hasil.daftarPeringatan, isEmpty);
    });

    test('Parse template asli Accurate Downloads/Histori Buku Besar (Jurnal).xlsx jika ada', () {
      final fileAsli = File(r'C:\Users\USER\Downloads\Histori Buku Besar (Jurnal).xlsx');
      if (fileAsli.existsSync()) {
        final bytes = fileAsli.readAsBytesSync();
        final hasil = parseAccurateJurnalXlsx(bytes);
        expect(hasil.daftarJurnal.isNotEmpty, isTrue);
        expect(hasil.totalBarisMentah, greaterThan(1000));
        // Cek salah satu jurnal umum
        final jv = hasil.daftarJurnal.firstWhere((j) => j.noBukti == 'JV.2026.06.11769');
        expect(jv.noBukti, equals('JV.2026.06.11769'));
        expect(jv.rincian.isNotEmpty, isTrue);
      }
    });

    test('Generate Standar XLSX', () {
      final bytes = buildStandarJurnalXlsx(
        namaToko: 'Toko Al Bahjah',
        mulai: DateTime(2026, 7, 1),
        sampai: DateTime(2026, 7, 31),
        daftarJurnal: [
          {
            'kode': 'JV.001',
            'tanggal': '2026-07-01',
            'keterangan': 'Biaya Listrik',
            'terposting': true,
            'baris': [
              {
                'kodeAkun': '5101',
                'namaAkun': 'Biaya Listrik',
                'debet': 150000.0,
                'kredit': 0.0,
              },
              {
                'kodeAkun': '1101',
                'namaAkun': 'Kas',
                'debet': 0.0,
                'kredit': 150000.0,
              }
            ]
          }
        ],
      );
      expect(bytes.isNotEmpty, isTrue);
    });
  });
}
