import 'dart:async';
import 'dart:io';

import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import '../services/server_config.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';
import 'login_screen.dart';
import '../widgets/safe_state.dart';

/// Pengaturan Alamat Server, layar penuh (padanan `setup.html` -- dipakai
/// SEKALI di awal, sebelum layar Masuk pernah tampil sama sekali, sehingga
/// SATU APK/EXE eBisnis bisa dipakai institusi mana pun tanpa hardcode
/// domain). Layar inline (`FormAlamatServer` langsung, tanpa Scaffold
/// pembungkus ini) juga tersedia di menu Konfigurasi -> tab "Alamat Server"
/// utk mengubahnya lagi tanpa perlu logout dulu.
class PengaturanServerScreen extends StatelessWidget {
  final bool pertamaKali;
  const PengaturanServerScreen({super.key, this.pertamaKali = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBgOf(context),
      appBar: pertamaKali
          ? null
          : AppBar(
              title: const Text('Ubah Alamat Server'),
              backgroundColor: AppColors.sidebarBg,
              foregroundColor: Colors.white),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pertamaKali)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [const Color(0xFF1E3A5F), AppColors.primary]),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pengaturan Alamat Server',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text(
                        'Isi sekali di awal supaya aplikasi tahu ke server AIS mana harus terhubung. Bisa diubah kembali kapan saja lewat menu Pengaturan.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Card(
                      color: AppColors.cardBgOf(context),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: AppColors.borderOf(context)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: FormAlamatServer(
                          labelSimpan:
                              pertamaKali ? 'Simpan & Buka Aplikasi' : 'Simpan',
                          onSelesai: () async {
                            if (pertamaKali) {
                              // Jalur normal (_GerbangAwal) yg biasanya memuat ini
                              // dilewati sama sekali saat setup pertama kali (layar
                              // ini jadi `home` langsung) -- muat di sini supaya
                              // nama mesin sudah terisi di transaksi pertama.
                              await IdentitasMesin.instance.muat();
                            }
                            if (!context.mounted) return;
                            if (pertamaKali) {
                              Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                      builder: (_) => const LoginScreen()));
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isi form Pengaturan Alamat Server (host/context-path/https + Tes Koneksi
/// + Simpan) -- dipakai BERSAMA oleh [PengaturanServerScreen] (layar penuh,
/// setup pertama kali/"Ubah Alamat Server" dari layar Masuk) dan tab "Alamat
/// Server" di KonfigurasiScreen (diubah dari DALAM aplikasi tanpa logout
/// dulu). [onSelesai] dipanggil SETELAH config tersimpan+token lama dihapus
/// -- pemanggil yang menentukan ke mana selanjutnya (pop, atau bersihkan
/// seluruh stack navigasi ke LoginScreen bila dipanggil sambil masih login).
///
/// "Tes Koneksi" murni cek server MENJAWAB di root context path (respons HTTP
/// apa pun dianggap sukses, bukan validasi login) -- padanan PERSIS
/// `tesKoneksiServer` (main.js): GET biasa dgn timeout 8 detik, kesalahan
/// DNS/koneksi-ditolak/reset/TLS diberi pesan Indonesia yang berbeda.
/// "Simpan" digerbang: host valid DAN tes terakhir sukses UNTUK NILAI FIELD
/// SAAT INI (mengubah field apa pun membatalkan status tes sebelumnya --
/// tak boleh ada status sukses basi lolos ke server yang beda).
class FormAlamatServer extends StatefulWidget {
  final String labelSimpan;
  final Future<void> Function() onSelesai;
  const FormAlamatServer(
      {super.key, this.labelSimpan = 'Simpan', required this.onSelesai});

  @override
  State<FormAlamatServer> createState() => _FormAlamatServerState();
}

class _FormAlamatServerState extends State<FormAlamatServer> {
  final _hostCtrl = TextEditingController();
  final _ctxCtrl = TextEditingController();
  bool _https = true;
  bool _mengetes = false;
  bool? _tesBerhasil;
  String? _pesanTes;
  bool _menyimpan = false;

  String? _hostDiuji;
  String? _ctxDiuji;
  bool? _httpsDiuji;

  @override
  void initState() {
    super.initState();
    _hostCtrl.text = ServerConfig.instance.host;
    _ctxCtrl.text = ServerConfig.instance.contextPath;
    _https = ServerConfig.instance.https;
    _hostCtrl.addListener(_batalkanStatusTes);
    _ctxCtrl.addListener(_batalkanStatusTes);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _ctxCtrl.dispose();
    super.dispose();
  }

  void _batalkanStatusTes() {
    if (_tesBerhasil != null) setStateIfMounted(() => _tesBerhasil = null);
  }

  bool get _hostValid => ServerConfig.hostValid(_hostCtrl.text);

  String get _previewUrl {
    final skema = _https ? 'https' : 'http';
    final h = ServerConfig.sanitizeHost(_hostCtrl.text);
    final c = ServerConfig.sanitizeContextPath(_ctxCtrl.text);
    return '$skema://$h${c.isNotEmpty ? '/$c' : ''}/';
  }

  bool get _cocokDenganUjiTerakhir =>
      _hostDiuji == _hostCtrl.text &&
      _ctxDiuji == _ctxCtrl.text &&
      _httpsDiuji == _https;

  bool get _bolehSimpan =>
      _hostValid && _tesBerhasil == true && _cocokDenganUjiTerakhir;

  Future<void> _tesKoneksi() async {
    if (!_hostValid) return;
    setStateIfMounted(() {
      _mengetes = true;
      _pesanTes = null;
      _tesBerhasil = null;
    });
    final hostSaatIni = _hostCtrl.text;
    final ctxSaatIni = _ctxCtrl.text;
    final httpsSaatIni = _https;
    try {
      final resp = await http
          .get(Uri.parse(_previewUrl))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      // Server MENJAWAB (kode apa pun -- 302/401/404 termasuk) = tes sukses,
      // ini cuma cek server hidup, BUKAN validasi login/kredensial.
      setStateIfMounted(() {
        _tesBerhasil = true;
        _pesanTes = 'Server menjawab (HTTP ${resp.statusCode}).';
        _hostDiuji = hostSaatIni;
        _ctxDiuji = ctxSaatIni;
        _httpsDiuji = httpsSaatIni;
      });
    } catch (e) {
      if (!mounted) return;
      setStateIfMounted(() {
        _tesBerhasil = false;
        _pesanTes = _pesanDariError(e);
      });
    } finally {
      if (mounted) setStateIfMounted(() => _mengetes = false);
    }
  }

  String _pesanDariError(Object e) {
    if (e is TimeoutException) {
      return 'Waktu koneksi habis. Periksa alamat host & koneksi jaringan Anda.';
    }
    if (e is SocketException) {
      final pesan = e.message.toLowerCase();
      if (pesan.contains('failed host lookup')) {
        return 'Alamat host tidak ditemukan. Periksa ejaan alamat host.';
      }
      if (pesan.contains('connection refused')) {
        return 'Koneksi ditolak server. Periksa context path, atau hubungi admin sistem.';
      }
      if (pesan.contains('connection reset')) {
        return 'Koneksi terputus oleh server. Coba lagi.';
      }
      return 'Gagal terhubung ke server: ${e.message}';
    }
    if (e is HandshakeException) {
      return 'Gagal verifikasi sertifikat HTTPS. Jika server Anda memakai HTTP biasa, matikan opsi "Gunakan HTTPS".';
    }
    return e.toString();
  }

  Future<void> _simpan() async {
    setStateIfMounted(() => _menyimpan = true);
    await ServerConfig.instance.simpan(
      host: ServerConfig.sanitizeHost(_hostCtrl.text),
      contextPath: ServerConfig.sanitizeContextPath(_ctxCtrl.text),
      https: _https,
    );
    // Kredensial lama (token tersimpan) terikat ke server lama -- hapus
    // supaya tidak dikira masih berlaku di server yang baru diatur.
    await ApiClient.instance.hapusToken();
    await widget.onSelesai();
    if (mounted) setStateIfMounted(() => _menyimpan = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFormTextField(
          label: 'Alamat Host',
          controller: _hostCtrl,
          hintText: 'mis. ebisnis.id',
          helperText:
              'Alamat domain/server AIS Anda, tanpa "https://" dan tanpa garis miring di akhir.',
          keyboardType: TextInputType.url,
        ),
        AppFormTextField(
          label: 'Context Path',
          controller: _ctxCtrl,
          hintText: 'mis. ebisnis (kosongkan bila tidak ada)',
          helperText:
              'Bagian path setelah domain. Kosongkan bila server langsung di root domain.',
        ),
        AppFormSwitchTile(
          title: 'Gunakan HTTPS',
          subtitle:
              'Disarankan. Matikan hanya jika admin sistem mengarahkan memakai HTTP biasa.',
          value: _https,
          onChanged: (v) {
            setStateIfMounted(() => _https = v);
            _batalkanStatusTes();
          },
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.info),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(8)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ALAMAT YANG AKAN DIPAKAI',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.info)),
              const SizedBox(height: 4),
              Text(_previewUrl,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      color: AppColors.textPrimaryOf(context))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_pesanTes != null)
          AppInfoBanner(
            icon: _tesBerhasil == true
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: _tesBerhasil == true ? AppColors.success : AppColors.danger,
            text: _pesanTes!,
          ),
        const SizedBox(height: 16),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _hostValid && !_mengetes ? _tesKoneksi : null,
                  icon: _mengetes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Tes Koneksi',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(144, 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _bolehSimpan && !_menyimpan ? _simpan : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(190, 44),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  child: _menyimpan
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(widget.labelSimpan,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            _bolehSimpan
                ? 'Pengaturan disimpan di perangkat ini saja dan tidak dikirim ke mana pun.'
                : 'Tekan "Tes Koneksi" dan pastikan berhasil dulu sebelum bisa lanjut.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondaryOf(context)),
          ),
        ),
      ],
    );
  }
}
