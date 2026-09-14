import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/main_inventory_sales.dart' as app;
import 'package:ebisnis/screens/inventory_sales/harga_screen.dart';
import 'package:ebisnis/screens/inventory_sales/hutang_supplier_screen.dart';
import 'package:ebisnis/screens/inventory_sales/kas_jurnal_screen.dart';
import 'package:ebisnis/screens/inventory_sales/laba_rugi_screen.dart';
import 'package:ebisnis/screens/inventory_sales/laporan_opname_screen.dart';
import 'package:ebisnis/screens/inventory_sales/master_customer_screen.dart';
import 'package:ebisnis/screens/inventory_sales/master_sales_screen.dart';
import 'package:ebisnis/screens/inventory_sales/master_supplier_screen.dart';
import 'package:ebisnis/screens/inventory_sales/persediaan_screen.dart';
import 'package:ebisnis/screens/inventory_sales/piutang_screen.dart';
import 'package:ebisnis/screens/inventory_sales/spj_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// UAT TANGKAPAN LAYAR — PERAN PEMILIK & MANAJEMEN (digabung menjadi satu peran).
///
/// PEMILIK DAN MANAJEMEN SENGAJA SATU PERAN, sesuai permintaan pemilik usaha. Pada basis
/// data tenant peran itu bernama OWNER ("Pemilik", seluruh area termasuk menyetujui);
/// PEMILIK_SALES_INVENTORY memiliki izin yang persis sama, sehingga tidak ada layar yang
/// terlewat karena memilih salah satunya.
///
/// MASUK SEBAGAI PEMILIK, BUKAN SEBAGAI SALES. Bedanya bukan kosmetik: layar sales
/// menyaring datanya menurut profil sales yang sedang masuk, sedangkan pemilik melihat
/// seluruh toko. Menu sidebar-nya pun berbeda — pemilik punya Master, Harga, Kas/Jurnal,
/// dan Laba Rugi yang tidak dimiliki sales.
///
/// DUA LAYAR DIPOTRET DUA KALI, dan itu disengaja:
///   - Master Sales: daftar DAN formulirnya. Bagian "Target & Akun" pada formulir itulah
///     yang sampai v25 mengumpulkan angka lalu membuangnya diam-diam.
///   - Laba Rugi: per produk DAN per sales. Pengelompokan per sales adalah yang selama ini
///     jatuh ke satu baris "(tanpa sales)".
///
/// PERIODE DIPILIH, TIDAK DIBIARKAN BAWAAN. Layar Laba Rugi berawal pada bulan berjalan,
/// dan faktur terakhir hasil migrasi berumur berbulan-bulan — potret bawaannya akan
/// memperlihatkan NOL dan mengajari pembaca manual hal yang keliru.
///
/// Jalankan (Tomcat UAT 18080 dan klaster 55600 harus hidup):
///   flutter test integration_test/uat_pemilik_manual_test.dart -d windows ^
///     --dart-define=EBISNIS_VARIANT=inventory_sales ^
///     --dart-define=POS_TEST_USERNAME=muklis --dart-define=POS_TEST_PASSWORD=muklis123 ^
///     --dart-define=POS_TEST_HOST=127.0.0.1:18080 --dart-define=POS_TEST_CONTEXT=ais ^
///     --dart-define=POS_TEST_HTTPS=false ^
///     "--dart-define=POS_TEST_OUTPUT_DIR=C:/opt/uat-inventory/layar-pemilik"
const _outputDir = String.fromEnvironment('POS_TEST_OUTPUT_DIR',
    defaultValue: r'C:\opt\uat-inventory\layar-pemilik');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT Pemilik: tangkap seluruh layar peran pemilik & manajemen',
      (tester) async {
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
          'labelPerangkat': 'UAT-Pemilik',
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
    /// tidak dilewati diam-diam. "14 berhasil, 0 gagal" terlihat sama sehatnya dengan 17
    /// kecuali ada yang menghitung.
    Future<bool> ketuk(Finder f, String kenapa, {int detik = 25}) async {
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
      await _tenang(tester, detik: 30);
    }

    Future<void> tutup() async {
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      if (nav.canPop()) nav.pop();
      await _tenang(tester, detik: 6);
    }

    // ---------------------------------------------------------------- 01 beranda
    await potret('01-beranda', 'Beranda Pemilik — modul yang benar-benar diizinkan perannya');

    // ---------------------------------------------------------------- 02-05 data induk
    await buka(const MasterSupplierScreen());
    await potret('02-master-supplier', 'Data Supplier — sumber barang dagangan');
    await tutup();

    await buka(const MasterCustomerScreen());
    await potret('03-master-customer', 'Data Pelanggan / Pedagang');
    // Rinci pelanggan 00489: satu dari sebelas pelanggan yang medan "Alamat" pada blok
    // rekening formulir lamanya (CUSTOMER.DBF ALMBANK, v27) terisi. Layar rinci ini juga
    // tempat Atas Nama dan Wilayah yang sampai v27 ditampilkan KOSONG walau datanya ada.
    //
    // .last, bukan .first: find.text juga cocok dengan isi kotak pencarian (EditableText),
    // dan kotak itu berada lebih dulu di pohon widget daripada baris daftarnya.
    final kotakCari = find.byType(TextField);
    if (kotakCari.evaluate().isNotEmpty) {
      await tester.enterText(kotakCari.first, '00489');
      await _tenang(tester, detik: 20);
    }
    if (await ketuk(
        find.ancestor(of: find.text('00489').last, matching: find.byType(InkWell)),
        'Buka rinci pelanggan 00489')) {
      await potret('03b-rinci-customer',
          'Rinci Pelanggan — Atas Nama, Wilayah, dan Alamat Bank (v27)');
    }
    await tutup();

    await buka(const MasterSalesScreen());
    await potret('04-master-sales', 'Data Sales — target, limit penagihan, dan akun login');
    if (await ketuk(find.text('Tambah Sales'), 'Buka formulir Master Sales')) {
      await potret('05-master-sales-form',
          'Formulir Sales — bagian "Target & Akun" yang tersimpan sejak v25');
    }
    await tutup();

    // ---------------------------------------------------------------- 06-07 harga
    await buka(const HargaScreen());
    await potret('06-harga-analisis', 'Analisis Harga — margin per barang, termasuk yang negatif');
    if (await ketuk(find.text('Harga Beli Supplier'), 'Pindah ke tab Harga Beli')) {
      await potret('07-harga-beli', 'Harga Beli per Supplier');
    }
    await tutup();

    // ---------------------------------------------------------------- 08-10 barang
    await buka(const PersediaanScreen());
    await potret('08-persediaan', 'Persediaan — saldo, masuk, keluar, dan penyesuaian opname');
    final barisProduk = find.textContaining(RegExp(r'^\d{6}$'));
    if (await ketuk(
        find.ancestor(of: barisProduk.first, matching: find.byType(InkWell)),
        'Buka kartu stok satu produk')) {
      await potret('09-kartu-stok', 'Kartu stok satu barang');
    }
    await tutup();

    await buka(const LaporanOpnameScreen());
    await potret('10-opname', 'Laporan Opname — selisih fisik terhadap sistem');
    await tutup();

    // ---------------------------------------------------------------- 11-13 pembelian
    await buka(const HutangSupplierScreen());
    // Tab Hutang TIDAK punya pintasan periode, dan itu benar: outstanding adalah keadaan
    // hari ini, bukan rentang. Pintasan "Semua data" hidup di tab Laporan Pembelian, dan
    // mencarinya di sini pernah tercatat GAGAL "kontrol tidak ditemukan" -- yang salah
    // langkahnya, bukan layarnya.
    await potret('11-hutang-supplier', 'Hutang Dagang — outstanding per supplier');
    if (await ketuk(find.text('Laporan Pembelian'), 'Pindah ke tab Laporan Pembelian')) {
      if (await ketuk(find.text('Semua data'), 'Perluas periode laporan pembelian',
          detik: 60)) {
        await potret('12-laporan-pembelian',
            'Laporan Pembelian — ringkasannya dihitung atas SELURUH rentang');
      }
    }
    if (await ketuk(find.text('Aging'), 'Pindah ke tab Aging hutang')) {
      await potret('13-aging-hutang', 'Umur Hutang — 1-30, 31-60, 61-90, di atas 90 hari');
    }
    await tutup();

    // ---------------------------------------------------------------- 14-15 piutang
    await buka(const PiutangScreen());
    await potret('14-piutang', 'Piutang Dagang — sisa yang sudah dikurangi pembayaran');
    if (await ketuk(find.text('Aging per Sales'), 'Pindah ke tab Aging per Sales')) {
      await potret('15-aging-piutang-sales', 'Umur Piutang per Sales');
    }
    await tutup();

    // ---------------------------------------------------------------- 16 SPJ
    await buka(const SpjScreen());
    await potret('16-spj', 'Surat Perintah Sales Jalan — penugasan sales oleh pemilik');
    await tutup();

    // ---------------------------------------------------------------- 17 kas/jurnal
    await buka(const KasJurnalScreen());
    await potret('17-kas-jurnal', 'Kas / Jurnal');
    if (await ketuk(find.text('Master Akun (COA)'), 'Pindah ke tab Master Akun')) {
      await potret('18-master-akun', 'Master Perkiraan (COA)');
    }
    await tutup();

    // ---------------------------------------------------------------- 19-20 laba rugi
    //
    // Periode DIPILIH lebih dulu. Bawaannya bulan berjalan, dan faktur terakhir hasil
    // migrasi bertanggal 2026-08-04 — potret bawaannya akan memperlihatkan nol dan
    // mengajari pembaca manual bahwa usahanya tidak menjual apa pun.
    await buka(const LabaRugiScreen());
    if (await ketuk(find.text('Semua data'), 'Perluas periode laba rugi', detik: 60)) {
      await potret('19-laba-rugi',
          'Laba Rugi — laba kotor dan margin sebenarnya (bukan lagi 100%)');
    }
    await tutup();

    final dir = Directory(_outputDir);
    await dir.create(recursive: true);
    await File('${dir.path}/hasil-tangkap-pemilik.csv')
        .writeAsString(catatan.toString(), flush: true);
    // ignore: avoid_print
    print('TANGKAP PEMILIK SELESAI: $sukses berhasil, $gagal gagal -> ${dir.path}');
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
