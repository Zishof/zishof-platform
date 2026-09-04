# Laporan UAT Kasir Apotik v1.34.25

Tanggal pelaksanaan: 5 September 2026 (WIB)  
Rilis yang diuji: `apotik-v1.34.25+187`  
Status akhir: **PASS**  
Kebutuhan deploy ulang: **Tidak**

## Ringkasan hasil

UAT dijalankan terhadap deployment server aktif dengan minimal 100 data pada setiap alur kasir. Seluruh 500 operasi utama selesai sukses, lalu 500 kode unik yang dihasilkan diperiksa ulang untuk membuktikan retry bersifat idempoten dan tidak membuat transaksi atau mutasi stok ganda.

| Alur kasir | Data/operasi utama | Post-flight idempoten | Hasil |
|---|---:|---:|---|
| OTC / Obat Bebas | 100 | 100 | PASS |
| Resep Dokter | 100 | 100 | PASS |
| Racikan | 100 | 100 | PASS |
| Produksi Farmasi | 100 | 100 | PASS |
| Tebus Resep campuran | 100 | 100 | PASS |
| **Total** | **500** | **500** | **PASS** |

## Pemeriksaan end-to-end

- Semua tombol mode kasir terbuka: OTC/Obat Bebas, Resep Dokter, Racikan, Produksi Farmasi, dan Tebus Resep.
- Pembayaran OTC berhasil sampai transaksi tersimpan; kode transaksi `apotik jual` tersedia pada server.
- Penjualan Resep Dokter berhasil dengan identitas dokter dan pasien.
- Penjualan Racikan memakai formula racikan aktual dan mengonsumsi komponen formula.
- Produksi Farmasi berhasil membuat batch hasil dan mengonsumsi bahan produksi.
- Tebus Resep berhasil untuk resep campuran berisi obat jadi dan racikan dalam satu transaksi atomik.
- Pemilihan obat OTC dan resep dokter memakai batch aktif/FEFO.
- Retry seluruh 500 kode transaksi dikenali sebagai idempoten; tidak ditemukan transaksi ganda.
- Sedikitnya 200 resep formula pada data UAT telah berstatus ditebus, melampaui target minimal 100.

## Volume data server

| Data | Tersedia | Target minimal | Hasil |
|---|---:|---:|---|
| Obat jadi | 10.000 | 100 | PASS |
| Bahan racikan | 1.000 | 100 | PASS |
| Formula racikan operasional | 250 | 100 | PASS |
| Formula produksi operasional | 250 | 100 | PASS |
| Resep siap jual setelah UAT | 4.499 | 100 | PASS |

## Regresi UI

Empat suite UI kasir dijalankan kembali: pembayaran, halaman POS, state POS, dan widget POS. Hasilnya **96 test lulus, 0 gagal**. Cakupan mencakup tombol mode tanpa ikon kunci, dialog pembayaran, validasi uang tunai, pemilihan batch FEFO, endpoint racikan/produksi, tebus resep campuran, serta anti-double-submit.

## Observasi non-blocking

Pada pemeriksaan post-flight segera setelah beban transaksi, gateway sempat memberikan 17 respons sementara berupa HTTP 502/503 atau timeout. Sebanyak 20 kode awal (mencakup seluruh kode yang terdampak) diperiksa ulang dengan retry; hasilnya 20/20 lulus, seluruhnya mengembalikan `idempoten=true`, dan tidak ada kegagalan atau data ganda yang tersisa.

Observasi ini tidak membutuhkan deploy aplikasi, tetapi metrik reverse proxy/Tomcat sebaiknya dipantau saat uji beban berikutnya.

## Bukti teknis

- Harness server nyata: `apps/ebisnis/integration_test/uat_apotik_v13425_cashier_e2e_test.dart`
- Ringkasan mesin: `docs/pos-apotik-emedik/uat-v1.34.25/cashier-retest/uat-kasir-summary.json`
- Commit implementasi frontend: `af8a54f`
- Revisi backend terakhir untuk resep campuran atomik: `r84380`

