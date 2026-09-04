import 'package:flutter/material.dart';

import '../../features/apotik/clinical/apotik_pasien_page.dart';
import '../../widgets/app_shell.dart';

class PasienApotikScreen extends StatelessWidget {
  const PasienApotikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Pasien & Alergi',
      subjudul: 'Profil klinis SIRS, alergi aktif, dan riwayat diagnosis',
      scrollable: false,
      body: ApotikPasienPage(),
    );
  }
}
