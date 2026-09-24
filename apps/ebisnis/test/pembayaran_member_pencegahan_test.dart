import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/models.dart';
import 'package:ebisnis/services/pengaturan_pembayaran.dart';
import 'package:ebisnis/widgets/app_error_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tunai = CaraBayar(id: 1, nama: 'Tunai', manual: true);
  final voucher = CaraBayar(id: 2, nama: 'Voucher', manual: false);
  final aturan = PengaturanPembayaran.instance;

  test('refresh default Tunai tidak menimpa voucher pilihan kasir', () {
    expect(
        aturan.pilihSaatPenyegaran([tunai, voucher],
            idTerpilih: 2, idDefaultMember: 1, terkunci: false),
        same(voucher));
  });
  test('metode yang dicabut tidak diganti diam-diam menjadi Tunai', () {
    expect(
        aturan.pilihSaatPenyegaran([tunai],
            idTerpilih: 2, idDefaultMember: 1, terkunci: false),
        isNull);
  });
  test('refresh kedua setelah izin dicabut tetap menunggu pilihan kasir', () {
    expect(
        aturan.pilihSaatPenyegaran([tunai],
            idTerpilih: null,
            idDefaultMember: 1,
            terkunci: false,
            perluKonfirmasi: true),
        isNull);
  });
  test('kunci tipe member dan default awal tetap berlaku', () {
    expect(
        aturan.pilihSaatPenyegaran([tunai, voucher],
            idTerpilih: 1, idDefaultMember: 2, terkunci: true),
        same(voucher));
    expect(
        aturan.pilihSaatPenyegaran([tunai, voucher],
            idTerpilih: null, idDefaultMember: 2, terkunci: false),
        same(voucher));
    expect(
        aturan.pilihSaatPenyegaran([],
            idTerpilih: 1, idDefaultMember: 1, terkunci: true),
        isNull);
  });

  const penolakan = 'Metode pembayaran "Tunai" tidak diizinkan untuk member '
      '(Jenis Member: Biasa; Tipe Member: Siswa). '
      'Menaikkan Batas Transaksi atau Maksimal Boleh Utang tidak menyelesaikan penolakan izin ini.';
  test('penolakan izin yang menyebut utang tidak menjadi galat limit', () {
    final hasil = panduanResolusiGalat(penolakan);
    expect(hasil.judul, 'Metode pembayaran belum diizinkan untuk member');
    expect(hasil.solusi.join(' '), contains('bukti pembayaran asli'));
    expect(hasil.solusi.join(' '), contains('Riwayat Penjualan'));
    expect(panduanResolusiGalat('Batas maksimal hutang terlampaui').judul,
        'Batas hutang member terlampaui');
  });
  test('HTTP 200 error bisnis menampilkan petunjuk khusus, bukan retry generik',
      () {
    final hasil = ApiException(penolakan,
        aktivitas: 'bayar',
        statusHttp: 200,
        judul: 'Proses belum berhasil',
        solusi: const [
          'Muat ulang halaman dan periksa kembali data yang diisi.',
          'Coba sekali lagi setelah beberapa saat.',
          'Jika berulang, buka Detail Error lalu salin informasinya untuk admin/developer.',
        ]).info;
    expect(hasil.judul, 'Metode pembayaran belum diizinkan untuk member');
    expect(hasil.solusi.join(' '), contains('bukti pembayaran asli'));
    expect(hasil.solusi.join(' '), contains('Jangan input ulang'));
  });
}
