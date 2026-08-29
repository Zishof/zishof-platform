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
              autofocus: true,
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
        await tampilkanSinkronisasiSeluruhTabel(context);
      }
    } finally {
      _sedangMemeriksa = false;
    }
  }
}

/// Membuka sinkronisasi seluruh adapter lokal yang didukung dari pemicu mana
/// pun (penawaran sesudah update maupun tombol Sinkronkan di header). Dengan
/// satu entry point, transaksi pending tidak lagi tertinggal karena tombol
/// header menjalankan alur yang lebih sempit daripada dialog instalasi.
Future<void> tampilkanSinkronisasiSeluruhTabel(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DialogSinkronisasiVersi(),
  );
}

class _DialogSinkronisasiVersi extends StatefulWidget {
  const _DialogSinkronisasiVersi();

  @override
  State<_DialogSinkronisasiVersi> createState() =>
      _DialogSinkronisasiVersiState();
}

class _DialogSinkronisasiVersiState extends State<_DialogSinkronisasiVersi> {
  List<String>? _hasil;
  final List<String> _hasilBerjalan = <String>[];
  final Map<String, KemajuanSinkronisasiTabel> _kemajuanPerTabel =
      <String, KemajuanSinkronisasiTabel>{};
  final PembatalanSinkronisasi _pembatalan = PembatalanSinkronisasi();
  KemajuanSinkronisasiTabel? _kemajuan;
  int _jumlahGagal = 0;
  bool _sedangMembatalkan = false;
  Object? _galat;

  bool get _adaKendala =>
      _galat != null ||
      _jumlahGagal > 0 ||
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
      final hasil = await SinkronisasiTabelService.instance.sinkronkanSemua(
        onProgress: _laporKemajuan,
        pembatalan: _pembatalan,
      );
      if (mounted) setState(() => _hasil = hasil);
    } catch (e) {
      if (mounted) setState(() => _galat = e);
    }
  }

  void _laporKemajuan(KemajuanSinkronisasiTabel kemajuan) {
    if (!mounted) return;
    setState(() {
      _kemajuan = kemajuan;
      _kemajuanPerTabel[kemajuan.nama] = kemajuan;
      if (!kemajuan.sedangBerjalan && kemajuan.pesan != null) {
        _hasilBerjalan.add(kemajuan.pesan!);
        if (kemajuan.gagal) _jumlahGagal++;
      }
    });
  }

  Widget _progressBerjalan() {
    final kemajuan = _kemajuan;
    final tahapan = _kemajuanPerTabel.values.toList(growable: false);
    final tahapanAktif =
        tahapan.where((e) => e.sedangBerjalan).toList(growable: false);
    final total = kemajuan?.total ?? 0;
    final selesai = tahapan.where((e) => !e.sedangBerjalan).length;
    final jumlahBagian = tahapan.fold<double>(0, (nilai, tahap) {
      if (!tahap.sedangBerjalan) return nilai + 1;
      return nilai + (tahap.fraksiTahap ?? 0).clamp(0.0, 1.0);
    });
    final fraksi =
        total <= 0 ? 0.0 : (jumlahBagian / total).clamp(0.0, 1.0).toDouble();
    final persen = (fraksi * 100).round();
    final aktif = tahapan.where((e) => e.sedangBerjalan).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _sedangMembatalkan
              ? 'Menghentikan sinkronisasi dengan aman…'
              : aktif <= 1
                  ? 'Sedang memproses ${aktif == 0 ? 1 : aktif} tabel'
                  : 'Sedang memproses $aktif tabel secara paralel',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Semantics(
          label: 'Kemajuan sinkronisasi $persen persen',
          value: '$selesai dari $total tahap selesai',
          child: LinearProgressIndicator(
            value: fraksi,
            minHeight: 12,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '$persen%',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Text('$selesai dari $total tahap selesai'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _sedangMembatalkan
              ? 'Menunggu permintaan server yang sedang aktif selesai. Cache '
                  'tidak akan diganti dengan data setengah lengkap.'
              : 'Jangan tutup aplikasi atau mematikan perangkat. Data lokal '
                  'yang sudah ada tetap dipertahankan bila salah satu tabel gagal.',
        ),
        if (tahapanAktif.isNotEmpty) ...[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: tahapanAktif.length,
              separatorBuilder: (_, __) => const Divider(height: 14),
              itemBuilder: (context, index) {
                final tahap = tahapanAktif[index];
                final berjalan = tahap.sedangBerjalan;
                final persenTahap = berjalan && tahap.fraksiTahap != null
                    ? ' ${(tahap.fraksiTahap! * 100).round()}%'
                    : '';
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: berjalan
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              tahap.gagal
                                  ? Icons.warning_amber
                                  : Icons.check_circle,
                              size: 18,
                              color: tahap.gagal ? Colors.orange : Colors.green,
                            ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${tahap.label}$persenTahap',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (tahap.detail?.trim().isNotEmpty == true)
                            Text(
                              tahap.detail!,
                              key: ValueKey(
                                  'detail-kemajuan-sinkronisasi-${tahap.nama}'),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
        if (_hasilBerjalan.isNotEmpty && tahapanAktif.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            '${_hasilBerjalan.length} dari $total tabel sudah selesai dan '
            'dikeluarkan dari daftar aktif.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
        if (_jumlahGagal > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$_jumlahGagal tahap mengalami kendala. Proses tabel lain tetap '
            'dilanjutkan dan data lokal tetap aman.',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  void _batalkan() {
    if (_sedangMembatalkan || _hasil != null || _galat != null) return;
    setState(() => _sedangMembatalkan = true);
    _pembatalan.batalkan();
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
              ? _progressBerjalan()
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
          if (!selesai)
            TextButton.icon(
              onPressed: _sedangMembatalkan ? null : _batalkan,
              icon: const Icon(Icons.stop_circle_outlined),
              label:
                  Text(_sedangMembatalkan ? 'Sedang membatalkan…' : 'Batalkan'),
            ),
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
