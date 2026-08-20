import 'dart:math';

import '../models/keranjang_item.dart';
import 'api_client.dart';
import 'keranjang.dart';
import 'sesi.dart';

/// Hasil upaya checkout.
class HasilCheckout {
  final bool berhasil;
  final bool manual;
  final double total;
  final String? pesanGagal;
  final int tokoBerhasil;
  final int tokoTotal;

  HasilCheckout({
    required this.berhasil,
    required this.manual,
    required this.total,
    required this.tokoBerhasil,
    required this.tokoTotal,
    this.pesanGagal,
  });
}

/// Alasan checkout ditolak SEBELUM menyentuh server.
class CheckoutDitolak implements Exception {
  final String pesan;
  CheckoutDitolak(this.pesan);
  @override
  String toString() => pesan;
}

/// Proses checkout, mengikuti `initiateCheckout()` versi JSP.
class CheckoutService {
  CheckoutService._();

  static final _acak = Random();

  /// Kode unik transaksi. Versi JSP memakai awalan "ONL-"; dipertahankan
  /// supaya transaksi dari aplikasi tetap dikenali sbg kanal online.
  static String kodeUnik() {
    const huruf = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buf = StringBuffer('ONL-');
    buf.write(DateTime.now().millisecondsSinceEpoch.toString());
    buf.write('-');
    for (var i = 0; i < 8; i++) {
      buf.write(huruf[_acak.nextInt(huruf.length)]);
    }
    return buf.toString();
  }

  static String waktuSekarang() {
    final n = DateTime.now();
    String dua(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${dua(n.month)}-${dua(n.day)} '
        '${dua(n.hour)}:${dua(n.minute)}:${dua(n.second)}';
  }

  /// Validasi yang dilakukan versi JSP sebelum mengirim apa pun ke server.
  ///
  /// [saldoTerkini] harus diambil ulang dari server tepat sebelum memanggil
  /// ini -- JSP pun menyegarkan saldo dulu supaya tidak memakai angka basi.
  static void validasi({
    required Keranjang keranjang,
    required bool caraBayarManual,
    required int saldoTerkini,
  }) {
    if (keranjang.items.isEmpty) {
      throw CheckoutDitolak(
          'Keranjang belanja masih kosong. Silakan tambah produk terlebih dahulu.');
    }

    if (!caraBayarManual) {
      if (saldoTerkini < keranjang.grandTotal) {
        throw CheckoutDitolak(
            'Saldo Anda tidak mencukupi untuk transaksi ini. '
            'Silakan isi ulang saldo terlebih dahulu.');
      }
      final sisa = saldoTerkini - keranjang.grandTotal;
      if (sisa < Sesi.instance.minimalSaldo) {
        throw CheckoutDitolak(
            'Transaksi gagal. Sisa saldo setelah transaksi kurang dari batas '
            'saldo mengendap yang diizinkan.');
      }
    }

    if (Sesi.instance.aktifkanPilihanMeja) {
      if (!keranjang.bawaPulang && keranjang.idMeja == null) {
        throw CheckoutDitolak(
            'Silakan scan QR meja tempat Anda berada, atau pilih Bawa Pulang.');
      }
    }
  }

  /// Kirim satu transaksi per toko. Berhenti pada kegagalan pertama, sama
  /// seperti versi JSP -- toko yang sudah berhasil TIDAK dibatalkan, jadi
  /// jumlahnya dilaporkan agar pengguna tahu keadaan sebenarnya.
  static Future<HasilCheckout> kirim({
    required Keranjang keranjang,
    required String idCaraBayar,
    required bool manual,
    String keterangan = '',
  }) async {
    final kelompok = keranjang.kelompokPerToko();
    final total = keranjang.grandTotal;
    var berhasilToko = 0;

    for (final entri in kelompok.entries) {
      final idToko = entri.key;
      final List<KeranjangItem> isi = entri.value;

      double sub = 0;
      double disc = 0;
      for (final it in isi) {
        sub += it.harga * it.jumlah;
        disc += it.diskon;
      }
      if (sub - disc < 0) continue;

      final payload = <String, dynamic>{
        'kodeUnik': kodeUnik(),
        'idToko': idToko,
        'waktu': waktuSekarang(),
        'kanalCheckout': 'anggota_online',
        'caraBayar': idCaraBayar,
        'keterangan': keterangan,
        'transaksi': isi.map((e) => e.keJsonTransaksi()).toList(),
      };
      if (Sesi.instance.aktifkanPilihanMeja &&
          !keranjang.bawaPulang &&
          keranjang.idMeja != null) {
        payload['mejaKantin'] = keranjang.idMeja;
      }

      try {
        await ApiClient.instance
            .aksi(manual ? 'kantin_draft_bayar' : 'kantin_bayar', payload);
        berhasilToko++;
      } on ApiException catch (e) {
        return HasilCheckout(
          berhasil: false,
          manual: manual,
          total: total,
          tokoBerhasil: berhasilToko,
          tokoTotal: kelompok.length,
          pesanGagal: e.pesan,
        );
      }
    }

    return HasilCheckout(
      berhasil: true,
      manual: manual,
      total: total,
      tokoBerhasil: berhasilToko,
      tokoTotal: kelompok.length,
    );
  }
}
