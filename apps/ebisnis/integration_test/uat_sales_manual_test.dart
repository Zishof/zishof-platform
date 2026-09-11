import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/main_inventory_sales.dart' as app;
import 'package:ebisnis/screens/inventory_sales/master_customer_screen.dart';
import 'package:ebisnis/screens/inventory_sales/nota_sales_screen.dart';
import 'package:ebisnis/screens/inventory_sales/penjualan_sales_screen.dart';
import 'package:ebisnis/screens/inventory_sales/persediaan_screen.dart';
import 'package:ebisnis/screens/inventory_sales/spj_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// UAT TANGKAPAN LAYAR — PERAN SALES KELILING (menyeluruh).
///
/// MASUK SEBAGAI SALES, BUKAN SEBAGAI PEMILIK. Itu bukan detail teknis: setiap layar di
/// sini menyaring datanya menurut profil sales yang sedang masuk, dan menu sidebar-nya pun
/// berbeda. Tangkapan yang diambil sebagai pemilik memperlihatkan hal yang tidak pernah
/// dilihat pengguna manual ini.
///
/// DUA KEADAAN SESI DIPOTRET, dan itu disengaja. Tombol "Jual Tunai", "Catat Biaya",
/// "Kulakan Sesi", "Setoran", dan "Kembali" HANYA muncul pada sesi yang masih berjalan;
/// pada sesi CLOSED tombol-tombol itu hilang. Manual yang hanya memotret sesi tertutup akan
/// memandu pengguna menekan tombol yang tidak ada di layarnya.
///
/// Datanya disiapkan dua skrip:
///   uat-sales-alur.py          -> SPJ-1-000004 / NSS-1-000004, sudah CLOSED (rekap penuh)
///   uat-sales-sesi-berjalan.py -> SPJ-1-000005 / NSS-1-000005, masih ACTIVE
///
/// Jalankan (Tomcat UAT 18080 dan klaster 55600 harus hidup):
///   flutter test integration_test/uat_sales_manual_test.dart -d windows ^
///     --dart-define=EBISNIS_VARIANT=inventory_sales ^
///     --dart-define=POS_TEST_USERNAME=sales --dart-define=POS_TEST_PASSWORD=sales123 ^
///     --dart-define=POS_TEST_HOST=127.0.0.1:18080 --dart-define=POS_TEST_CONTEXT=ais ^
///     --dart-define=POS_TEST_HTTPS=false ^
///     "--dart-define=POS_TEST_OUTPUT_DIR=C:/opt/uat-inventory/layar-sales"
const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR',
    defaultValue: r'C:\opt\uat-inventory\layar-sales');

/// Layar Pelanggan sengaja TIDAK ada di daftar ini: ia jendela desktop KEDUA
/// (`desktop_multi_window`), bukan layar di dalam jendela utama, sehingga tidak dapat
/// dipotret oleh uji widget — dan ia bukan bagian alur kerja sales.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT Sales: tangkap seluruh layar peran sales keliling', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const konteks = String.fromEnvironment('POS_TEST_CONTEXT');
    const https = bool.fromEnvironment('POS_TEST_HTTPS', defaultValue: false);
    expect(username, isNotEmpty, reason: 'POS_TEST_USERNAME wajib');
    expect(host, isNotEmpty, reason: 'POS_TEST_HOST wajib');

    await ServerConfig.instance
        .simpan(host: host, contextPath: konteks, https: https);

    Map<String, dynamic>? login;
    Object? galat;
    for (var i = 1; i <= 3 && login == null; i++) {
      try {
        login = await ApiClient.instance.aksi('login', {
          'username': username,
          'password': password,
          'labelPerangkat': 'UAT-Sales',
        });
      } catch (e) {
        galat = e;
        await Future<void>.delayed(Duration(seconds: i));
      }
    }
    if (login == null) {
      throw StateError('Login gagal ke $host/$konteks sebagai $username: $galat');
    }
    await ApiClient.instance.simpanToken(login['token'] as String);

    app.main();
    await _tunggu(tester, () => find.byType(MaterialApp).evaluate().isNotEmpty,
        detik: 120, alasan: 'Aplikasi tidak selesai dimuat');
    await tester.pump(const Duration(seconds: 3));

    final catatan = StringBuffer('berkas,judul,hasil,bita,catatan\n');
    var sukses = 0, gagal = 0;

    /// Memotret dan MEMERIKSA ISI. Penjaga ukuran berkas saja pernah meloloskan tiga
    /// penangkapan berturut-turut yang isinya pesan kesalahan.
    Future<void> potret(String berkas, String judul) async {
      try {
        final bita = await _potret(tester, berkas);
        final g = _galatDiLayar(tester);
        if (g != null) {
          catatan.writeln('$berkas,"$judul",GALAT-LAYAR,$bita,"${g.replaceAll('"', "'")}"');
          gagal++;
        } else {
          catatan.writeln('$berkas,"$judul",OK,$bita,');
          sukses++;
        }
      } catch (e) {
        final p = e.toString().replaceAll('"', "'").replaceAll('\n', ' ');
        catatan.writeln('$berkas,"$judul",GAGAL,0,'
            '"${p.substring(0, p.length > 150 ? 150 : p.length)}"');
        gagal++;
      }
    }

    /// Langkah yang HARUS menemukan sesuatu di layar. Bila tidak ketemu, dicatat GAGAL —
    /// tidak dilewati diam-diam. "12 berhasil, 0 gagal" terlihat sama sehatnya dengan 14
    /// kecuali ada yang menghitung.
    Future<bool> ketuk(Finder f, String kenapa, {int detik = 20}) async {
      if (f.evaluate().isEmpty) {
        catatan.writeln(',"$kenapa",GAGAL,0,"kontrol tidak ditemukan di layar"');
        gagal++;
        return false;
      }
      await tester.tap(f.first, warnIfMissed: false);
      await _tenang(tester, detik: detik);
      return true;
    }

    Future<void> buka(Widget w) async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      // ignore: unawaited_futures
      nav.push(MaterialPageRoute<void>(builder: (_) => w));
      await _tenang(tester, detik: 25);
    }

    Future<void> tutup() async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (nav.canPop()) nav.pop();
      await _tenang(tester, detik: 6);
    }

    // ---------------------------------------------------------------- 01 beranda
    await potret('01-beranda', 'Beranda Sales — landing sesudah masuk');

    // ---------------------------------------------------------------- 02-03 SPJ
    await buka(const SpjScreen());
    await potret('02-spj-daftar', 'Daftar Surat Perintah Sales Jalan (SPJ)');
    final barisSpj = find.textContaining(RegExp(r'^SPJ-\d+-\d+$'));
    if (await ketuk(
        find.ancestor(of: barisSpj.last, matching: find.byType(InkWell)),
        'Buka rincian SPJ')) {
      await potret('03-spj-rincian', 'Rincian SPJ: barang dibawa, nota, dan tombol aksi');
    }
    await tutup();

    // ---------------------------------------------------------------- 04-06 sesi
    await buka(const NotaSalesScreen());
    await potret('04-sesi-daftar', 'Daftar sesi keliling (berjalan dan sudah selesai)');

    // Sesi yang MASIH BERJALAN: tombol aksinya hanya ada di sini.
    //
    // textContaining, BUKAN find.text: judul barisnya satu Text utuh berisi
    // "NSS-1-000005 · 1. MUCHLIS", sehingga kecocokan persis tidak pernah kena. Ini
    // memang sempat terjadi — dua langkah tercatat GAGAL "kontrol tidak ditemukan",
    // dan itu benar: yang salah pencarinya, bukan layarnya.
    final sesiAktif = find.textContaining('NSS-1-000005');
    if (await ketuk(
        find.ancestor(of: sesiAktif, matching: find.byType(ListTile)),
        'Buka sesi yang masih berjalan')) {
      await potret('05-sesi-berjalan',
          'Sesi BERJALAN — tombol Jual Tunai / Catat Biaya / Kulakan / Setoran / Kembali');
    }
    await tutup();

    await buka(const NotaSalesScreen());
    final sesiTutup = find.textContaining('NSS-1-000004');
    if (await ketuk(
        find.ancestor(of: sesiTutup, matching: find.byType(ListTile)),
        'Buka sesi yang sudah ditutup')) {
      await potret('06-sesi-selesai', 'Sesi SELESAI — rekap kas, biaya, setoran, selisih');
    }
    await tutup();

    // ---------------------------------------------------------------- 07-09 pesanan
    await buka(const PenjualanSalesScreen());
    await potret('07-pesanan-daftar', 'Daftar pesanan pedagang (Sales Order)');
    final barisSo = find.textContaining(RegExp(r'^SO-\d+-\d+$'));
    if (await ketuk(
        find.ancestor(of: barisSo.first, matching: find.byType(InkWell)),
        'Buka rincian pesanan')) {
      await potret('08-pesanan-rincian', 'Rincian pesanan: item, harga, status');
    }
    await tutup();

    await buka(const PenjualanSalesScreen());
    if (await ketuk(find.text('Order Baru'), 'Buka formulir pesanan baru')) {
      await potret('09-pesanan-baru', 'Formulir pesanan baru — dipakai saat stok kosong');
    }
    await tutup();

    // ---------------------------------------------------------------- 10-11 stok
    await buka(const PersediaanScreen());
    await potret('10-persediaan', 'Persediaan — cek stok sebelum menawarkan barang');
    final barisProduk = find.textContaining(RegExp(r'^\d{6}$'));
    if (await ketuk(
        find.ancestor(of: barisProduk.first, matching: find.byType(InkWell)),
        'Buka kartu stok satu produk')) {
      await potret('11-kartu-stok', 'Kartu stok: riwayat masuk/keluar satu barang');
    }
    await tutup();

    // ---------------------------------------------------------------- 12 customer
    await buka(const MasterCustomerScreen());
    await potret('12-master-customer', 'Data pelanggan — dibuka sales untuk cek alamat & wilayah');
    await tutup();

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}/hasil-tangkap-sales.csv')
        .writeAsString(catatan.toString(), flush: true);
    // ignore: avoid_print
    print('TANGKAP SALES SELESAI: $sukses berhasil, $gagal gagal -> ${dir.path}');
    final bergalat = catatan
        .toString()
        .split('\n')
        .where((b) => b.contains(',GALAT-LAYAR,') || b.contains(',GAGAL,'))
        .toList();
    if (bergalat.isNotEmpty) {
      // ignore: avoid_print
      print('PERLU DIPERIKSA (${bergalat.length}):\n${bergalat.join('\n')}');
    }
  });
}

Future<void> _tenang(WidgetTester tester, {required int detik}) async {
  final batas = DateTime.now().add(Duration(seconds: detik));
  while (DateTime.now().isBefore(batas)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 800));
      return;
    }
  }
}

Future<void> _tunggu(WidgetTester tester, bool Function() syarat,
    {required int detik, required String alasan}) async {
  final batas = DateTime.now().add(Duration(seconds: detik));
  while (DateTime.now().isBefore(batas)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (syarat()) return;
  }
  fail(alasan);
}

String? _galatDiLayar(WidgetTester tester) {
  for (final penanda in ['Coba Lagi', 'Detail Error']) {
    if (find.text(penanda).evaluate().isEmpty) continue;
    for (final e in find.byType(Text).evaluate()) {
      final t = (e.widget as Text).data ?? '';
      if (t.length > 25 &&
          (t.contains('Data belum berubah') ||
              t.contains('gagal') ||
              t.contains('Gagal') ||
              t.contains('tidak dapat') ||
              t.contains('tidak diizinkan') ||
              t.contains('Tidak diketahui') ||
              t.contains('tidak diketahui'))) {
        return t.replaceAll('\n', ' ');
      }
    }
    return 'layar menampilkan keadaan galat ($penanda)';
  }
  return null;
}

Future<int> _potret(WidgetTester tester, String nama) async {
  await tester.pump(const Duration(milliseconds: 500));
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer $nama tidak ada');
  final image = await layer.toImage(
    // ignore: deprecated_member_use
    tester.binding.renderView.paintBounds,
    pixelRatio: 1,
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $nama gagal');
  final dir = Directory(_outputDir);
  await dir.create(recursive: true);
  final f = File('${dir.path}/$nama.png');
  await f.writeAsBytes(data.buffer.asUint8List(), flush: true);
  final bita = f.lengthSync();
  if (bita < 5000) throw StateError('PNG $nama hanya $bita bita (layar kosong?)');
  return bita;
}
