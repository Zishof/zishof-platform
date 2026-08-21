-- ============================================================================
-- PEMERIKSAAN: transaksi yang berpotensi selisih antara STRUK KERTAS dan SISTEM
-- ============================================================================
-- HANYA MEMBACA. Tidak ada INSERT/UPDATE/DELETE/ALTER di berkas ini.
--
-- Latar belakang
-- --------------
-- POS bersifat local-first: struk dicetak dari angka keranjang segera setelah
-- transaksi tersimpan di perangkat, TANPA menunggu balasan server. Server
-- sendiri selalu menghitung ULANG promo saat menyimpan dan tidak memakai nilai
-- kiriman kasir. Bila evaluasi diskon di kasir gagal (jaringan lambat/putus),
-- struk tercetak dengan harga PENUH sementara sistem mencatat harga SETELAH
-- diskon -- pelanggan membayar lebih, dan setoran harian jadi lebih besar
-- daripada omzet sistem. Contoh: nota AB22008202600004 (20-08-2026), struk
-- Rp 25.000, tercatat Rp 24.600, selisih Rp 400.
--
-- Batas yang jujur
-- ----------------
-- Database TIDAK menyimpan angka yang tercetak di struk, sehingga kueri ini
-- tidak bisa memastikan mana yang benar-benar selisih. Yang bisa dilakukan:
-- mempersempit ke transaksi yang MEMANG kena diskon -- hanya transaksi inilah
-- yang mungkin berselisih. Kolom `selisih_maksimal` adalah batas ATAS kelebihan
-- bayar bila struknya ternyata mencetak harga penuh.
--
-- Cara pakai: ganti dua tanggal di bawah, lalu cocokkan `selisih_maksimal`
-- dengan setoran QRIS/tunai harian. Transaksi setelah perbaikan terpasang
-- tidak akan muncul lagi sebagai kandidat baru.
-- ============================================================================

WITH periode AS (
    SELECT DATE '2026-08-01' AS dari,
           DATE '2026-08-31' AS sampai
)
SELECT
    t.nama                                   AS toko,
    h.kode                                   AS no_nota,
    h.tanggal_pembayaran                     AS waktu,
    h.kasir_login_nama                       AS kasir,
    cb.nama                                  AS metode_pembayaran,
    ROUND(COALESCE(SUM(b.diskon), 0)::numeric, 2)                        AS diskon_baris,
    ROUND(COALESCE(h.total_diskon, 0)::numeric, 2)                       AS diskon_tercatat_header,
    ROUND(COALESCE(h.total_biaya, 0)::numeric, 2)                        AS total_tercatat,
    ROUND((COALESCE(h.total_biaya, 0) + COALESCE(SUM(b.diskon), 0))::numeric, 2)
                                             AS total_bila_struk_harga_penuh,
    ROUND(COALESCE(SUM(b.diskon), 0)::numeric, 2)                        AS selisih_maksimal
FROM koperasi.pembelian_anggota_koperasi h
JOIN koperasi.toko t
      ON t.id = h.toko
LEFT JOIN koperasi.cara_pembayaran_koperasi cb
      ON cb.id = h.cara_pembayaran_koperasi
JOIN koperasi.pembelian b
      ON b.pembelian_anggota_koperasi = h.id
CROSS JOIN periode p
WHERE h.tanggal_pembayaran >= p.dari
  AND h.tanggal_pembayaran <  p.sampai + 1
GROUP BY t.nama, h.kode, h.tanggal_pembayaran, h.kasir_login_nama,
         cb.nama, h.total_diskon, h.total_biaya
HAVING COALESCE(SUM(b.diskon), 0) > 0
ORDER BY h.tanggal_pembayaran DESC, h.kode;
