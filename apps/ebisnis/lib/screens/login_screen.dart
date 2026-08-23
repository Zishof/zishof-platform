import 'package:core_auth/core_auth.dart';
import 'package:flutter/material.dart';
import '../app_variant.dart';
import '../api_client.dart';
import '../product_profile.dart';
import '../theme/app_colors.dart';
import 'pengaturan_server_screen.dart';
import '../widgets/safe_state.dart';
import '../widgets/app_error_info.dart';
import '../widgets/app_version_label.dart';
import '../services/transaksi_outbox_service.dart';
import '../services/pengikatan_tenant.dart';
import '../widgets/pemilih_tenant.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _memproses = false;
  AppErrorInfo? _pesanError;

  Future<void> _login() async {
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
          'Nama pengguna dan kata sandi tidak boleh kosong.',
          aktivitas: 'login'));
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

      // Pengikatan tenant DIPERIKSA SEBELUM apa pun yang lain (P6/P7).
      //
      // Satu perangkat melayani satu tenant. Bila perangkat ini ternyata
      // memuat data usaha lain dan antreannya belum terkirim, login harus
      // BERHENTI di sini -- sebelum bukti kata sandi luring ditulis, sebelum
      // penyiram antrean dinyalakan, dan sebelum cache dimuat. Berhenti
      // setelahnya berarti perangkat sudah terlanjur menyimpan jejak identitas
      // baru padahal pemiliknya belum boleh masuk.
      var ikat = await PengikatanTenant.periksaSetelahLogin();

      if (ikat.keputusan == KeputusanPengikatan.pilihTenant) {
        final daftar = await PengikatanTenant.daftarTenant();
        if (!mounted) return;
        if (daftar.isEmpty) {
          // Server bilang harus memilih tetapi daftarnya kosong -- keadaan yang
          // tidak masuk akal. Jangan menebak; hentikan dengan jujur.
          await ApiClient.instance.hapusToken();
          setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
              'Daftar usaha tidak dapat dimuat. Coba lagi, atau hubungi admin.',
              aktivitas: 'login'));
          return;
        }
        final dipilih = await PemilihTenant.pilih(context, daftar);
        if (dipilih == null) {
          // Membatalkan pemilihan berarti membatalkan login: pengguna dengan
          // beberapa usaha tidak boleh masuk tanpa menyebut yang mana.
          await ApiClient.instance.hapusToken();
          setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
              'Anda belum memilih usaha, jadi belum masuk.',
              aktivitas: 'login'));
          return;
        }
        // Pilihan dikirim ulang ke server, yang tetap memvalidasi keanggotaan,
        // status, dan modulnya. Pilihan klien menyebut yang mana, bukan memberi
        // kewenangan.
        ikat = await PengikatanTenant.periksaSetelahLogin(
            tenantIdPilihan: dipilih);
      }

      if (!ikat.bolehLanjut) {
        await ApiClient.instance.hapusToken();
        setStateIfMounted(() => _pesanError = AppErrorInfo.dari(
            PengikatanTenant.pesan(ikat),
            aktivitas: 'login'));
        return;
      }
      await ApiClient.instance.simpanTenantId(ikat.tenantAktifId);

      // Bukti kata sandi disimpan HANYA sesudah server menerimanya, supaya
      // jalur luring tidak pernah lebih longgar daripada keputusan server.
      // Dipakai LayarKunciScreen saat sesi terkunci dan server tak terjangkau.
      await VerifikatorSandiLokal.instance
          .simpan(_userCtrl.text.trim(), _passCtrl.text);
      TransaksiOutboxService.instance.mulai();
      if (ikat.keputusan == KeputusanPengikatan.dialihkan && mounted) {
        // Bukan galat, tetapi pengguna berhak tahu kenapa datanya kosong.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PengikatanTenant.pesan(ikat))),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => AppProductProfile.aktif.buatLayarAwal()),
      );
    } catch (e) {
      setStateIfMounted(() => _pesanError = e is ApiException
          ? e.info
          : AppErrorInfo.dari(e, aktivitas: 'login'));
    } finally {
      if (mounted) setStateIfMounted(() => _memproses = false);
    }
  }

  /// Latar kartu Masuk & tombol "Masuk" -- BUKAN [AppColors.primary] (yang
  /// bisa diubah pengguna kapan saja lewat Konfigurasi) krn layar ini muncul
  /// SEBELUM identitas pengguna diketahui, jadi warnanya murni identitas
  /// VARIAN build, sama spt [AppVariant.logoAsset]/[AppVariant.judulLogin].
  static const _warnaLatar = AppVariant.isAlBahjah
      ? Color(0xFF14532D)
      : (AppVariant.isPetra ? Color(0xFF1565D8) : Color(0xFF1E3A5F));

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.gelap(context);
    final warnaJudul = isDark ? AppColors.darkTextPrimary : AppColors.sidebarBg;
    final warnaSubjudul = AppColors.textSecondaryOf(context);

    return Scaffold(
      backgroundColor: _warnaLatar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            label: 'Latar ${AppVariant.namaAplikasi}',
            image: true,
            child: Image.asset(
              AppVariant.loginBackgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) =>
                  const ColoredBox(color: _warnaLatar),
            ),
          ),
          // Lapisan tipis mempertahankan keterbacaan kartu pada layar kecil
          // ketika sisi gambar ikut terpotong oleh BoxFit.cover.
          ColoredBox(color: _warnaLatar.withValues(alpha: 0.18)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(builder: (context, kendala) {
                  // Dua kolom hanya bila varian memintanya DAN layar cukup
                  // lebar; di ponsel/jendela sempit tetap satu kolom supaya
                  // formulir tidak terhimpit.
                  final duaKolom =
                      AppVariant.loginDuaKolom && kendala.maxWidth >= 720;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: duaKolom ? 860 : 380),
                    child: Card(
                      elevation: 12,
                      shadowColor: Colors.black54,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: duaKolom
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                      flex: 5,
                                      child: _panelIdentitas(warnaSubjudul)),
                                  Expanded(
                                    flex: 6,
                                    child: Padding(
                                      padding: const EdgeInsets.all(32),
                                      child: _kolomFormulir(
                                          warnaJudul, warnaSubjudul,
                                          tampilkanLogo: false),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(28),
                              child: _kolomFormulir(warnaJudul, warnaSubjudul,
                                  tampilkanLogo: true),
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

  /// Kolom formulir Masuk. Dipakai apa adanya pada tata letak satu
  /// kolom, dan sebagai kolom kanan pada tata letak dua kolom (di sana
  /// logo dimatikan karena sudah tampil di panel identitas kiri).
  Widget _kolomFormulir(Color warnaJudul, Color warnaSubjudul,
      {required bool tampilkanLogo}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tampilkanLogo) ...[
          Image.asset(AppVariant.logoAsset, height: 64),
          const SizedBox(height: 12),
        ],
        Text(AppVariant.judulLogin,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: warnaJudul)),
        Text(AppVariant.subJudulLogin,
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
          AppErrorPanel(info: _pesanError!),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _memproses ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: _warnaLatar,
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PengaturanServerScreen())),
            child: const Text('Ubah Alamat Server'),
          ),
        ),
        const SizedBox(height: 2),
        AppVersionLabel(
          style: TextStyle(
            color: warnaSubjudul,
            fontSize: 12,
          ),
        ),
        // Kaki kartu khusus varian yang menyediakan teks hak cipta (Petra),
        // mengikuti tampilan versi web-nya.
        if (AppVariant.hakCiptaLogin.isNotEmpty) ...[
          const SizedBox(height: 14),
          Divider(color: warnaSubjudul.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 12),
          Text(
            AppVariant.hakCiptaLogin,
            textAlign: TextAlign.center,
            style: TextStyle(color: warnaSubjudul, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _warnaLatar.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _warnaLatar.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: _warnaLatar),
                  const SizedBox(width: 6),
                  Text('Sistem Informasi Terpadu & Terenkripsi',
                      style: TextStyle(color: _warnaLatar, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Panel identitas (kolom kiri) pada tata letak Masuk dua kolom: logo unit,
  /// nama organisasi, dan kotak kontak -- mengikuti versi web eKantin.
  Widget _panelIdentitas(Color warnaSubjudul) {
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
      color: _warnaLatar,
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
                  barisKontak(
                      Icons.location_on_outlined, AppVariant.alamatKontakLogin),
                  barisKontak(
                      Icons.phone_outlined, AppVariant.teleponKontakLogin),
                  barisKontak(Icons.mail_outline, AppVariant.emailKontakLogin),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
