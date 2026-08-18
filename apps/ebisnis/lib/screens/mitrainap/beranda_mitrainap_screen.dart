import 'package:flutter/material.dart';

import '../../sesi.dart';
import '../../widgets/app_shell.dart';
import 'kamar_hotel_screen.dart';
import 'properti_hotel_screen.dart';
import 'reservasi_hotel_screen.dart';
import 'resepsionis_hotel_screen.dart';

/// Beranda varian "MitraInap" -- landing setelah login (MVP LANGKAH 3).
///
/// Sengaja TANPA panggilan API: kartu menu dirender fail-closed dari
/// `aksesMenu` server ([Sesi.bolehMenuVarianBaru]) sehingga role tanpa kunci
/// hotel_* melihat kuncinya terkunci, bukan galat request yang ditolak
/// PosApi. Admin global selalu boleh (provisioning/diagnostik).
class BerandaMitraInapScreen extends StatelessWidget {
  const BerandaMitraInapScreen({super.key});

  static const _menuHotel = <(String, String, String, IconData)>[
    (
      'hotel_properti',
      'Properti Hotel',
      'Data properti/penginapan yang dikelola akun ini',
      Icons.apartment_outlined
    ),
    (
      'hotel_kamar',
      'Kamar & Tipe Kamar',
      'Tipe kamar, harga dasar, dan kamar fisik per properti',
      Icons.meeting_room_outlined
    ),
    (
      'hotel_reservasi',
      'Tamu & Reservasi',
      'Booking kamar, data tamu, pembatalan',
      Icons.event_available_outlined
    ),
    (
      'hotel_checkin',
      'Check-in / Check-out',
      'Tamu in-house, folio, pembayaran, pindah kamar',
      Icons.luggage_outlined
    ),
  ];

  bool _boleh(String kunci) {
    final s = Sesi.instance;
    if (s.isAdmin) return true;
    if (kunci == 'hotel_checkin') {
      return s.bolehMenuVarianBaru('hotel_checkin') ||
          s.bolehMenuVarianBaru('hotel_folio');
    }
    return s.bolehMenuVarianBaru(kunci);
  }

  Widget _bangunTujuan(String kunci) {
    switch (kunci) {
      case 'hotel_properti':
        return const PropertiHotelScreen();
      case 'hotel_kamar':
        return const KamarHotelScreen();
      case 'hotel_reservasi':
        return const ReservasiHotelScreen();
      default:
        return const ResepsionisHotelScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final adaMenu = _menuHotel.any((m) => _boleh(m.$1));
    return AppShell(
      menuAktif: MenuEBisnis.berandaMitraInap,
      judul: 'Dashboard MitraInap',
      subjudul: 'Properti, kamar, reservasi, dan resepsionis (front desk)',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!adaMenu)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Akun ini belum diberi menu MitraInap oleh admin (Grup '
                    'Pengguna). Menu hotel fail-closed: kunci yang belum '
                    'diaktifkan tidak pernah terbuka sendiri.'),
              ),
            ),
          ..._menuHotel.map((m) {
            final boleh = _boleh(m.$1);
            return Card(
              child: ListTile(
                leading: Icon(m.$4,
                    color: boleh
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).disabledColor),
                title: Text(m.$2),
                subtitle: Text(boleh ? m.$3 : 'Tidak diberi akses (${m.$1})'),
                trailing: boleh
                    ? const Icon(Icons.chevron_right)
                    : const Icon(Icons.lock_outline),
                enabled: boleh,
                onTap: boleh
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _bangunTujuan(m.$1)))
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }
}
