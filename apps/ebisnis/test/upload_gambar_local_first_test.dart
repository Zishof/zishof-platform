import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semua jalur upload gambar memakai antrean local-first bersama', () {
    final produk = File('lib/screens/produk_screen.dart').readAsStringSync();
    final member =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    final screensaver =
        File('lib/screens/konfigurasi/tab_screensaver.dart').readAsStringSync();
    final layanan =
        File('lib/services/simpan_gambar_local_first.dart').readAsStringSync();

    for (final sumber in [produk, member, screensaver]) {
      expect(sumber, contains('simpanGambarLocalFirst('));
    }
    expect(
      produk,
      isNot(contains("ApiClient.instance.aksi('produk_foto_upload'")),
    );
    expect(
      screensaver,
      isNot(contains("ApiClient.instance.aksi('layar_pelanggan_slide_upload'")),
    );
    expect(layanan, contains('MasterOffline.antreLokal('));
    expect(layanan, contains('MasterOffline.kirimSatuAntrean('));
    expect(layanan, contains('TimeoutException'));
    expect(layanan, contains('muatGambarLokalTertunda'));
    expect(layanan, contains('outboxMasterAktif'));
    expect(member, contains('muatGambarLokalTertunda('));
    expect(produk, contains('muatGambarLokalTertunda('));
    expect(screensaver, contains('muatGambarLokalTertunda('));
    expect(screensaver, contains("fieldBase64: 'gambar_base64'"));
    expect(screensaver, contains('Image.memory(gambarLokal'));
  });

  test('foto produk baru ikut antre dengan id produk sementara', () {
    final sumber = File('lib/screens/produk_screen.dart').readAsStringSync();
    expect(sumber, contains('MasterOffline.idSementaraBaru()'));
    expect(sumber, contains("entitas: 'produk'"));
    expect(sumber, contains('idLokal: ubah ? null : idProduk'));
    expect(sumber, contains('await _unggahBaris(baris, produkIdBaru)'));
  });

  test('referensi dropdown produk dideduplikasi dan punya fallback nilai lama',
      () {
    final sumber = File('lib/screens/produk_screen.dart').readAsStringSync();
    expect(sumber, contains('unik.putIfAbsent(kategori.id'));
    expect(sumber, contains('unik.putIfAbsent(kebijakan.id'));
    expect(sumber, contains('referensi belum tersinkron'));
    expect(sumber, contains('grupUnik.putIfAbsent(id'));
  });
}
