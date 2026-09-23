import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checkout membawa antrean catatan dan program meal sampai struk', () {
    final checkout =
        File('lib/screens/keranjang_screen.dart').readAsStringSync();
    final struk = File('lib/screens/struk_screen.dart').readAsStringSync();

    for (final marker in const [
      "'nomor_antrian': _nomorAntrianPercobaan",
      "'keterangan': _catatanPesananController.text.trim()",
      "'jenis_konsumsi': _jenisKonsumsi",
      "Manager Meal maksimal Rp20.000",
      "Crew Meal (diskon 10%)",
    ]) {
      expect(checkout, contains(marker));
    }
    expect(struk, contains("'ANTRIAN \${nomorAntrian!.trim()}'"));
    expect(struk, contains("_infoPdf('Catatan', catatanPesanan!.trim())"));
    expect(struk, contains("jenisDokumen: 'TIKET DAPUR'"));
    expect(struk, contains("label: const Text('Cetak Tiket Dapur')"));
  });

  test('nomor antrean dipisahkan per toko perangkat dan tanggal', () {
    final source =
        File('lib/services/pengaturan_nomor_antrian.dart').readAsStringSync();
    expect(
        source, contains("'nomor_antrian_\${tokoId}_\${perangkat}_\$tanggal'"));
    expect(source, contains("urutan.toString().padLeft(3, '0')"));
  });

  test('self order memakai endpoint publik toko dan masuk menu operasional',
      () {
    final layar = File('lib/screens/self_order_screen.dart').readAsStringSync();
    final menu = File('lib/widgets/app_shell.dart').readAsStringSync();
    expect(layar, contains("resolve('Kantin')"));
    expect(layar, contains("bc.Barcode.qrCode()"));
    expect(menu, contains("'Self Order / QR Menu'"));
    expect(menu, contains('MenuEBisnis.selfOrder'));
  });

  test('shift otomatis tetap melalui buka kas dan rekonsiliasi resmi', () {
    final kasir = File('lib/screens/kasir_screen.dart').readAsStringSync();
    final layar =
        File('lib/screens/shift_otomatis_screen.dart').readAsStringSync();
    expect(kasir, contains("_bukaKas(p.modalAwal, 'Shift dibuka otomatis"));
    expect(kasir, contains('await _bukaDialogTutupKas()'));
    expect(layar, contains('Kasir tetap wajib mengisi uang fisik.'));
  });
}
