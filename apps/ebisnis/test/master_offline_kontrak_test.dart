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
    'lib/screens/retur_pembelian_screen.dart': [
      "daftarCacheDulu('retur_pembelian_list'",
      "daftarCacheDulu('kulakan_faktur_list'",
      "objekDenganCache(",
      "'master:kulakan_faktur:detail:",
      "aksi: 'retur_pembelian_simpan'",
      "aksi: 'retur_pembelian_hapus'",
      "'faktur_pengadaan_id'",
      "'kode_faktur_asal'",
      "'Pratinjau & Cetak'",
    ],
    'lib/screens/mutasi_antar_outlet_screen.dart': [
      "daftarCacheDulu('mutasi_stok_list'",
      "aksi: 'mutasi_stok_simpan'",
    ],
    'lib/screens/anggota/tab_mutasi_hutang.dart': [
      "aksi: 'hutang_bayar_simpan'",
      // Pembayaran yang salah kini bisa dibatalkan dari aplikasi. Dikunci di sini
      // karena menyentuh uang: kalau hapusnya kembali jadi kirim-langsung, kegagalan
      // kirim berarti pembayaran tampak terhapus di layar tetapi tetap ada di server.
      "aksi: 'hutang_bayar_hapus'",
    ],
    'lib/screens/jenis_produk_screen.dart': [
      "daftarCacheDulu('jenis_produk_list'",
      "'jenis_produk_hapus'",
      "'master:jenis_produk'",
      'IndikatorSinkronMaster(',
    ],
    // Kelompok Aset menggantikan kelompok_asset.zul yang sebelumnya dibuka di
    // browser sistem. Penandanya dikunci di sini supaya tidak diam-diam kembali
    // menjadi kirim-langsung: layar ini menyunting akun POSTING, jadi kegagalan
    // kirim yang tidak terantre berarti perbaikan akun hilang tanpa jejak.
    'lib/screens/kelompok_aset_screen.dart': [
      "daftarCacheDulu('kelompok_aset_list'",
      "'master:kelompok_aset",
      "aksi: 'kelompok_aset_akun_simpan'",
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
    'lib/screens/anggota/tab_tipe_member.dart': [
      "'master:tipe_anggota'",
      "'master:cara_bayar:pilihan_tipe'",
      "'daftarCaraPembayaranYangBolehDiPilih'",
      "'maksimalTransaksiHarian'",
      "'maksimalTransaksiMingguan'",
      "'maksimalTransaksiBulanan'",
      "'berlakuSemuaToko'",
      "'daftarToko'",
    ],
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
    // Varian POS Apotik: layar master hasil modernisasi UI/UX. Indikator
    // sinkron dipasang di AppShell induk (beranda_apotik_screen), mengikuti
    // pola "Gelombang 2" di atas.
    'lib/features/apotik/inventory/apotik_formularium_page.dart': [
      "'apotik_item_cari'",
      'kunciCacheItemApotik',
      "'apotik_item_profil:",
      'tampilkanRiwayatData(',
    ],
    'lib/features/apotik/inventory/apotik_batch_expiry_page.dart': [
      "'apotik_batch_monitor'",
      'kunciCacheBatchApotik',
      "'apotik_batch_status:",
      'tampilkanRiwayatData(',
    ],
  };

  // Layar yang DAFTARnya lokal-dulu tetapi mutasinya memang harus online:
  // yang di-cache hanya daftar untuk dibaca, bukan izin melakukan tindakan.
  const bacaLokalDuluSaja = <String, List<String>>{
    'lib/features/apotik/prescription/apotik_resep_page.dart': [
      "'apotik_resep_list'",
      'kunciCacheResepApotik(',
      'MasterOffline.daftarCacheDulu',
    ],
    // Katalog kasir: harga & penanda keselamatan tetap terbaca saat jaringan
    // mati, dengan penanda bahwa stoknya bisa basi. Menjual tetap online.
    'lib/features/apotik/pos/apotik_pos_page.dart': [
      "'apotik_item_cari'",
      'kunciCacheItemApotik',
      'kunciCacheCaraBayarApotik',
      'kunciCacheResepApotik(',
      'MasterOffline.daftarCacheDulu',
      'saringCacheLokal(',
      '_katalogDariCache',
    ],
    // Pencarian obat saat menyusun baris penerimaan (postingnya tetap online).
    'lib/features/apotik/procurement/apotik_penerimaan_page.dart': [
      "'apotik_item_cari'",
      'kunciCacheItemApotik',
      'MasterOffline.daftarCacheDulu',
    ],
    // Dasbor: gambaran terakhir lebih berguna daripada layar kosong; angkanya
    // sudah ditandai tidak pasti lewat ApotikRingkasan.angkaPasti.
    'lib/features/apotik/dashboard/apotik_dashboard_data.dart': [
      'kunciCacheItemApotik',
      'kunciCacheBatchApotik',
      'kunciCacheResepApotik(',
      'MasterOffline.daftarCacheDulu',
    ],
  };

  // POS Apotik: mutasi yang SENGAJA tidak diantre, beserta berkas tempat
  // alasannya ditulis. Bentuk pemeriksaannya beda dari `tetapOnline` di bawah
  // karena layar apotik memanggil server lewat closure yang disuntik (agar
  // dapat diuji), sehingga literal `ApiClient.instance` tidak berdampingan
  // dengan nama aksinya.
  const apotikTetapOnline = <String, List<String>>{
    'lib/features/apotik/pos/apotik_pos_page.dart': ["'apotik_bayar'"],
    'lib/features/apotik/procurement/apotik_penerimaan_page.dart': [
      "'apotik_terima_barang'"
    ],
    'lib/features/apotik/reports/apotik_rekonsiliasi_page.dart': [
      "'apotik_sesi_kas_tutup'"
    ],
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
    // Topup online membuat VA/payment-link dan saldo hanya boleh bertambah
    // setelah callback resmi bank/gateway; tidak aman dibuat sukses lokal.
    'lib/screens/anggota/tab_topup.dart': ["aksi('topup_online_buat'"],
    // kulakan_bulk_entry produk_simpan: dulu online-only karena butuh id
    // server seketika; sejak 2026-08-29 memakai id sementara MasterOffline
    // (lihat test 'produk baru bulk entry ...' di bawah) -- entrinya pindah.
    // Bagan akun: spec 13.3 menempatkan "perubahan rekening/harga sensitif"
    // sebagai wajib online. Akun yang baru muncul setelah sinkronisasi akan
    // membuat jurnal mengacu ke akun tak dikenal.
    'lib/screens/inventory_sales/kas_jurnal_screen.dart': ["'si_coa_save'"],
    // Pembalikan transaksi = "reversal" pada spec 13.3.
    'lib/screens/riwayat_penjualan_screen.dart': ["aksi('batalkan_transaksi'"],
    // Posting jurnal = "journal posting" pada spec 13.3.
    'lib/screens/jurnal_umum_screen.dart': ["aksi('jurnal_umum_posting'"],
    // Pembalikan pembayaran/penagihan = "reversal" pada spec 13.3.
    'lib/screens/inventory_sales/hutang_supplier_screen.dart': [
      "aksi('si_payable_payment_reverse'"
    ],
    'lib/screens/inventory_sales/piutang_screen.dart': [
      "aksi('si_collection_reverse'"
    ],
    // Koreksi sesi kas baru sah bila server mengonfirmasi status barunya;
    // sekeluarga dgn sesi_kas_buka/tutup.
    'lib/screens/konfigurasi/tab_sesi_kasir.dart': ["aksi('sesi_kas_koreksi'"],
    // sessionId server dipakai saat itu juga utk membuka layar sesi nota.
    'lib/screens/inventory_sales/spj_screen.dart': ["aksi('si_trip_start'"],
    // ATURAN KAMAR: penempatan kamar diperebutkan, jadi diputuskan server.
    // Check-out ikut online karena menyelesaikan UANG (folio).
    'lib/screens/mitrainap/resepsionis_hotel_screen.dart': [
      "'hotel_tamu_simpan'",
      "aksi('hotel_checkin'",
      "aksi('hotel_pindah_kamar'",
      "aksi('hotel_checkout'",
    ],
    'lib/screens/mitrainap/reservasi_hotel_screen.dart': [
      "aksi('hotel_reservasi_buat'"
    ],
    // Ganti password pedagang = KREDENSIAL: tidak pernah diantre (aturan
    // secret handover). Edit non-password akun yang sama sudah lokal-dulu
    // lewat prosesSimpanMaster dgn kunci 'pedagang:<id>'.
    'lib/screens/konfigurasi_screen.dart': ["'password_baru':"],
    // Server yang memilih baris: himpunan yang disetujui pengguna bisa berubah
    // sebelum antrean terkirim.
    'lib/screens/ringkasan/tab_umum.dart': ["aksi('layani_semua_transaksi'"],
    'lib/screens/riwayat_audit_screen.dart': ["aksi('revisi_pulihkan_massal'"],
    'lib/screens/produk_screen.dart': [
      "aksi('produk_isi_pemasok_dari_kulakan', {'pratinjau': false}"
    ],
    // reservasi_hotel_screen: data TAMU kini sengaja offline-first (lihat
    // komentar di layarnya: tamu diantre, RESERVASI tetap butuh server
    // real-time) -- entri lamanya dipindah dari daftar online-only ini.
    // Ditambahkan dari daftar 'wajib online' di docs/pos/33-audit-lokal-dulu.md.
    // Dokumen itu menyebut seluruh daftarnya dikunci berkas ini, padahal sebelumnya
    // hanya tiga entri teratas yang benar-benar terkunci -- sisanya benar dalam
    // praktik tetapi tidak dijaga tes apa pun.
    'lib/screens/inventory_sales/kas_jurnal_screen.dart': ["'si_coa_save'"],
    'lib/screens/riwayat_penjualan_screen.dart': ["'batalkan_transaksi'"],
    'lib/screens/ringkasan/tab_umum.dart': ["'batalkan_transaksi'"],
    'lib/screens/anggota/tab_sinkronisasi.dart': ["'sinkron_referensi'"],
    'lib/services/layar_pelanggan_broadcaster.dart': [
      "'layar_pelanggan_kirim'"
    ],
    'lib/screens/produk_screen.dart': ["'produk_duplikat_hapus'"],
    'lib/screens/mutasi_antar_outlet_screen.dart': ["'mutasi_stok_simpan'"],
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
      // Bentuk ketiga yang sah: tear-off `?? prosesSimpanMaster` sebagai
      // nilai bawaan parameter yang dapat disuntik pada test (dipakai layar
      // features/apotik). Fungsinya sama; hanya cara merangkainya berbeda.
      expect(
          source.contains('MasterOffline.simpanAtauAntre') ||
              source.contains('prosesSimpanMaster(') ||
              source.contains('?? prosesSimpanMaster'),
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
    'lib/screens/pengadaan_tagihan_screen.dart': "'pengadaan_lampiran_hapus'",
    'lib/screens/inventory_sales/hutang_supplier_screen.dart':
        "'si_purchase_terms_save'",
  };

  test('mutasi wajib local-first tidak kembali ke pola server-dulu', () {
    for (final entri in wajibLokalDulu.entries) {
      final source = File(entri.key).readAsStringSync();
      final indeks = source.indexOf(entri.value);
      expect(indeks, greaterThanOrEqualTo(0),
          reason: '${entri.key} kehilangan penanda ${entri.value}');
      final sekitar = source.substring((indeks - 400).clamp(0, indeks),
          (indeks + 200).clamp(0, source.length));
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

  test('daftar yang lokal-dulu tanpa antrean tulis tetap membaca dari cache',
      () {
    for (final entri in bacaLokalDuluSaja.entries) {
      final source = File(entri.key).readAsStringSync();
      for (final penanda in entri.value) {
        expect(source, contains(penanda),
            reason: '${entri.key} kehilangan penanda: $penanda');
      }
    }
  });

  test('POS Apotik: penjualan/penerimaan/tutup kas tidak diantre', () {
    const berkasAlasan = 'lib/features/apotik/core/apotik_lokal_dulu.dart';
    final alasan = File(berkasAlasan).readAsStringSync();
    for (final entri in apotikTetapOnline.entries) {
      final source = File(entri.key).readAsStringSync();
      for (final aksi in entri.value) {
        expect(source, contains(aksi),
            reason: '${entri.key} kehilangan aksi $aksi');
        // Tidak boleh diam-diam dipindah ke antrean master.
        expect(source.contains('prosesSimpanMaster'), isFalse,
            reason: '${entri.key}: $aksi menyentuh uang/stok dan tidak boleh '
                'diantre offline');
        expect(source.contains('simpanAtauAntre'), isFalse,
            reason: '${entri.key}: $aksi tidak boleh diantre offline');
        // Alasannya WAJIB tertulis, supaya keputusan ini tidak tampak seperti
        // kelalaian dan tidak "dirapikan" orang berikutnya.
        expect(alasan, contains(aksi.replaceAll("'", '')),
            reason: '$berkasAlasan harus menjelaskan kenapa $aksi '
                'tetap online-only');
      }
    }
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
        final sebelum =
            padat.substring((indeks - 200).clamp(0, indeks), indeks);
        expect(sebelum, contains(rapat('ApiClient.instance')),
            reason: '${entri.key}: $aksi harus tetap lewat ApiClient '
                '(online-only sesuai spec 13.3 / aturan kredensial)');
      }
    }
  });

  test('topup online gagal offline tanpa sukses atau saldo semu', () {
    final source =
        File('lib/screens/anggota/tab_topup.dart').readAsStringSync();
    final padat = rapat(source);
    expect(
        padat, contains(rapat("ApiClient.instance.aksi('topup_online_buat'")),
        reason: 'pembuatan VA wajib meminta konfirmasi server saat itu juga');
    expect(padat, isNot(contains(rapat("antreLokal('topup_online_buat'"))),
        reason: 'topup online tidak boleh masuk outbox sebagai sukses lokal');
    expect(source, contains('Topup Online memerlukan koneksi ke server'));
    expect(source, contains('saldo member tidak berubah'));
    expect(source, contains('Saldo member belum bertambah'));
    expect(source, contains('callback resmi bank'));
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

    final layanan = File('lib/services/master_offline.dart').readAsStringSync();
    expect(layanan, contains('Duration(minutes: 5)'),
        reason: 'retry latar 5 menit sekali (permintaan bisnis)');
    expect(layanan, contains('_timer?.cancel()'),
        reason: 'pengecekan berhenti otomatis saat antrean kosong');
  });

  test('baca lokal-dulu + animasi perubahan server + riwayat AuditTrails', () {
    final layanan = File('lib/services/master_offline.dart').readAsStringSync();
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
    final layanan = File('lib/services/master_offline.dart').readAsStringSync();
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

  test('layar produk menyediakan sinkron penuh server ke cache lokal', () {
    final produk = File('lib/screens/produk_screen.dart').readAsStringSync();
    final layanan = File('lib/services/master_offline.dart').readAsStringSync();
    expect(
        produk,
        contains(
            "label: _menyinkronProduk ? 'Menyinkron...' : 'Sinkron Produk'"));
    expect(produk, contains('replaceProdukCache('));
    expect(produk, contains("'page_size': ukuranHalaman"));
    expect(produk, contains('jalankanDenganProgressSinkron<int>'));
    expect(layanan, contains('simpanDaftarLengkapDariServer'));
    expect(layanan, contains('_statusBaris.containsKey(kunciOutbox)'));
  });

  test('edit produk langsung tersedia di cache Kasir/Kulakan/SO', () {
    final produk = File('lib/screens/produk_screen.dart').readAsStringSync();
    final opname =
        File('lib/screens/stok_opname_screen.dart').readAsStringSync();
    expect(produk, contains('upsertProdukCache'));
    expect(produk, contains('Produk.baseKeCacheRow'));
    expect(opname, contains('cariProdukLokalPersis(kode)'));
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
    final source = File('lib/services/master_offline.dart').readAsStringSync();
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

  // Bagan akun dipakai 9 layar keuangan sekaligus; sejak audit 2026-08-29
  // semuanya membaca lewat SATU cache bersama 'master:akun' (fallback offline)
  // dengan limit seragam 5000, bukan fetch ApiClient sendiri-sendiri per layar.
  test('akun_list dibaca lewat cache bersama master:akun', () {
    const layarAkun = <String>[
      'lib/screens/anggaran_screen.dart',
      'lib/screens/jurnal_umum_screen.dart',
      'lib/screens/kelompok_aset_screen.dart',
      'lib/screens/kas_besar_screen.dart',
      'lib/screens/kas_kecil_screen.dart',
      'lib/screens/laporan_screen.dart',
      'lib/screens/master_keuangan_screen.dart',
      'lib/screens/penggantian_kas_kecil_screen.dart',
      'lib/screens/siklus_akuntansi_screen.dart',
      'lib/screens/uang_muka_screen.dart',
    ];
    for (final file in layarAkun) {
      final source = rapat(File(file).readAsStringSync());
      expect(
          source,
          contains(rapat(
              "daftarDenganCache('akun_list', {'limit': 5000}, 'master:akun')")),
          reason: '$file harus memuat akun_list lewat cache bersama');
      expect(
          source, isNot(contains(rapat("ApiClient.instance.aksi('akun_list'"))),
          reason: '$file tidak boleh lagi fetch akun_list langsung per layar');
    }
  });

  // Konfigurasi & profil toko adalah respons OBJEK (bukan daftar) -- jalur
  // fallback offline-nya objekDenganCache (langkah 2 audit 2026-08-29):
  // kasir/beranda tetap hidup saat offline dan struk tetap ber-kop dari
  // snapshot profil toko. Kunci profil toko WAJIB per toko.
  test('konfigurasi dan toko_profil_ambil punya fallback cache objek', () {
    final layanan =
        rapat(File('lib/services/master_offline.dart').readAsStringSync());
    expect(
        layanan,
        contains(
            rapat('static Future<Map<String, dynamic>> objekDenganCache(')));

    const layarKonfig = <String>[
      'lib/screens/kasir_screen.dart',
      'lib/screens/apotik/beranda_apotik_screen.dart',
      'lib/screens/inventory_sales/beranda_is_screen.dart',
    ];
    for (final file in layarKonfig) {
      final source = rapat(File(file).readAsStringSync());
      expect(
          source,
          contains(rapat(
              "objekDenganCache('konfigurasi', const {}, 'konfigurasi')")),
          reason: '$file harus memuat konfigurasi dengan fallback cache');
    }
    // Refetch konfigurasi PASCA ganti toko sengaja tetap online-only:
    // snapshot lokal masih milik toko sebelumnya.
    final kasir =
        rapat(File('lib/screens/kasir_screen.dart').readAsStringSync());
    expect(kasir,
        contains(rapat("return await ApiClient.instance.aksi('konfigurasi')")),
        reason: 'refetch konfigurasi setelah pilih toko harus tetap online');

    const layarProfil = <String>[
      'lib/screens/struk_screen.dart',
      'lib/screens/konfigurasi_screen.dart',
    ];
    for (final file in layarProfil) {
      final source = rapat(File(file).readAsStringSync());
      expect(
          source,
          contains(rapat("objekDenganCache('toko_profil_ambil', "
              "{'toko_id': idToko}, 'toko_profil_ambil:\$idToko')")),
          reason: '$file harus membaca profil toko lewat cache per toko');
    }
  });

  // Keluarga *_opsi ber-body kosong (langkah 3 audit 2026-08-29): opsi form
  // stabil, dibaca lewat objekDenganCache dgn kunci = nama aksinya sehingga
  // form tetap bisa dibuka saat offline. laporan_metode_bayar_opsi SENGAJA
  // tidak ikut: hasilnya bergantung rentang tanggal sehingga kunci cache-nya
  // tak terbatas -- tetap online-only.
  test('keluarga *_opsi dibaca lewat objekDenganCache', () {
    const layarOpsi = <String, String>{
      'lib/screens/closing_screen.dart': 'closing_opsi',
      'lib/screens/dana_talangan_screen.dart': 'dana_talangan_opsi',
      'lib/screens/kas_kecil_screen.dart': 'kas_kecil_opsi',
      'lib/screens/kas_besar_screen.dart': 'kas_besar_opsi',
      'lib/screens/master_keuangan_screen.dart': 'master_keuangan_opsi',
      'lib/screens/nomor_surat_keuangan_screen.dart':
          'nomor_surat_keuangan_opsi',
      'lib/screens/pengadaan_bayar_screen.dart': 'pengadaan_cara_bayar_opsi',
      'lib/screens/penggantian_kas_kecil_screen.dart':
          'penggantian_kas_kecil_opsi',
      'lib/screens/pj_uang_muka_screen.dart': 'pj_uang_muka_opsi',
      'lib/screens/pj_kas_besar_screen.dart': 'pj_kas_besar_opsi',
      'lib/screens/proses_transfer_screen.dart': 'proses_transfer_opsi',
      'lib/screens/proses_transitori_screen.dart': 'proses_transitori_opsi',
      'lib/screens/reimbursement_screen.dart': 'reimbursement_opsi',
      'lib/screens/uang_muka_screen.dart': 'uang_muka_opsi',
    };
    for (final entri in layarOpsi.entries) {
      final source = rapat(File(entri.key).readAsStringSync());
      expect(
          source,
          contains(rapat("objekDenganCache('${entri.value}', "
              "const {}, '${entri.value}')")),
          reason: '${entri.key} harus memuat ${entri.value} lewat cache');
      expect(source,
          isNot(contains(rapat("ApiClient.instance.aksi('${entri.value}'"))),
          reason: '${entri.key} tidak boleh lagi fetch ${entri.value} '
              'langsung');
    }
    final laporan = rapat(
        File('lib/screens/laporan_transaksi_screen.dart').readAsStringSync());
    expect(laporan,
        contains(rapat("ApiClient.instance.aksi('laporan_metode_bayar_opsi'")),
        reason: 'laporan_metode_bayar_opsi bergantung rentang tanggal -- '
            'harus tetap online-only, bukan objekDenganCache');
  });

  // Langkah 4 audit 2026-08-29: pencarian produk (koreksi transaksi &
  // dialog cari produk Sales) jatuh ke cache produk core_db saat offline,
  // lewat pemetaan tunggal Produk.cacheRowKeJson (kebalikan baseKeCacheRow --
  // pemetaan SQLite<->JSON tidak boleh digandakan per layar). Jalur katalog
  // lain sudah benar sejak awal: kasir cache-dulu, price_tag cache+fallback,
  // produk_screen sinkron penuh ber-progress.
  test('pencarian produk jatuh ke cache produk lokal saat offline', () {
    final models = rapat(File('lib/models.dart').readAsStringSync());
    expect(
        models, contains(rapat('static Map<String, dynamic> cacheRowKeJson(')));
    for (final file in const [
      'lib/screens/riwayat_penjualan_screen.dart',
      'lib/screens/inventory_sales/penjualan_sales_screen.dart',
    ]) {
      final source = rapat(File(file).readAsStringSync());
      expect(source, contains(rapat('produkCache(keyword:')),
          reason: '$file harus membaca cache produk lokal saat offline');
      expect(source, contains('Produk.cacheRowKeJson'),
          reason: '$file harus memakai pemetaan cache tunggal dari models');
    }
  });

  // Langkah 5 audit 2026-08-29: register riwayat cetak (P10) tidak lagi
  // hilang diam-diam saat offline -- diantre lewat OutboxIs dgn kode_unik
  // PRN-* per kejadian cetak. Server printLogCreate belum men-dedup
  // kode_unik (append-only); pengirimannya kini tercatat supaya dedup server
  // dapat menyusul tanpa mengubah klien.
  test('log cetak diantre lewat OutboxIs, tidak hilang saat offline', () {
    final outbox =
        rapat(File('lib/services/outbox_is.dart').readAsStringSync());
    expect(outbox, contains(rapat("'si_print_log_create'")),
        reason: 'si_print_log_create harus terdaftar di aksiDidukung OutboxIs');
    const layarCetak = <String>[
      'lib/screens/inventory_sales/piutang_screen.dart',
      'lib/screens/inventory_sales/nota_sales_screen.dart',
      'lib/screens/inventory_sales/laba_rugi_screen.dart',
      'lib/screens/inventory_sales/hutang_supplier_screen.dart',
    ];
    for (final file in layarCetak) {
      final source = rapat(File(file).readAsStringSync());
      expect(source,
          contains(rapat("OutboxIs.kirimAtauAntre('si_print_log_create'")),
          reason: '$file harus mengantre log cetak lewat OutboxIs');
      expect(
          source,
          isNot(
              contains(rapat("ApiClient.instance.aksi('si_print_log_create'"))),
          reason: '$file tidak boleh lagi fire-and-forget tanpa antrean');
      expect(source, contains(rapat("'kode_unik': 'PRN-")),
          reason: '$file wajib memberi kode_unik per kejadian cetak');
      expect(source, contains(rapat('OutboxIs.flush()')),
          reason: '$file harus mengirim ulang antrean saat layar dibuka');
    }
  });

  // Langkah 6 audit 2026-08-29: produk baru di Bulk Entry Kulakan tidak lagi
  // memblokir posting saat offline. Id SEMENTARA negatif dipakai item faktur
  // dan ditukar id server oleh tukarIdSementara saat antrean terkirim; faktur
  // yang menunjuk produk belum-terkirim DITAHAN flush. Sukses-tanpa-id tetap
  // dilempar (bukan jatuh ke id sementara) supaya faktur tidak tertahan
  // selamanya, dan penolakan bisnis tetap menghentikan posting.
  test('produk baru bulk entry dibuat lokal-dulu dgn id sementara', () {
    final source = rapat(
        File('lib/screens/kulakan_bulk_entry_screen.dart').readAsStringSync());
    expect(source, contains(rapat('MasterOffline.idSementaraBaru()')));
    expect(source, contains(rapat("antreLokal('produk_simpan'")));
    expect(source, contains(rapat("entitas: 'produk'")));
    expect(source,
        isNot(contains(rapat("ApiClient.instance.aksi('produk_simpan'"))),
        reason: 'produk_simpan bulk entry tidak boleh lagi online-only');
    expect(source, contains(rapat('if (!e.offline) rethrow')),
        reason: 'penolakan bisnis harus tetap menghentikan posting');
  });

  // P3 gelombang 1 (2026-08-29): statistik/dashboard ber-body kosong/tetap
  // dibaca lewat objekDenganCache + PenandaDataTersimpan saat salinan
  // tersimpan dipakai. Yang berparameter rentang/filter (monitor_promo_
  // cashback, draft_jurnal_ringkasan, sop_dashboard) tetap online karena
  // kunci cache-nya tak terbatas. error_log_health SENGAJA tetap online:
  // status "server sehat" dari cache saat server justru tak terjangkau
  // menyesatkan secara aktif.
  test('statistik dashboard ber-cache + penanda data tersimpan', () {
    const layarStatistik = <String, List<String>>{
      'lib/screens/anggota/tab_data_member.dart': [
        "objekDenganCache('anggota_statistik', const {}, 'anggota_statistik')",
      ],
      'lib/screens/laporan_transaksi_screen.dart': [
        "objekDenganCache("
            "'transaksi_statistik', const {}, 'transaksi_statistik')",
      ],
      'lib/screens/produk_screen.dart': [
        "objekDenganCache('produk_statistik', const {}, 'produk_statistik')",
      ],
      'lib/screens/stok_opname_screen.dart': [
        "objekDenganCache("
            "'stok_dashboard', {'periode': 'month'}, 'stok_dashboard:month')",
        "objekDenganCache('so_ringkasan', const {}, 'so_ringkasan')",
      ],
    };
    for (final entri in layarStatistik.entries) {
      final source = rapat(File(entri.key).readAsStringSync());
      for (final penanda in entri.value) {
        expect(source, contains(rapat(penanda)),
            reason: '${entri.key} kehilangan penanda: $penanda');
      }
      expect(source, contains('PenandaDataTersimpan('),
          reason: '${entri.key} menampilkan angka cache TANPA penanda');
    }
    final logError =
        rapat(File('lib/screens/log_error_screen.dart').readAsStringSync());
    expect(
        logError, contains(rapat("ApiClient.instance.aksi('error_log_health'")),
        reason: 'error_log_health harus tetap online-only -- kesehatan server '
            'dari cache saat offline menyesatkan');
  });

  // P3 gelombang 2 (2026-08-29): daftar berhalaman sederhana dibaca
  // lokal-dulu lewat daftarCacheDulu (merge -- respons parsial tidak pernah
  // menghapus baris lokal) + penanda salinan tersimpan. Pencarian BERFILTER
  // riwayat cetak tetap online: satu cache tak berfilter tidak boleh
  // disajikan sebagai hasil filter. Ekspor Excel topup (deposit_list loop
  // berhalaman) SENGAJA tetap online: ekspor wajib data server lengkap.
  test('daftar sederhana lokal-dulu + penanda salinan tersimpan', () {
    const layarDaftar = <String, String>{
      'lib/screens/konfigurasi/tab_riwayat_cetak.dart':
          "daftarCacheDulu('si_print_log_list', const {}, 'si_print_log'",
      'lib/screens/konfigurasi/tab_sesi_kasir.dart':
          "daftarCacheDulu('sesi_kas_list'",
    };
    for (final entri in layarDaftar.entries) {
      final source = rapat(File(entri.key).readAsStringSync());
      expect(source, contains(rapat(entri.value)),
          reason: '${entri.key} kehilangan jalur baca lokal-dulu');
      expect(source, contains('PenandaDataTersimpan('),
          reason: '${entri.key} menampilkan data cache TANPA penanda');
    }
    // Kunci cache sesi kas wajib per toko.
    final sesi = rapat(
        File('lib/screens/konfigurasi/tab_sesi_kasir.dart').readAsStringSync());
    expect(sesi, contains(rapat("'sesi_kas:\${Sesi.instance.tokoId")),
        reason: 'cache sesi kas harus dipisah per toko');
    // Ekspor topup tetap mengunduh seluruh halaman dari server.
    final topup =
        rapat(File('lib/screens/anggota/tab_topup.dart').readAsStringSync());
    expect(topup, contains(rapat("ApiClient.instance.aksi('deposit_list'")),
        reason: 'ekspor Excel topup wajib data server lengkap, bukan cache');
  });

  // P3 gelombang 3 (2026-08-29): dua pelengkap alur offline yang SUDAH
  // queueable. Kategori biaya nota sales ber-cache (si_expense_create sudah
  // di OutboxIs -- pencatatan biaya tidak boleh terblokir daftar kategorinya),
  // dan pemilih customer kwitansi piutang jatuh ke cache master
  // 'master:si_customer' saat offline (si_collection_create sudah di
  // OutboxIs). pengadaan_transitori_daftar SENGAJA tetap online: barisnya
  // dipilih utk diposting, seleksi dari salinan basi berisiko.
  test('pelengkap alur offline: kategori biaya & pemilih customer', () {
    final nota = rapat(
        File('lib/screens/inventory_sales/nota_sales_screen.dart')
            .readAsStringSync());
    expect(
        nota,
        contains(rapat("daftarDenganCache('si_expense_category_list', "
            "const {}, 'master:si_expense_category'")),
        reason: 'kategori biaya harus ber-cache offline');
    final piutang = rapat(
        File('lib/screens/inventory_sales/piutang_screen.dart')
            .readAsStringSync());
    expect(
        piutang, contains(rapat("ambilCacheReferensi('master:si_customer')")),
        reason: 'pemilih customer kwitansi harus jatuh ke cache master');
    final transitori = rapat(
        File('lib/screens/pengadaan_transitori_tab.dart').readAsStringSync());
    expect(
        transitori,
        contains(
            rapat("ApiClient.instance.aksi('pengadaan_transitori_daftar'")),
        reason: 'daftar transitori dipilih utk posting -- harus data server');
  });

  // P3 gelombang 4 (2026-08-29): daftar jurnal umum lokal-dulu. Kunci cache
  // WAJIB sama dgn cacheKey editor draf ('master:jurnal_umum') supaya draf
  // offline langsung tampil di daftar; filter periode/status/kata diterapkan
  // ulang di klien karena emisi cache memuat semua baris yang pernah
  // terlihat. Nominal debet/kredit dari salinan diberi penanda. Posting
  // (jurnal_umum_posting) tetap online-only -- sudah dikunci di tetapOnline.
  test('daftar jurnal umum lokal-dulu satu kunci dgn draf editor', () {
    final source =
        rapat(File('lib/screens/jurnal_umum_screen.dart').readAsStringSync());
    expect(source, contains(rapat("daftarCacheDulu('jurnal_umum_list'")),
        reason: 'daftar jurnal harus lokal-dulu');
    // Kunci yang sama dipakai daftarCacheDulu DAN prosesSimpanMaster draf.
    expect(
        RegExp(r"'master:jurnal_umum'")
            .allMatches(
                File('lib/screens/jurnal_umum_screen.dart').readAsStringSync())
            .length,
        greaterThanOrEqualTo(2),
        reason: 'kunci cache daftar & draf editor harus sama-sama '
            "'master:jurnal_umum'");
    expect(source, contains(rapat('_lolosFilterLokal')),
        reason: 'emisi cache wajib disaring ulang mengikuti filter layar');
    expect(source, contains('PenandaDataTersimpan('),
        reason: 'nominal jurnal dari cache wajib ber-penanda');
    expect(source,
        contains(rapat("daftarDenganCache('jurnal_umum_jenis_transaksi'")),
        reason: 'dropdown jenis transaksi ikut ber-cache');
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
