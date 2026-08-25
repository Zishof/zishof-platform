import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Verifikator kata sandi LOKAL untuk membuka kunci sesi saat server tidak
/// terjangkau.
///
/// <h3>Kenapa ada</h3>
/// Token perangkat berlaku 30 hari di server, tetapi sesi bisa terkunci lebih
/// dulu karena aplikasi lama tidak dipakai. Tanpa cara memeriksa kata sandi
/// secara lokal, membuka kunci WAJIB menghubungi server -- dan justru pada saat
/// server sedang mati itulah kasir paling butuh masuk. Verifikator ini menyimpan
/// **bukti kata sandi**, bukan kata sandinya, supaya kunci tetap dapat dibuka
/// tanpa jaringan.
///
/// <h3>Yang disimpan (dan yang TIDAK)</h3>
/// Yang disimpan: nama pengguna, garam acak 16 bita, jumlah iterasi, dan hasil
/// PBKDF2-HMAC-SHA256 sepanjang 32 bita. Kata sandi asli **tidak pernah**
/// disimpan, tidak juga bentuk yang dapat dikembalikan menjadi kata sandi.
/// Perbandingannya memakai waktu tetap ([_samaWaktuTetap]) supaya lama proses
/// tidak membocorkan seberapa banyak bita yang sudah cocok.
///
/// <h3>Batas yang jujur</h3>
/// Siapa pun yang memegang berkas preferensi perangkat dapat mencoba menebak
/// kata sandi secara luring. Iterasi PBKDF2 memperlambatnya, tetapi kata sandi
/// pendek tetap dapat ditebak. Karena itu:
///
/// * verifikator hanya dibuat SESUDAH login daring berhasil -- akun yang belum
///   pernah masuk di perangkat ini tidak akan pernah bisa masuk luring;
/// * [terakhirDaring] dicatat supaya pemanggil dapat menolak buka kunci luring
///   yang sudah terlalu lama tidak diverifikasi ke server;
/// * verifikator DIHAPUS saat keluar akun atau saat server menolak token.
///
/// Perlu diingat juga bahwa token perangkat sendiri sudah tersimpan apa adanya
/// di preferensi yang sama, jadi berkas itu memang sudah harus diperlakukan
/// sebagai rahasia perangkat -- verifikator ini tidak mengubah kelas rahasianya.
class VerifikatorSandiLokal {
  VerifikatorSandiLokal._();

  static final VerifikatorSandiLokal instance = VerifikatorSandiLokal._();

  /// Iterasi PBKDF2. Cukup tinggi untuk memperlambat tebakan luring, dan tetap
  /// wajar dijalankan sekali per buka kunci di perangkat kasir yang lemah.
  /// Dijalankan di isolate terpisah ([compute]) supaya layar tidak membeku.
  static const int iterasiBawaan = 100000;

  /// Bukti lokal tidak boleh hidup lebih lama daripada token perangkat yang
  /// diterbitkan server. Setelah batas ini, perangkat wajib terhubung kembali
  /// agar status akun, perubahan sandi, dan pencabutan akses diperiksa ulang.
  static const Duration batasLuringBawaan = Duration(days: 30);

  static const int _panjangGaram = 16;
  static const int _panjangKunci = 32;

  static const _kUsername = 'auth_luring_username';
  static const _kGaram = 'auth_luring_garam';
  static const _kIterasi = 'auth_luring_iterasi';
  static const _kHash = 'auth_luring_hash';
  static const _kDibuat = 'auth_luring_dibuat_pada';
  static const _kDaring = 'auth_luring_daring_terakhir';

  /// Simpan bukti kata sandi untuk [username]. Dipanggil HANYA sesudah server
  /// benar-benar menerima kata sandi itu, sehingga bukti lokal tidak pernah
  /// lebih longgar daripada keputusan server.
  Future<void> simpan(String username, String password) async {
    final garam = _garamAcak();
    final hash = await compute(_hitungPbkdf2, <String, dynamic>{
      'sandi': password,
      'garam': garam,
      'iterasi': iterasiBawaan,
      'panjang': _panjangKunci,
    });
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kUsername, username.trim());
    await sp.setString(_kGaram, base64Encode(garam));
    await sp.setInt(_kIterasi, iterasiBawaan);
    await sp.setString(_kHash, base64Encode(hash));
    await sp.setInt(_kDibuat, DateTime.now().millisecondsSinceEpoch);
    await sp.setInt(_kDaring, DateTime.now().millisecondsSinceEpoch);
  }

  /// Catat bahwa server baru saja menerima identitas ini (login/perpanjangan
  /// token). Dipakai pemanggil untuk membatasi umur mode luring.
  Future<void> catatVerifikasiDaring() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kDaring, DateTime.now().millisecondsSinceEpoch);
  }

  /// Nama pengguna yang buktinya tersimpan; null bila belum ada.
  Future<String?> usernameTersimpan() async {
    final sp = await SharedPreferences.getInstance();
    final nama = sp.getString(_kUsername);
    if (nama == null || nama.trim().isEmpty) return null;
    if (sp.getString(_kHash) == null || sp.getString(_kGaram) == null) {
      return null;
    }
    return nama;
  }

  Future<bool> tersedia() async => (await usernameTersimpan()) != null;

  /// Kapan terakhir kali identitas ini diterima server; null bila belum pernah.
  Future<DateTime?> terakhirDaring() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_kDaring);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Apakah bukti masih cukup baru untuk dipakai membuka kunci tanpa server.
  ///
  /// Timestamp masa depan ditolak. Selain menjaga clock rollback, ini membuat
  /// data preferensi yang rusak tidak dapat memperpanjang akses luring.
  Future<bool> bolehDipakaiLuring({
    DateTime? sekarang,
    Duration batas = batasLuringBawaan,
  }) async {
    if (batas <= Duration.zero) return false;
    final daring = await terakhirDaring();
    if (daring == null) return false;
    final umur = (sekarang ?? DateTime.now()).difference(daring);
    if (umur.isNegative) return false;
    return umur <= batas;
  }

  /// Benar bila [username] + [password] cocok dengan bukti tersimpan.
  ///
  /// Mengembalikan false -- bukan melempar -- bila belum ada bukti sama sekali;
  /// pemanggil membedakan keduanya lewat [tersedia] supaya dapat menjelaskan
  /// "belum pernah masuk di perangkat ini" alih-alih "kata sandi salah".
  Future<bool> cocok(String username, String password) async {
    final sp = await SharedPreferences.getInstance();
    final namaTersimpan = sp.getString(_kUsername);
    final garamB64 = sp.getString(_kGaram);
    final hashB64 = sp.getString(_kHash);
    final iterasi = sp.getInt(_kIterasi) ?? iterasiBawaan;
    if (namaTersimpan == null || garamB64 == null || hashB64 == null) {
      return false;
    }
    if (namaTersimpan.trim().toLowerCase() != username.trim().toLowerCase()) {
      return false;
    }
    final hitung = await compute(_hitungPbkdf2, <String, dynamic>{
      'sandi': password,
      'garam': base64Decode(garamB64),
      'iterasi': iterasi,
      'panjang': _panjangKunci,
    });
    return _samaWaktuTetap(hitung, base64Decode(hashB64));
  }

  /// Buang seluruh bukti -- dipanggil saat keluar akun dan saat server menolak
  /// token (identitasnya tidak lagi sah, jadi jalan luringnya pun harus tutup).
  Future<void> hapus() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kUsername);
    await sp.remove(_kGaram);
    await sp.remove(_kIterasi);
    await sp.remove(_kHash);
    await sp.remove(_kDibuat);
    await sp.remove(_kDaring);
  }

  Uint8List _garamAcak() {
    final acak = Random.secure();
    final garam = Uint8List(_panjangGaram);
    for (var i = 0; i < garam.length; i++) {
      garam[i] = acak.nextInt(256);
    }
    return garam;
  }

  /// Perbandingan waktu tetap: selalu menyusuri seluruh bita, tidak berhenti
  /// pada ketidakcocokan pertama.
  static bool _samaWaktuTetap(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var beda = 0;
    for (var i = 0; i < a.length; i++) {
      beda |= a[i] ^ b[i];
    }
    return beda == 0;
  }
}

/// PBKDF2-HMAC-SHA256 (RFC 8018). Ditulis sendiri, bukan menambah dependensi
/// baru: `crypto` sudah dipakai paket lain di repo ini dan sudah menyediakan
/// HMAC-SHA256 yang menjadi satu-satunya bahan yang dibutuhkan.
///
/// Berupa fungsi tingkat atas karena [compute] menjalankannya di isolate lain,
/// yang hanya menerima fungsi tanpa tangkapan (top-level/static).
Uint8List _hitungPbkdf2(Map<String, dynamic> arg) {
  final sandi = utf8.encode(arg['sandi'] as String);
  final garam = arg['garam'] as List<int>;
  final iterasi = arg['iterasi'] as int;
  final panjang = arg['panjang'] as int;

  final hmac = Hmac(sha256, sandi);
  final keluaran = <int>[];
  var blok = 1;
  while (keluaran.length < panjang) {
    // U1 = HMAC(sandi, garam || INT_BE32(blok))
    final masukan = <int>[
      ...garam,
      (blok >> 24) & 0xff,
      (blok >> 16) & 0xff,
      (blok >> 8) & 0xff,
      blok & 0xff,
    ];
    var u = hmac.convert(masukan).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterasi; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    keluaran.addAll(t);
    blok++;
  }
  return Uint8List.fromList(keluaran.sublist(0, panjang));
}
