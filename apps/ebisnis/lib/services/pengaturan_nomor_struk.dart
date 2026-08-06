import 'dart:math';

import 'package:core_device/core_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_variant.dart';

enum FormatNomorStruk {
  defaultPos,
  tanggalUrut,
  deviceTanggalUrut,
}

extension FormatNomorStrukLabel on FormatNomorStruk {
  String get kode => switch (this) {
        FormatNomorStruk.defaultPos => 'default',
        FormatNomorStruk.tanggalUrut => 'tanggal_urut',
        FormatNomorStruk.deviceTanggalUrut => 'device_tanggal_urut',
      };

  String get label => switch (this) {
        FormatNomorStruk.defaultPos => 'Default POS',
        FormatNomorStruk.tanggalUrut => 'Tanggal + nomor urut 5 digit',
        FormatNomorStruk.deviceTanggalUrut =>
          'Kode device + tanggal + nomor urut 5 digit',
      };

  String get contoh => switch (this) {
        FormatNomorStruk.defaultPos => 'EB260806153045A1B2',
        FormatNomorStruk.tanggalUrut => '0608202600001',
        FormatNomorStruk.deviceTanggalUrut => 'A1B20608202600001',
      };
}

/// Pengaturan nomor struk lokal per perangkat.
///
/// Mode tanggal-urut memakai format ddMMyyyy + 5 digit urutan dan reset setiap
/// tanggal berganti. Counter disimpan lokal supaya tetap lanjut setelah app
/// ditutup. Pada banyak mesin kasir, nomor ini unik per perangkat, bukan global.
class PengaturanNomorStruk {
  PengaturanNomorStruk._();
  static final PengaturanNomorStruk instance = PengaturanNomorStruk._();

  static const _kFormat = 'nomor_struk_format';
  static const _kKodeDevice = 'nomor_struk_kode_device';
  static const _kTanggalUrutTerakhir = 'nomor_struk_tanggal_urut_terakhir';
  static const _kUrutanTerakhir = 'nomor_struk_urutan_terakhir';

  FormatNomorStruk format = FormatNomorStruk.defaultPos;
  String? kodeDeviceKustom;

  Future<void> muat() async {
    final sp = await SharedPreferences.getInstance();
    format = _dariKode(sp.getString(_kFormat));
    kodeDeviceKustom = _normalisasiKodeDevice(sp.getString(_kKodeDevice));
  }

  Future<void> simpanFormat(FormatNomorStruk nilai) async {
    format = nilai;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kFormat, nilai.kode);
  }

  Future<void> simpanKodeDevice(String kode) async {
    final normal = _normalisasiKodeDevice(kode);
    kodeDeviceKustom = normal;
    final sp = await SharedPreferences.getInstance();
    if (normal == null) {
      await sp.remove(_kKodeDevice);
    } else {
      await sp.setString(_kKodeDevice, normal);
    }
  }

  Future<void> simpan({
    required FormatNomorStruk format,
    required String kodeDevice,
  }) async {
    await simpanFormat(format);
    await simpanKodeDevice(kodeDevice);
  }

  Future<String> buatNomor() async {
    await muat();
    return switch (format) {
      FormatNomorStruk.defaultPos => _buatDefault(),
      FormatNomorStruk.tanggalUrut => _buatTanggalUrut(),
      FormatNomorStruk.deviceTanggalUrut => _buatDeviceTanggalUrut(),
    };
  }

  static String kodeDeviceDariId(String idMesin) {
    final bersih = idMesin
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '')
        .padRight(4, '0');
    return bersih.substring(0, 4);
  }

  static String? _normalisasiKodeDevice(String? kode) {
    final bersih =
        (kode ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (bersih.isEmpty) return null;
    return bersih.length > 8 ? bersih.substring(0, 8) : bersih;
  }

  String _buatDefault() {
    final rand = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final now = DateTime.now();
    String pad(int x) => x.toString().padLeft(2, '0');
    final tanggal =
        '${(now.year % 100).toString().padLeft(2, '0')}${pad(now.month)}${pad(now.day)}';
    final jam = '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
    final acak =
        List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    final prefix = AppVariant.isAlBahjah ? 'AB' : 'EB';
    return '$prefix$tanggal$jam$acak';
  }

  Future<String> _buatTanggalUrut() async {
    final sp = await SharedPreferences.getInstance();
    final now = DateTime.now();
    String pad(int x) => x.toString().padLeft(2, '0');
    final tanggal = '${pad(now.day)}${pad(now.month)}${now.year}';
    final tanggalTerakhir = sp.getString(_kTanggalUrutTerakhir);
    final urutanSebelumnya =
        tanggalTerakhir == tanggal ? sp.getInt(_kUrutanTerakhir) ?? 0 : 0;
    final urutan = urutanSebelumnya + 1;
    await sp.setString(_kTanggalUrutTerakhir, tanggal);
    await sp.setInt(_kUrutanTerakhir, urutan);
    return '$tanggal${urutan.toString().padLeft(5, '0')}';
  }

  Future<String> _buatDeviceTanggalUrut() async {
    await IdentitasMesin.instance.muat();
    final kodeDevice =
        kodeDeviceKustom ?? kodeDeviceDariId(IdentitasMesin.instance.idMesin);
    return '$kodeDevice${await _buatTanggalUrut()}';
  }

  FormatNomorStruk _dariKode(String? kode) {
    for (final item in FormatNomorStruk.values) {
      if (item.kode == kode) return item;
    }
    return FormatNomorStruk.defaultPos;
  }
}
