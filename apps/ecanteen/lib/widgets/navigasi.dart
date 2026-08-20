import 'package:flutter/material.dart';

import '../screens/bayar_qr_screen.dart';
import '../screens/beranda_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/keranjang_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/topup_screen.dart';
import '../screens/transaksi_screen.dart';
import 'app_shell.dart';

/// Perpindahan antar menu cangkang.
///
/// Memakai `pushReplacement` supaya sidebar berperilaku seperti tab: menekan
/// menu tidak menumpuk halaman, dan tombol kembali tidak menelusuri riwayat
/// menu yang panjang.
void navigasiMenu(BuildContext context, MenuAnggota menu) {
  final sekarang = ModalRoute.of(context)?.settings.name;
  final nama = 'menu-${menu.name}';
  if (sekarang == nama) return;

  Widget bangun() {
    switch (menu) {
      case MenuAnggota.belanja:
        return const BerandaScreen();
      case MenuAnggota.keranjang:
        return const KeranjangScreen();
      case MenuAnggota.pesanan:
        return const PesananScreen();
      case MenuAnggota.riwayat:
        return const TransaksiScreen();
      case MenuAnggota.isiSaldo:
        return const TopupScreen();
      case MenuAnggota.bayarQr:
        return const BayarQrScreen();
      case MenuAnggota.ringkasan:
        return const DashboardScreen();
    }
  }

  Navigator.of(context).pushReplacement(MaterialPageRoute(
    settings: RouteSettings(name: nama),
    builder: (_) => bangun(),
  ));
}
