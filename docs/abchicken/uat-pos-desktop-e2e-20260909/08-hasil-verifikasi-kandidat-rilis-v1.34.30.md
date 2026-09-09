# Verifikasi Kandidat Rilis AB Chicken POS Desktop v1.34.30

## Identitas pengujian

- Tanggal verifikasi: 9 September 2026.
- Aplikasi: POS Desktop Windows varian `abchicken`.
- Versi kandidat rilis: `1.34.30+193`.
- Tenant/domain: `abchiken` / `abchiken.ebisnis.id`.
- Isolasi: mode `TENANT_ONLY`, schema bisnis `abchiken`, dan schema audit `abchiken__audit`.
- Aplikasi Web hanya digunakan untuk registrasi tenant, konfigurasi administratif, pemantauan, dan audit. Semua transaksi operasional diuji dari POS Desktop.

## Hasil verifikasi

| Gate | Cakupan | Hasil |
|---|---|---|
| Analisis statis | Berkas varian, konfigurasi server, shell, installer, dan updater | LULUS |
| Kontrak aplikasi | 23 pengujian konfigurasi tenant, URL, media, dan varian | LULUS 23/23 |
| Isolasi kanal pembaruan | Pemilihan aset, prefix rilis, dan larangan fallback lintas varian | LULUS 7/7 |
| Paket Android AB Chicken | Package ID, label, versi, target SDK, dan signature produksi | LULUS |
| Paket Windows AB Chicken | Identitas aplikasi, executable tunggal, dan pembuatan installer | LULUS untuk UAT; Authenticode belum tersedia |
| Data settle | 13 layar data utama; setiap daftar transaksi utama memuat sekurang-kurangnya 50 record | LULUS 13/13 |
| Aksi end-to-end | Pesanan outlet, PR, PO, BAST, tagihan, pembayaran, produksi, pengiriman/BAST outlet, klaim, dan POS | LULUS 10/10 |
| Laporan akuntansi | Keseluruhan Jurnal, Buku Besar, Neraca Saldo, Laba Rugi, Neraca, dan Arus Kas | LULUS 6/6 |

UAT transaksional end-to-end yang ditetapkan untuk kandidat ini dijalankan pada POS Desktop dan lulus
seluruh gate. APK Android memakai kode fitur dan kontrak server yang sama, memiliki package ID
`id.zishof.ebisnis.abchicken`, label `AB Chicken`, versi `1.34.30`/build `193`, minimum SDK 23,
target SDK 35, serta signature produksi. Pengujian UI pada perangkat Android belum dinyatakan sebagai
UAT end-to-end karena host pengujian tidak memiliki Android device dan emulator x86_64 tidak dapat
berjalan tanpa driver akselerasi virtualisasi. Karena itu APK disediakan untuk instalasi dan smoke test
perangkat, sedangkan bukti UAT transaksi pada dokumen ini tetap bukti POS Desktop.

## Bukti volume data

Pengujian data menampilkan 170 pesanan outlet, 50 resep/BOM, masing-masing 170 PR, PO, BAST vendor,
tagihan vendor, pembayaran vendor, proses produksi, dan pengiriman. Tersedia pula 80 klaim/backorder,
120 penjualan POS, serta tiga sumber konfigurasi akun posting. Tidak ditemukan status gagal pada gate data.

## Bukti perubahan status dan jurnal

| Proses | Dokumen | Perubahan status | Jurnal |
|---|---|---|---|
| Pesanan bahan baku outlet | `UAT-AB-REQ-0006` | DRAFT → ALLOCATED | Tidak membentuk jurnal |
| Permintaan pembelian | `UAT-AB-PR-0008` | DRAFT → APPROVED | Tidak membentuk jurnal |
| Pesanan pembelian | `UAT-AB-PO-0008` | DRAFT → APPROVED | Tidak membentuk jurnal |
| BAST vendor di gudang pusat | `UAT-AB-BAST-0008` | DRAFT → POSTED | 307 |
| Terima tagihan vendor | `UAT-AB-INV-0009` | DRAFT → POSTED | 308 |
| Pembayaran vendor | `UAT-AB-PAY-0009` | DRAFT → POSTED | 309 |
| Produksi/packing | `UAT-AB-PROD-0009` | DRAFT → POSTED | 310 |
| Delivery Order dan BAST outlet | `UAT-AB-SHP-0009` | DRAFT → DELIVERY → ARRIVED → COMPLETED | 311 |
| Klaim/retur/backorder | `UAT-AB-CLM-0009` | DRAFT → RESOLVED | Tidak membentuk jurnal pada skenario ini |
| Penjualan POS Kasir | `UAT-AB-POS-00016` | DRAF → TERPOSTING | 312 |

Seluruh enam transaksi yang semestinya membentuk jurnal berhasil menghasilkan jurnal baru. Setiap aksi
mempertahankan keterlacakan nomor dokumen sumber dan tidak ada proses bisnis yang dijalankan melalui
halaman Web.

## Bukti laporan keuangan

| Laporan | Baris | Hasil |
|---|---:|---|
| Keseluruhan Jurnal (Jurnal Umum) | 608 | LULUS |
| Rincian Buku Besar per Akun | 608 | LULUS |
| Neraca Percobaan / Neraca Saldo | 7 | LULUS |
| Laba Rugi berbasis jurnal | 7 | LULUS |
| Neraca berbasis jurnal | 11 | LULUS |
| Arus Kas berbasis jurnal | 5 | LULUS |

Tangkapan layar halaman terakhir Keseluruhan Jurnal ikut disimpan untuk membuktikan bahwa pemeriksaan
tidak berhenti pada halaman pertama. Saldo awal kas/bank pilot belum dimuat; karena itu nilai saldo akhir
Arus Kas dapat negatif walaupun aritmetika dan keterlacakan jurnal telah lulus. Saldo awal wajib dimasukkan
sebelum tenant digunakan sebagai pembukuan produksi.

## Isolasi rilis

Kanal pembaruan AB Chicken memakai prefix tag `abchicken-` dan pencarian aset `abchicken`. Kandidat rilis
tidak menggunakan tag global `v*`, tidak menyediakan aset eBisnis/AlBahjah/Nahl, dan tidak melakukan
fallback ke varian lain. Publikasi harus berupa prerelease khusus AB Chicken agar rilis `latest` global tidak
berubah untuk varian lain.

Installer Windows berhasil dibangun dengan identitas `AB Chicken`, executable `abchicken.exe`, dan
versi `1.34.30+193`. Mesin build tidak memiliki sertifikat Authenticode publik yang sesuai; installer
Windows wajib diperlakukan sebagai artefak UAT sampai ditandatangani dengan sertifikat organisasi.
Kondisi ini tidak mengubah hasil UAT fungsional, tetapi mencegah kandidat disebut rilis produksi final.

## Lokasi bukti

Seluruh tangkapan layar dan CSV regresi kandidat rilis tersedia pada
`evidence/release-candidate-1.34.30/`. Berkas tersebut melengkapi—bukan mengganti—bukti UAT awal yang
terdokumentasi di manual utama.
