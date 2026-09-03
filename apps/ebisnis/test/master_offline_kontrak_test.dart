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
    'lib/screens/kulakan_bulk_entry_screen.dart': ["'produk_simpan'"],
    'lib/screens/mitrainap/resepsionis_hotel_screen.dart': [
      "'hotel_tamu_simpan'"
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

  test('layar master memakai MasterOffline + indikator sinkron', () {
    for (final entri in layarMaster.entries) {
      final source = File(entri.key).readAsStringSync();
      for (final penanda in entri.value) {
        expect(source, contains(penanda),
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
      for (final aksi in entri.value) {
        final indeks = source.indexOf(aksi);
        expect(indeks, greaterThanOrEqualTo(0),
            reason: '${entri.key} kehilangan aksi $aksi');
        // Aksi harus dipanggil lewat ApiClient.instance.aksi (bukan antrean).
        final sebelum =
            source.substring((indeks - 200).clamp(0, indeks), indeks);
        expect(sebelum, contains('ApiClient.instance'),
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
