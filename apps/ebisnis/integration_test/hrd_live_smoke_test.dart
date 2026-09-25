import 'package:core_db/core_db.dart';
import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('modul HRD membaca tabel ZK melalui server ABChicken',
      (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const contextPath = String.fromEnvironment('POS_TEST_CONTEXT');
    expect(username, isNotEmpty, reason: 'POS_TEST_USERNAME wajib diisi.');
    expect(password, isNotEmpty, reason: 'POS_TEST_PASSWORD wajib diisi.');
    expect(host, isNotEmpty, reason: 'POS_TEST_HOST wajib diisi.');

    CoreDb.configureStorage('abchicken_hrd_live_smoke');
    await CoreDb.instance.db;
    addTearDown(() => CoreDb.instance.tutup());
    await ServerConfig.instance
        .simpan(host: host, contextPath: contextPath, https: true);

    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-HRD-ABChicken-POS-Desktop',
    });
    expect(login['token'], isNotNull,
        reason: 'Login tidak menghasilkan token.');
    await ApiClient.instance.simpanToken(login['token'] as String);

    final master = await ApiClient.instance.aksi('hrd_master_daftar', const {});
    expect(master['status'], anyOf('00', 'success'),
        reason: 'Master organisasi dan shift ZK tidak dapat dibaca.');
    final jumlahMaster = <String, int>{};
    for (final key in const [
      'unitKerja',
      'golongan',
      'jabatan',
      'tipePegawai',
      'departemen',
      'levelJabatan',
      'jenisCuti',
      'jenisShift',
      'waktuShift',
      'liburNasional',
      'liburRutin',
    ]) {
      expect(master[key], isA<List>(), reason: 'Master $key tidak valid.');
      jumlahMaster[key] = (master[key] as List).length;
    }
    expect(jumlahMaster.values.fold<int>(0, (a, b) => a + b), greaterThan(0),
        reason: 'Seluruh master HRD ZK masih kosong.');
    // Dicetak sebagai bukti UAT terukur tanpa menampilkan isi data pegawai.
    // ignore: avoid_print
    print('Jumlah master HRD live: $jumlahMaster');

    final pegawai = await ApiClient.instance
        .aksi('hrd_pegawai_daftar', const {'page_size': 500});
    final rows =
        ((pegawai['data'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      final kandidat = await ApiClient.instance
          .aksi('hrd_pegawai_tenant_kandidat', const {'page_size': 200});
      expect(kandidat['status'], anyOf('00', 'success'),
          reason: 'Endpoint impor pegawai ZK belum tersedia.');
      expect(kandidat['data'], isA<List>(),
          reason: 'Daftar kandidat pegawai ZK tidak valid.');
      return;
    }
    final pegawaiId = (rows.first['id'] as num).toInt();

    final reads = <(String, Map<String, dynamic>)>[
      ('hrd_pegawai_detail', {'pegawai_id': pegawaiId}),
      ('hrd_riwayat_pegawai', {'pegawai_id': pegawaiId}),
      ('hrd_jenis_cuti_daftar', const {}),
      ('hrd_cuti_daftar', const {'page_size': 100}),
      ('hrd_kehadiran_daftar', const {'page_size': 100}),
      ('hrd_kehadiran_ringkasan', const {'page_size': 100}),
      ('hrd_payroll_daftar', const {'page_size': 100}),
      ('hrd_pengajuan_jenis', const {}),
      ('hrd_pengajuan_daftar', const {'page_size': 100}),
      ('hrd_gaji_pokok_daftar', {'pegawai_id': pegawaiId}),
      ('hrd_kenaikan_gaji_daftar', const {'page_size': 100}),
      ('hrd_kinerja_daftar', const {'page_size': 100}),
    ];
    for (final request in reads) {
      final result = await ApiClient.instance.aksi(request.$1, request.$2);
      expect(result['status'], anyOf('00', 'success'),
          reason: '${request.$1} tidak mengembalikan status berhasil.');
    }
  });
}
