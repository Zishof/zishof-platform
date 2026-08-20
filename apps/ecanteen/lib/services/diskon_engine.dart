import '../models/aturan_diskon.dart';
import '../models/keranjang_item.dart';

/// Evaluasi aturan diskon di sisi klien.
///
/// Ini adalah PORT LANGSUNG dari `evaluateDiscount()` + `recalculateCart()`
/// pada _beranda_anggota.jsp. Urutannya sengaja dipertahankan supaya angka
/// yang dilihat member di aplikasi sama dgn yang dilihat di web:
///
///  1. Aturan dipindai berurutan; yang PERTAMA cocok yang dipakai (break).
///  2. Aturan produk/toko spesifik hanya berlaku utk produk/toko itu.
///  3. Rentang tanggal: mulai <= sekarang <= selesai (selesai s/d 23:59:59).
///  4. Bila bukan "berlaku semua member", jenis & tipe anggota harus cocok.
///  5. Persentase didahulukan; kalau nol baru nominal (nominal x jumlah,
///     dibatasi subtotal baris).
///  6. Aturan "berlaku per hari dan per toko" punya pagu harian: sisa =
///     maksimal - terpakai hari ini - terpakai di keranjang.
///  7. `potongan_langsung` menentukan hasilnya jadi diskon (potong harga)
///     atau cashback (dikembalikan sbg saldo/poin).
///
/// Nilai ini hanya pratinjau; server tetap menghitung ulang saat finalisasi.
class DiskonEngine {
  DiskonEngine._();

  /// Hitung ulang SELURUH keranjang. Akumulator per aturan direset dulu,
  /// kalau tidak pagu harian akan menyusut tiap kali layar digambar ulang.
  static void hitungUlang(
    List<KeranjangItem> keranjang,
    List<AturanDiskon> aturan, {
    required int? idJenisAnggota,
    required int? idTipeAnggota,
    DateTime? sekarang,
  }) {
    for (final a in aturan) {
      a.terpakaiDiKeranjang = 0;
    }
    for (final item in keranjang) {
      evaluasi(
        item,
        aturan,
        idJenisAnggota: idJenisAnggota,
        idTipeAnggota: idTipeAnggota,
        sekarang: sekarang,
      );
    }
  }

  static void evaluasi(
    KeranjangItem item,
    List<AturanDiskon> aturan, {
    required int? idJenisAnggota,
    required int? idTipeAnggota,
    DateTime? sekarang,
  }) {
    final now = sekarang ?? DateTime.now();
    AturanDiskon? terpilih;

    for (final rule in aturan) {
      if (rule.produk != null && rule.produk != item.id) continue;
      if (rule.toko != null && rule.toko != item.idToko) continue;

      if (rule.tanggalMulai != null && rule.tanggalMulai!.isAfter(now)) continue;
      if (rule.tanggalSelesai != null) {
        final batas = DateTime(
          rule.tanggalSelesai!.year,
          rule.tanggalSelesai!.month,
          rule.tanggalSelesai!.day,
          23,
          59,
          59,
          999,
        );
        if (batas.isBefore(now)) continue;
      }

      if (!rule.berlakuSemuaMember) {
        if (rule.jenisAnggota != null &&
            rule.jenisAnggota != '${idJenisAnggota ?? ''}') {
          continue;
        }
        if (rule.tipeAnggota != null &&
            rule.tipeAnggota != '${idTipeAnggota ?? ''}') {
          continue;
        }
      }

      if (rule.persentase <= 0 && rule.nominal <= 0) continue;

      terpilih = rule;
      break;
    }

    item.diskon = 0;
    item.cashback = 0;
    item.aturanDiskon = null;
    item.berlakuPerHariDanPerToko = false;
    if (terpilih == null) return;

    final subtotal = item.harga * item.jumlah;
    double nilai = 0;
    if (terpilih.persentase > 0) {
      nilai = subtotal * (terpilih.persentase / 100);
    } else if (terpilih.nominal > 0) {
      nilai = terpilih.nominal * item.jumlah;
      if (nilai > subtotal) nilai = subtotal;
    }

    final maks = terpilih.maksimalPotongan;
    if (terpilih.berlakuPerHariDanPerToko && maks > 0) {
      final sisa =
          maks - terpilih.terpakaiHariIni - terpilih.terpakaiDiKeranjang;
      if (sisa <= 0) {
        nilai = 0;
      } else if (nilai > sisa) {
        nilai = sisa;
      }
      terpilih.terpakaiDiKeranjang += nilai;
    } else if (maks > 0 && nilai > maks) {
      nilai = maks;
    }

    if (terpilih.potonganLangsung) {
      item.diskon = nilai;
    } else {
      item.cashback = nilai;
    }
    item.aturanDiskon = terpilih.id;
    item.berlakuPerHariDanPerToko = terpilih.berlakuPerHariDanPerToko;
  }
}
