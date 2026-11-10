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
    Map<String, double>? hargaBeliTambahan,
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

    // PosApi.prosesLaporanJalankan mengirim elemen kolom berupa objek JSON
    // {"l": kl.label, "t": kl.tipe}. Membaca hanya e['judul'] ?? e['nama'] ?? e
    // akan mengubah Map menjadi string "{l: Stok, t: num}" sehingga pencocokan
    // nama kolom ("Stok", "Kode", "Harga Beli", "Nilai Stok") gagal total dan
    // kartu dashboard menjadi 0 / "Belum lengkap".
    final kolom = ((hasil['kolom'] as List?) ?? [])
        .map((e) => '${(e is Map ? (e['judul'] ?? e['nama'] ?? e['l'] ?? e['label'] ?? e) : e)}')
        .toList();
    final baris = ((hasil['baris'] as List?) ?? [])
        .whereType<List>()
        .map((r) => r.map((v) => v).toList())
        .toList();

    // Kolom laporan: kode, barcode, nama, kategori, toko, satuan, stok,
    // hargabeli, hargajual, nilai stok. Indeksnya dicari lewat judul supaya
    // perubahan urutan di server tidak diam-diam menggeser nilai yang dibaca.
    int cariKode() {
      for (var i = 0; i < kolom.length; i++) {
        final k = kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (k == 'kode' || k == 'kodebarang' || k == 'kodeproduk' || k.contains('kode')) {
          return i;
        }
      }
      return baris.isNotEmpty && baris.first.isNotEmpty ? 0 : -1;
    }

    int cariStok() {
      for (var i = 0; i < kolom.length; i++) {
        final k = kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (k == 'stok' ||
            k == 'sisastok' ||
            k == 'stokakhir' ||
            k == 'jumlahstok' ||
            (k.startsWith('stok') && !k.contains('nilai'))) {
          return i;
        }
      }
      for (var i = 0; i < kolom.length; i++) {
        final k = kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (k.contains('stok') && !k.contains('nilai')) return i;
      }
      return baris.isNotEmpty && baris.first.length >= 7 ? 6 : -1;
    }

    final iKode = cariKode();
    final iStok = cariStok();

    // Muat peta harga beli produk dari cache lokal CoreDb sebagai fallback
    // jaminan agar totalNilaiPersediaan tetap terhitung akurat bila ada baris
    // laporan yang membutuhkan harga beli dari master lokal.
    final hargaBeliPerKode = <String, double>{
      if (hargaBeliTambahan != null) ...hargaBeliTambahan,
    };
    try {
      final cacheProduk =
          await CoreDb.instance.produkCache(keyword: '', limit: 100000);
      for (final p in cacheProduk) {
        final kd = '${p['kode'] ?? ''}'.trim();
        if (kd.isNotEmpty) {
          final hb = (p['harga_beli'] as num?)?.toDouble() ?? 0;
          if (hb > 0) hargaBeliPerKode[kd] = hb;
        }
      }
    } catch (_) {}

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
      hargaBeliPerKode: hargaBeliPerKode,
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

  /// Peta kode produk -> harga beli dari katalog lokal untuk fallback perhitungan
  /// nilai persediaan bila kolom Nilai / Harga Beli tidak dikirim oleh server.
  final Map<String, double> hargaBeliPerKode;

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
    this.hargaBeliPerKode = const {},
    this.tanggal,
    this.dariCache = false,
    this.disimpanPada,
  });

  bool get kosong => baris.isEmpty;

  /// Jumlah produk pada hasil yang sedang ditampilkan setelah filter pencarian.
  int get jumlahProduk => baris.length;

  /// Indeks kolom kuantitas Stok pada `baris` laporan (publik agar dialog rincian
  /// klik kartu di `produk_screen.dart` memakai indeks yang persis sama).
  int get indeksStok => _indeksStok;

  int get _indeksStok {
    for (var i = 0; i < kolom.length; i++) {
      final normal =
          kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal == 'stok' ||
          normal == 'sisastok' ||
          normal == 'stokakhir' ||
          normal == 'jumlahstok' ||
          (normal.startsWith('stok') && !normal.contains('nilai'))) {
        return i;
      }
    }
    for (var i = 0; i < kolom.length; i++) {
      final normal =
          kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal.contains('stok') && !normal.contains('nilai')) return i;
    }
    if (baris.isNotEmpty && baris.first.length >= 7) return 6;
    return -1;
  }

  int get _indeksHargaBeli {
    for (var i = 0; i < kolom.length; i++) {
      final normal =
          kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal.contains('hargabeli') || normal.contains('hpp')) return i;
    }
    if (baris.isNotEmpty && baris.first.length >= 8) return 7;
    return -1;
  }

  int get _indeksNilai {
    for (var i = 0; i < kolom.length; i++) {
      final normal =
          kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal == 'nilai' ||
          normal == 'nilaistok' ||
          normal == 'nilaipersediaan' ||
          normal == 'totalnilaipersediaan') {
        return i;
      }
    }
    if (baris.isNotEmpty && baris.first.length >= 10) return 9;
    return -1;
  }

  /// Membaca angka stok satu baris laporan secara aman.
  double angkaStokBaris(List<dynamic> row) {
    final iStok = _indeksStok;
    if (iStok >= 0 && iStok < row.length) {
      return _angkaOpsional(row[iStok]) ?? 0.0;
    }
    final iKode = _indeksKode;
    if (iKode >= 0 && iKode < row.length) {
      final kd = '${row[iKode] ?? ''}'.trim();
      if (stokPerKode.containsKey(kd)) return stokPerKode[kd] ?? 0.0;
    }
    return 0.0;
  }

  /// Jumlah produk yang memiliki stok > 0 pada tanggal pilihan.
  int get jumlahStokTersedia {
    if (baris.isEmpty && stokPerKode.isNotEmpty) {
      return stokPerKode.values.where((s) => s > 0).length;
    }
    final iStok = _indeksStok;
    if (iStok < 0) return 0;
    var n = 0;
    for (final row in baris) {
      if (angkaStokBaris(row) > 0) n++;
    }
    return n;
  }

  /// Jumlah produk dengan stok menipis (0 < stok <= 5) pada tanggal pilihan.
  int get jumlahStokMenipis {
    if (baris.isEmpty && stokPerKode.isNotEmpty) {
      return stokPerKode.values.where((s) => s > 0 && s <= 5).length;
    }
    final iStok = _indeksStok;
    if (iStok < 0) return 0;
    var n = 0;
    for (final row in baris) {
      final s = angkaStokBaris(row);
      if (s > 0 && s <= 5) n++;
    }
    return n;
  }

  /// Jumlah produk dengan stok habis (= 0) pada tanggal pilihan.
  int get jumlahStokHabis {
    if (baris.isEmpty && stokPerKode.isNotEmpty) {
      return stokPerKode.values.where((s) => s == 0).length;
    }
    final iStok = _indeksStok;
    if (iStok < 0) return 0;
    var n = 0;
    for (final row in baris) {
      if (angkaStokBaris(row) == 0) n++;
    }
    return n;
  }

  /// Jumlah produk dengan stok minus (< 0) pada tanggal pilihan.
  int get jumlahStokMinus {
    if (baris.isEmpty && stokPerKode.isNotEmpty) {
      return stokPerKode.values.where((s) => s < 0).length;
    }
    final iStok = _indeksStok;
    if (iStok < 0) return 0;
    var n = 0;
    for (final row in baris) {
      if (angkaStokBaris(row) < 0) n++;
    }
    return n;
  }

  int get _indeksKode {
    for (var i = 0; i < kolom.length; i++) {
      final normal =
          kolom[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normal == 'kode' || normal.contains('kode')) return i;
    }
    if (baris.isNotEmpty && baris.first.isNotEmpty) return 0;
    return -1;
  }

  /// Jumlah nilai persediaan yang dikirim bersama baris laporan.
  ///
  /// Mendukung kolom `Nilai` / `Nilai Stok` / `Nilai Persediaan`, fallback
  /// perkalian `Stok * Harga Beli` dari kolom laporan, serta fallback lapis ketiga
  /// `Stok * hargaBeliPerKode[kode]` dari cache katalog lokal bila HPP benar-benar
  /// tersedia. Harga jual tidak boleh dipakai sebagai pengganti HPP.
  double? get totalNilaiPersediaan {
    final indeks = _indeksNilai;
    final iStok = _indeksStok;
    final iHrgBeli = _indeksHargaBeli;
    final iKode = _indeksKode;
    if (baris.isEmpty && stokPerKode.isNotEmpty) {
      if (stokPerKode.entries.any((e) =>
          e.value != 0 &&
          (hargaBeliPerKode[e.key] == null || hargaBeliPerKode[e.key]! <= 0))) {
        return null;
      }
      var totalFallback = 0.0;
      stokPerKode.forEach((kd, st) {
        totalFallback += st * (hargaBeliPerKode[kd] ?? 0.0);
      });
      return totalFallback;
    }
    var jumlah = 0.0;
    var nilaiTidakDiketahui = false;
    for (final row in baris) {
      double? nilaiBaris;
      if (indeks >= 0 && indeks < row.length) {
        nilaiBaris = _angkaOpsional(row[indeks]);
      }
      final s = (iStok >= 0 && iStok < row.length)
          ? (_angkaOpsional(row[iStok]) ?? 0.0)
          : 0.0;
      if (nilaiBaris == null &&
          iStok >= 0 &&
          iHrgBeli >= 0 &&
          iStok < row.length &&
          iHrgBeli < row.length) {
        final hb = _angkaOpsional(row[iHrgBeli]) ?? 0.0;
        nilaiBaris = s * hb;
      }
      if ((nilaiBaris == null || nilaiBaris == 0) &&
          s != 0 &&
          iKode >= 0 &&
          iKode < row.length) {
        final kd = '${row[iKode] ?? ''}'.trim();
        final hbCache = hargaBeliPerKode[kd];
        if (hbCache != null && hbCache > 0) {
          nilaiBaris = s * hbCache;
        }
      }
      // Nilai server yang hadir tetapi tidak terbaca, atau baris tanpa kolom
      // stok/nilai untuk menghitungnya, berarti total parsial tidak boleh
      // ditampilkan seolah-olah lengkap.
      if (nilaiBaris == null && (s != 0 || indeks >= 0 || iStok < 0)) {
        nilaiTidakDiketahui = true;
      }
      jumlah += nilaiBaris ?? 0.0;
    }
    return nilaiTidakDiketahui ? null : jumlah;
  }

  static double? _angkaOpsional(Object? nilai) {
    if (nilai is num) return nilai.toDouble();
    if (nilai == null) return null;
    var teks = '$nilai'.trim().replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (teks.isEmpty) return null;
    if (teks.contains(',') && teks.contains('.')) {
      // Format Indonesia: titik ribuan dan koma desimal.
      teks = teks.replaceAll('.', '').replaceAll(',', '.');
    } else if (teks.contains(',')) {
      teks = teks.replaceAll(',', '.');
    }
    return double.tryParse(teks);
  }

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
