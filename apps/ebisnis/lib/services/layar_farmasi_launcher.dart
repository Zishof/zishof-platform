import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/apotik/layar_antrean_farmasi_screen.dart';
import 'layar_kedua.dart';

/// Memilih isi dan monitor tujuan. Tombol dapat ditekan berulang kali sehingga
/// satu instalasi dapat membuka sebanyak mungkin layar farmasi yang diperlukan.
Future<void> pilihDanBukaLayarFarmasi(BuildContext context) async {
  var mode = ModeLayarFarmasi.semua;
  var monitor = 1;
  var jumlahMonitor = 1;
  if (defaultTargetPlatform == TargetPlatform.windows) {
    try {
      jumlahMonitor = await jumlahMonitorTersedia();
      if (jumlahMonitor <= 1) monitor = 0;
    } catch (_) {}
  }
  if (!context.mounted) return;
  final pilihan = await showDialog<(ModeLayarFarmasi, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
              title: const Text('Buka Layar Farmasi'),
              content: SizedBox(
                width: 430,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Setiap kali tombol ini digunakan, aplikasi membuka jendela baru. Anda dapat membuka layar gabungan, khusus obat jadi, atau khusus racikan pada monitor berbeda.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ModeLayarFarmasi>(
                    value: mode,
                    decoration: const InputDecoration(
                        labelText: 'Konten layar',
                        border: OutlineInputBorder()),
                    items: ModeLayarFarmasi.values
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m.label)))
                        .toList(),
                    onChanged: (v) => setLocal(() => mode = v!),
                  ),
                  if (defaultTargetPlatform == TargetPlatform.windows) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: monitor,
                      decoration: const InputDecoration(
                          labelText: 'Monitor tujuan',
                          border: OutlineInputBorder()),
                      items: List.generate(
                          jumlahMonitor,
                          (i) => DropdownMenuItem(
                              value: i,
                              child: Text(i == 0
                                  ? 'Monitor 1 (utama)'
                                  : 'Monitor ${i + 1}'))),
                      onChanged: (v) => setLocal(() => monitor = v!),
                    ),
                  ],
                ]),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Batal')),
                FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, (mode, monitor)),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Buka Layar')),
              ],
            )),
  );
  if (pilihan == null || !context.mounted) return;

  if (defaultTargetPlatform == TargetPlatform.windows) {
    try {
      await bukaLayarFarmasiJendelaBaru(
          mode: pilihan.$1.kode, monitorIndex: pilihan.$2);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal membuka layar farmasi: $e')));
      }
    }
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LayarAntreanFarmasiScreen(mode: pilihan.$1)));
}
