import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kontrak sisi klien grup "Keuangan": dasbor, cetak, tulis lokal-dulu, dan
/// penghapusan yang di perangkat bersifat SOFT (barisnya ditandai, bukan dibuang)
/// sehingga datanya masih bisa dipulihkan. Di server penghapusannya sungguhan --
/// riwayatnya ada pada audit trail server.
void main() {
  final layar = {
    'Uang Muka': File('lib/screens/uang_muka_screen.dart').readAsStringSync(),
    'PJ Uang Muka': File('lib/screens/pj_uang_muka_screen.dart').readAsStringSync(),
    'Kas Besar': File('lib/screens/kas_besar_screen.dart').readAsStringSync(),
    'PJ Kas Besar': File('lib/screens/pj_kas_besar_screen.dart').readAsStringSync(),
    'Kas Kecil': File('lib/screens/kas_kecil_screen.dart').readAsStringSync(),
    'Penggantian Kas Kecil':
        File('lib/screens/penggantian_kas_kecil_screen.dart').readAsStringSync(),
    'Dana Talangan': File('lib/screens/dana_talangan_screen.dart').readAsStringSync(),
    'Reimbursement': File('lib/screens/reimbursement_screen.dart').readAsStringSync(),
  };

  layar.forEach((nama, source) {
    group(nama, () {
      test('membaca salinan lokal dulu', () {
        expect(source, contains('MasterOffline.daftarCacheDulu('));
        expect(source, contains('_cacheKey'));
      });

      test('create/edit/hapus ditulis lokal dulu, bukan langsung ke server', () {
        expect(source, contains('prosesSimpanMaster('));
        expect(source, contains('_kirimLokalDulu('));
        // Tidak boleh ada lagi jalur tulis yang menembak server langsung.
        expect(source, isNot(contains('await ApiClient.instance.aksi(\'uang_muka_simpan')));
        expect(source, isNot(contains('await ApiClient.instance.aksi(\'pj_uang_muka_simpan')));
        // Baris baru yang dibuat offline membawa id sementaranya sendiri.
        expect(source, contains('MasterOffline.idSementaraBaru()'));
        expect(source, contains('idLokal:'));
      });

      test('hapus bersifat soft di perangkat + dapat dibatalkan', () {
        // Penandaannya diserahkan ke MasterOffline (mekanisme bersama): baris
        // ditandai `_dihapus`, disaring dari daftar, dan pembatalannya IKUT
        // membuang perintah hapus yang masih mengantre -- tanpa itu baris kembali
        // tampil tetapi tetap terhapus di server begitu jaringan tersambung.
        expect(source, contains('hapusLokal: true'));
        expect(source, contains('MasterOffline.pulihkanLokal('));
        expect(source, contains('MasterOffline.daftarTerhapusLokal('));
        // Daftar utama menyembunyikannya; ada penyaring khusus untuk melihatnya.
        expect(source, contains('_terlihat'));
        expect(source, contains('_tampilkanTerhapus'));
      });

      test('punya tab Dasbor dan tombol Cetak seperti menu Pengadaan', () {
        expect(source, contains('PengadaanDasborTab('));
        expect(source, contains("aksi: 'keuangan_dasbor'"));
        expect(source, contains("namaParam: 'modul'"));
        expect(source, contains('cetakDokumenKeuangan('));
      });
    });
  });

  test('Penggantian Kas Kecil menunjuk DOKUMEN kas kecil, bukan jenisnya', () {
    final src =
        File('lib/screens/penggantian_kas_kecil_screen.dart').readAsStringSync();
    // Seperti layar ZK: yang dipilih satu dokumen kas kecil yang sudah disetujui
    // dan belum diganti; rinciannya ikut terbawa untuk disunting di sini.
    expect(src, contains("'penggantian_kas_kecil_cari_kas_kecil'"));
    expect(src, contains("'kasKecilId'"));
    expect(src, contains('Kas Kecil yang Diganti'));
    // Jenis kas kecil adalah milik dokumen induknya, bukan dokumen penggantian.
    expect(src, isNot(contains("'jenisKasKecilId'")));
  });

  group('penggunaan anggaran', () {
    // Pemotongan anggaran AIS dicatat PER BARIS: PenggunaanAnggaran.prosesKasKecil /
    // prosesKasBesar melewati baris formula yang tidak membawa `workspace`. Karena itu
    // rincian kas wajib punya pemilih anggarannya sendiri.
    for (final nama in const [
      'kas_kecil_screen.dart',
      'kas_besar_screen.dart',
      'penggantian_kas_kecil_screen.dart',
    ]) {
      test('$nama: rincian membawa anggaran', () {
        final src = File('lib/screens/$nama').readAsStringSync();
        expect(src, contains('PemilihAnggaranField('));
        expect(src, contains("'workspace': workspaceId"));
        expect(src, contains('_cari_anggaran'));
        // Akun biaya ikut ditentukan anggaran, seperti banbox ZK.
        expect(src, contains("(w['akunId'] as num?)?.toInt()"));
      });
    }

    test('pemilih anggaran memakai satu widget bersama', () {
      final w = File('lib/widgets/pemilih_anggaran.dart').readAsStringSync();
      expect(w, contains('class PemilihAnggaranField'));
      expect(w, contains('aksiCari'));
      // Anggaran difilter per tahun dokumen, sama seperti di ZK.
      expect(w, contains("'tahun': tahun"));
    });
  });

  group('muara DPC (Daftar Pengajuan Transfer)', () {
    // Kas Kecil sengaja TIDAK ada di daftar ini: pengeluaran kas kecil tidak
    // ditransfer satu per satu, uangnya kembali lewat Penggantian Kas Kecil.
    const modul = {
      'uang_muka_screen.dart': 'uang_muka',
      'pj_uang_muka_screen.dart': 'pj_uang_muka',
      'kas_besar_screen.dart': 'kas_besar',
      'pj_kas_besar_screen.dart': 'pj_kas_besar',
      'penggantian_kas_kecil_screen.dart': 'penggantian_kas_kecil',
    };
    modul.forEach((berkas, kunci) {
      test('$berkas: punya tombol Ajukan Transfer + status DPC', () {
        final src = File('lib/screens/$berkas').readAsStringSync();
        expect(src, contains("'${kunci}_ajukan_transfer'"));
        // Hanya dokumen yang sudah disetujui yang boleh diajukan.
        expect(src, contains("status == 'Disetujui'"));
        // Yang sudah masuk kolam transfer tidak ditawarkan lagi.
        expect(src, contains("b['dpcAda'] == true"));
      });
    });

    test('Kas Kecil tidak punya pengajuan transfer', () {
      final src = File('lib/screens/kas_kecil_screen.dart').readAsStringSync();
      expect(src, isNot(contains('ajukan_transfer')));
    });
  });

  test('Dana Talangan menunjuk uang muka yang transfernya sudah terealisasi', () {
    final src = File('lib/screens/dana_talangan_screen.dart').readAsStringSync();
    expect(src, contains("'dana_talangan_cari_uang_muka'"));
    expect(src, contains("'uangMukaId'"));
    expect(src, contains('Uang Muka yang Ditalangi'));
    // Sumber dana menentukan akun kredit jurnalnya; baru wajib saat disetujui.
    expect(src, contains('Sumber Dana Talangan'));
    // Dokumen ini bernilai tunggal -- tidak ada mesin rincian seperti kas kecil.
    expect(src, isNot(contains('Rincian Biaya')));
  });

  test('kunci antrean luring unik per modul, tidak menumpang Kas Besar', () {
    // Pernah salah: layar Kas Kecil, Penggantian, dan Dana Talangan memakai
    // "kas_besar:<id>" saat menyunting, sehingga suntingan luring dokumen ber-id
    // sama menempati slot antrean yang sama dan saling menimpa.
    const pasangan = {
      'kas_kecil_screen.dart': 'kas_kecil',
      'penggantian_kas_kecil_screen.dart': 'penggantian_kas_kecil',
      'dana_talangan_screen.dart': 'dana_talangan',
      'kas_besar_screen.dart': 'kas_besar',
    };
    pasangan.forEach((berkas, kunci) {
      final src = File('lib/screens/$berkas').readAsStringSync();
      expect(src, contains("kunci: ubah ? '$kunci:"), reason: berkas);
    });
  });

  group('Reimbursement Pegawai', () {
    final src = File('lib/screens/reimbursement_screen.dart').readAsStringSync();

    test('keputusan tiga arah, bukan hanya setuju/tolak', () {
      // "Minta Revisi" mengembalikan pengajuan kepada pengaju; itu yang membedakan
      // modul ini dari modul Keuangan lain.
      expect(src, contains("'reimbursement_setujui'"));
      expect(src, contains("'reimbursement_revisi'"));
      expect(src, contains("'reimbursement_tolak'"));
    });

    test('penolakan & revisi menuntut catatan atasan', () {
      expect(src, contains('_mintaCatatan('));
      expect(src, contains("'catatanAtasan'"));
    });

    test('akun baris diturunkan dari Jenis Pengeluaran, bukan dipilih langsung', () {
      expect(src, contains("'jenisPengeluaran'"));
      expect(src, contains('Jenis Pengeluaran *'));
      // Jenis yang akunnya belum dipetakan tetap tampil, dengan peringatan.
      expect(src, contains('belum dipetakan administrator'));
    });

    test('anggaran hanya diminta bila jenisnya memakai anggaran', () {
      expect(src, contains('_pakaiAnggaran('));
      expect(src, contains("e['menggunakanAnggaran'] == true"));
    });

    test('pegawai penerima dipilih dari daftar', () {
      expect(src, contains("'reimbursement_cari_pegawai'"));
      expect(src, contains('Pegawai Penerima'));
    });
  });

  test('widget dasbor dipakai ulang, bukan diduplikasi', () {
    final tab = File('lib/screens/pengadaan_dasbor_tab.dart').readAsStringSync();
    // Aksi & nama parameternya kini dapat diatur, sehingga grup menu lain memakai
    // widget yang sama persis dengan Pengadaan.
    expect(tab, contains('this.aksi ='));
    expect(tab, contains('this.namaParam ='));
    expect(tab, contains('widget.aksi'));
    expect(tab, contains('widget.namaParam'));
  });

  group('Proses Transfer (pencairan DPC)', () {
    final src = File('lib/screens/proses_transfer_screen.dart').readAsStringSync();

    test('empat tahap alurnya lengkap', () {
      // Tanpa salah satu aksi ini, dokumen Keuangan berhenti sebelum bisa dijurnal.
      for (final aksi in [
        'proses_transfer_kandidat',
        'proses_transfer_simpan',
        'proses_transfer_setujui',
        'proses_transfer_tandai',
        'proses_transfer_realisasikan',
      ]) {
        expect(src, contains("'$aksi'"), reason: aksi);
      }
    });

    test('pembatalan tersedia untuk kedua tahap yang mengunci', () {
      expect(src, contains("'proses_transfer_batal_setuju'"));
      expect(src, contains("'proses_transfer_batal_realisasi'"));
    });

    test('tanda Transfer/Transitori dijelaskan sebagai penentu akun kredit', () {
      // Kalau tandanya diperlakukan sebagai label kosmetik, pengguna tidak akan
      // tahu mengapa dokumennya tidak terjurnal.
      expect(src, contains('akun kredit'));
      expect(src, contains('belum bertanda'));
    });

    test('aksi baris mengikuti status dokumen, bukan selalu tersedia', () {
      expect(src, contains("final draft = status == 'Draft';"));
      expect(src, contains("final disetujui = status == 'Disetujui';"));
      expect(src, contains("final cair = status == 'Terealisasi';"));
    });

    test('kategori Lainnya ikut ditawarkan sebagai jaring pengaman', () {
      // Penyaring kategori di layar ZK berpola daftar putih per kolom sumber,
      // sehingga sumber yang belum punya cabangnya tidak pernah tampil. Di sini
      // kategorinya datang dari server dan memuat "Lainnya".
      expect(src, contains('kategoriAktif'));
      expect(src, contains('_kategori'));
    });
  });

  group('Master Data Keuangan', () {
    final src = File('lib/screens/master_keuangan_screen.dart').readAsStringSync();

    test('keenam tipe dilayani satu formulir yang digerakkan metadata server', () {
      // Yang berbeda antar tipe hanya LABEL medan akunnya; kuncinya posisional
      // dan sama untuk semuanya, sehingga tidak ada cabang per tipe di layar ini.
      for (final aksi in [
        'master_keuangan_opsi',
        'master_keuangan_daftar',
        'master_keuangan_simpan',
        'master_keuangan_hapus',
      ]) {
        expect(src, contains("'$aksi'"), reason: aksi);
      }
      expect(src, contains('medanAkun'));
      expect(src, contains('punyaKode'));
      expect(src, contains('punyaAnggaran'));
      expect(src, contains('punyaSatuanKerja'));
      // Tidak boleh ada cabang berdasarkan nama tipe di sisi layar.
      expect(src, isNot(contains("== 'jenis_kas_besar'")));
      expect(src, isNot(contains("== 'jenis_uang_muka'")));
    });

    test('antrean luring dan cache dipisah per tipe', () {
      // Enam tipe berbagi satu layar tetapi id-nya berasal dari tabel berbeda:
      // tanpa nama tipe pada kuncinya, dua master ber-id sama akan bertabrakan
      // di antrean luring maupun di cache.
      expect(src, contains(r"'master_keuangan:$tipe'"));
      expect(src, contains(r"kunci: 'master_keuangan:${meta['tipe']}:"));
    });

    test('akun yang belum lengkap diperingatkan, bukan didiamkan', () {
      // Dokumen yang jenisnya belum berakun tetap bisa diajukan tetapi DILEWATI
      // mesin posting tanpa pesan galat -- itulah yang diperingatkan di sini.
      expect(src, contains('belumLengkap'));
      expect(src, contains('akunLengkap'));
      expect(src, contains('tidak akan terjurnal'));
    });

    test('jenis yang sudah dipakai dokumen tidak ditawarkan untuk dihapus', () {
      expect(src, contains("b['dipakai']"));
      expect(src, contains('Nonaktifkan saja bila tidak dipakai lagi.'));
    });
  });

  test('cetak Keuangan memakai jendela pratinjau yang sama dengan Pengadaan', () {
    final util = File('lib/screens/keuangan_cetak_util.dart').readAsStringSync();
    expect(util, contains("'keuangan_cetak'"));
    expect(util, contains('tampilkanPratinjauPdf('));
  });
}
