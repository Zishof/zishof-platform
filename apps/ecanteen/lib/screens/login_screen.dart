import 'package:flutter/material.dart';

import '../app_variant.dart';
import '../services/api_client.dart';
import '../services/server_config.dart';
import '../services/sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/panel_galat.dart';
import 'beranda_screen.dart';
import 'pengaturan_server_screen.dart';

/// Masuk memakai akun member.
///
/// Aksi `login` menerima username/password yang sama dengan akun web: server
/// mencocokkannya ke Mahasiswa, Siswa, Tbmuser, atau Penduduk, lalu membalas
/// token. Token itulah yang dipakai seluruh aksi `kantin_*`.
///
/// Tata letaknya sengaja disamakan dgn POS Desktop varian yang sama: kartu
/// dua kolom (panel identitas + formulir) pada layar lebar, kartu satu kolom
/// pada layar sempit.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _sandi = TextEditingController();
  bool _memproses = false;
  bool _sembunyikanSandi = true;
  String? _galat;

  @override
  void initState() {
    super.initState();
    _user.text = Sesi.instance.username ?? '';
  }

  @override
  void dispose() {
    _user.dispose();
    _sandi.dispose();
    super.dispose();
  }

  Future<void> _masuk() async {
    final u = _user.text.trim();
    final p = _sandi.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _galat = 'Username dan password wajib diisi.');
      return;
    }
    setState(() {
      _memproses = true;
      _galat = null;
    });
    try {
      final res = await ApiClient.instance.aksi(
        'login',
        {'username': u, 'password': p},
        sertakanToken: false,
      );
      final token = '${res['token'] ?? ''}';
      if (token.isEmpty) {
        throw ApiException('Server tidak mengirimkan token sesi.');
      }
      await Sesi.instance.simpanToken(token, u);

      // Pastikan akun ini memang punya data anggota koperasi sebelum masuk;
      // kalau tidak, member akan melihat beranda kosong tanpa penjelasan.
      final info = await ApiClient.instance.aksi('kantin_info', const {});
      final data = info['data'];
      if (data is Map) {
        Sesi.instance.terapkanInfo(data.map((k, v) => MapEntry('$k', v)));
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const BerandaScreen()));
    } on ApiException catch (e) {
      await Sesi.instance.keluar();
      if (!mounted) return;
      setState(() => _galat = e.pesan);
    } catch (e) {
      await Sesi.instance.keluar();
      if (!mounted) return;
      setState(() => _galat = '$e');
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.latarMasuk,
      body: Stack(
        children: [
          // Cap air logo di sudut, mengikuti latar layar Masuk POS Desktop.
          Positioned(
            right: -120,
            bottom: -100,
            child: Opacity(
              opacity: 0.07,
              child: Image.asset(AppVariant.logoAsset,
                  height: 520,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink()),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(builder: (context, kendala) {
                  // Dua kolom hanya bila varian memintanya DAN layar cukup
                  // lebar; di jendela sempit tetap satu kolom supaya formulir
                  // tidak terhimpit.
                  final duaKolom =
                      AppVariant.loginDuaKolom && kendala.maxWidth >= 720;
                  return ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: duaKolom ? 860 : 400),
                    child: Card(
                      elevation: 12,
                      shadowColor: Colors.black54,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: duaKolom
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 5, child: _panelIdentitas()),
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child:
                                          _kolomFormulir(tampilkanLogo: false),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(28),
                              child: _kolomFormulir(tampilkanLogo: true),
                            ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Panel identitas (kolom kiri): logo, nama organisasi, dan kotak kontak.
  Widget _panelIdentitas() {
    Widget barisKontak(IconData ikon, String teks) {
      if (teks.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikon, size: 14, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: Text(teks,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.4)),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: AppColors.latarMasuk,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(AppVariant.logoAsset, height: 84),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              AppVariant.namaOrganisasiLogin,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  height: 1.3,
                  fontWeight: FontWeight.bold),
            ),
            if (AppVariant.alamatKontakLogin.isNotEmpty) ...[
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('HUBUNGI KAMI',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    barisKontak(Icons.location_on_outlined,
                        AppVariant.alamatKontakLogin),
                    barisKontak(
                        Icons.phone_outlined, AppVariant.teleponKontakLogin),
                    barisKontak(
                        Icons.mail_outline, AppVariant.emailKontakLogin),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Kolom formulir. Dipakai apa adanya pada tata letak satu kolom, dan
  /// sebagai kolom kanan pada dua kolom (logo dimatikan di sana karena sudah
  /// tampil di panel identitas).
  Widget _kolomFormulir({required bool tampilkanLogo}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tampilkanLogo) ...[
          Center(
            child: Image.asset(AppVariant.logoAsset,
                height: 72,
                errorBuilder: (context, error, stack) => const Icon(
                    Icons.storefront,
                    size: 54,
                    color: AppColors.primary)),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          AppVariant.judulLogin,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppColors.sidebarBg,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          AppVariant.subJudulLogin,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _user,
          decoration: const InputDecoration(hintText: 'Username'),
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _sandi,
          obscureText: _sembunyikanSandi,
          decoration: InputDecoration(
            hintText: 'Password',
            suffixIcon: IconButton(
              icon: Icon(_sembunyikanSandi
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () =>
                  setState(() => _sembunyikanSandi = !_sembunyikanSandi),
            ),
          ),
          onSubmitted: (_) => _masuk(),
        ),
        if (_galat != null) ...[
          const SizedBox(height: 14),
          PanelGalat(pesan: _galat!),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _memproses ? null : _masuk,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _memproses
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Masuk',
                  style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PengaturanServerScreen()));
              if (mounted) setState(() {});
            },
            child: const Text('Ubah Alamat Server',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        Center(
          child: Text(
            ServerConfig.instance.baseUrl,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
        if (AppVariant.hakCiptaLogin.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Text(
            AppVariant.hakCiptaLogin,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined,
                      size: 13, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text('Sistem Informasi Terpadu & Terenkripsi',
                      style:
                          TextStyle(color: AppColors.primary, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
