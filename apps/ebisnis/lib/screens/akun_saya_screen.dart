import 'package:core_auth/core_auth.dart';
import 'package:flutter/material.dart';
import '../api_client.dart';
import '../sesi.dart';
import '../widgets/app_components.dart';
import '../widgets/app_error_info.dart';
import '../widgets/safe_state.dart';

/// Akun Saya (self-service ganti password) -- memanggil aksi server
/// `akun_ganti_password` (KantinHelper.gantiPasswordSendiri) pada `PosApi`.
/// Berlaku untuk seluruh akun yang login ke aplikasi POS Desktop maupun
/// POS Android (Kasir, Supervisor Toko, maupun Admin Toko/Manager), serta
/// menyegarkan bukti kata sandi lokal ([VerifikatorSandiLokal]) agar pembuka
/// kunci sesi luring ([LayarKunciScreen]) langsung memakai kata sandi baru.
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
  bool _lihatKonfirmasi = false;

  @override
  void dispose() {
    _lamaController.dispose();
    _baruController.dispose();
    _konfirmasiController.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    final sandiLama = _lamaController.text;
    final sandiBaru = _baruController.text;
    final konfirmasi = _konfirmasiController.text;
    setStateIfMounted(() => _menyimpan = true);
    try {
      await ApiClient.instance.aksi('akun_ganti_password', {
        'password_lama': sandiLama,
        'password_baru': sandiBaru,
        'konfirmasi_password': konfirmasi,
      });
      // Segarkan bukti kata sandi lokal agar LayarKunciScreen (saat luring)
      // langsung mengenali kata sandi baru yang baru saja disimpan di server.
      final uidAktif = Sesi.instance.userId.trim().isNotEmpty
          ? Sesi.instance.userId.trim()
          : (await VerifikatorSandiLokal.instance.usernameTersimpan() ?? '');
      if (uidAktif.isNotEmpty) {
        await VerifikatorSandiLokal.instance.simpan(uidAktif, sandiBaru);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password berhasil diganti.')),
      );
      _lamaController.clear();
      _baruController.clear();
      _konfirmasiController.clear();
    } catch (e) {
      if (!mounted) return;
      await tampilkanKesalahan(
        context,
        e is ApiException ? e.info : e,
        aktivitas: 'mengganti kata sandi',
      );
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
                        obscureText: !_lihatKonfirmasi,
                        suffixIcon: IconButton(
                          icon: Icon(_lihatKonfirmasi
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setStateIfMounted(
                              () => _lihatKonfirmasi = !_lihatKonfirmasi),
                        ),
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
