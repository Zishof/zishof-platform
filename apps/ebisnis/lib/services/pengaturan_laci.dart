import 'package:shared_preferences/shared_preferences.dart';

/// Pengaturan Cash Drawer (Buka Laci) -- gap-closure: sebelumnya `bukaLaciKasir`
/// SELALU menembak printer DEFAULT Windows apa adanya, padahal laci fisik
/// tersambung via kabel RJ11 ke SATU printer thermal tertentu (lihat riset
/// video tutorial cash-drawer: laci tak punya driver sendiri, ia numpang port
/// "cash drawer kick" printer). Kalau toko punya >1 printer atau default-nya
/// bukan printer thermal (mis. "Microsoft Print to PDF"), laci tak pernah
/// terbuka walau perintah ESC/POS-nya sudah benar -- itu penyebab paling
/// umum laporan "Buka Laci tidak berfungsi". Disimpan device-level (bukan
/// per-toko/server) krn ini murni pengaturan fisik mesin ini.
class PengaturanLaci {
  PengaturanLaci._();
  static final PengaturanLaci instance = PengaturanLaci._();

  static const _kNamaPrinter = 'laci_nama_printer';
  static const _kPinAlternatif = 'laci_pin_alternatif';

  /// `null`/kosong = ikut printer default Windows (perilaku lama).
  String? namaPrinter;
  bool pinAlternatif = false;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    namaPrinter = sp.getString(_kNamaPrinter);
    pinAlternatif = sp.getBool(_kPinAlternatif) ?? false;
  }

  Future<void> simpan({String? namaPrinter, required bool pinAlternatif}) async {
    final sp = await SharedPreferences.getInstance();
    if (namaPrinter == null || namaPrinter.trim().isEmpty) {
      await sp.remove(_kNamaPrinter);
    } else {
      await sp.setString(_kNamaPrinter, namaPrinter.trim());
    }
    await sp.setBool(_kPinAlternatif, pinAlternatif);
    this.namaPrinter = namaPrinter;
    this.pinAlternatif = pinAlternatif;
  }
}
