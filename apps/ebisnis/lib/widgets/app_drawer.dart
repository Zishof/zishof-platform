import 'package:flutter/material.dart';
import '../sesi.dart';
import '../screens/produk_screen.dart';
import '../screens/anggota_screen.dart';
import '../screens/pesanan_screen.dart';
import '../screens/stok_opname_screen.dart';
import '../screens/laporan_transaksi_screen.dart';
import '../screens/ringkasan_screen.dart';
import '../screens/diskon_screen.dart';
import '../screens/kulakan_screen.dart';
import '../screens/konfigurasi_screen.dart';
import '../screens/log_error_screen.dart';
import '../screens/riwayat_sinkronisasi_screen.dart';

/// Menu navigasi utama -- padanan sidebar kiri versi Electron (Kasir/Ringkasan/
/// Pesanan/Customer-Anggota/Produk/Stok Opname/Kulakan/Aturan Diskon/Laporan
/// Transaksi/Laporan-Laporan/Riwayat Sinkronisasi/Log Error/Konfigurasi).
/// Layar yang belum dibangun ditandai "Segera Hadir" (dinonaktifkan) -- lihat
/// task #182-189 utk urutan pengerjaan, jangan hapus entrinya supaya progres
/// tetap terlihat sambil layar-layar itu menyusul satu per satu.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1E3A5F)),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  Sesi.instance.tokoNama.isEmpty ? 'eBisnis' : Sesi.instance.tokoNama,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _ItemMenu(icon: Icons.point_of_sale, label: 'Kasir', aktif: true, onTap: () => Navigator.of(context).pop()),
                  _ItemMenu(
                    icon: Icons.bar_chart,
                    label: 'Ringkasan',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RingkasanScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.receipt_long,
                    label: 'Pesanan',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PesananScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.people_outline,
                    label: 'Customer/Anggota',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AnggotaScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.inventory_2_outlined,
                    label: 'Produk',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProdukScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.fact_check_outlined,
                    label: 'Stok Opname',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StokOpnameScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.local_shipping_outlined,
                    label: 'Kulakan',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KulakanScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.sell_outlined,
                    label: 'Aturan Diskon',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiskonScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.assessment_outlined,
                    label: 'Laporan Transaksi',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LaporanTransaksiScreen()));
                    },
                  ),
                  _ItemMenu(icon: Icons.folder_outlined, label: 'Laporan-Laporan', segeraHadir: true),
                  _ItemMenu(
                    icon: Icons.sync,
                    label: 'Riwayat Sinkronisasi',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RiwayatSinkronisasiScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.error_outline,
                    label: 'Log Error',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogErrorScreen()));
                    },
                  ),
                  _ItemMenu(
                    icon: Icons.settings_outlined,
                    label: 'Konfigurasi',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KonfigurasiScreen()));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool aktif;
  final bool segeraHadir;
  final VoidCallback? onTap;
  const _ItemMenu({required this.icon, required this.label, this.aktif = false, this.segeraHadir = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: segeraHadir ? Colors.black26 : (aktif ? const Color(0xFF1E3A5F) : Colors.black87)),
      title: Text(label, style: TextStyle(color: segeraHadir ? Colors.black26 : Colors.black87)),
      trailing: segeraHadir
          ? const Text('Segera Hadir', style: TextStyle(fontSize: 11, color: Colors.black26, fontStyle: FontStyle.italic))
          : null,
      selected: aktif,
      onTap: segeraHadir
          ? () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$label sedang dikerjakan, menyusul di rilis berikutnya.')))
          : onTap,
    );
  }
}
