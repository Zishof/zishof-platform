import 'package:flutter/material.dart';

import '../../features/apotik/inventory/apotik_inventory_intelligence_page.dart';
import '../../widgets/app_shell.dart';
import '../mutasi_antar_outlet_screen.dart';
import 'persediaan_apotik_screen.dart';

class InventoryIntelligenceApotikScreen extends StatelessWidget {
  final int tabAwal;

  const InventoryIntelligenceApotikScreen({super.key, this.tabAwal = 0});

  void _buka(BuildContext context, Widget tujuan) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => tujuan));
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.manajemenFarmasiApotik,
      judul: 'Kendali Persediaan Farmasi',
      subjudul: 'Recall, cold-chain, lokasi, transfer, dan perencanaan stok',
      scrollable: false,
      body: ApotikInventoryIntelligencePage(
        tabAwal: tabAwal,
        bukaMonitorBatch: () =>
            _buka(context, const PersediaanApotikScreen(tabAwal: 1)),
        bukaTransfer: () => _buka(context, const MutasiAntarOutletScreen()),
        bukaPengadaan: () =>
            _buka(context, const PersediaanApotikScreen(tabAwal: 2)),
      ),
    );
  }
}
