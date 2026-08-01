import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../theme/app_colors.dart';
import '../widgets/app_components.dart';

/// Akun Saya (self-service ganti password) -- memanggil aksi server
/// `akun_ganti_password` (KantinHelper.gantiPasswordSendiri) yang SUDAH ADA
/// di Api_eBisnis tapi belum punya UI Flutter. Hanya berlaku utk akun kasir
/// (Pedagang) -- server sendiri yang menolak akun admin murni (status "91"),
/// jadi error server ditampilkan apa adanya, tidak ditebak/disaring di sini.
class AkunSayaScreen extends StatefulWidget {
  const AkunSayaScreen({super.key});

  @override
  State<AkunSayaScreen> createState() => _AkunSayaScreenState();
}

class _AkunSayaScreenState extends State<AkunSayaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _lamaController = TextEditingController();
  final _baruController = TextEditingController();
  final _konfirmasiController = TextEditingController();
  bool _menyimpan = false;
  bool _lihatLama = false;
  bool _lihatBaru = false;

  @override
  void dispose() {
    _lamaController.dispose();
    _baruController.dispose();
    _konfirmasiController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _menyimpan = true);
    try {
      await ApiClient.instance.aksi('akun_ganti_password', {
        'password_lama': _lamaController.text,
        'password_baru': _baruController.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password berhasil diganti.')),
      );
      _lamaController.clear();
      _baruController.clear();
      _konfirmasiController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akun Saya')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSectionCard(
                    judul: 'Pengguna Saat Ini',
                    child: Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person)),
                        const SizedBox(width: 12),
                        Text(Sesi.instance.userId.isNotEmpty ? Sesi.instance.userId : '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppSectionCard(
                    judul: 'Ganti Password',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _lamaController,
                          obscureText: !_lihatLama,
                          decoration: InputDecoration(
                            labelText: 'Password Lama',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_lihatLama ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _lihatLama = !_lihatLama),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _baruController,
                          obscureText: !_lihatBaru,
                          decoration: InputDecoration(
                            labelText: 'Password Baru',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_lihatBaru ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _lihatBaru = !_lihatBaru),
                            ),
                          ),
                          validator: (v) => (v == null || v.length < 6) ? 'Minimal 6 karakter' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _konfirmasiController,
                          obscureText: !_lihatBaru,
                          decoration: const InputDecoration(labelText: 'Konfirmasi Password Baru', border: OutlineInputBorder()),
                          validator: (v) => (v != _baruController.text) ? 'Konfirmasi tidak cocok' : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _menyimpan ? null : _simpan,
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: _menyimpan
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Simpan Password Baru'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
