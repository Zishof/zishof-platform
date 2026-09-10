# Hasil UAT End-to-End Operasional eBisnis v1.34.35

- Waktu audit: `2026-09-10T12:54:25.0424338+07:00`
- Lingkungan: `eBisnis live - Kantin Demo`
- Periode: `2026-09-01` s.d. `2026-09-10`
- Ruang lingkup: POS, PR, PO termin/bukan termin, BAST, tagihan, pembayaran vendor, laporan penjualan, pembelian, Omzet, margin, dan laba kotor harian.
- Akuntansi/COA/jurnal/posting: **dikecualikan sesuai permintaan**.
- Hasil: **LULUS 100% untuk seluruh skenario dalam ruang lingkup**.

## Ringkasan bukti

| Pemeriksaan | Hasil |
|---|---:|
| Pengadaan PR/PO/BAST/Tagihan/Pembayaran | 5/5; masing-masing 100 dokumen |
| Laporan dan PDF server | 12/12 lulus |
| Katalog Laporan Omzet | 4/4 lulus |
| API dan PDF Laporan Omzet | 4/4 lulus |
| Popup rincian transaksi Omzet | 6/6 lulus |
| Ekspor XLSX dibuka kembali | 4/4 lulus |
| Rekonsiliasi Laporan Omzet | Rp212.590.000; selisih Rp0 |
| Integrasi layar Windows | 2/2 lulus |
| Pengujian aplikasi eBisnis | 851/851 lulus |
| Transaksi penjualan | 504 |
| Omzet Saldo per Produk | 101 produk |
| Penerimaan/Faktur Pembelian | 452 baris |
| Margin per Produk | 201 baris |

## Empat Laporan Omzet

1. Transaksi Omzet
2. Omzet Produk Non-Saldo/Tunai
3. Omzet Produk Saldo
4. Rekap Omzet

Setiap nilai atau baris yang ditandai dapat diklik untuk melihat nota dan rincian transaksi penyusunnya. Keempat laporan dapat diunduh sebagai Excel/XLSX dan PDF.

## Langkah UAT pada perangkat

1. Pastikan transaksi lokal sudah disinkronkan.
2. Tutup aplikasi POS.
3. Pasang build eBisnis 1.34.35 (build 198).
4. Login, pilih Kantin Demo, dan tekan Sinkronkan.
5. Buka menu Laporan-Laporan dan pilih kategori Omzet.
6. Jalankan keempat laporan pada periode yang sama.
7. Klik angka/baris untuk memeriksa transaksi penyusunnya.
8. Uji tombol Excel dan PDF, lalu buka kembali file hasilnya.
9. Cocokkan Transaksi Omzet dengan Non-Saldo + Saldo dan Rekap Omzet; selisih harus Rp0.

Backend Laporan Omzet yang diperlukan sudah tersedia dan lulus audit live; tidak ada deploy server tambahan untuk skenario ini. Paket Windows merupakan build UAT internal tanpa tanda tangan Authenticode. Paket produksi harus ditandatangani dengan sertifikat resmi organisasi setelah disetujui pengguna.

## Artefak

- `Manual-UAT-E2E-POS-Pengadaan-Laporan-eBisnis-v1.34.35.docx`
- `Manual-UAT-E2E-POS-Pengadaan-Laporan-eBisnis-v1.34.35.pdf`
- `evidence/uat-e2e-ebisnis-v1.34.35.json`
- `evidence/uat-laporan-omzet-ebisnis-v1.34.35.json`
- `evidence/uat-xlsx-ebisnis-v1.34.35.json`
- `screenshots/` dan `annotated/`
- `diagrams/`
