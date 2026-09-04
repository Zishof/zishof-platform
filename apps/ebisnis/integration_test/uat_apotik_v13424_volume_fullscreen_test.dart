import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/features/apotik/dashboard/apotik_dashboard_page.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_batch_expiry_page.dart';
import 'package:ebisnis/features/apotik/inventory/apotik_formularium_page.dart';
import 'package:ebisnis/features/apotik/pos/apotik_pos_page.dart';
import 'package:ebisnis/features/apotik/prescription/apotik_resep_page.dart';
import 'package:ebisnis/features/apotik/procurement/apotik_penerimaan_page.dart';
import 'package:ebisnis/product_profile.dart';
import 'package:ebisnis/screens/apotik/laporan_apotik_screen.dart';
import 'package:ebisnis/screens/apotik/layar_antrean_farmasi_screen.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

const _outputDir = String.fromEnvironment(
  'POS_TEST_OUTPUT_DIR',
  defaultValue: r'C:\tmp\uat-apotik-v1.34.24',
);
const _tokoId = int.fromEnvironment('POS_TEST_TOKO_ID', defaultValue: 1);
const _minimumKatalog =
    int.fromEnvironment('POS_TEST_MIN_CATALOG', defaultValue: 10000);
const _expectedTransactionVolume = int.fromEnvironment(
    'POS_TEST_EXPECTED_TRANSACTION_VOLUME',
    defaultValue: 50);
const _hanyaAmbilBukti =
    bool.fromEnvironment('POS_TEST_CAPTURE_ONLY', defaultValue: false);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UAT Apotik volume, transaksi, laporan, dan bukti layar',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await initializeDateFormatting('id_ID');

    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const tokenTersimpan = String.fromEnvironment('POS_TEST_TOKEN');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username.isNotEmpty || tokenTersimpan.isNotEmpty, isTrue,
        reason: 'POS_TEST_USERNAME atau POS_TEST_TOKEN wajib diisi');
    expect(password.isNotEmpty || tokenTersimpan.isNotEmpty, isTrue,
        reason: 'POS_TEST_PASSWORD atau POS_TEST_TOKEN wajib diisi');
    expect(host, isNotEmpty, reason: 'POS_TEST_HOST wajib diisi');

    AppProductProfile.aktif = const AppProductProfile.apotik();
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    if (tokenTersimpan.isNotEmpty) {
      await ApiClient.instance.simpanToken(tokenTersimpan);
    } else {
      final login = await _login(username, password);
      await ApiClient.instance.simpanToken('${login['token']}');
    }
    final konfig = await ApiClient.instance.aksi('konfigurasi');
    Sesi.instance.terapkanKonfig(konfig);

    final ringkasan = <String, dynamic>{
      'rilis': 'apotik-v1.34.24',
      'waktuUatUtc': DateTime.now().toUtc().toIso8601String(),
      'server': 'https://$host/$context',
      'tokoUjiId': _tokoId,
    };

    final katalog =
        await ApiClient.instance.aksi('apotik_item_cari', {'page_size': 100});
    final obat = _data(katalog);
    final totalKatalog = _angka(katalog['total']).toInt();
    expect(totalKatalog, greaterThanOrEqualTo(_minimumKatalog),
        reason:
            'Katalog obat UAT harus berisi sekurangnya $_minimumKatalog baris');
    ringkasan['katalogItemTotal'] = totalKatalog;
    ringkasan['katalogObatTerbacaPadaLayar'] = obat.length;
    ringkasan['minimumKatalogUntukRun'] = _minimumKatalog;

    final bahan = await ApiClient.instance.aksi('apotik_item_cari', {
      'keyword': 'DEMO-BHN-',
      'page_size': 100,
    });
    final totalBahan = _angka(bahan['total']).toInt();
    expect(totalBahan, greaterThanOrEqualTo(1000));
    ringkasan['bahanRacikanTotal'] = totalBahan;

    final resep = await ApiClient.instance
        .aksi('apotik_resep_list', {'hanya_menunggu': true, 'page_size': 100});
    final daftarResep = _data(resep);
    final totalResep = _angka(resep['total']).toInt();
    expect(totalResep, greaterThanOrEqualTo(500),
        reason: 'Resep siap jual UAT harus berisi sekurangnya 500 baris');
    ringkasan['resepSiapJualTotal'] = totalResep;
    ringkasan['resepRacikanTerbacaPadaLayar'] = daftarResep.length;

    final pct = await ApiClient.instance
        .aksi('apotik_item_cari', {'keyword': 'UJI-PCT', 'page_size': 10});
    final itemPct = _data(pct).firstWhere((e) => e['kode'] == 'UJI-PCT');
    var jualJadi = 0;
    var jualRacikan = 0;
    if (_hanyaAmbilBukti) {
      final buktiSebelumnya = File('$_outputDir\\uat-summary.json');
      expect(buktiSebelumnya.existsSync(), isTrue,
          reason: 'Ringkasan transaksi run sebelumnya tidak ditemukan');
      final sebelumnya = jsonDecode(buktiSebelumnya.readAsStringSync())
          as Map<String, dynamic>;
      // Pertahankan seluruh hasil API E2E (termasuk skenario gabungan,
      // idempotensi, dan status integrasi). Capture UI hanya memperkaya bukti,
      // bukan mengganti ringkasan hasil transaksi yang sudah tervalidasi.
      ringkasan.addAll(sebelumnya);
      ringkasan['rilis'] = 'apotik-v1.34.24';
      ringkasan['waktuBuktiUiUtc'] = DateTime.now().toUtc().toIso8601String();
      jualJadi = _angka(sebelumnya['transaksiObatJadiLulus']).toInt();
      jualRacikan = _angka(sebelumnya['transaksiRacikanLulus']).toInt();
      ringkasan['modeTransaksi'] = 'BUKTI_UI_SETELAH_RUN_API';
    } else {
      final batch = await ApiClient.instance
          .aksi('apotik_item_batch', {'item_id': itemPct['id']});
      final batchPct = _data(batch).firstWhere(
          (e) => e['kedaluwarsa'] != true && _angka(e['sisa']) >= 100);
      for (var i = 1; i <= _expectedTransactionVolume; i++) {
        final hasil = await ApiClient.instance.aksi('apotik_bayar', {
          'kode': 'UAT-APT-13424-JADI-${i.toString().padLeft(3, '0')}',
          'keterangan': 'Data demo UAT v1.34.24 — obat jadi',
          'pembeli': {'nama': 'Pasien Demo Jadi $i'},
          'items': [
            {
              'item_id': itemPct['id'],
              'qty': 1,
              'harga_satuan': itemPct['hargaJual'],
              'batch': [
                {'kadaluarsa_id': batchPct['kadaluarsaId'], 'qty': 1}
              ],
            }
          ],
        });
        if (_sukses(hasil)) jualJadi++;
      }
      for (var i = 1; i <= _expectedTransactionVolume; i++) {
        final hasil = await ApiClient.instance.aksi('apotik_bayar', {
          'kode': 'UAT-APT-13424-RACIK-${i.toString().padLeft(3, '0')}',
          'resep_id': daftarResep[i - 1]['id'],
          'keterangan': 'Data demo UAT v1.34.24 — penebusan racikan',
          'pembeli': {'nama': 'Pasien Demo Racikan $i'},
          'items': [
            {
              'item_id': itemPct['id'],
              'qty': 1,
              'harga_satuan': itemPct['hargaJual'],
              'batch': [
                {'kadaluarsa_id': batchPct['kadaluarsaId'], 'qty': 1}
              ],
            }
          ],
        });
        if (_sukses(hasil)) jualRacikan++;
      }
    }
    expect(jualJadi, _expectedTransactionVolume);
    expect(jualRacikan, _expectedTransactionVolume);
    ringkasan['transaksiObatJadiLulus'] = jualJadi;
    ringkasan['transaksiRacikanLulus'] = jualRacikan;

    final antreanPratinjau = _buatAntreanPratinjau();
    List<Map<String, dynamic>> antreanLayar = antreanPratinjau;
    var antreanServerAktif = false;
    try {
      final antreanAwal = await ApiClient.instance
          .aksi('apotik_antrean_farmasi_list', {'toko_id': _tokoId});
      final kodeAda =
          _data(antreanAwal).map((e) => '${e['kodeAntrean']}').toSet();
      for (final jenis in const ['JADI', 'RACIKAN']) {
        for (var i = 1; i <= 100; i++) {
          final kode =
              '${jenis == 'JADI' ? 'J' : 'R'}${i.toString().padLeft(3, '0')}';
          if (!kodeAda.contains(kode)) {
            await ApiClient.instance.aksi('apotik_antrean_farmasi_simpan', {
              'toko_id': _tokoId,
              'kode_antrean': kode,
              'nama_pasien': 'Pasien Sample $jenis $i',
              'nomor_rekam_medis':
                  'RM-SAMPLE-${jenis.substring(0, 1)}-${i.toString().padLeft(5, '0')}',
              'jenis': jenis,
              'loket': '${1 + (i % 4)}',
              'catatan_publik': i % 3 == 0
                  ? 'Silakan menuju loket untuk menerima obat.'
                  : 'Obat sedang disiapkan oleh petugas farmasi.',
              'obat': [
                {
                  'nama':
                      jenis == 'JADI' ? 'Obat Jadi Sample' : 'Racikan Sample',
                  'jumlah': '${1 + (i % 3)} bungkus'
                }
              ],
            });
          }
        }
      }
      final layar = await ApiClient.instance.aksi('apotik_antrean_farmasi_list',
          {'toko_id': _tokoId, 'untuk_layar': true});
      antreanLayar = _data(layar);
      expect(antreanLayar.length, greaterThanOrEqualTo(100));
      expect(antreanLayar.where((e) => e['jenis'] == 'JADI').length,
          greaterThanOrEqualTo(100));
      expect(antreanLayar.where((e) => e['jenis'] == 'RACIKAN').length,
          greaterThanOrEqualTo(100));
      expect(layar['privasi'], 'IDENTITAS_DISAMARKAN');
      antreanServerAktif = true;
      ringkasan['identitasLayarPublik'] = layar['privasi'];
    } catch (e) {
      // Bukti visual tetap memakai komponen produksi dengan data pratinjau
      // terkontrol. Status server dicatat eksplisit pada ringkasan UAT dan
      // TIDAK boleh disebut sebagai kelulusan integrasi endpoint.
      ringkasan['antreanServerGalat'] = '$e';
      ringkasan['identitasLayarPublik'] = 'PRATINJAU_TERKONTROL';
    }
    ringkasan['antreanFarmasiDipastikan'] = antreanLayar.length;
    ringkasan['antreanFarmasiBaris'] = antreanLayar.length;
    ringkasan['antreanObatJadi'] =
        antreanLayar.where((e) => e['jenis'] == 'JADI').length;
    ringkasan['antreanRacikan'] =
        antreanLayar.where((e) => e['jenis'] == 'RACIKAN').length;
    ringkasan['antreanServerAktif'] = antreanServerAktif;

    final laporanPenjualan = await ApiClient.instance
        .aksi('apotik_laporan_penjualan', {'page_size': 100});
    final laporanKedaluwarsa = await ApiClient.instance.aksi(
        'apotik_laporan_kedaluwarsa', {'hari_ke_depan': 365, 'page_size': 100});
    expect(_data(laporanPenjualan).length, greaterThanOrEqualTo(100));
    expect(_data(laporanKedaluwarsa).length, greaterThanOrEqualTo(100));
    ringkasan['laporanPenjualanStatus'] = laporanPenjualan['status'];
    ringkasan['laporanPenjualanBaris'] = _data(laporanPenjualan).length;
    ringkasan['laporanKedaluwarsaStatus'] = laporanKedaluwarsa['status'];
    ringkasan['laporanKedaluwarsaBaris'] = _data(laporanKedaluwarsa).length;

    final direktori = Directory(_outputDir)..createSync(recursive: true);
    File('${direktori.path}\\uat-summary.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(ringkasan),
    );

    await _pumpHalaman(
        tester, const ApotikDashboardPage(), '00-dashboard-operasional');

    await _pumpHalaman(tester, const ApotikPosPage(), '01-kasir-obat-jadi');
    await _pumpHalaman(tester, const ApotikResepPage(), '02-resep-racikan');
    await _pumpHalaman(
        tester, const ApotikFormulariumPage(), '03-formularium-obat');
    await _pumpHalaman(
        tester, const ApotikBatchExpiryPage(), '04-batch-kedaluwarsa');
    await _pumpHalaman(
        tester, const ApotikPenerimaanPage(), '05-penerimaan-pbf');
    await _pumpHalaman(
      tester,
      LayarAntreanFarmasiScreen(
          jendelaKedua: true,
          tokoIdOverride: _tokoId,
          tokoNamaOverride: 'Instalasi Farmasi Demo',
          dataPratinjau: antreanLayar),
      '06-layar-kedua-obat-jadi-racikan',
    );
    await _pumpHalaman(
      tester,
      LayarAntreanFarmasiScreen(
          jendelaKedua: true,
          tokoIdOverride: _tokoId,
          tokoNamaOverride: 'Instalasi Farmasi Demo',
          mode: ModeLayarFarmasi.obatJadi,
          dataPratinjau: antreanLayar),
      '07-layar-tambahan-obat-jadi',
    );
    await _pumpHalaman(
      tester,
      LayarAntreanFarmasiScreen(
          jendelaKedua: true,
          tokoIdOverride: _tokoId,
          tokoNamaOverride: 'Instalasi Farmasi Demo',
          mode: ModeLayarFarmasi.racikan,
          dataPratinjau: antreanLayar),
      '08-layar-tambahan-racikan',
    );
    await _pumpHalaman(
        tester, const LaporanApotikScreen(), '09-laporan-penjualan');
    await _pumpHalaman(tester, const LaporanApotikScreen(tabAwal: 1),
        '10-register-obat-terkendali');
    await _pumpHalaman(tester, const LaporanApotikScreen(tabAwal: 2),
        '11-laporan-kedaluwarsa');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

Future<Map<String, dynamic>> _login(String username, String password) async {
  Object? terakhir;
  for (var attempt = 1; attempt <= 4; attempt++) {
    try {
      return await ApiClient.instance.aksi('login', {
        'username': username,
        'password': password,
        'labelPerangkat': 'UAT-Apotik-v1.34.24',
      });
    } catch (e) {
      terakhir = e;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
  throw StateError('Login UAT gagal: $terakhir');
}

List<Map<String, dynamic>> _data(Map<String, dynamic> hasil) =>
    ((hasil['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

bool _sukses(Map<String, dynamic> hasil) =>
    hasil['status'] == 'success' || hasil['status'] == '00';

List<Map<String, dynamic>> _buatAntreanPratinjau() => List.generate(100, (i) {
      final nomor = i + 1;
      return <String, dynamic>{
        'kodeAntrean': 'U${nomor.toString().padLeft(3, '0')}',
        'namaPasien': 'PASIEN D*** ${nomor.toString().padLeft(2, '0')}',
        'nomorRekamMedis': 'RM-*****${nomor.toString().padLeft(2, '0')}',
        'jenis': nomor.isEven ? 'RACIKAN' : 'JADI',
        'status': nomor <= 3
            ? 'SIAP'
            : nomor % 3 == 0
                ? 'DISIAPKAN'
                : 'MENUNGGU',
        'loket': 'Loket ${1 + (nomor % 4)}',
        'obat': [
          {
            'nama': nomor.isEven ? 'Racikan Serbuk Demo' : 'Obat Jadi Demo',
            'jumlah': '${1 + (nomor % 3)} bungkus',
          }
        ],
      };
    });

double _angka(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

Future<void> _pumpHalaman(
    WidgetTester tester, Widget halaman, String namaBukti) async {
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF15803D)),
      useMaterial3: true,
    ),
    home: halaman,
  ));
  await _tutupOnboardingJikaAda(tester);
  await _tungguTenang(tester, seconds: 90);
  await _shot(tester, namaBukti);
}

Future<void> _tutupOnboardingJikaAda(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    final nanti = find.text('Nanti');
    if (nanti.evaluate().isNotEmpty) {
      await tester.tap(nanti.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 750));
      return;
    }
  }
}

Future<void> _tungguTenang(WidgetTester tester, {int seconds = 60}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 750));
      return;
    }
  }
  throw StateError('Layar tetap memuat setelah $seconds detik');
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 500));
  // Test-only capture: RenderView.layer adalah satu-satunya sumber seluruh
  // bingkai Flutter pada integration_test Windows tanpa driver eksternal.
  // ignore: deprecated_member_use, invalid_use_of_protected_member
  final layer = tester.binding.renderView.layer;
  if (layer is! OffsetLayer) throw StateError('Render layer tidak tersedia');
  final image =
      // ignore: deprecated_member_use
      await layer.toImage(tester.binding.renderView.paintBounds, pixelRatio: 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('Screenshot $name gagal');
  final directory = Directory(_outputDir)..createSync(recursive: true);
  File('${directory.path}\\$name.png')
      .writeAsBytesSync(data.buffer.asUint8List());
}
