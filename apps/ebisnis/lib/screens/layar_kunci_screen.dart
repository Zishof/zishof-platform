import 'package:core_auth/core_auth.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../app_variant.dart';
import '../product_profile.dart';
import '../services/pengaturan_sesi_lokal.dart';
import '../services/transaksi_outbox_service.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_version_label.dart';
import '../widgets/safe_state.dart';
import 'login_screen.dart';
import 'pengaturan_server_screen.dart';

/// Layar kunci sesi -- muncul saat aplikasi dibuka lagi setelah lama tidak
/// dipakai ([PengaturanSesiLokal.timeoutMenit]).
///
/// <h3>Kenapa mengunci, bukan mengeluarkan</h3>
/// Sebelumnya batas waktu lokal MENGHAPUS token perangkat, padahal token itu
/// masih sah 30 hari di server. Akibatnya toko yang membuka aplikasi keesokan
/// pagi wajib login daring -- dan ketika server sedang mati, kasir tidak dapat
/// bekerja sama sekali walaupun seluruh jalur luring (katalog, antrean
/// transaksi) sebenarnya siap. Sekarang batas waktu hanya MENGUNCI layar:
/// tokennya dipertahankan, dan hanya dibuang bila pengguna keluar akun atau
/// server sendiri menolaknya.
///
/// <h3>Urutan membuka kunci</h3>
/// 1. Coba ke server. Ini verifikasi yang sebenarnya, sekaligus memperbarui
///    token (masa berlakunya kembali penuh) dan bukti sandi lokal.
/// 2. Bila server TIDAK terjangkau ({@code ApiException.offline}), kata sandi
///    diperiksa terhadap bukti lokal ([VerifikatorSandiLokal]) yang dibuat saat
///    login daring terakhir. Cocok berarti kunci terbuka dalam mode luring.
/// 3. Bila server menolak kata sandi, pesannya ditampilkan apa adanya --
///    penolakan bisnis tidak pernah dialihkan ke jalur luring.
///
/// Akun yang belum pernah login daring di perangkat ini tidak punya bukti
/// lokal, jadi tidak akan pernah bisa membuka kunci tanpa jaringan.
class LayarKunciScreen extends StatefulWidget {
  const LayarKunciScreen({super.key});

  @override
  State<LayarKunciScreen> createState() => _LayarKunciScreenState();
}

class _LayarKunciScreenState extends State<LayarKunciScreen> {
  final _passCtrl = TextEditingController();
  final _fokusSandi = FocusNode();
  bool _memproses = false;
  AppErrorInfo? _pesanError;
  String _username = '';
  bool _adaBuktiLokal = false;
  DateTime? _terakhirDaring;

  @override
  void initState() {
    super.initState();
    _muatIdentitas();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _fokusSandi.dispose();
    super.dispose();
  }

  Future<void> _muatIdentitas() async {
    final nama = await VerifikatorSandiLokal.instance.usernameTersimpan();
    final daring = await VerifikatorSandiLokal.instance.terakhirDaring();
    setStateIfMounted(() {
      _username = nama ?? '';
      _adaBuktiLokal = nama != null;
      _terakhirDaring = daring;
    });
  }

  Future<void> _buka() async {
    if (_passCtrl.text.isEmpty) {
      setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
          'Kata sandi tidak boleh kosong.',
          aktivitas: 'buka kunci'));
      return;
    }
    setStateIfMounted(() {
      _memproses = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('login', {
        'username': _username,
        'password': _passCtrl.text,
        'labelPerangkat': AppVariant.labelPerangkat,
      });
      // Token baru sekaligus memperpanjang masa berlaku; bukti lokal disegarkan
      // supaya perubahan kata sandi di server ikut terbawa ke jalur luring.
      await ApiClient.instance.simpanToken(hasil['token'] as String);
      await VerifikatorSandiLokal.instance.simpan(_username, _passCtrl.text);
      await _lanjutMasuk();
    } on ApiException catch (e) {
      if (!e.offline) {
        // Penolakan dari server (kata sandi salah, akun nonaktif) -- jangan
        // pernah dialihkan ke jalur luring.
        setStateIfMounted(() => _pesanError = e.info);
        return;
      }
      await _bukaLuring();
    } catch (e) {
      setStateIfMounted(() =>
          _pesanError = AppErrorInfo.dari(e, aktivitas: 'buka kunci'));
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  Future<void> _bukaLuring() async {
    if (!_adaBuktiLokal) {
      setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
          'Server belum dapat dihubungi, dan perangkat ini belum pernah '
          'menyimpan bukti kata sandi Anda. Buka kunci pertama kali memang '
          'harus tersambung ke server.',
          aktivitas: 'buka kunci'));
      return;
    }
    final cocok =
        await VerifikatorSandiLokal.instance.cocok(_username, _passCtrl.text);
    if (!cocok) {
      setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
          'Kata sandi tidak cocok dengan yang terakhir dipakai di perangkat '
          'ini. Server sedang tidak terjangkau, jadi kata sandi baru dari '
          'server belum dapat diperiksa.',
          aktivitas: 'buka kunci'));
      return;
    }
    await _lanjutMasuk();
  }

  Future<void> _lanjutMasuk() async {
    await PengaturanSesiLokal.instance.catatAktifSekarang();
    TransaksiOutboxService.instance.mulai();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AppProductProfile.aktif.buatLayarAwal()),
    );
  }

  /// Keluar akun sungguhan: token DAN bukti lokal dibuang, jadi perangkat ini
  /// kembali membutuhkan login daring.
  Future<void> _keluarAkun() async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Keluar akun?'),
        content: const Text(
            'Sesi perangkat ini akan dihapus. Untuk masuk kembali Anda '
            'membutuhkan sambungan ke server.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Keluar')),
        ],
      ),
    );
    if (ya != true) return;
    // hapusToken() sudah sekaligus membuang catatan aktif dan bukti sandi.
    await ApiClient.instance.hapusToken(tutupBasisData: true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  String get _keteranganDaring {
    final t = _terakhirDaring;
    if (t == null) return '';
    final selisih = DateTime.now().difference(t);
    if (selisih.inMinutes < 60) return 'Terhubung server ${selisih.inMinutes} menit lalu';
    if (selisih.inHours < 24) return 'Terhubung server ${selisih.inHours} jam lalu';
    return 'Terhubung server ${selisih.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    final teksSekunder = Colors.black.withValues(alpha: 0.6);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 3,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(AppVariant.logoAsset, height: 56),
                    const SizedBox(height: 14),
                    const Text('Sesi Terkunci',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      _username.isEmpty
                          ? 'Masukkan kata sandi untuk melanjutkan.'
                          : 'Masuk kembali sebagai $_username.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: teksSekunder),
                    ),
                    if (_keteranganDaring.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(_keteranganDaring,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: teksSekunder, fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _passCtrl,
                      focusNode: _fokusSandi,
                      autofocus: true,
                      decoration: const InputDecoration(
                          labelText: 'Password', border: OutlineInputBorder()),
                      obscureText: true,
                      onSubmitted: (_) => _buka(),
                    ),
                    if (_pesanError != null) ...[
                      const SizedBox(height: 12),
                      AppErrorPanel(info: _pesanError!),
                    ],
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _memproses ? null : _buka,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _memproses
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Buka Kunci'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _memproses ? null : _keluarAkun,
                      child: const Text('Keluar Akun'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PengaturanServerScreen())),
                      child: const Text('Ubah Alamat Server'),
                    ),
                    AppVersionLabel(
                      style: TextStyle(color: teksSekunder, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
