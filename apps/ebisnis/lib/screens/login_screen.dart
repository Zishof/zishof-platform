import 'package:flutter/material.dart';
import '../app_variant.dart';
import '../api_client.dart';
import '../theme/app_colors.dart';
import 'kasir_screen.dart';
import 'pengaturan_server_screen.dart';
import '../widgets/safe_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _memproses = false;
  String? _pesanError;

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setStateIfMounted(
          () => _pesanError = 'Username dan password wajib diisi.');
      return;
    }
    setStateIfMounted(() {
      _memproses = true;
      _pesanError = null;
    });
    try {
      final hasil = await ApiClient.instance.aksi('login', {
        'username': _userCtrl.text.trim(),
        'password': _passCtrl.text,
        'labelPerangkat': AppVariant.labelPerangkat,
      });
      await ApiClient.instance.simpanToken(hasil['token'] as String);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const KasirScreen()),
      );
    } catch (e) {
      setStateIfMounted(() => _pesanError = e.toString());
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.gelap(context);
    final warnaJudul = isDark ? AppColors.darkTextPrimary : AppColors.sidebarBg;
    final warnaSubjudul = AppColors.textSecondaryOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(AppVariant.logoAsset, height: 64),
                    const SizedBox(height: 12),
                    Text(AppVariant.namaAplikasi,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: warnaJudul)),
                    Text('Masuk sebagai Kasir',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: warnaSubjudul)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Username', border: OutlineInputBorder()),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Password', border: OutlineInputBorder()),
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                    ),
                    if (_pesanError != null) ...[
                      const SizedBox(height: 12),
                      Text(_pesanError!,
                          style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _memproses ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _memproses
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Masuk'),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const PengaturanServerScreen())),
                        child: const Text('Ubah Alamat Server'),
                      ),
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
