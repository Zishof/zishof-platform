import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/indikator_sinkron_master.dart';
import 'diskon/tab_aturan_diskon.dart';
import 'diskon/tab_diskon_grup.dart';
import 'diskon/tab_pencairan_diskon.dart';
import 'diskon/tab_monitor_diskon.dart';

/// Layar Diskon -- 3 sub-tab (padanan JSP `kantin/diskon/*.jsp`: Aturan
/// Diskon + Pencairan Diskon, plus tab Monitor Diskon yang di sisi server
/// hidup di framework "new" terpisah/ZK `MonitorDiskonKantinAction`, tapi
/// di Flutter digabung jadi 1 layar konsisten dgn pola 9-tab Ringkasan).
/// Setiap tab StatefulWidget terpisah (lihat folder diskon/) yg memuat
/// datanya sendiri di initState.
class DiskonScreen extends StatefulWidget {
  const DiskonScreen({super.key});

  @override
  State<DiskonScreen> createState() => _DiskonScreenState();
}

class _DiskonScreenState extends State<DiskonScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.diskon,
      judul: 'Diskon & Promo',
      subjudul: 'Aturan diskon, pencairan cashback, dan monitor performa promo',
      scrollable: false,
      actionsAppBar: [
        const IndikatorSinkronMaster(),
        IconButton(
            icon: const Icon(Icons.refresh), onPressed: () => setState(() {}))
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.primary,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Aturan Diskon'),
              Tab(text: 'Diskon Grup'),
              Tab(text: 'Pencairan Diskon'),
              Tab(text: 'Monitor Diskon'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [
                TabAturanDiskon(),
                TabDiskonGrup(),
                TabPencairanDiskon(),
                TabMonitorDiskon(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
