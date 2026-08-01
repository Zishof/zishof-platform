import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_client.dart';
import '../sesi.dart';

/// Polling pesanan online baru (padanan pesanan-badge.js Electron) -- tiap 20
/// detik memanggil `pesanan_online_baru` dgn cursor `sejak_id` tersimpan lokal
/// (SharedPreferences, bukan cuma memori, supaya bertahan lintas restart app).
/// Polling PERTAMA kali (belum pernah ada baseline tersimpan) hanya mencatat
/// `maksId` saat itu tanpa menaikkan [jumlahBaru] -- kalau tidak, pesanan lama
/// yg sudah ada sebelum app dipasang akan "membanjiri" badge begitu instal baru.
/// Dijalankan sekali di seluruh app (KasirScreen.initState, layar induk stlh
/// login) dan TIDAK pernah dihentikan selama sesi berjalan -- badge harus
/// tetap terlihat di semua layar, bukan cuma saat berada di layar Pesanan.
class PesananPoller {
  PesananPoller._();
  static final PesananPoller instance = PesananPoller._();

  static const _kunciSejakId = 'pesanan_poller_sejak_id';

  final ValueNotifier<int> jumlahBaru = ValueNotifier<int>(0);
  Timer? _timer;

  void mulai() {
    if (_timer != null) return;
    _polling();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _polling());
  }

  void tandaiSudahDilihat() {
    jumlahBaru.value = 0;
  }

  Future<void> _polling() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final sudahAdaBaseline = sp.containsKey(_kunciSejakId);
      final sejakId = sp.getInt(_kunciSejakId) ?? 0;
      final hasil = await ApiClient.instance.aksi('pesanan_online_baru', {'id_toko': Sesi.instance.tokoId, 'sejak_id': sejakId});
      final pesanan = (hasil['pesanan'] as List?) ?? [];
      final maksId = (hasil['maksId'] as num?)?.toInt() ?? sejakId;
      await sp.setInt(_kunciSejakId, maksId);
      if (!sudahAdaBaseline) return;
      if (pesanan.isNotEmpty) {
        jumlahBaru.value += pesanan.length;
      }
    } catch (_) {
      // Offline/gagal -- coba lagi di siklus polling 20 detik berikutnya, bukan alasan crash.
    }
  }
}
