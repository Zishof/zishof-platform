import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pelunasan piutang harus bisa dimulai dari barisnya, bukan diketik ulang.
///
/// Permintaan produksi 17-09-2026 (Ika Salsabila):
///   "bisa gak ya ketika kita mau proses pelunasan piutang ini tinggal klik
///    aja transaksi nya untk dilunasi, agar tidak perlu pelunasan manual"
///   "kalau di entry pelunasan ini kita harus manual yaa"
///
/// Yang dikerjakan: tombol "Lunasi" pada baris yang MENAMBAH piutang membuka
/// lembar pelunasan yang sudah terisi nominal dan keterangannya.
///
/// Yang TIDAK dikerjakan, dan disebut di sini supaya tidak salah dibaca nanti:
/// server mencatat pelunasan pada SALDO anggota (aksi `hutang_bayar_simpan`
/// hanya menerima id_member/nominal/keterangan/waktu -- tidak ada alokasi per
/// nota). Jadi ini bantuan pengisian, bukan janji alokasi per transaksi.
///
/// Rantai yang diikat: tombol -> parameter -> controller. Kalau salah satu
/// mata rantai putus, tombolnya tetap ada dan tetap membuka lembar KOSONG --
/// gagal diam-diam, persis keluhan aslinya kembali tanpa pesan galat apa pun.
void main() {
  late String layar;

  setUpAll(() {
    layar =
        File('lib/screens/anggota/tab_mutasi_hutang.dart').readAsStringSync();
  });

  test('ada tombol Lunasi pada baris piutang', () {
    expect(layar, contains("label: const Text('Lunasi')"));
  });

  test('tombol mengirim nominal baris, bukan membuka lembar kosong', () {
    expect(layar, contains("nominalAwal: ((r['bertambah'] as num?) ?? 0)"),
        reason: 'inti permintaannya: tidak perlu mengetik ulang nominalnya');
  });

  test('lembar pelunasan benar-benar membaca nilai awal itu', () {
    // Mata rantai yang paling mudah putus: parameter dikirim, lalu tidak
    // pernah dibaca. Lembarnya tetap terbuka kosong dan tak ada yang gagal.
    expect(layar, contains('widget.nominalAwal'));
    expect(layar, contains('widget.keteranganAwal'));
  });

  test('nilai awal masuk ke controller, bukan sekadar disimpan di field', () {
    expect(layar, contains('_nominal.text ='));
    expect(layar, contains('_keterangan.text ='));
  });

  test('hanya baris penambah piutang yang bisa dilunasi', () {
    // Baris pembayaran tidak punya sisa untuk dilunasi; menampilkan tombol di
    // sana mengundang pelunasan ganda.
    expect(layar, contains("if (((r['bertambah'] as num?) ?? 0) > 0 &&"));
  });

  test('tombol tetap tunduk pada izin pelunasan', () {
    final i = layar.indexOf("label: const Text('Lunasi')");
    expect(i, greaterThan(0));
    final blok = layar.substring((i - 700).clamp(0, layar.length), i);
    expect(blok, contains('Sesi.instance.bolehEntryPelunasanPiutang'),
        reason: 'jalan pintas baru tidak boleh melewati gerbang izin lama');
  });
}
