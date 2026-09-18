import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kartu hasil sinkronisasi harus menyebut pegawai MANA yang gagal.
///
/// `sinkronPegawai` mengumpulkan sampai lima `{pegawaiId, alasan}` pegawai yang
/// gagal menjadi member, dan deskripsinya menyuruh admin "Buka Log Error ...
/// untuk baris yang gagal". Jejak log galat server dikunci `idPegawai=<id>`.
/// Sebelum ini klien membuang `contohGagal`: admin tahu ADA yang gagal, tetapi
/// tidak tahu baris log mana yang dimaksud. Ditemukan setelah
/// `alat/field-tanpa-pembaca.py` berhenti memakai pencocokan substring
/// (ais docs/pos/134).
///
/// Kenapa uji ini perlu padahal penjaga sudah hijau: penjaga berbasis NAMA.
/// Dalam kontrol negatif, baris pemetaan dicabut sementara kartu masih
/// menyebut `r['contohGagal']` -- penjaga tetap hijau, padahal nilainya tidak
/// lagi sampai ke layar. Rantai di dalam klien hanya bisa dijaga di sini.
void main() {
  late String layar;

  setUpAll(() {
    layar = File('lib/screens/anggota/tab_sinkronisasi.dart').readAsStringSync();
  });

  test('respons server dipetakan ke hasil per sumber', () {
    // Mata rantai pertama: tanpa ini kartu membaca kunci yang tak pernah diisi.
    expect(layar, contains("'contohGagal': hasil['contohGagal']"),
        reason: 'nilai server harus masuk ke peta hasil, bukan hanya disebut');
  });

  test('kartu membaca id pegawai dari contoh itu', () {
    expect(layar, contains("r['contohGagal']"));
    expect(layar, contains("e['pegawaiId']"));
  });

  test('pesannya menunjuk ke tempat yang bisa dicocokkan', () {
    // Tanpa rujukan ke Log Error, id mentah tidak membantu siapa pun.
    expect(layar, contains('cocokkan dengan idPegawai di Log Error'));
  });

  test('pemotongan lima contoh diakui, bukan disembunyikan', () {
    // Server membatasi lima; bila gagalnya lebih banyak, pengguna harus tahu
    // bahwa daftar ini bukan semuanya.
    expect(layar, contains('pertama dari'));
  });

  test('hanya tampil bila memang ada yang gagal', () {
    expect(layar, contains('if (error == null && idGagal.isNotEmpty)'));
  });
}
