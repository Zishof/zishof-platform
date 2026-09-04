import 'dart:convert';

import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/services/server_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _tokoId = 1;
const _tanggal = '2026-09-04';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('seed sample best-practice UAT Akuntansi', (tester) async {
    const username = String.fromEnvironment('POS_TEST_USERNAME');
    const password = String.fromEnvironment('POS_TEST_PASSWORD');
    const host = String.fromEnvironment('POS_TEST_HOST');
    const context = String.fromEnvironment('POS_TEST_CONTEXT');
    await ServerConfig.instance
        .simpan(host: host, contextPath: context, https: true);
    final login = await ApiClient.instance.aksi('login', {
      'username': username,
      'password': password,
      'labelPerangkat': 'UAT-Seed-Akuntansi',
    });
    await ApiClient.instance.simpanToken(login['token'] as String);

    Future<Map<String, dynamic>> aksi(
        String nama, Map<String, dynamic> body) async {
      final hasil =
          Map<String, dynamic>.from(await ApiClient.instance.aksi(nama, body));
      // ignore: avoid_print
      print('SEED_$nama=${jsonEncode({
            'id': hasil['id'] ?? hasil['fakturId'] ?? hasil['piutangDocId'],
            'message': hasil['message'] ?? hasil['description'],
            'diposting': hasil['diposting'],
            'siap': hasil['siap'],
          })}');
      return hasil;
    }

    Future<Map<String, dynamic>> akun(String kode) async {
      final r =
          await ApiClient.instance.aksi('kode_akun_daftar', {'cari': kode});
      return ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .firstWhere((e) => '${e['kode']}' == kode,
              orElse: () => <String, dynamic>{});
    }

    Future<Map<String, dynamic>> pastikanAkun({
      required String kode,
      required String nama,
      required String induk,
      required int posisi,
    }) async {
      var ada = await akun(kode);
      if (ada.isNotEmpty) return ada;
      final parent = await akun(induk);
      expect(parent, isNotEmpty, reason: 'Induk akun $induk tidak ditemukan');
      final dibuat = await aksi('kode_akun_simpan', {
        'kode': kode,
        'nama': nama,
        'keterangan': 'Data sample UAT Akuntansi eBisnis',
        'debetCredit': posisi,
        'grupAkunId': parent['grupAkunId'],
        'parentId': parent['id'],
        'aktifitas': '',
        'bankId': 0,
        'atasNama': '',
        'noRek': '',
      });
      ada = await akun(kode);
      expect(ada, isNotEmpty, reason: 'Akun $kode gagal dibuat: $dibuat');
      return ada;
    }

    final pendapatan = await pastikanAkun(
        kode: '410.900',
        nama: 'PENDAPATAN PENJUALAN TOKO',
        induk: '410.000',
        posisi: 2);
    final hpp = await pastikanAkun(
        kode: '510.900',
        nama: 'BEBAN POKOK PENJUALAN TOKO',
        induk: '510.000',
        posisi: 1);
    final piutang = await pastikanAkun(
        kode: '131.300',
        nama: 'PIUTANG USAHA TOKO',
        induk: '130.000',
        posisi: 1);
    final utang = await pastikanAkun(
        kode: '310.600', nama: 'UTANG USAHA TOKO', induk: '310.000', posisi: 2);
    final labaDitahan = await pastikanAkun(
        kode: '331.900',
        nama: 'LABA DITAHAN EBISNIS',
        induk: '330.000',
        posisi: 2);
    await pastikanAkun(
        kode: '512.115', nama: 'BEBAN SEWA TOKO', induk: '512.100', posisi: 1);
    await pastikanAkun(
        kode: '131.900',
        nama: 'CADANGAN KERUGIAN PIUTANG',
        induk: '130.000',
        posisi: 2);

    const kasId = 3800001;
    const persediaanId = 6400001;
    const modalId = 33800001;
    const bebanListrikId = 23000001;

    await aksi('toko_kelola_simpan', {
      'id': _tokoId,
      'nama': 'Demo',
      'kode': '001',
      'keterangan': 'Toko Demo dengan data sample praktik akuntansi Apotik',
      'aktif': true,
      'boleh_melihat_toko_lain': false,
      'boleh_transaksi_stok_habis': true,
      'toko_demo': true,
      'unit_usaha': ['TOKO_KELONTONG'],
      'akun_kas_id': kasId,
      'akun_piutang_id': piutang['id'],
      'akun_modal_awal_id': modalId,
      'akun_laba_ditahan_id': labaDitahan['id'],
    });

    final cara = await ApiClient.instance.aksi('cara_bayar_list_admin', {
      'keyword': 'Tunai',
      'page': 1,
      'page_size': 20,
    });
    final tunai = ((cara['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere((e) => '${e['nama']}'.toLowerCase() == 'tunai');
    await aksi('cara_bayar_simpan', {
      'id': tunai['id'],
      'kode': tunai['kode'],
      'nama': tunai['nama'],
      'keterangan': tunai['keterangan'],
      'manual': tunai['manual'] != false,
      'online': tunai['online'] == true,
      'memotongDeposit': tunai['memotongDeposit'] == true,
      'masukSebagaiHutang': tunai['masukSebagaiHutang'] == true,
      'wajibPilihMember': tunai['wajibPilihMember'],
      'akunId': kasId,
      'adaKembalian': tunai['adaKembalian'] == true,
      'aktif': tunai['aktif'] != false,
    });

    // Satu metode kredit dengan akun piutang diperlukan sebagai fallback jurnal
    // penerimaan piutang. Layar posting lanjutan saat ini tidak mengirim tokoId,
    // sehingga server memakai metode bertanda masukSebagaiHutang untuk mencari akun.
    final caraKredit = await ApiClient.instance.aksi('cara_bayar_list_admin', {
      'keyword': 'KREDIT-UAT',
      'page': 1,
      'page_size': 20,
    });
    final daftarKredit = ((caraKredit['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => '${e['kode']}'.toUpperCase() == 'KREDIT-UAT')
        .toList();
    final kredit =
        daftarKredit.isEmpty ? <String, dynamic>{} : daftarKredit.first;
    await aksi('cara_bayar_simpan', {
      if (kredit.isNotEmpty) 'id': kredit['id'],
      'kode': 'KREDIT-UAT',
      'nama': 'Kredit Pelanggan (Sample)',
      'keterangan': 'Metode sample untuk jurnal piutang UAT Akuntansi',
      'manual': true,
      'online': false,
      'memotongDeposit': false,
      'masukSebagaiHutang': true,
      'wajibPilihMember': true,
      'akunId': piutang['id'],
      'adaKembalian': false,
      'aktif': true,
    });

    Future<Map<String, dynamic>> produk(String kata) async {
      final r = await ApiClient.instance
          .aksi('katalog', {'keyword': kata, 'semuaToko': true});
      final daftar = (r['produk'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));
      return daftar.firstWhere((e) => '${e['nama']}' == kata,
          orElse: () => daftar.first);
    }

    Future<void> petakanJenisProduk(Map<String, dynamic> p) async {
      final kategori = '${p['kategoriNama']}';
      final r = await ApiClient.instance.aksi('jenis_produk_list', {
        'keyword': kategori,
        'page': 1,
        'page_size': 100,
        'termasuk_nonaktif': true,
      });
      final daftar = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));
      final jenis = daftar.firstWhere(
          (e) => (e['id'] as num).toInt() == (p['kategoriId'] as num).toInt());
      await aksi('jenis_produk_simpan', {
        'id': jenis['id'],
        'nama': jenis['nama'],
        'keterangan': jenis['keterangan'],
        'maksimalHarian': jenis['maksimalHarian'],
        'defaultProduk': jenis['defaultProduk'] == true,
        'aktif': jenis['aktif'] != false,
        'akunPendapatanId': pendapatan['id'],
        'akunPpnKeluaranId': jenis['akunPpnKeluaranId'],
        'akunHppId': hpp['id'],
        'akunSelisihPersediaanId': hpp['id'],
        'akunReturPenjualanId': pendapatan['id'],
      });
    }

    // Fixture katalog demo aktif pada toko 1. Nama produk lama sudah tidak ada
    // setelah penyegaran basis data publik, sehingga gunakan item yang benar-
    // benar tersedia dan memiliki stok pada toko ini.
    final produkKecap = await produk('ABC Kacang hijau 200ml (hijau)');
    final produkWafer = await produk('ABC Kacang hijau 200ml (hijau)');
    await petakanJenisProduk(produkKecap);
    await petakanJenisProduk(produkWafer);

    // Produk demo hasil provision berada pada kelompok aset bawaan "Barang
    // ATK". Posting Kulakan membaca akun persediaan dari Kelompok Aset (yang
    // memang mengalahkan akun Master Aset), sehingga kategori produk saja tidak
    // cukup. Data tenant ini adalah tenant demo/UAT; pemetaan global berikut
    // sengaja menjadikan pembelian barang dagang sebagai persediaan dan HPP.
    final kelompokAset = await ApiClient.instance
        .aksi('kelompok_aset_list', {'keyword': 'Barang ATK', 'limit': 20});
    final kelompokBarang = ((kelompokAset['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .firstWhere((e) => '${e['nama']}' == 'Barang ATK',
            orElse: () => <String, dynamic>{});
    if (kelompokBarang.isNotEmpty) {
      await aksi('kelompok_aset_akun_simpan', {
        'id': kelompokBarang['id'],
        'bidang': 'pembelian',
        'baris': [
          {'akun': persediaanId, 'satuanKerja': null}
        ],
      });
      await aksi('kelompok_aset_akun_simpan', {
        'id': kelompokBarang['id'],
        'bidang': 'hpp',
        'baris': [
          {'akun': hpp['id'], 'satuanKerja': null}
        ],
      });
    }

    Future<int> pastikanSupplier() async {
      final r = await ApiClient.instance
          .aksi('penyedia_list', {'keyword': 'CV Sumber Pangan Nusantara'});
      final daftar = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final existing =
          daftar.where((e) => '${e['nama']}' == 'CV Sumber Pangan Nusantara');
      int? id = existing.isEmpty ? null : (existing.first['id'] as num).toInt();
      final simpan = await aksi('penyedia_simpan', {
        if (id != null) 'id': id,
        'kode': 'UAT-SUP-001',
        'nama': 'CV Sumber Pangan Nusantara',
        'kontak': 'Rina Pratama',
        'telp': '021-555-0101',
        'fax': '',
        'email': 'purchasing@contoh.invalid',
        'alamat': 'Kawasan Niaga Demo, Jakarta',
        'kode_pos': '10110',
        'keterangan': 'Supplier sample UAT Akuntansi eBisnis',
        'akunUtangId': utang['id'],
      });
      id ??= (simpan['id'] as num?)?.toInt();
      expect(id, isNotNull, reason: 'Supplier sample tidak terbentuk');
      return id!;
    }

    final supplierId = await pastikanSupplier();

    Future<int> pastikanFaktur(String nomor, int qty, double harga) async {
      final list = await ApiClient.instance.aksi('kulakan_faktur_list', {
        'keyword': nomor,
        'page': 1,
        'page_size': 20,
      });
      final cocok = ((list['data'] as List?) ?? const [])
          .whereType<Map>()
          .where((e) => '${e['nomorFaktur']}' == nomor)
          .toList();
      if (cocok.isNotEmpty) return (cocok.first['fakturId'] as num).toInt();
      final r = await aksi('kulakan_faktur_simpan', {
        'toko_id': _tokoId,
        'nomor_faktur': nomor,
        'tanggal_faktur': '${_tanggal}T09:00:00',
        'supplier_id': supplierId,
        'keterangan': 'Pembelian persediaan sample UAT Akuntansi',
        'items': [
          {
            'produk_id': produkWafer['id'],
            'qty': qty,
            'harga_beli_satuan': harga,
          }
        ],
      });
      return (r['fakturId'] as num).toInt();
    }

    final fakturA = await pastikanFaktur('UAT-INV-20260904-A', 4, 150000);
    final fakturB = await pastikanFaktur('UAT-INV-20260904-B', 3, 150000);
    for (final id in [fakturA, fakturB]) {
      await aksi('si_purchase_terms_save', {
        'faktur_id': id,
        'jenis_pembayaran': 'CREDIT',
        'termin_hari': 30,
        'keterangan': 'Termin sample 30 hari',
      });
    }

    Future<void> pastikanPembayaran(
        int fakturId, String kode, double nilai) async {
      final r = await ApiClient.instance.aksi('si_payable_list', {
        'supplier_id': supplierId,
        'tampilkan_lunas': true,
        'page_size': 100,
      });
      final baris = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .firstWhere((e) => (e['fakturId'] as num).toInt() == fakturId);
      final outstanding = (baris['outstanding'] as num).toDouble();
      if (outstanding <=
          (baris['totalFaktur'] as num).toDouble() - nilai + .01) {
        return;
      }
      await aksi('si_payable_payment_create', {
        'supplier_id': supplierId,
        'nominal': nilai,
        'metode': 'TUNAI',
        'no_bg': '',
        'nama_bank': '',
        'keterangan': 'Pembayaran parsial sample UAT Akuntansi',
        'kode_unik': kode,
        'alokasi': [
          {'faktur_id': fakturId, 'nominal': nilai}
        ],
      });
    }

    await pastikanPembayaran(fakturA, 'UAT-PH-20260904-A', 200000);
    await pastikanPembayaran(fakturB, 'UAT-PH-20260904-B', 150000);

    Future<int> pastikanOrder(String kode, double harga) async {
      final dibuat = await aksi('si_sales_order_create', {
        'toko_id': _tokoId,
        'customer_id': 1,
        'kode_unik': kode,
        'tanggal': _tanggal,
        'keterangan': 'Penjualan kredit sample UAT Akuntansi',
        'items': [
          {
            'produk_id': produkWafer['id'],
            'jumlah': 1,
            'harga': harga,
          }
        ],
      });
      final id = (dibuat['id'] as num).toInt();
      for (var i = 0; i < 5; i++) {
        final detail = await ApiClient.instance
            .aksi('si_sales_order_detail', {'order_id': id});
        final d = Map<String, dynamic>.from(detail['data'] as Map);
        final status = '${d['status']}';
        if (status == 'DRAFT') {
          await aksi(
              'si_sales_order_status', {'order_id': id, 'status': 'PESAN'});
        } else if (status == 'PESAN') {
          await aksi('si_sales_order_status',
              {'order_id': id, 'status': 'SIAP_KIRIM'});
        } else if (status == 'SIAP_KIRIM') {
          await aksi(
              'si_sales_order_status', {'order_id': id, 'status': 'TERKIRIM'});
        } else if (status == 'TERKIRIM') {
          await aksi('si_sales_order_invoice', {'order_id': id});
        } else {
          break;
        }
      }
      return id;
    }

    final orderA = await pastikanOrder('UAT-SO-AKUNTANSI-20260904-A', 375000);
    final orderB = await pastikanOrder('UAT-SO-AKUNTANSI-20260904-B', 425000);

    Future<void> pastikanPenerimaan(
        int orderId, String kode, double nilai) async {
      final r = await ApiClient.instance.aksi('si_receivable_list', {
        'customer_id': 1,
        'tampilkan_lunas': true,
        'page': 1,
        'page_size': 100,
      });
      final piutangDoc = ((r['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .firstWhere((e) => (e['orderId'] as num?)?.toInt() == orderId);
      final total = (piutangDoc['totalFaktur'] as num).toDouble();
      final outstanding = (piutangDoc['outstanding'] as num).toDouble();
      if (outstanding <= total - nilai + .01) return;
      await aksi('si_collection_create', {
        'customer_id': 1,
        'nominal': nilai,
        'metode': 'TUNAI',
        'keterangan': 'Penerimaan parsial sample UAT Akuntansi',
        'kode_unik': kode,
        'alokasi': [
          {'piutang_id': piutangDoc['id'], 'nominal': nilai}
        ],
      });
    }

    await pastikanPenerimaan(orderA, 'UAT-KWT-20260904-A', 175000);
    await pastikanPenerimaan(orderB, 'UAT-KWT-20260904-B', 200000);

    Future<void> jurnalSample(String keterangan,
        List<({String kode, double debet, double kredit})> baris) async {
      // Satu kali saja: endpoint daftar Jurnal Umum pada build server pasca-
      // restart sedang regresi, sehingga pemeriksaan idempoten server tidak
      // tersedia. Aktifkan hanya pada eksekusi awal dengan POS_SEED_PNL_ONCE.
      const seedSekali = bool.fromEnvironment('POS_SEED_PNL_ONCE');
      if (!seedSekali) return;
      final akunBaris = <Map<String, dynamic>>[];
      for (final b in baris) {
        final a = await akun(b.kode);
        expect(a, isNotEmpty, reason: 'Akun ${b.kode} jurnal sample tidak ada');
        akunBaris.add({
          'akunId': a['id'],
          'debet': b.debet,
          'kredit': b.kredit,
          'keterangan': keterangan,
        });
      }
      final dibuat = await aksi('jurnal_umum_simpan', {
        'tanggal': _tanggal,
        'keterangan': keterangan,
        'jenisTransaksiId': 0,
        'baris': akunBaris,
      });
      final id = (dibuat['id'] as num).toInt();
      await aksi('jurnal_umum_posting', {
        'ids': [id]
      });
    }

    await jurnalSample('UAT Sample - Penjualan tunai harian', [
      (kode: '111.101', debet: 3500000, kredit: 0),
      (kode: '410.900', debet: 0, kredit: 3500000),
    ]);
    await jurnalSample('UAT Sample - Penjualan kredit pelanggan', [
      (kode: '131.300', debet: 1250000, kredit: 0),
      (kode: '410.900', debet: 0, kredit: 1250000),
    ]);
    await jurnalSample('UAT Sample - Beban pokok penjualan', [
      (kode: '510.900', debet: 2100000, kredit: 0),
      (kode: '151.200', debet: 0, kredit: 2100000),
    ]);
    await jurnalSample('UAT Sample - Beban listrik dan internet', [
      (kode: '512.104', debet: 350000, kredit: 0),
      (kode: '111.101', debet: 0, kredit: 350000),
    ]);
    await jurnalSample('UAT Sample - Beban sewa outlet', [
      (kode: '512.115', debet: 500000, kredit: 0),
      (kode: '111.101', debet: 0, kredit: 500000),
    ]);
    await jurnalSample('UAT Sample - Penyisihan piutang', [
      (kode: '516.101', debet: 100000, kredit: 0),
      (kode: '131.900', debet: 0, kredit: 100000),
    ]);

    Future<void> saldo(
        String kode, double debet, double kredit, String ket) async {
      final r = await ApiClient.instance.aksi('saldo_awal_daftar', {});
      final sudah = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .any((e) => '${e['kodeAkun']}' == kode);
      if (!sudah) {
        await aksi('saldo_awal_simpan', {
          'kodeAkun': kode,
          'debet': debet,
          'kredit': kredit,
          'tanggal': '2026-01-01',
          'keterangan': ket,
        });
      }
    }

    await saldo('111.101', 15000000, 0, 'Saldo kas operasional awal');
    await saldo('151.200', 5000000, 0, 'Persediaan barang dagang awal');
    await saldo('131.300', 2000000, 0, 'Piutang usaha awal');
    await saldo('310.600', 0, 4000000, 'Utang usaha awal');
    await saldo('800.000', 0, 18000000, 'Modal awal usaha');
    final drafSaldo = await aksi('saldo_awal_draft', {});
    if (drafSaldo['siap'] == true &&
        ((drafSaldo['rincian'] as List?) ?? const []).isNotEmpty) {
      await aksi('saldo_awal_posting', {});
    }

    Future<void> template(String nama, String debet, String kredit,
        double nilai, String ket) async {
      final r =
          await ApiClient.instance.aksi('penyesuaian_template_daftar', {});
      final sudah = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .any((e) => '${e['nama']}' == nama);
      if (!sudah) {
        await aksi('penyesuaian_template_simpan', {
          'nama': nama,
          'akunDebetKode': debet,
          'akunKreditKode': kredit,
          'nilai': nilai,
          'frekuensi': 'BULANAN',
          'aktif': true,
          'keterangan': ket,
        });
      }
    }

    await template('Amortisasi Sewa Dibayar Dimuka', '512.115', '161.100',
        500000, 'Amortisasi sewa outlet per bulan');
    await template('Akrual Listrik dan Internet', '512.104', '311.403', 350000,
        'Estimasi utilitas yang belum ditagih');
    await template('Penyisihan Piutang Usaha', '516.101', '131.900', 100000,
        'Estimasi kerugian piutang bulanan');
    final drafPenyesuaian =
        await aksi('penyesuaian_draft', {'periode': '2026-09'});
    final idSiap = ((drafPenyesuaian['rincian'] as List?) ?? const [])
        .whereType<Map>()
        .where((e) => e['siap'] == true)
        .map((e) => e['id'])
        .where((e) => e != null)
        .toList();
    if (idSiap.isNotEmpty) {
      await aksi('penyesuaian_posting', {
        'periode': '2026-09',
        'posting_ids': idSiap,
      });
    }

    Future<void> anggaran(
        String kode, String nama, int akunId, List<double> bulan) async {
      final r = await ApiClient.instance.aksi('anggaran_item_list', {
        'tahun': 2025,
        'satkerId': 20000025,
        'sumberDanaId': 0,
        'revisi': 1,
        'cari': kode,
      });
      final cocok = ((r['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => '${e['kode']}' == kode)
          .toList();
      // Bersihkan duplikat yang pernah terbentuk oleh versi awal skrip UAT.
      // Hanya baris sample berpenanda ini yang disentuh; data pengguna lain aman.
      for (final duplikat in cocok.skip(1)) {
        if ('${duplikat['keterangan']}' ==
            'RAB sample praktik terbaik eBisnis') {
          await aksi('anggaran_item_hapus', {'id': duplikat['id']});
        }
      }
      if (cocok.isEmpty) {
        await aksi('anggaran_item_simpan', {
          'tahun': 2025,
          'satkerId': 20000025,
          'sumberDanaId': 0,
          'revisi': 1,
          'parentId': 0,
          'kode': kode,
          'nama': nama,
          'keterangan': 'RAB sample praktik terbaik eBisnis',
          'qty': 1,
          'satuanVolume': 'Paket',
          'hargaSatuan': bulan.fold<double>(0, (a, b) => a + b),
          'akunId': akunId,
          'aktif': true,
          'bulan': bulan,
        });
      }
    }

    await anggaran('OPS-001', 'Pembelian Persediaan Toko', persediaanId,
        List<double>.filled(12, 2000000));
    await anggaran('OPS-002', 'Listrik dan Internet Outlet', bebanListrikId,
        List<double>.filled(12, 750000));
    await anggaran(
        'OPS-003', 'Pemasaran dan Promosi', (hpp['id'] as num).toInt(), [
      500000,
      500000,
      750000,
      750000,
      1000000,
      1000000,
      1000000,
      1000000,
      1250000,
      1250000,
      1500000,
      1500000
    ]);

    Future<void> postingSatuJikaBisa(String jenis) async {
      final draf = await aksi('posting_${jenis}_draft', {
        'mulai': '2026-09-01',
        'sampai': _tanggal,
      });
      final siap = ((draf['rincian'] as List?) ?? const [])
          .whereType<Map>()
          .where((e) => e['siap'] == true)
          .toList();
      if (siap.length >= 2) {
        await aksi('posting_${jenis}_terapkan', {
          'mulai': '2026-09-01',
          'sampai': _tanggal,
          'posting_ids': [siap.first['id']],
        });
      }
    }

    await postingSatuJikaBisa('kulakan');
    await postingSatuJikaBisa('bayar_hutang');
    await postingSatuJikaBisa('terima_piutang');

    final verifikasi = <String, dynamic>{};
    for (final jenis in ['kulakan', 'bayar_hutang', 'terima_piutang']) {
      final r = await ApiClient.instance.aksi('posting_${jenis}_draft', {
        'mulai': '2026-09-01',
        'sampai': _tanggal,
      });
      verifikasi[jenis] = {
        'jumlahDraf': r['jumlahDraf'],
        'jumlahSiap': r['jumlahSiap'],
      };
    }
    // ignore: avoid_print
    print('SEED_VERIFIKASI=${jsonEncode(verifikasi)}');
  });
}
