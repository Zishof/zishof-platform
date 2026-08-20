import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/api_client.dart';
import '../services/server_config.dart';
import '../services/sesi.dart';
import '../widgets/panel_galat.dart';
import 'beranda_screen.dart';
import 'pengaturan_server_screen.dart';

/// Masuk memakai akun member.
///
/// Aksi `login` menerima username/password yang sama dengan akun web: server
/// mencocokkannya ke Mahasiswa, Siswa, Tbmuser, atau Penduduk, lalu membalas
/// token. Token itulah yang dipakai seluruh aksi `kantin_*`.
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
    final warna = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.storefront, size: 54, color: warna.primary),
                    const SizedBox(height: 10),
                    Text(
                      AppConfig.namaAplikasi,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: warna.primary,
                      ),
                    ),
                    const Text(
                      'Masuk dengan akun member Anda',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _user,
                      decoration: const InputDecoration(labelText: 'Username'),
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sandi,
                      obscureText: _sembunyikanSandi,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          icon: Icon(_sembunyikanSandi
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _sembunyikanSandi = !_sembunyikanSandi),
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
                      child: _memproses
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Masuk'),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const PengaturanServerScreen()));
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.dns_outlined, size: 16),
                      label: Text(
                        ServerConfig.instance.baseUrl,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
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
