import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_components.dart';
import '../widgets/safe_state.dart';

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
    setStateIfMounted(() => _menyimpan = true);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal: $e')));
    } finally {
      if (mounted) setStateIfMounted(() => _menyimpan = false);
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
                  AppFormSection(
                    judul: 'Pengguna Saat Ini',
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Text(
                              Sesi.instance.userId.isNotEmpty
                                  ? Sesi.instance.userId
                                  : '-',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppFormSection(
                    judul: 'Ganti Password',
                    children: [
                      AppFormTextField(
                        label: 'Password Lama',
                        controller: _lamaController,
                        obscureText: !_lihatLama,
                        suffixIcon: IconButton(
                          icon: Icon(_lihatLama
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setStateIfMounted(() => _lihatLama = !_lihatLama),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Wajib diisi' : null,
                      ),
                      AppFormTextField(
                        label: 'Password Baru',
                        controller: _baruController,
                        obscureText: !_lihatBaru,
                        helperText: 'Minimal 6 karakter.',
                        suffixIcon: IconButton(
                          icon: Icon(_lihatBaru
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setStateIfMounted(() => _lihatBaru = !_lihatBaru),
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Minimal 6 karakter'
                            : null,
                      ),
                      AppFormTextField(
                        label: 'Konfirmasi Password Baru',
                        controller: _konfirmasiController,
                        obscureText: !_lihatBaru,
                        validator: (v) => (v != _baruController.text)
                            ? 'Konfirmasi tidak cocok'
                            : null,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: AppTombolAksi(
                          icon: Icons.save_outlined,
                          label: _menyimpan
                              ? 'Menyimpan...'
                              : 'Simpan Password Baru',
                          onPressed: _menyimpan ? null : _simpan,
                        ),
                      ),
                    ],
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
