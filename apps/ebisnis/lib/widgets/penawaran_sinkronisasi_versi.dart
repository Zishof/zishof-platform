import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../app_variant.dart';
import '../services/sinkronisasi_tabel_service.dart';

/// Menawarkan hidrasi data lokal satu kali pada instalasi baru dan setiap
/// versi/build aplikasi berubah.
///
/// Pemeriksaan dilakukan setelah pengguna masuk karena seluruh adapter
/// sinkronisasi memerlukan token dan konteks tenant. Saat server benar-benar
/// tidak terjangkau, versi tidak ditandai sehingga penawaran dapat muncul pada
/// pembukaan layar berikutnya setelah koneksi pulih.
class PenawaranSinkronisasiVersi {
  PenawaranSinkronisasiVersi._();

  static bool _sedangMemeriksa = false;
  static final Set<String> _sudahDitawarkanPadaSesi = <String>{};

  static String identitasVersi(PackageInfo info) =>
      '${info.version}+${info.buildNumber}';

  static String kunciPenyimpanan({required int? tenantId}) =>
      'sinkronisasi_setelah_instalasi.'
      '${AppVariant.storageNamespace}.tenant_${tenantId ?? 0}';

  static bool perluDitawarkan({
    required String versiSaatIni,
    required String? versiTerakhirDitawarkan,
  }) =>
      versiSaatIni.trim().isNotEmpty && versiSaatIni != versiTerakhirDitawarkan;

  /// Aman dipanggil dari setiap [AppShell]. Penjaga proses dan preferensi
  /// membuat dialog tetap hanya muncul satu kali per versi/build dan tenant.
  static Future<void> tawarkanJikaPerlu(BuildContext context) async {
    if (_sedangMemeriksa || !ApiClient.instance.sudahLogin) return;
    _sedangMemeriksa = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final versi = identitasVersi(info);
      final tenantId = ApiClient.instance.tenantId;
      final kunci = kunciPenyimpanan(tenantId: tenantId);
      final identitasSesi = '$kunci:$versi';
      if (_sudahDitawarkanPadaSesi.contains(identitasSesi)) return;

      final prefs = await SharedPreferences.getInstance();
      if (!perluDitawarkan(
        versiSaatIni: versi,
        versiTerakhirDitawarkan: prefs.getString(kunci),
      )) {
        _sudahDitawarkanPadaSesi.add(identitasSesi);
        return;
      }

      // Jangan menandai apa pun ketika offline. Dengan demikian instalasi
      // baru yang pertama kali dibuka tanpa internet tetap memperoleh tawaran
      // setelah koneksi tersedia pada pembukaan layar berikutnya.
      final terjangkau =
          await SinkronisasiTabelService.instance.serverTerjangkau();
      if (!terjangkau || !context.mounted) return;

      final sinkronSekarang = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Siapkan data lokal untuk versi baru?'),
          content: const SizedBox(
            width: 620,
            child: Text(
              'Aplikasi mendeteksi instalasi baru atau versi yang baru '
              'dipasang, dan server dapat dihubungi.\n\n'
              'Pilih Sinkronkan Sekarang untuk mengunduh katalog dan member, '
              'mengirim antrean transaksi/perubahan lokal, serta menjalankan '
              'adapter lain yang sudah didukung. Setelah selesai, data '
              'operasional tersebut dapat dibaca lokal-dulu saat koneksi '
              'lambat atau terputus.\n\n'
              'Tabel konfigurasi, log, keamanan perangkat, dan tabel baru '
              'yang belum mempunyai kontrak API tidak akan ditimpa. Riwayat '
              'transaksi lama yang dipaginasi server tetap dimuat sesuai '
              'rentang halaman/laporannya.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Nanti'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.sync),
              label: const Text('Sinkronkan Sekarang'),
            ),
          ],
        ),
      );
      if (sinkronSekarang == null) return;

      // "Nanti" hanya menunda sampai aplikasi dibuka lagi; selama sesi ini
      // jangan mengganggu setiap perpindahan menu. Versi baru dicatat permanen
      // hanya ketika pengguna benar-benar memilih sinkronisasi.
      _sudahDitawarkanPadaSesi.add(identitasSesi);
      if (sinkronSekarang) {
        await prefs.setString(kunci, versi);
      }
      if (sinkronSekarang && context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _DialogSinkronisasiVersi(),
        );
      }
    } finally {
      _sedangMemeriksa = false;
    }
  }
}

class _DialogSinkronisasiVersi extends StatefulWidget {
  const _DialogSinkronisasiVersi();

  @override
  State<_DialogSinkronisasiVersi> createState() =>
      _DialogSinkronisasiVersiState();
}

class _DialogSinkronisasiVersiState extends State<_DialogSinkronisasiVersi> {
  List<String>? _hasil;
  Object? _galat;

  bool get _adaKendala =>
      _galat != null ||
      (_hasil?.any((pesan) {
            final teks = pesan.toLowerCase();
            return teks.contains('belum dapat dihubungi') ||
                teks.contains('ditolak/gagal') ||
                teks.contains('belum memiliki adapter');
          }) ??
          false);

  @override
  void initState() {
    super.initState();
    _jalankan();
  }

  Future<void> _jalankan() async {
    try {
      final hasil = await SinkronisasiTabelService.instance.sinkronkanSemua();
      if (mounted) setState(() => _hasil = hasil);
    } catch (e) {
      if (mounted) setState(() => _galat = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selesai = _hasil != null || _galat != null;
    return PopScope(
      canPop: selesai,
      child: AlertDialog(
        title: Row(
          children: [
            if (!selesai)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            else
              Icon(
                _adaKendala ? Icons.warning_amber : Icons.check_circle,
                color: _adaKendala ? Colors.orange : Colors.green,
              ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Sinkronisasi data lokal')),
          ],
        ),
        content: SizedBox(
          width: 680,
          child: !selesai
              ? const Text(
                  'Sedang menyinkronkan seluruh tabel yang didukung. Jangan '
                  'tutup aplikasi atau mematikan perangkat. Data lokal yang '
                  'sudah ada tetap dipertahankan bila salah satu adapter gagal.',
                )
              : SelectableText(
                  _galat != null
                      ? 'Sinkronisasi belum selesai: $_galat\n\nData lokal '
                          'tetap aman. Periksa koneksi dan alamat server, buka '
                          'Sistem > Log Error bila perlu, lalu buka Sistem > '
                          'Riwayat Sinkronisasi dan tekan Sinkronkan Semua '
                          'yang Didukung.'
                      : '${_hasil!.join('\n\n')}\n\nBila ada baris yang '
                          'belum berhasil, buka Sistem > Riwayat Sinkronisasi '
                          'untuk melihat tabel dan petunjuk penyelesaiannya.',
                ),
        ),
        actions: [
          if (selesai)
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
        ],
      ),
    );
  }
}
