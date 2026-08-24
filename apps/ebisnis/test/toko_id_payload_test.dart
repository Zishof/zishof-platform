import 'package:ebisnis/api_client.dart';
import 'package:ebisnis/sesi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aturan penyisipan toko ke payload. Ini menentukan ke toko MANA sebuah
/// simpanan mendarat -- salah di sini tidak memunculkan galat apa pun, hanya
/// data yang duduk di tempat yang keliru sampai ada yang menyadarinya.
void main() {
  group('kontrak status respons server', () {
    test('menerima status baru dan status legacy', () {
      expect(ApiClient.statusResponsSukses('success'), isTrue);
      expect(ApiClient.statusResponsSukses('00'), isTrue);
    });

    test('tetap menolak status kegagalan', () {
      expect(ApiClient.statusResponsSukses('99'), isFalse);
      expect(ApiClient.statusResponsSukses('error'), isFalse);
      expect(ApiClient.statusResponsSukses(null), isFalse);
    });
  });

  setUp(() {
    Sesi.instance
      ..tokoId = null
      ..tokoFilter = null
      ..bolehSemuaToko = false
      ..isAdmin = false
      ..daftarTokoFilter = const [];
  });

  group('aksi yang butuh toko_id', () {
    test('toko terpilih ikut terkirim', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = 22;
      final p = ApiClient.susunPayload('toko_profil_ambil', null);
      expect(p['toko_id'], 22);
    });

    test('nilai dari pemanggil TIDAK ditimpa', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = 22;
      final p = ApiClient.susunPayload('so_simpan', {'toko_id': 99});
      expect(p['toko_id'], 99,
          reason: 'layar yang sudah menentukan tokonya sendiri harus menang');
    });

    test('tanpa toko terpilih, kunci tidak dikirim (server yang menolak)', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = null
        ..tokoId = null;
      final p = ApiClient.susunPayload('produk_simpan', null);
      expect(p.containsKey('toko_id'), isFalse,
          reason: 'lebih baik ditolak daripada menebak toko lalu salah tulis');
    });

    test('akun terikat satu toko memakai tokonya sendiri', () {
      Sesi.instance.tokoId = 7;
      final p = ApiClient.susunPayload('kulakan_faktur_simpan', null);
      expect(p['toko_id'], 7);
    });
  });

  group('aksi yang SENGAJA tidak disisipi', () {
    // Ini mengurus toko AKTIF (tempat transaksi dicatat), bukan toko yang
    // sedang dilihat. Menyuntik pilihan filter ke sini berarti membuka sesi kas
    // atau mencatat transaksi di toko yang salah.
    for (final aksi in const [
      'sesi_kas_buka',
      'sesi_kas_status',
      'sesi_kas_list',
      'pilih_toko_aktif',
      'bayar',
    ]) {
      test('$aksi tidak menerima toko dari filter', () {
        Sesi.instance
          ..bolehSemuaToko = true
          ..tokoFilter = 22
          ..tokoId = 7;
        final p = ApiClient.susunPayload(aksi, null);
        expect(p.containsKey('toko_id'), isFalse);
        expect(p.containsKey('tokoId'), isFalse);
        expect(ApiClient.aksiMemakaiTokoId(aksi), isFalse);
      });
    }
  });

  group('filter Dashboard/Laporan (kunci tokoId, kontrak lama)', () {
    test('dashboard_ ikut filter', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = 22;
      expect(ApiClient.susunPayload('dashboard_ringkasan', null)['tokoId'], 22);
    });

    test('laporan_ ikut filter', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = 22;
      expect(ApiClient.susunPayload('laporan_jalankan', null)['tokoId'], 22);
    });

    test('tanpa izin lintas toko, filter tidak disisipkan', () {
      Sesi.instance
        ..bolehSemuaToko = false
        ..tokoFilter = 22;
      expect(
          ApiClient.susunPayload('dashboard_ringkasan', null)
              .containsKey('tokoId'),
          isFalse);
    });
  });

  group('lingkup katalog dipusatkan', () {
    test('akun satu toko selalu membawa toko_id', () {
      Sesi.instance.tokoId = 7;
      expect(ApiClient.susunPayload('katalog', null)['toko_id'], 7);
    });

    test('admin lintas toko tanpa pilihan menyatakan semuaToko', () {
      Sesi.instance
        ..isAdmin = true
        ..tokoId = null
        ..tokoFilter = null;
      expect(ApiClient.susunPayload('katalog', null)['semuaToko'], isTrue);
    });

    test('lingkup eksplisit dari layar tidak ditimpa', () {
      Sesi.instance
        ..isAdmin = true
        ..tokoId = 7;
      final p = ApiClient.susunPayload('katalog', {'semuaToko': true});
      expect(p['semuaToko'], isTrue);
      expect(p.containsKey('toko_id'), isFalse);
    });
  });

  test('daftar aksi ber-toko_id memuat layar yang tadinya gagal utk admin', () {
    // Daftar ini disusun dari penelusuran handler server satu per satu. Uji ini
    // menjaga supaya tidak ada yang terhapus diam-diam saat daftar dirapikan.
    for (final aksi in const [
      'toko_profil_ambil',
      'toko_profil_simpan',
      'pedagang_list',
      'produk_simpan',
      'produk_ekspor_excel',
      'produk_impor_excel_preview',
      'produk_rekonsiliasi_ledger',
      'so_simpan',
      'so_ekspor_excel',
      'so_impor_excel',
      'kulakan_faktur_simpan',
      'peringkat_mitra',
      'layani_transaksi',
      'detail_transaksi',
    ]) {
      expect(ApiClient.aksiMemakaiTokoId(aksi), isTrue, reason: aksi);
    }
  });

  group('aksi transaksi dari layar agregat', () {
    test('pilihan toko dikirim bila tersedia', () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = 22;
      expect(
          ApiClient.susunPayload('layani_transaksi', {'id': 200019})['toko_id'],
          22);
      expect(
          ApiClient.susunPayload('detail_transaksi', {'id': 200019})['toko_id'],
          22);
    });

    test('tanpa pilihan toko, ID tetap dikirim untuk resolusi aman di server',
        () {
      Sesi.instance
        ..bolehSemuaToko = true
        ..tokoFilter = null
        ..tokoId = null;
      final p = ApiClient.susunPayload('layani_transaksi', {'id': 200019});
      expect(p['id'], 200019);
      expect(p.containsKey('toko_id'), isFalse);
    });
  });
}
