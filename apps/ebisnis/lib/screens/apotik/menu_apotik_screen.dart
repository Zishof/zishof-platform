import 'package:flutter/material.dart';

import '../../features/apotik/pos/apotik_pos_page.dart';
import '../../features/apotik/pos/apotik_pos_state.dart';
import '../../features/apotik/prescription/apotik_resep_page.dart';
import '../../widgets/app_shell.dart';
import 'pos_help.dart';

/// Halaman langsung untuk antrean/tebus resep.
///
/// Sebelumnya fungsi ini hanya dapat dicapai dari Dashboard Apotik atau tombol
/// di dalam Kasir. Pembungkus ini membuat hak `apotik_resep` mempunyai tujuan
/// sidebar sendiri tanpa menduplikasi implementasi resep.
class TebusResepApotikScreen extends StatelessWidget {
  const TebusResepApotikScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.tebusResepApotik,
      judul: 'Tebus Resep Dokter',
      subjudul:
          'Telaah, daftar periksa pra-serah, pemeriksaan kedua, dan konseling',
      scrollable: false,
      actionsAppBar: [
        PosHelp.button(context, 'apotik_resep', compact: true),
      ],
      body: const ApotikResepPage(),
    );
  }
}

/// Pintu langsung ke mode Racikan pada ruang kerja kasir yang sama.
///
/// Controller dibuat sekali per lifecycle agar perubahan keranjang tidak
/// hilang ketika shell melakukan rebuild.
class RacikanApotikScreen extends StatefulWidget {
  const RacikanApotikScreen({super.key});

  @override
  State<RacikanApotikScreen> createState() => _RacikanApotikScreenState();
}

class _RacikanApotikScreenState extends State<RacikanApotikScreen> {
  late final ApotikPosController _controller = ApotikPosController()
    ..mode = ApotikModePos.racikan;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.racikanApotik,
      judul: 'Racikan',
      subjudul: 'Penyiapan dan penjualan obat racikan',
      scrollable: false,
      actionsAppBar: [
        PosHelp.button(context, 'apotik_racikan', compact: true),
      ],
      body: ApotikPosPage(controller: _controller),
    );
  }
}

/// Pintu langsung ke produksi farmasi berbasis formula/BOM SIRS.
class ProduksiFarmasiApotikScreen extends StatefulWidget {
  const ProduksiFarmasiApotikScreen({super.key});

  @override
  State<ProduksiFarmasiApotikScreen> createState() =>
      _ProduksiFarmasiApotikScreenState();
}

class _ProduksiFarmasiApotikScreenState
    extends State<ProduksiFarmasiApotikScreen> {
  late final ApotikPosController _controller = ApotikPosController()
    ..mode = ApotikModePos.produksi;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      menuAktif: MenuEBisnis.produksiFarmasiApotik,
      judul: 'Produksi Farmasi',
      subjudul: 'Formula produksi, konsumsi bahan, batch hasil, dan stok',
      scrollable: false,
      actionsAppBar: [
        PosHelp.button(context, 'apotik_racikan', compact: true),
      ],
      body: ApotikPosPage(controller: _controller),
    );
  }
}
