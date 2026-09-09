import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak konsistensi metode pembayaran antar perangkat kasir.
///
/// Daftar metode tidak boleh hanya mengandalkan snapshot saat login karena
/// admin dapat mengubah izin member/metode sementara Kasir 2/3 masih terbuka.
/// Picker harus mengambil daftar terbaru dan tetap menjaga split yang seluruh
/// metodenya masih diizinkan.
void main() {
  late String source;
  late String sourceKasir;
  late String sourcePesanan;

  setUpAll(() {
    source = File('lib/screens/keranjang_screen.dart').readAsStringSync();
    sourceKasir = File('lib/screens/kasir_screen.dart').readAsStringSync();
    sourcePesanan = File('lib/screens/pesanan_screen.dart').readAsStringSync();
  });

  test('picker membuka snapshot aman sebelum menunggu refresh server', () {
    final awal = source.indexOf('Future<void> _pilihMetode() async');
    final akhir = source.indexOf('Future<void> _aturDiskonFaktur()', awal);
    expect(awal, greaterThanOrEqualTo(0));
    expect(akhir, greaterThan(awal));

    final method = source.substring(awal, akhir);
    expect(method, contains('if (_caraBayarTersedia.isEmpty ||'));
    expect(method, contains('await _muatCaraBayarUntukMember(memberId)'));
    expect(method, contains('unawaited(_muatCaraBayarUntukMember(memberId))'));
    expect(
        method,
        contains(
            '_semuaCaraBayarUntukMemberAwal ? null : _memberTerpilih?.id'));
    expect(method.indexOf('showModalBottomSheet'), greaterThanOrEqualTo(0));
  });

  test('refresh tidak mengunci picker dan bayar saat snapshot aman tersedia',
      () {
    expect(source,
        contains('onTap: _pemilihCaraBayarBisaDibuka ? _pilihMetode : null'));
    expect(source, contains('KebijakanOfflinePembayaran.bolehBayar('));
    expect(source, isNot(contains('!_memuatCaraBayar &&')));
    expect(source, contains('Metode tersimpan siap dipakai'));
  });

  test('snapshot dipersistenkan dan dipisahkan menurut konteks akses', () {
    expect(source, contains('MasterOffline.ambilObjekTersimpan(cacheKey)'));
    expect(source.replaceAll(RegExp(r'\s+'), ''),
        contains("MasterOffline.objekDenganCache('cara_bayar_list',"));
    expect(source, contains('KebijakanOfflinePembayaran.kunciCache('));
    expect(source, contains('_konteksCaraBayarMemberId != memberId'));
    expect(source, contains('_caraBayarTersedia = memberId == null'));
  });

  test('refresh mempertahankan split yang seluruh metodenya masih sah', () {
    expect(source, contains('splitMasihDiizinkan'));
    expect(source, contains('metodeMenurutId.containsKey(slot.caraBayar.id)'));
    expect(source, contains('_splitBayar = splitTersegar'));
  });

  test('member awal dari draft menawarkan semua metode aktif', () {
    expect(sourcePesanan,
        contains('semuaCaraBayarUntukMemberAwal: member != null'));
    expect(
        sourceKasir,
        contains(
            'semuaCaraBayarUntukMemberAwal: _semuaCaraBayarUntukMemberAwal'));
    expect(source, contains('_semuaCaraBayarUntukMemberAwal ? null'));
  });

  test('mengganti member mengaktifkan kembali filter jenis member', () {
    final awal = source.indexOf('Future<void> _pilihMember() async');
    final akhir = source.indexOf('void _hapusMember()', awal);
    final method = source.substring(awal, akhir);
    expect(method, contains('_semuaCaraBayarUntukMemberAwal = false'));
    expect(method, contains('_muatCaraBayarUntukMember(terpilih.id)'));
  });

  test('penolakan izin metode memberi langkah setting dan membedakan limit',
      () {
    final errorSource =
        File('lib/widgets/app_error_info.dart').readAsStringSync();
    expect(errorSource, contains("lower.contains('metode pembayaran')"));
    expect(errorSource, contains('Pelanggan > Jenis Member'));
    expect(errorSource, contains('Pelanggan > Tipe Member'));
    expect(errorSource, contains('Maksimal Boleh Utang tidak menyelesaikan'));
    expect(errorSource, contains('Coba Kirim Transaksi Pending satu kali'));
  });
}
