import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../services/dynamic_report.dart';

/// Stok per tanggal + bahan ekspor untuk layar Produk.
///
/// Sumbernya laporan server `stok_per_tanggal`, BUKAN perhitungan baru di
/// klien. Rumus laporan itu mencerminkan persis `StokKantinUtil.formulaStokSql`
/// (7 suku: pengadaan, selisih opname, pembelian, pemakaian bahan baku, retur
/// penjualan yang dikembalikan ke stok, mutasi masuk/keluar antar toko, dan
/// retur pembelian) dengan tambahan batas tanggal per tabel sumber. Karena itu
/// memilih tanggal HARI INI menghasilkan angka yang sama dengan kolom Stok
/// biasa -- laporan ini rekonsiliasi, bukan rumus tandingan.
///
/// Menghitung ulang di klien akan menciptakan sumber kebenaran kedua yang
/// pasti menyimpang begitu salah satu sisi berubah; itu sebabnya jalur ini
/// memanggil server.
class StokPerTanggal {
  StokPerTanggal._();

  static final _fmtTgl = DateFormat('yyyy-MM-dd');

  /// Ambil stok per tanggal beserta baris laporannya.
  ///
  /// [tanggal] null berarti stok terkini (server memakai batas hari ini).
  /// [kataKunci] diteruskan sebagai `qProduk` supaya hasil ekspor SAMA dengan
  /// yang tersaring di layar.
  /// Kunci cache dibentuk dari SELURUH parameter yang memengaruhi hasil,
  /// supaya kombinasi tanggal + kata kunci yang berbeda tidak saling menimpa.
  static String _kunciCache(DateTime? tanggal, String kataKunci) =>
      'laporan:stok_per_tanggal'
      ':${tanggal == null ? "terkini" : _fmtTgl.format(tanggal)}'
      ':${kataKunci.trim().isEmpty ? "-" : kataKunci.trim().toLowerCase()}';

  static Future<HasilStokTanggal> ambil({
    DateTime? tanggal,
    String kataKunci = '',
  }) async {
    final payload = <String, dynamic>{
      'r': 'stok_per_tanggal',
      if (tanggal != null) 'tglSampai': _fmtTgl.format(tanggal),
      if (kataKunci.trim().isNotEmpty) 'qProduk': kataKunci.trim(),
    };
    final kunci = _kunciCache(tanggal, kataKunci);

    Map<String, dynamic> hasil;
    var dariCache = false;
    DateTime? disimpanPada;
    try {
      hasil = await ApiClient.instance.aksi('laporan_jalankan', payload);
      // Simpan salinan supaya filter tanggal & ekspor tetap bisa dipakai saat
      // jaringan putus. Stempel waktu ikut disimpan DI DALAM amplop agar
      // pemuatan berikutnya bisa memberi tahu KAPAN salinan ini dibuat.
      await CoreDb.instance.simpanCacheReferensi(
          kunci,
          jsonEncode({
            ...hasil,
            '_disimpanPada': DateTime.now().toIso8601String(),
          }));
    } on ApiException catch (e) {
      // Hanya gangguan jaringan yang boleh jatuh ke salinan. Penolakan server
      // (mis. hak akses) TIDAK disamarkan jadi data lama -- itu akan menutupi
      // masalah sebenarnya.
      final tersimpan =
          e.offline ? await CoreDb.instance.ambilCacheReferensi(kunci) : null;
      if (tersimpan == null) rethrow;
      hasil = jsonDecode(tersimpan) as Map<String, dynamic>;
      dariCache = true;
      disimpanPada = DateTime.tryParse('${hasil['_disimpanPada'] ?? ''}');
    }

    final kolom = ((hasil['kolom'] as List?) ?? [])
        .map((e) => '${(e is Map ? (e['judul'] ?? e['nama'] ?? e) : e)}')
        .toList();
    final baris = ((hasil['baris'] as List?) ?? [])
        .whereType<List>()
        .map((r) => r.map((v) => v).toList())
        .toList();

    // Kolom laporan: kode, barcode, nama, kategori, toko, satuan, stok,
    // hargabeli, hargajual. Indeksnya dicari lewat judul supaya perubahan
    // urutan di server tidak diam-diam menggeser nilai yang dibaca.
    int cari(List<String> kandidat) {
      for (var i = 0; i < kolom.length; i++) {
        final k = kolom[i].toLowerCase();
        for (final c in kandidat) {
          if (k.contains(c)) return i;
        }
      }
      return -1;
    }

    final iKode = cari(['kode']);
    final iStok = cari(['stok']);

    final perKode = <String, double>{};
    if (iKode >= 0 && iStok >= 0) {
      for (final r in baris) {
        if (iKode >= r.length || iStok >= r.length) continue;
        final kode = '${r[iKode] ?? ''}'.trim();
        if (kode.isEmpty) continue;
        perKode[kode] = _angka(r[iStok]);
      }
    }

    return HasilStokTanggal(
      kolom: kolom,
      baris: baris,
      stokPerKode: perKode,
      tanggal: tanggal,
      dariCache: dariCache,
      disimpanPada: disimpanPada,
    );
  }

  static double _angka(Object? v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v'.replaceAll(',', '.')) ?? 0;
  }
}

/// Hasil pengambilan stok per tanggal.
class HasilStokTanggal {
  final List<String> kolom;
  final List<List<dynamic>> baris;

  /// Peta kode produk -> stok pada tanggal acuan. Dipakai layar Produk untuk
  /// menimpa kolom Stok tanpa mengubah sumber data katalognya.
  final Map<String, double> stokPerKode;

  final DateTime? tanggal;

  /// true bila angka ini berasal dari salinan tersimpan (jaringan sedang
  /// terputus), bukan dari server. Layar WAJIB menampilkannya -- stok lama
  /// yang disangka terkini lebih berbahaya daripada tidak ada angka.
  final bool dariCache;
  final DateTime? disimpanPada;

  const HasilStokTanggal({
    required this.kolom,
    required this.baris,
    required this.stokPerKode,
    this.tanggal,
    this.dariCache = false,
    this.disimpanPada,
  });

  bool get kosong => baris.isEmpty;

  /// Ubah menjadi bahan DynamicReportDesigner (Preview/Atur Model/PDF/Excel/
  /// Word). Isinya PERSIS baris laporan yang sudah tersaring server, jadi apa
  /// yang diekspor sama dengan apa yang tampil.
  DynamicReportData keLaporan({required String judul, String subjudul = ''}) {
    final kunci = <String>[];
    final kolomLaporan = <DynamicReportColumn>[];
    for (var i = 0; i < kolom.length; i++) {
      final k = 'k$i';
      kunci.add(k);
      final judulKolom = kolom[i];
      final angka = _kolomAngka(judulKolom);
      kolomLaporan.add(DynamicReportColumn(k, judulKolom, numeric: angka));
    }

    final rows = <Map<String, dynamic>>[];
    for (final r in baris) {
      final m = <String, dynamic>{};
      for (var i = 0; i < kunci.length; i++) {
        m[kunci[i]] = i < r.length ? r[i] : '';
      }
      rows.add(m);
    }

    return DynamicReportData(
      title: judul,
      subtitle: subjudul,
      columns: kolomLaporan,
      rows: rows,
    );
  }

  static bool _kolomAngka(String judul) {
    final j = judul.toLowerCase();
    return j.contains('stok') ||
        j.contains('harga') ||
        j.contains('qty') ||
        j.contains('jumlah') ||
        j.contains('nilai') ||
        j.contains('total');
  }
}
