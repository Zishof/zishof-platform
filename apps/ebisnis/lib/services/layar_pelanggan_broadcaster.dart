import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../api_client.dart';
import '../sesi.dart';

/// Menyiarkan isi keranjang aktif ke `layar_pelanggan_kirim` (spec §16) --
/// dipanggil dari KeranjangScreen setiap keranjang berubah. Debounce 400ms
/// (sama dgn spesifikasi Desktop) supaya tidak membanjiri server tiap ketukan
/// stepper qty.
///
/// CATATAN SCOPE: kontrak server (`layarPelangganKirim`/`layarPelangganAmbil`
/// di KantinHelper.java) hanya punya state "keranjang aktif" (items/subtotal/
/// diskon/total/memberNama) -- tidak ada sinyal "sukses"/"idle" eksplisit
/// terpisah, jadi layar sukses ~4 detik ala Desktop TIDAK direplikasi di sini
/// (butuh field baru di server, di luar scope gap-fill klien-saja). Layar
/// kedua otomatis kembali ke Idle sendiri lewat TTL 90 detik server begitu
/// kasir berhenti menyiarkan (mis. pindah layar/transaksi selesai).
class LayarPelangganBroadcaster {
  LayarPelangganBroadcaster._();
  static final LayarPelangganBroadcaster instance = LayarPelangganBroadcaster._();

  static const channel = WindowMethodChannel(
    'ebisnis/layar_pelanggan_live',
    mode: ChannelMode.unidirectional,
  );

  Timer? _debounce;
  int _versi = 0;

  void jadwalkanKirim({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double diskon,
    required double total,
    String? memberNama,
  }) {
    final payload = {
      'versi': ++_versi,
      'aktif': true,
      'toko_id': Sesi.instance.tokoId,
      'items': items,
      'subtotal': subtotal,
      'diskon': diskon,
      'total': total,
      'member_nama': memberNama ?? '',
      'memberNama': memberNama ?? '',
    };
    channel.invokeMethod('update', payload).catchError((_) => null);

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 100), () {
      ApiClient.instance.aksi('layar_pelanggan_kirim', payload).catchError((_) {
        // Gagal menyiarkan (mis. offline) -- bukan alasan mengganggu kasir,
        // layar pelanggan sekadar tak ikut termutakhirkan sesaat.
        return <String, dynamic>{};
      });
    });
  }

  void berhenti() {
    _debounce?.cancel();
  }
}
