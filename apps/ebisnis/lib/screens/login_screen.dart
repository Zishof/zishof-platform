import 'package:flutter/material.dart';
import '../app_variant.dart';
import '../api_client.dart';
import 'kasir_screen.dart';
import 'pengaturan_server_screen.dart';

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
      setState(() => _pesanError = 'Username dan password wajib diisi.');
      return;
    }
    setState(() {
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
      setState(() => _pesanError = e.toString());
    } finally {
      if (mounted) setState(() => _memproses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A5F),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (AppVariant.logoAsset == null)
                      const Icon(Icons.storefront,
                          size: 56, color: Color(0xFF1E3A5F))
                    else
                      Image.asset(AppVariant.logoAsset!, height: 64),
                    const SizedBox(height: 12),
                    const Text(AppVariant.namaAplikasi,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
                    const Text('Masuk sebagai Kasir',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passCtrl,
                      decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                      obscureText: true,
                      onSubmitted: (_) => _login(),
                    ),
                    if (_pesanError != null) ...[
                      const SizedBox(height: 12),
                      Text(_pesanError!, style: const TextStyle(color: Colors.red)),
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
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Masuk'),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PengaturanServerScreen())),
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
