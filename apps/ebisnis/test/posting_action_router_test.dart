import 'package:ebisnis/services/posting_action_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routing posting Apotik', () {
    test('penjualan dan HPP memakai endpoint khusus Apotik', () {
      expect(
        aksiPostingKeuangan(apotik: true, jenis: 'penjualan', terapkan: false),
        'apotik_posting_penjualan_draft',
      );
      expect(
        aksiPostingKeuangan(apotik: true, jenis: 'hpp', terapkan: true),
        'apotik_posting_hpp_terapkan',
      );
    });

    test('penerimaan dan pembayaran PBF memakai endpoint khusus Apotik', () {
      expect(
        aksiPostingToko(apotik: true, jenis: 'kulakan', terapkan: false),
        'apotik_posting_pbf_draft',
      );
      expect(
        aksiPostingToko(apotik: true, jenis: 'bayar_hutang', terapkan: true),
        'apotik_posting_bayar_hutang_pbf_terapkan',
      );
    });

    test('varian toko lama tidak berubah', () {
      expect(
        aksiPostingKeuangan(apotik: false, jenis: 'penjualan', terapkan: false),
        'laporan_keuangan_pendukung',
      );
      expect(
        aksiPostingToko(apotik: false, jenis: 'kulakan', terapkan: true),
        'posting_kulakan_terapkan',
      );
    });

    test('proses Apotik tanpa kontrak khusus ditolak fail-closed', () {
      expect(
        () => aksiPostingToko(
            apotik: true, jenis: 'terima_piutang', terapkan: false),
        throwsUnsupportedError,
      );
      expect(
        () =>
            aksiPostingToko(apotik: true, jenis: 'penyesuaian', terapkan: true),
        throwsUnsupportedError,
      );
    });
  });
}
