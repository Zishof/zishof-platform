import 'package:ebisnis/screens/apotik/layar_antrean_farmasi_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mode layar farmasi stabil untuk argumen multi-window', () {
    expect(ModeLayarFarmasi.semua.kode, 'SEMUA');
    expect(ModeLayarFarmasi.obatJadi.kode, 'JADI');
    expect(ModeLayarFarmasi.racikan.kode, 'RACIKAN');
    expect(ModeLayarFarmasiX.dari('JADI'), ModeLayarFarmasi.obatJadi);
    expect(ModeLayarFarmasiX.dari('RACIKAN'), ModeLayarFarmasi.racikan);
    expect(ModeLayarFarmasiX.dari('tidak-dikenal'), ModeLayarFarmasi.semua);
  });

  test('setiap mode mempunyai label yang dapat dibaca pasien', () {
    expect(ModeLayarFarmasi.values.map((m) => m.label).toSet().length, 3);
    expect(ModeLayarFarmasi.semua.label, contains('Racikan'));
  });
}
