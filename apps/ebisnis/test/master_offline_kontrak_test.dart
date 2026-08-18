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
      "daftarDenganCache('jenis_produk_list'",
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
      "daftarDenganCache('cara_bayar_list_admin'",
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
    'lib/screens/mitrainap/reservasi_hotel_screen.dart': [
      "'hotel_tamu_simpan'"
    ],
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
      expect(source, contains('MasterOffline.simpanAtauAntre'),
          reason: '${entri.key} belum memakai simpanAtauAntre');
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
