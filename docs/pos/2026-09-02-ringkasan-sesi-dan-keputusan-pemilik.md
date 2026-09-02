# 78. Ringkasan Sesi & Daftar Keputusan Pemilik

Tanggal: 2 September 2026  
Tujuan: satu halaman untuk pemilik — apa yang sudah selesai & terverifikasi, dan
apa yang menunggu keputusan Anda. Rincian ada di dok. 63–77.

## A. Selesai, terkode, dan terverifikasi

| Area | Hasil | Bukti | Dokumen |
| --- | --- | --- | --- |
| Master UOM per kategori | 4 kategori × 1 acuan; 17 satuan standar | TesUomRapi 9/9 | 63 |
| Satuan dasar Pcs massal (8.674 produk) | sisa tanpa satuan 0 | jejak byte-identik | 63 |
| Otomasi UOM saat boot (InitIndex) | rapikan + isi + saklar pembalikan | TesInitUom 12/12 | 63 |
| Tab "Rincian Produk" (permintaan An Nahl) | rincian item per transaksi, ekspor | TesRincianProduk 18/18 | 64 |
| Laporan web: item batal, kasir, produk terhapus | 3 cacat ditutup | TesLaporanWeb 17/17 | 65, 67 |
| Filter produk/kasir + rekap per produk (tab) | + penanda ekspor terpotong | uji Dart 16/16 | 67 |
| Batas 20.000 baris laporan web | + self-test aturan SQL | 11/11 | 68 |
| Dashboard Stok: nilai "Barang Keluar" | pakai nilai final `total` | 22/22 | 68 |
| 7 panel Ringkasan menyaring baris batal | 11 kueri | TesPanelRingkasan 5/5 | 69 |
| Dashboard POS menyaring baris batal | 4 kueri | TesDashboardPos 6/6 | 77 |
| **Keamanan:** tulis SQL anonim ditutup | selalu aktif | — | 71 |
| **Keamanan:** kolom kredensial diblokir | selalu aktif, tanpa konfigurasi | 20/20 | 72 |
| **Keamanan:** resolusi kelas unggahan | tanpa inisialisasi kelas asing | TesUploadKelas 8/8 | 73 |
| **Keamanan:** resolusi kelas entitas `/Data` | idem | TesResolveEntitas 5/5 | 75 |

Konsistensi angka penjualan kini seragam di seluruh layar (laporan, Dashboard
Stok, Ringkasan, POS) — sepadan untuk periode yang sama. Aplikasi Flutter tidak
menghitung riwayat penjualan sendiri, jadi mewarisi perbaikan server.

Rilis aplikasi **1.34.17** dibangun (APK varian An Nahl bertanda debug untuk uji
internal + dua installer Windows); SHA-256 di dok. 66.

## B. Menunggu keputusan / tindakan Anda

Diurut dari yang paling berdampak.

1. **Deploy build server ke ebisnis.id + restart Tomcat.**  
   Hampir semua di bagian A hanya berlaku di server setelah ini: perbaikan
   laporan, filter, saklar UOM, dan seluruh pengerasan keamanan. Tanpa deploy,
   produksi belum menerima apa pun dari sesi ini.

2. **Naikkan proteksi endpoint SQL.**  
   UAT sudah `log` (dok. 71/76). Pre-flight menyatakan **GO** untuk `enforce`
   (dok. 76 — tidak ada halaman yang patah pada kode saat ini). Langkah:
   `log` → amati beberapa hari → `enforce`, di UAT lalu produksi. Perintah
   lengkap di dok. 70/76. *Saya tidak menaikkan ke `enforce` sendiri karena itu
   mengubah perilaku dari mencatat menjadi memblokir — perlu kata Anda.*

3. **Keystore produksi untuk APK.**  
   APK 1.34.16 dan 1.34.17 sama-sama bertanda **debug** — tidak layak edar dan
   tak bisa menimpa aplikasi produksi. Perlu `android/key.properties` + keystore
   (disimpan di luar repo, dengan cadangan aman) agar ada APK produksi (dok. 66).

4. **Pemetaan `ref` pada unggah anonim** (dok. 73) dan **operasi tulis klien ke
   endpoint ber-aksi** (dok. 70).  
   Keduanya menutup sisa risiko yang tidak boleh ditebak — butuh Anda memetakan
   alur pra-akun (PMB, calon anggota) yang sah.

5. **Pemetaan akun jurnal produksi/QC** (dok. 48 §7) — menunggu kode akun dari
   akuntansi.

6. **Rekap per produk yang mengikuti filter Laporan Transaksi** — bila An Nahl
   menghendaki bentuk selain "Produk Terlaris" yang sudah ada; keputusan bentuk.

## C. Utang teknis tercatat (bukan mendesak)

- Refactor `ApiClient` agar dapat disuntik → memungkinkan uji tingkat layar untuk
  tab laporan (kini hanya uji unit; dok. 67 §4).
- Kueri panel Ringkasan dirakit di sisi klien (JavaScript) → sumber berulangnya
  cacat penyaringan; layak dipindah ke endpoint ber-aksi (dok. 69).

## Cara memakai daftar ini

Butir B-1 (deploy) membuka nilai seluruh bagian A untuk produksi — itu satu
tindakan dengan dampak terbesar. B-2 dan B-3 menyusul sebagai langkah keamanan
dan rilis. Sisanya (B-4..B-6, C) dapat dijadwalkan.
