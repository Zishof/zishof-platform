import 'dart:convert';
import 'dart:typed_data';

/// Satu baris struk sebagaimana dicetak.
class BarisStruk {
  final String nama;
  final double qty;
  final double harga;
  const BarisStruk(
      {required this.nama, required this.qty, required this.harga});
  double get subtotal => qty * harga;
}

/// Data yang dibutuhkan untuk mencetak struk apotik.
class DataStruk {
  final String namaApotek;
  final String alamat;
  final String telepon;
  final String kodeTransaksi;
  final DateTime waktu;
  final String kasir;
  final List<BarisStruk> baris;
  final double total;
  final String metode;

  /// Uang diterima & kembalian: dihitung di kasir, TIDAK dibukukan server.
  /// Dicetak hanya bila memang ada (pembayaran tunai).
  final double tunai;
  final double kembalian;
  final String referensi;
  final String catatanKaki;

  /// Ditandai saat struk dicetak ulang, supaya lembar kedua tidak dapat
  /// disalahartikan sebagai transaksi kedua.
  final bool cetakUlang;

  const DataStruk({
    required this.kodeTransaksi,
    required this.waktu,
    required this.baris,
    required this.total,
    this.namaApotek = '',
    this.alamat = '',
    this.telepon = '',
    this.kasir = '',
    this.metode = '',
    this.tunai = 0,
    this.kembalian = 0,
    this.referensi = '',
    this.catatanKaki = '',
    this.cetakUlang = false,
  });
}

/// <h3>Struk apotik sebagai teks polos (Fase 6 — perangkat).</h3>
///
/// Dibangun sebagai **fungsi murni** supaya isi struk dapat diuji tanpa
/// printer, lalu dikirim sebagai byte ESC/POS lewat `core_hw.cetakRawKasir`
/// (jalur RAW yang sama dengan Buka Laci, sehingga driver tidak mengubah roll
/// termal menjadi A4).
///
/// **Batas jujur.** Ini murni cetakan LOKAL. Server belum punya endpoint
/// riwayat cetak maupun bukti digital (IR-08), jadi struk ini tidak
/// meninggalkan jejak apa pun di server dan layar tidak mengklaim sebaliknya.
/// Penanda `CETAK ULANG` pun hanya jujur di mesin ini.
class ApotikStrukTeks {
  ApotikStrukTeks._();

  /// Lebar kolom untuk lebar kertas dalam mm (58 mm ≈ 32 kolom pada font A).
  static int kolomUntukKertas(double lebarMm) {
    if (lebarMm <= 58) return 32;
    if (lebarMm <= 72) return 42;
    return 48;
  }

  /// Susun seluruh baris struk. Angka dirapatkan ke kanan supaya kolom total
  /// tetap lurus pada printer monospace.
  static List<String> susun(DataStruk d, {int kolom = 32}) {
    final l = <String>[];
    void tengah(String s) {
      if (s.isEmpty) return;
      for (final potong in _bungkus(s, kolom)) {
        final sisa = kolom - potong.length;
        l.add(sisa <= 0 ? potong : ' ' * (sisa ~/ 2) + potong);
      }
    }

    void kiriKanan(String kiri, String kanan) {
      final sisa = kolom - kanan.length;
      if (sisa <= 1) {
        l.add(kanan);
        return;
      }
      final kiriPotong =
          kiri.length > sisa - 1 ? kiri.substring(0, sisa - 1) : kiri;
      l.add(kiriPotong.padRight(sisa) + kanan);
    }

    tengah(d.namaApotek.isEmpty ? 'APOTEK' : d.namaApotek.toUpperCase());
    tengah(d.alamat);
    tengah(d.telepon);
    l.add('-' * kolom);
    if (d.cetakUlang) {
      tengah('** CETAK ULANG **');
      l.add('-' * kolom);
    }
    kiriKanan('No', d.kodeTransaksi);
    kiriKanan('Tanggal', _waktu(d.waktu));
    if (d.kasir.isNotEmpty) kiriKanan('Kasir', d.kasir);
    l.add('-' * kolom);

    for (final b in d.baris) {
      for (final potong in _bungkus(b.nama, kolom)) {
        l.add(potong);
      }
      final kiri = '  ${_angka(b.qty)} x ${_angka(b.harga)}';
      kiriKanan(kiri, _angka(b.subtotal));
    }

    l.add('-' * kolom);
    kiriKanan('TOTAL', _angka(d.total));
    if (d.metode.isNotEmpty) kiriKanan('Metode', d.metode);
    // Uang diterima/kembalian hanya dicetak bila pembayaran tunai; keduanya
    // memang tidak pernah dikirim ke server.
    if (d.tunai > 0) {
      kiriKanan('Tunai', _angka(d.tunai));
      kiriKanan('Kembali', _angka(d.kembalian));
    }
    if (d.referensi.isNotEmpty) kiriKanan('Ref', d.referensi);
    l.add('-' * kolom);
    tengah(d.catatanKaki.isEmpty
        ? 'Terima kasih, semoga lekas sembuh'
        : d.catatanKaki);
    tengah('Obat keras hanya dengan resep dokter');
    return l;
  }

  /// Bungkus teks struk menjadi byte ESC/POS: reset, isi, umpan kertas,
  /// lalu potong. Pemanggil tinggal menyerahkannya ke `cetakRawKasir`.
  static Uint8List keEscPos(List<String> baris) {
    final b = BytesBuilder();
    b.add(const [0x1B, 0x40]); // ESC @ — reset printer
    b.add(latin1.encode('${baris.join('\n')}\n'));
    b.add(const [0x0A, 0x0A, 0x0A]); // umpan sebelum potong
    b.add(const [0x1D, 0x56, 0x42, 0x00]); // GS V B 0 — potong sebagian
    return b.toBytes();
  }

  static List<String> _bungkus(String s, int kolom) {
    if (s.length <= kolom) return [s];
    final hasil = <String>[];
    var sisa = s;
    while (sisa.length > kolom) {
      hasil.add(sisa.substring(0, kolom));
      sisa = sisa.substring(kolom);
    }
    if (sisa.isNotEmpty) hasil.add(sisa);
    return hasil;
  }

  static String _angka(double v) {
    final bulat = v.round();
    final s = bulat.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return (bulat < 0 ? '-' : '') + buf.toString();
  }

  static String _dua(int v) => v.toString().padLeft(2, '0');

  static String _waktu(DateTime d) =>
      '${_dua(d.day)}/${_dua(d.month)}/${d.year} ${_dua(d.hour)}:${_dua(d.minute)}';
}
