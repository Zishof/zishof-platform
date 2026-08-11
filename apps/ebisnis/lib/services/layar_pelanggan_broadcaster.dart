import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../api_client.dart';
import '../sesi.dart';

/// Menyiarkan isi keranjang aktif ke `layar_pelanggan_kirim` (spec §16) --
/// dipanggil dari KeranjangScreen setiap keranjang berubah. Debounce 400ms
/// (sama dgn spesifikasi Desktop) supaya tidak membanjiri server tiap ketukan
/// stepper qty.
///
/// CATATAN "Survey Kepuasan Pelanggan": kontrak server
/// (`layarPelangganKirim`/`layarPelangganAmbil` di KantinHelper.java) sekarang
/// punya field opsional `tipe` ("keranjang" default, atau "sukses") --
/// [kirimSukses] memakainya utk memberi tahu Layar Pelanggan (arsitektur
/// polling 2-perangkat, BEDA dgn Layar Pelanggan Electron yang push langsung
/// antar-window lewat IPC lokal tanpa lewat server) bahwa transaksi baru saja
/// SUKSES, supaya layar kedua pindah dari tampilan keranjang ke layar ucapan
/// terima kasih + rating (lihat LayarPelangganScreen). Broadcast biasa (lewat
/// [jadwalkanKirim]) TIDAK mengirim `tipe` sama sekali -- server sendiri yang
/// default ke "keranjang" saat field itu tak ada.
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

  /// Siarkan SATU broadcast "transaksi baru saja SUKSES" (`tipe: 'sukses'`) --
  /// dipanggil SEKALI dari KeranjangScreen._bayar() tepat setelah checkout
  /// dianggap selesai (offline-first: sudah dianggap sukses begitu tersimpan
  /// lokal, sama dgn alur menuju StrukScreen), MENGGANTIKAN broadcast
  /// keranjang-kosong biasa di titik itu -- sekaligus mengosongkan tampilan
  /// keranjang di Layar Pelanggan DAN memberi sinyal pindah ke layar rating.
  /// Langsung dikirim (tanpa debounce) krn ini kejadian sekali-jalan, bukan
  /// mutasi keranjang beruntun spt [jadwalkanKirim].
  void kirimSukses() {
    _debounce?.cancel();
    final payload = {
      'versi': ++_versi,
      'aktif': true,
      'toko_id': Sesi.instance.tokoId,
      'items': const [],
      'subtotal': 0,
      'diskon': 0,
      'total': 0,
      'member_nama': '',
      'memberNama': '',
      'tipe': 'sukses',
    };
    channel.invokeMethod('update', payload).catchError((_) => null);
    ApiClient.instance.aksi('layar_pelanggan_kirim', payload).catchError((_) {
      // Gagal menyiarkan (mis. offline) -- bukan alasan mengganggu kasir,
      // layar pelanggan sekadar tak ikut menampilkan layar rating kali ini.
      return <String, dynamic>{};
    });
  }
}
