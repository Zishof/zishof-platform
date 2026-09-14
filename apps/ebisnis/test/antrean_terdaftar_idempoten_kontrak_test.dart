import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak lintas repo: setiap aksi yang DIANTRE klien wajib terdaftar
/// idempoten di server.
///
/// Latar belakangnya cacat nyata (AIS r89377/r89397, `docs/pos/130`): 53 aksi
/// tulis dikirim lewat antrean `MasterOffline` tanpa pernah terdaftar di
/// `MutasiIdempotenEBisnisUtil.AKSI_MASTER_ANTREAN`, sehingga server tidak
/// pernah me-replay-nya. Setelah lost-ack — server sudah commit, responsnya
/// hilang di jaringan — antrean mengirim ulang body yang sama dan efeknya
/// terjadi dua kali: pembayaran vendor ganda, mutasi stok ganda, saldo anggota
/// tersesuaikan dua kali.
///
/// Yang membuatnya bertahan lama adalah senyapnya: tidak ada galat, tidak ada
/// peringatan, dan seluruh test tetap hijau.
///
/// Test ini tidak bisa membaca sumber AIS, jadi yang dijaganya adalah
/// INVENTARIS aksi antrean. Begitu ada aksi antrean baru (atau satu dihapus),
/// test gagal dan memaksa pengembang menyelaraskan sisi server pada commit yang
/// sama.
void main() {
  // Aksi yang saat ini dikirim lewat antrean MasterOffline. Setiap nama di sini
  // WAJIB ada di AKSI_MASTER_ANTREAN pada sisi AIS.
  const inventaris = <String>{
    'akun_tambah',
    'anggota_hapus',
    'anggota_simpan',
    'anggota_simpan_cepat',
    'apotik_item_simpan',
    'apotik_opname_simpan',
    'apotik_retur_simpan',
    'apotik_terima_barang',
    'batal_pesanan',
    'cara_bayar_hapus',
    'cara_bayar_simpan',
    'deposit_hapus',
    'diskon_grup_simpan',
    'diskon_simpan',
    'distribusi_simpan',
    'grup_produk_hapus',
    'grup_produk_simpan',
    'harga_grosir_hapus',
    'harga_grosir_simpan',
    'hotel_folio_transaksi_tambah',
    'hotel_kitchen_ticket_update',
    'hotel_properti_simpan',
    'hotel_reservasi_batalkan',
    'hutang_bayar_hapus',
    'hutang_bayar_simpan',
    'jenis_anggota_hapus',
    'jenis_anggota_simpan',
    'jenis_produk_hapus',
    'jenis_produk_simpan',
    'jurnal_umum_simpan',
    'kebijakan_retur_hapus',
    'kebijakan_retur_simpan',
    'kelompok_aset_akun_simpan',
    'kulakan_faktur_batal',
    'kulakan_faktur_simpan',
    'layani_transaksi',
    'mutasi_stok_simpan',
    'otomatis_pesanan_global_simpan',
    'pencairan_diskon_hapus',
    'pencairan_diskon_simpan',
    'pengadaan_bast_hapus',
    'pengadaan_bast_putusan',
    'pengadaan_bast_simpan',
    'pengadaan_bast_sinkron_kulakan',
    'pengadaan_bayar_hapus',
    'pengadaan_bayar_putusan',
    'pengadaan_bayar_simpan',
    'pengadaan_lampiran_hapus',
    'pengadaan_pajak_batal',
    'pengadaan_pajak_setor',
    'pengadaan_po_back_order',
    'pengadaan_po_hapus',
    'pengadaan_po_putusan',
    'pengadaan_po_simpan',
    'pengadaan_pr_hapus',
    'pengadaan_pr_putusan',
    'pengadaan_pr_simpan',
    'pengadaan_transitori_realisasi',
    'penyedia_hapus',
    'penyedia_simpan',
    'penyesuaian_saldo_simpan',
    'produk_simpan',
    'produksi_qc_disposisi',
    'produksi_simpan',
    'retur_pembelian_hapus',
    'retur_pembelian_simpan',
    'retur_penjualan_hapus',
    'retur_penjualan_simpan',
    'satuan_kerja_anggota_simpan',
    'satuan_kerja_hapus',
    'satuan_kerja_simpan',
    'sesi_kas_rekonsiliasi_simpan',
    'si_payable_payment_create',
    'si_purchase_terms_save',
    'so_batalkan',
    'so_simpan',
    'survey_kepuasan_simpan',
    'tipe_anggota_hapus',
    'tipe_anggota_simpan',
    'toko_kelola_hapus',
    'toko_kelola_simpan',
    'uom_hapus',
    'uom_simpan',
  };

  test('inventaris aksi antrean tidak berubah tanpa menyelaraskan server', () {
    final ditemukan = _pindaiAksiAntrean();

    final baru = ditemukan.difference(inventaris).toList()..sort();
    final hilang = inventaris.difference(ditemukan).toList()..sort();

    expect(
      baru,
      isEmpty,
      reason: 'Aksi antrean BARU terdeteksi: $baru\n'
          'Sebelum menambahkannya ke inventaris test ini, daftarkan tiap nama di '
          'AKSI_MASTER_ANTREAN (ais/action/servlet/api/'
          'MutasiIdempotenEBisnisUtil.java) pada commit yang sama. Tanpa itu, '
          'kiriman ulang antrean setelah lost-ack akan mengeksekusi efeknya dua '
          'kali tanpa galat apa pun. Lihat docs/pos/130.',
    );

    expect(
      hilang,
      isEmpty,
      reason: 'Aksi ini tidak lagi diantre: $hilang\n'
          'Perbarui inventaris di test ini. Entri servernya boleh tetap ada '
          '(tidak berbahaya), tetapi sebaiknya ikut dirapikan.',
    );
  });

  test('pemindai benar-benar menemukan aksi (bukan hasil kosong palsu)', () {
    // Penjaga bagi pemindainya sendiri: bila regex atau tata letak berkas
    // berubah sehingga tidak ada yang terdeteksi, kedua expect di atas akan
    // lulus secara palsu.
    expect(_pindaiAksiAntrean().length, greaterThan(50));
  });
}

/// Mencari aksi yang masuk antrean dengan DUA metode, karena masing-masing
/// melewatkan bentuk panggilan yang berbeda.
Set<String> _pindaiAksiAntrean() {
  // Metode A: argumen posisi pertama; sering berada di baris berikutnya.
  final posisi = RegExp(
      r"MasterOffline\.(?:antreLokal|simpanAtauAntre)\s*\(\s*'([a-z0-9_]+)'");
  // Metode B: argumen bernama milik prosesSimpanMaster. Panggilannya kerap
  // lebih panjang daripada jendela regex mana pun yang wajar, jadi pemanggil
  // dicari dengan menelusuri MUNDUR dari baris `aksi:`. Penelusuran itu pula
  // yang menyingkirkan positif palsu: `aksi:` juga dipakai dasbor ringkasan dan
  // pengunggah gambar.
  final barisAksi = RegExp(r"aksi:\s*'([a-z0-9_]+)'");
  final pemanggil = RegExp(r'([A-Za-z_][A-Za-z0-9_.]*)\s*\(\s*$');

  final hasil = <String>{};
  for (final berkas in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final teks = berkas.readAsStringSync();
    for (final m in posisi.allMatches(teks)) {
      hasil.add(m.group(1)!);
    }
    final baris = teks.split('\n');
    for (var i = 0; i < baris.length; i++) {
      final m = barisAksi.firstMatch(baris[i]);
      if (m == null) continue;
      for (var j = i; j >= 0 && j > i - 30; j--) {
        final p = pemanggil.firstMatch(baris[j].trimRight());
        if (p == null) continue;
        final nama = p.group(1)!;
        if (nama.contains('prosesSimpan') || nama.toLowerCase().contains('antre')) {
          hasil.add(m.group(1)!);
        }
        break;
      }
    }
  }
  return hasil;
}
