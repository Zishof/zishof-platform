import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';

/// Keadaan sesi member yang sedang masuk.
///
/// Nilai konfigurasi di bawah berasal dari aksi `kantin_info` -- sumbernya
/// Jenis Anggota Koperasi + Konfigurasi server, persis seperti yang dibaca
/// halaman JSP. Nama istilah (label) memang dapat berbeda per institusi,
/// jadi JANGAN menulis "Saldo"/"Cashback" secara langsung di layar.
class Sesi {
  Sesi._();
  static final Sesi instance = Sesi._();

  String? token;
  String? username;

  int idMember = 0;
  String nama = '';
  String kode = '';

  int saldo = 0;
  int sisaCashback = 0;

  /// Konfigurasi server (Konfigurasi.*).
  bool aktifkanTopup = false;
  bool aktifkanBayarQr = false;
  bool aktifkanPilihanMeja = false;

  /// Konfigurasi Jenis Anggota.
  int? idJenisAnggota;
  int? idTipeAnggota;
  String labelSaldo = 'Saldo';
  String labelCashback = 'Cashback';
  bool tampilkanSaldo = true;
  bool tampilkanCashback = false;

  /// Saldo yang WAJIB tersisa setelah transaksi (saldo mengendap).
  int minimalSaldo = 0;

  bool get sudahMasuk => (token ?? '').isNotEmpty;

  void terapkanInfo(Map<String, dynamic> d) {
    idMember = _int(d['id_member']);
    nama = '${d['nama'] ?? ''}';
    kode = '${d['kode'] ?? ''}';
    saldo = _int(d['saldo']);
    sisaCashback = _int(d['sisa_cashback']);
    aktifkanTopup = d['aktifkan_topup'] == true;
    aktifkanBayarQr = d['aktifkan_bayar_qr'] == true;
    aktifkanPilihanMeja = d['aktifkan_pilihan_meja'] == true;
    idJenisAnggota = d['id_jenis_anggota'] == null ? null : _int(d['id_jenis_anggota']);
    idTipeAnggota = d['id_tipe_anggota'] == null ? null : _int(d['id_tipe_anggota']);
    labelSaldo = '${d['label_saldo'] ?? 'Saldo'}';
    labelCashback = '${d['label_cashback'] ?? 'Cashback'}';
    tampilkanSaldo = d['tampilkan_saldo'] != false;
    tampilkanCashback = d['tampilkan_cashback'] == true;
    minimalSaldo = _int(d['minimal_saldo']);
  }

  static int _int(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('$v'.split('.').first) ?? 0;
  }

  Future<void> muatToken() async {
    final sp = await SharedPreferences.getInstance();
    token = sp.getString(AppConfig.kToken);
    username = sp.getString(AppConfig.kUsername);
  }

  Future<void> simpanToken(String nilai, String user) async {
    token = nilai;
    username = user;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(AppConfig.kToken, nilai);
    await sp.setString(AppConfig.kUsername, user);
  }

  Future<void> keluar() async {
    token = null;
    idMember = 0;
    nama = '';
    kode = '';
    saldo = 0;
    sisaCashback = 0;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(AppConfig.kToken);
  }
}
