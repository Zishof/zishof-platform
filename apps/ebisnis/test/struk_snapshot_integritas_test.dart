import 'package:ebisnis/screens/struk_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cetak langsung menahan grand total campuran sebelum mengakses printer',
      () async {
    const struk = StrukScreen(
      kode: 'UAT-CETAK',
      waktu: '15-09-2026 13:00:00',
      item: [
        {'nama': 'Barang', 'harga': 18500, 'qty': 1}
      ],
      total: 401890,
      metode: 'Tunai',
      modeCetakUlang: true,
    );
    // Tanpa guard, pemanggilan ini mencoba plugin printer yang tidak tersedia
    // di lingkungan tes. Tidak ada dokumen campuran yang boleh dikirim ke sana.
    await expectLater(struk.cetakLangsung(), completes);
  });
  final itemStruk = <Map<String, dynamic>>[
    {'nama': 'Barang A', 'harga': 3000, 'qty': 2},
    {'nama': 'Barang B', 'harga': 73000, 'qty': 1},
  ];

  test('snapshot utuh menerima total yang sesuai rincian', () {
    expect(
      totalServerKonsistenDenganSnapshot(
        item: itemStruk,
        totalServer: 79000,
        pajak: 0,
        totalDiskonServer: 0,
      ),
      isTrue,
    );
  });

  test('struk campuran 79.000 dan total server 341.575 ditolak', () {
    expect(
      totalServerKonsistenDenganSnapshot(
        item: itemStruk,
        totalServer: 341575,
        pajak: 0,
        totalDiskonServer: 0,
      ),
      isFalse,
    );
  });

  test('koreksi diskon server tetap dianggap konsisten', () {
    expect(
      totalServerKonsistenDenganSnapshot(
        item: itemStruk,
        totalServer: 78600,
        pajak: 0,
        totalDiskonServer: 400,
      ),
      isTrue,
    );
  });
}
