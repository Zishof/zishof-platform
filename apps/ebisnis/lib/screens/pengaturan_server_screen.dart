import 'dart:async';
import 'dart:io';

import 'package:core_device/core_device.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import '../services/server_config.dart';
import '../theme/app_colors.dart';
import 'login_screen.dart';

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
      backgroundColor: AppColors.pageBg,
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
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF1E3A5F), AppColors.primary]),
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
                      color: AppColors.cardBg,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: AppColors.border),
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
    if (_tesBerhasil != null) setState(() => _tesBerhasil = null);
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
    setState(() {
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
      setState(() {
        _tesBerhasil = true;
        _pesanTes = 'Server menjawab (HTTP ${resp.statusCode}).';
        _hostDiuji = hostSaatIni;
        _ctxDiuji = ctxSaatIni;
        _httpsDiuji = httpsSaatIni;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tesBerhasil = false;
        _pesanTes = _pesanDariError(e);
      });
    } finally {
      if (mounted) setState(() => _mengetes = false);
    }
  }

  String _pesanDariError(Object e) {
    if (e is TimeoutException)
      return 'Waktu koneksi habis. Periksa alamat host & koneksi jaringan Anda.';
    if (e is SocketException) {
      final pesan = e.message.toLowerCase();
      if (pesan.contains('failed host lookup'))
        return 'Alamat host tidak ditemukan. Periksa ejaan alamat host.';
      if (pesan.contains('connection refused'))
        return 'Koneksi ditolak server. Periksa context path, atau hubungi admin sistem.';
      if (pesan.contains('connection reset'))
        return 'Koneksi terputus oleh server. Coba lagi.';
      return 'Gagal terhubung ke server: ${e.message}';
    }
    if (e is HandshakeException)
      return 'Gagal verifikasi sertifikat HTTPS. Jika server Anda memakai HTTP biasa, matikan opsi "Gunakan HTTPS".';
    return e.toString();
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);
    await ServerConfig.instance.simpan(
      host: ServerConfig.sanitizeHost(_hostCtrl.text),
      contextPath: ServerConfig.sanitizeContextPath(_ctxCtrl.text),
      https: _https,
    );
    // Kredensial lama (token tersimpan) terikat ke server lama -- hapus
    // supaya tidak dikira masih berlaku di server yang baru diatur.
    await ApiClient.instance.hapusToken();
    await widget.onSelesai();
    if (mounted) setState(() => _menyimpan = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Alamat Host',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _hostCtrl,
          decoration: const InputDecoration(
              hintText: 'mis. ebisnis.id',
              border: OutlineInputBorder(),
              isDense: true),
          keyboardType: TextInputType.url,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Alamat domain/server AIS Anda, TANPA "https://" dan tanpa garis miring di akhir. Tanyakan ke admin sistem/IT institusi Anda bila belum tahu.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Context Path',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _ctxCtrl,
          decoration: const InputDecoration(
              hintText: 'mis. ebisnis (kosongkan bila tidak ada)',
              border: OutlineInputBorder(),
              isDense: true),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Bagian path setelah domain (bila ada). Kosongkan bila server Anda langsung di root domain.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Protokol Koneksi',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8)),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _https,
            onChanged: (v) {
              setState(() => _https = v);
              _batalkanStatusTes();
            },
            title: Row(children: [
              const Text('Gunakan HTTPS'),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.latarLembut(AppColors.success),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Disarankan',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.success,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Biarkan tercentang kecuali admin sistem Anda secara eksplisit mengarahkan memakai HTTP biasa. Koneksi tanpa HTTPS tidak terenkripsi.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.latarLembut(AppColors.info),
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
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (_pesanTes != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _pesanTes!,
              style: TextStyle(
                  color: _tesBerhasil == true
                      ? AppColors.success
                      : AppColors.danger,
                  fontSize: 13),
            ),
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
            style:
                const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
