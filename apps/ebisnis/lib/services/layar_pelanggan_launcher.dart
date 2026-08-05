import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/layar_pelanggan_screen.dart';
import 'layar_kedua.dart';

/// Satu pintu untuk membuka Layar Pelanggan.
///
/// Di Windows tombol/menu ini bekerja sebagai toggle: klik pertama membuka
/// jendela customer display borderless fullscreen di monitor kedua, klik
/// berikutnya menutup jendela itu. Di platform lain tetap masuk lewat Navigator
/// seperti fallback lama di Kasir.
Future<void> bukaLayarPelanggan(BuildContext context) async {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    try {
      await toggleLayarPelangganJendelaKedua();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka Layar Pelanggan: $e')),
        );
      }
    }
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const LayarPelangganScreen()),
  );
}
