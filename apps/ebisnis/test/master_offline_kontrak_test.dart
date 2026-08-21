import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak offline-first data MASTER: layar CRUD wajib lewat MasterOffline
/// (bukan ApiClient langsung) utk simpan/hapus + daftar ber-cache, dan
/// memasang IndikatorSinkronMaster. Pola test sama dgn
/// grup_produk_kontrak_api_test.dart (source-contract; ApiClient singleton
/// tidak injectable utk widget test ber-mock).
void main() {
  const layarMaster = <String, List<String>>{
    // file : penanda wajib ada di source-nya
    // Tiga layar berikut dikonversi 2026-08-21 atas permintaan pemilik produk.
    // Semuanya menyentuh stok/uang, jadi penandanya dikunci di sini supaya tidak
    // diam-diam kembali menjadi kirim-langsung.
    'lib/screens/kulakan_screen.dart': [
      "daftarCacheDulu('kulakan_faktur_list'",
      "'master:kulakan_faktur'",
      "aksi: 'kulakan_faktur_simpan'",
      "aksi: 'kulakan_faktur_batal'",
      // Supplier baru dibuat offline memakai id sementara supaya faktur yang
      // diketik menyusul bisa langsung menunjuknya.
      'MasterOffline.idSementaraBaru()',
    ],
    'lib/screens/mutasi_antar_outlet_screen.dart': [
      "daftarCacheDulu('mutasi_stok_list'",
      "aksi: 'mutasi_stok_simpan'",
    ],
    'lib/screens/anggota/tab_mutasi_hutang.dart': [
      "aksi: 'hutang_bayar_simpan'",
    ],
    'lib/screens/jenis_produk_screen.dart': [
      "daftarCacheDulu('jenis_produk_list'",
      "'jenis_produk_hapus'",
      "'master:jenis_produk'",
      'IndikatorSinkronMaster(',
    ],
    'lib/screens/grup_produk_screen.dart': [
      "'grup_produk_daftar'",
      "'master:grup_produk'",
      'IndikatorSinkronMaster(',
    ],
    'lib/screens/toko_kelola_screen.dart': [
      "'toko_kelola_list'",
      "'master:toko_kelola'",
      'IndikatorSinkronMaster(',
    ],
    'lib/screens/cara_bayar_screen.dart': [
      "daftarCacheDulu('cara_bayar_list_admin'",
      "'master:cara_bayar'",
      'IndikatorSinkronMaster(',
    ],
    // Gelombang 2 -- indikator ada di layar INDUK (anggota_screen/diskon_
    // screen), tab cukup jalur MasterOffline + cacheKey-nya.
    'lib/screens/anggota/tab_data_member.dart': ["'master:anggota'"],
    'lib/screens/anggota/tab_jenis_member.dart': ["'master:jenis_anggota'"],
    'lib/screens/anggota/tab_tipe_member.dart': ["'master:tipe_anggota'"],
    'lib/screens/supplier_screen.dart': [
      "'master:penyedia'",
      'IndikatorSinkronMaster(',
    ],
    'lib/screens/diskon/tab_aturan_diskon.dart': ["'master:diskon'"],
    'lib/screens/diskon/tab_diskon_grup.dart': ["'master:diskon_grup'"],
    'lib/screens/diskon/tab_pencairan_diskon.dart': [
      "'master:pencairan_diskon'"
    ],
    'lib/screens/produk_screen.dart': [
      "'master:produk_list'",
      "'master:kebijakan_retur'",
      'IndikatorSinkronMaster(',
    ],
    'lib/screens/konfigurasi_screen.dart': [
      "'akun:baru:",
      "'toko_profil:",
      "'pedagang:",
    ],
    // Tambah-member-cepat di keranjang POS ikut offline-first.
    'lib/screens/keranjang_screen.dart': ["'anggota_simpan_cepat'"],
    // Gelombang 3 -- sisa master lintas varian.
    'lib/screens/konfigurasi/tab_screensaver.dart': [
      "'screensaver:",
      "'screensaver_slide:",
    ],
    'lib/screens/anggota/tab_notifikasi.dart': ["'notifikasi:"],
    'lib/screens/kedaluwarsa_screen.dart': ["'produk_batch:"],
    'lib/screens/inventory_sales/master_customer_screen.dart': [
      "'si_customer:"
    ],
    'lib/screens/inventory_sales/master_supplier_screen.dart': [
      "'si_supplier:"
    ],
    'lib/screens/inventory_sales/master_sales_screen.dart': ["'si_sales:"],
    'lib/screens/mitrainap/properti_hotel_screen.dart': ["'hotel_properti:"],
    'lib/screens/mitrainap/kontrak_pemilik_screen.dart': ["'hotel_kontrak:"],
    'lib/screens/apotik/persediaan_apotik_screen.dart': ["'apotik_item:"],
  };

  // Layar daftar master yang WAJIB menampilkan indikator sinkron PER-BARIS
  // (IndikatorBarisSinkron/SelTeksDenganSinkron) -- permintaan bisnis:
  // animasi centang saat baris terbukti sampai server.
  const layarIndikatorBaris = <String>[
    'lib/screens/jenis_produk_screen.dart',
    'lib/screens/grup_produk_screen.dart',
    'lib/screens/toko_kelola_screen.dart',
    'lib/screens/cara_bayar_screen.dart',
    'lib/screens/supplier_screen.dart',
    'lib/screens/produk_screen.dart',
    'lib/screens/anggota/tab_data_member.dart',
    'lib/screens/anggota/tab_jenis_member.dart',
    'lib/screens/anggota/tab_tipe_member.dart',
    'lib/screens/diskon/tab_aturan_diskon.dart',
    'lib/screens/diskon/tab_diskon_grup.dart',
    'lib/screens/diskon/tab_pencairan_diskon.dart',
    'lib/screens/inventory_sales/master_customer_screen.dart',
    'lib/screens/inventory_sales/master_supplier_screen.dart',
    'lib/screens/inventory_sales/master_sales_screen.dart',
  ];

  // Mutasi yang SENGAJA tetap online-only (jangan diam-diam diantre):
  // kredensial/kontrol akses, alur yang butuh id server seketika, uang,
  // dan aksi sensitif menurut spec offline (PERINTAH_MASTER... section 13.3).
  const tetapOnline = <String, List<String>>{
    'lib/screens/hak_akses_screen.dart': ["'ebisnis_role_menu_simpan'"],
    'lib/screens/kulakan_bulk_entry_screen.dart': ["'produk_simpan'"],
    'lib/screens/mitrainap/resepsionis_hotel_screen.dart': [
      "'hotel_tamu_simpan'"
    ],
    // Bagan akun: spec 13.3 menempatkan "perubahan rekening/harga sensitif"
    // sebagai wajib online. Akun yang baru muncul setelah sinkronisasi akan
    // membuat jurnal mengacu ke akun tak dikenal.
    'lib/screens/inventory_sales/kas_jurnal_screen.dart': ["'si_coa_save'"],
    // Pembalikan transaksi = "reversal" pada spec 13.3.
    'lib/screens/riwayat_penjualan_screen.dart': ["aksi('batalkan_transaksi'"],
    // Posting jurnal = "journal posting" pada spec 13.3.
    'lib/screens/jurnal_umum_screen.dart': ["aksi('jurnal_umum_posting'"],
    // reservasi_hotel_screen: data TAMU kini sengaja offline-first (lihat
    // komentar di layarnya: tamu diantre, RESERVASI tetap butuh server
    // real-time) -- entri lamanya dipindah dari daftar online-only ini.
  };

  // Layar induk yang hanya menjadi tuan-rumah indikator (tanpa mutasi CRUD).
  const tuanRumahIndikator = <String>[
    'lib/screens/anggota_screen.dart',
    'lib/screens/diskon_screen.dart',
  ];

  /// Salinan sumber tanpa spasi -- dipakai mencocokkan penanda agar pemenggalan
  /// baris oleh `dart format` tidak menggagalkan penjaga. Yang dikunci di sini
  /// PERILAKU (jalur mana yang dipakai), bukan gaya pemformatannya.
  String rapat(String teks) => teks.replaceAll(RegExp(r'\s+'), '');

  test('layar master memakai MasterOffline + indikator sinkron', () {
    for (final entri in layarMaster.entries) {
      final source = File(entri.key).readAsStringSync();
      for (final penanda in entri.value) {
        expect(rapat(source), contains(rapat(penanda)),
            reason: '${entri.key} kehilangan penanda: $penanda');
      }
      // Mutasi master tidak boleh lagi memanggil ApiClient.aksi utk
      // *_simpan/*_hapus entitas layar ybs (transaksi/aksi lain boleh).
      // Dua jalur sah: simpanAtauAntre (programatik) atau prosesSimpanMaster
      // (dialog "lokal dulu" ber-indikator animasi -- standar form CRUD).
      expect(
          source.contains('MasterOffline.simpanAtauAntre') ||
              source.contains('prosesSimpanMaster('),
          isTrue,
          reason: '${entri.key} belum memakai jalur simpan offline-first');
    }
    for (final file in tuanRumahIndikator) {
      expect(File(file).readAsStringSync(), contains('IndikatorSinkronMaster('),
          reason: '$file belum memasang indikator sinkron');
    }
  });

  test('daftar master menampilkan indikator sinkron per-baris', () {
    for (final file in layarIndikatorBaris) {
      final source = File(file).readAsStringSync();
      expect(
          source.contains('IndikatorBarisSinkron(') ||
              source.contains('SelTeksDenganSinkron('),
          isTrue,
          reason: '$file belum memasang indikator per-baris');
    }
  });

  // Mutasi yang WAJIB local-first: ditulis ke antrean lokal LEBIH DULU, baru
  // dikirim. Daftar ini menjaga hasil audit agar tidak diam-diam dikembalikan
  // ke pola "server dulu" (MasterOffline.simpanAtauAntre) di kemudian hari.
  const wajibLokalDulu = <String, String>{
    'lib/screens/anggota/tab_satuan_kerja.dart': "'satuan_kerja_simpan'",
    'lib/screens/anggota/tab_topup.dart': "'deposit_hapus'",
    'lib/screens/mitrainap/kamar_hotel_screen.dart': 'prosesSimpanMaster(',
    'lib/screens/pengadaan_tagihan_screen.dart':
        "'pengadaan_lampiran_hapus'",
    'lib/screens/inventory_sales/hutang_supplier_screen.dart':
        "'si_purchase_terms_save'",
  };

  test('mutasi wajib local-first tidak kembali ke pola server-dulu', () {
    for (final entri in wajibLokalDulu.entries) {
      final source = File(entri.key).readAsStringSync();
      final indeks = source.indexOf(entri.value);
      expect(indeks, greaterThanOrEqualTo(0),
          reason: '${entri.key} kehilangan penanda ${entri.value}');
      final sekitar = source.substring(
          (indeks - 400).clamp(0, indeks), (indeks + 200).clamp(0, source.length));
      expect(sekitar, contains('prosesSimpanMaster'),
          reason: '${entri.key}: ${entri.value} harus lewat prosesSimpanMaster '
              '(tulis lokal dulu), bukan ApiClient langsung atau '
              'simpanAtauAntre yang mencoba server lebih dulu');
    }
  });

  test('rating pelanggan diantre lokal dulu tanpa dialog kasir', () {
    final layar =
        File('lib/screens/layar_pelanggan_screen.dart').readAsStringSync();
    expect(layar, contains('MasterOffline.antreLokal'),
        reason: 'rating harus tercatat lokal sebelum dikirim');
    expect(layar, isNot(contains('prosesSimpanMaster')),
        reason: 'layar pelanggan tidak boleh memunculkan dialog proses kasir');
  });

  test('aksi sensitif tetap online-only (tidak diantre diam-diam)', () {
    for (final entri in tetapOnline.entries) {
      final source = File(entri.key).readAsStringSync();
      final padat = rapat(source);
      for (final aksi in entri.value) {
        final indeks = padat.indexOf(rapat(aksi));
        expect(indeks, greaterThanOrEqualTo(0),
            reason: '${entri.key} kehilangan aksi $aksi');
        // Aksi harus dipanggil lewat ApiClient.instance.aksi (bukan antrean).
        final sebelum = padat.substring((indeks - 200).clamp(0, indeks), indeks);
        expect(sebelum, contains(rapat('ApiClient.instance')),
            reason: '${entri.key}: $aksi harus tetap lewat ApiClient '
                '(online-only sesuai spec 13.3 / aturan kredensial)');
      }
    }
  });

  test('dialog simpan "lokal dulu" bertahap + retry 5 menit berhenti sendiri',
      () {
    final dialog =
        File('lib/widgets/proses_simpan_master.dart').readAsStringSync();
    // Tahapan yang dijanjikan ke user: lokal dulu -> kirim animasi ->
    // terkirim/offline -> jendela menutup (offline pun langsung lanjut).
    expect(dialog, contains('Tersimpan di perangkat'));
    expect(dialog, contains('Terkirim ke server'));
    expect(dialog, contains('akan dikirim otomatis'));
    expect(dialog, contains('Curves.elasticOut'));
    expect(dialog, contains('canPop: false'),
        reason: 'proses tidak boleh dibatalkan di tengah');
    expect(dialog, contains('antreLokal'),
        reason: 'wajib menulis lokal SEBELUM menyentuh jaringan');

    final layanan =
        File('lib/services/master_offline.dart').readAsStringSync();
    expect(layanan, contains('Duration(minutes: 5)'),
        reason: 'retry latar 5 menit sekali (permintaan bisnis)');
    expect(layanan, contains('_timer?.cancel()'),
        reason: 'pengecekan berhenti otomatis saat antrean kosong');
  });

  test('baca lokal-dulu + animasi perubahan server + riwayat AuditTrails', () {
    final layanan =
        File('lib/services/master_offline.dart').readAsStringSync();
    // Emisi ganda: cache instan lalu server + diff utk animasi.
    expect(layanan, contains('daftarCacheDulu'));
    expect(layanan, contains("'idBaru'"));
    expect(layanan, contains("'idBerubah'"));
    expect(layanan, contains("'jumlahHapus'"));

    final kilau = File('lib/widgets/kilau_perubahan.dart').readAsStringSync();
    expect(kilau, contains('class KilauBaris'));
    expect(kilau, contains('class BannerPerubahanServer'));

    // Dialog riwayat per baris: baca utk semua user, pulihkan admin-only
    // sesuai jawaban server (Common.apakahAdminLain di RevisiApiHelper).
    final riwayat =
        File('lib/widgets/riwayat_data_dialog.dart').readAsStringSync();
    expect(riwayat, contains("'revisi_daftar'"));
    expect(riwayat, contains("'revisi_detail'"));
    expect(riwayat, contains("'revisi_pulihkan'"));
    expect(riwayat, contains("bolehPulihkan"));

    // Layar referensi memakai ketiganya.
    final referensi =
        File('lib/screens/jenis_produk_screen.dart').readAsStringSync();
    expect(referensi, contains('daftarCacheDulu'));
    expect(referensi, contains('KilauBaris('));
    expect(referensi, contains('tampilkanRiwayatData('));
  });

  test('sinkron awal ber-progress saat cache lokal kosong (generik)', () {
    final layanan =
        File('lib/services/master_offline.dart').readAsStringSync();
    // API generik utk SEMUA modul CRUD (permintaan bisnis: reuse, bukan
    // helper khusus satu layar).
    expect(layanan, contains('perluSinkronAwal'));
    expect(layanan, contains('jumlahCacheLokal'));
    expect(layanan, contains('hidrasiAwal'));

    final dialog =
        File('lib/widgets/progress_sinkron_awal.dart').readAsStringSync();
    expect(dialog, contains('jalankanDenganProgressSinkron'));
    expect(dialog, contains('LinearProgressIndicator'));
    expect(dialog, contains('canPop: false'));

    // Layar member: sinkron awal otomatis saat cache kosong + tombol Sinkron
    // manual memakai dialog progress yang sama.
    final member =
        File('lib/screens/anggota/tab_data_member.dart').readAsStringSync();
    expect(member, contains('jumlahAnggotaCache'));
    expect(member, contains('jalankanDenganProgressSinkron'));
  });

  // Layar LAPORAN yang menyajikan angka uang dari cache lokal WAJIB
  // menandainya: diam-diam menampilkan angka basi itu menyesatkan (beda dgn
  // daftar master, yang keterlambatannya tidak berbahaya).
  test('laporan ber-cache menandai data tersimpan', () {
    const layarLaporanBerCache = <String>[
      'lib/screens/riwayat_penjualan_analisis_screen.dart',
      'lib/screens/laporan_detail_screen.dart',
      'lib/screens/apotik/laporan_apotik_screen.dart',
      'lib/screens/inventory_sales/laba_rugi_screen.dart',
      'lib/screens/ringkasan/tab_umum.dart',
    ];
    for (final file in layarLaporanBerCache) {
      final source = File(file).readAsStringSync();
      expect(source, contains('ambilCacheReferensi'),
          reason: '$file kehilangan jalur baca cache lokal');
      expect(source, contains('PenandaDataTersimpan('),
          reason: '$file menampilkan angka dari cache TANPA penanda');
    }
  });

  test('layanan MasterOffline terikat ke outbox_master core_db', () {
    final source =
        File('lib/services/master_offline.dart').readAsStringSync();
    expect(source, contains('outboxMasterTambah'));
    expect(source, contains('outboxMasterPending'));
    expect(source, contains('outboxMasterTandaiSukses'));
    expect(source, contains('outboxMasterTandaiGagal'));
    // Penolakan bisnis TIDAK diantre -- kontrak inti supaya pesan server
    // selalu sampai ke user, bukan lenyap di antrean.
    expect(source, contains('if (!e.offline) rethrow'));
    // Pagar baca lokal-dulu (insiden "41 dihapus" 2026-08-19): penghapusan
    // hanya dari respons yang benar-benar lengkap, dan baris lokal yang masih
    // antre/gagal tidak boleh ditimpa/dihapus salinan server.
    expect(source, contains('benarLengkap'));
    expect(source, contains('kunciDilindungi'));
    // Field top-level LAIN dari respons server (summary/ringkasan/
    // totalOutstanding/daftarKasir) wajib diteruskan ke layar -- pernah
    // dibuang sehingga KPI hutang/piutang diam-diam nol (2026-08-19).
    expect(source, contains('responsAsli'));
    expect(source, contains('...?responsAsli'));
    // 'total' tidak boleh di-cast paksa: sebagian aksi memakainya utk objek
    // agregat (pembantu_piutang_list) -> TypeError tiap muat.
    expect(source, isNot(contains("total'] as num?)?.toInt()")));
    // Kunci baris versi publik supaya KilauBaris memakai kunci yang PERSIS
    // sama dgn diff internal (kalau beda, animasi tidak pernah menyala).
    expect(source, contains('static String kunciBaris('));
    // Coalesce lewat kunci; create diberi kunci unik per draf oleh layar.
    expect(source, contains('kunci'));
  });

  test('indikator punya 4 wujud fase termasuk animasi sukses', () {
    final source =
        File('lib/widgets/indikator_sinkron_master.dart').readAsStringSync();
    expect(source, contains('FaseSinkron.adaAntrean'));
    expect(source, contains('FaseSinkron.mengirim'));
    expect(source, contains('FaseSinkron.baruTersinkron'));
    expect(source, contains('FaseSinkron.adaGagal'));
    expect(source, contains('Curves.elasticOut'),
        reason: 'centang sukses harus beranimasi (permintaan bisnis)');
  });
}
