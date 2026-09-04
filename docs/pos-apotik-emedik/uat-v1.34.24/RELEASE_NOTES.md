# Apotik v1.34.24 (build 186)

Tanggal rilis: 5 September 2026

Tenant UAT: `Demo`

Server: `https://demo.ecampus.id/ecampus/`

Status: **LULUS UAT untuk pilot terkontrol**

Rilis ini menyediakan APK Android dan installer Windows EXE secara langsung, tanpa paket ZIP. Laporan UAT sekaligus panduan pengguna tersedia dalam DOCX dan PDF, disertai presentasi PPTX dan checksum SHA-256.

## Aset rilis

- `app-apotik-release.apk` — application ID `id.zishof.ebisnis.apotik`, versionName `1.34.24`, versionCode `186`.
- `eBisnis-POS-Apotik-Setup-1.34.24.exe` — installer Windows 64-bit Inno Setup, ProductVersion `1.34.24`.
- `Laporan-UAT-dan-Panduan-Apotik-v1.34.24.docx` — laporan dan panduan pengguna 48 halaman.
- `Laporan-UAT-dan-Panduan-Apotik-v1.34.24.pdf` — ekspor PDF final 48 halaman yang sudah dirender dan diperiksa.
- `Presentasi-UAT-Apotik-v1.34.24.pptx` — presentasi 35 slide; uji overflow dan pemeriksaan visual lulus.
- `RELEASE_NOTES.md` dan `SHA256SUMS.txt` — catatan rilis dan checksum seluruh aset publik.

## Perubahan utama

- Identitas visual varian Apotik memakai tema hijau yang konsisten pada Android, Windows, layar operasional, layar publik, dan materi UAT.
- Nama toko UAT ditetapkan menjadi `Demo`.
- Laporan penjualan pemasok dan laporan Apotik menggunakan lebar area kerja secara penuh agar kolom tidak terpotong.
- Halaman batch/kedaluwarsa diperkuat untuk pemantauan FEFO, status risiko, dan bukti volume.
- Seluruh halaman posting terkait Apotik menampilkan tab `Semua`, `Telah Diposting`, dan `Belum Diposting`, status eksplisit per baris, serta ringkasan jumlah.
- Skenario UAT menambah seed dan eksekusi posting HPP, penjualan, kulakan, bayar utang, terima piutang, dan penyesuaian persediaan.
- Query metrik operasional backend diperbaiki dengan relasi `detail_transaksi_pasien.transaksi_detail → transaksi_medis_detail.transaksi`; perbaikan telah dideploy sebagai SVN r84374 dan endpoint kembali berstatus `success`.

## Hasil UAT live server

### Data, transaksi, dan farmasi

- 11.000 item katalog, termasuk 10.000 obat jadi dan 1.000 bahan racikan.
- 4.800 resep siap jual; 100 resep racikan terbaca pada layar pengujian.
- 100 penjualan obat jadi, 100 racikan, 100 gabungan, dan 100 obat terkendali lulus; total 400 transaksi.
- Uji idempotensi transaksi: PASS.
- 100 batch layak uji; monitor batch mengembalikan 100 baris tanpa memilih batch kedaluwarsa.
- Laporan penjualan 102 baris, register obat terkendali 101 baris, dan laporan kedaluwarsa 999 baris.
- Antrean farmasi live 300 baris; identitas pada layar publik disamarkan.

### Procure-to-pay

- 100 purchase request, 100 purchase order, 100 BAST, 100 penerimaan tagihan, dan 100 pembayaran vendor tersedia serta dapat ditelusuri.
- Bukti layar daftar PR, BAST, penerimaan tagihan, dan pembayaran vendor masing-masing menampilkan sedikitnya 100 data.
- 100 jurnal pembayaran vendor terposting terverifikasi; pemetaan contoh memakai debit `310.500 HUTANG VENDOR` dan kredit `111.101 KAS YAYASAN`.

### Posting dan akuntansi

- Posting HPP: 202 belum diposting dan 400 telah diposting.
- Posting penjualan: 1.100 belum diposting dan 100 telah diposting.
- Posting kulakan, bayar utang, dan terima piutang: masing-masing 100 belum diposting dan 100 telah diposting.
- Posting penyesuaian persediaan: 250 belum diposting dan 100 telah diposting.
- Sumber laporan keuangan: 100 jurnal sample terposting terverifikasi; akun belum dipetakan: 0.
- Laba Rugi 11 baris, Neraca 32, Arus Kas 21, Keseluruhan Jurnal 2.500, Buku Besar 2.500, dan Neraca Saldo 7.

## Quality gate

- Seluruh 1.006 pengujian unit Flutter lulus.
- UAT fullscreen Apotik: 12/12 layar lulus pada 1920×1080 tanpa overflow.
- UAT fullscreen pengadaan lulus dengan data 100+ pada tahap yang dipersyaratkan.
- UAT fullscreen akuntansi lulus untuk 23 menu dan 6 laporan; deteksi RenderFlex overflow tetap aktif.
- Dokumen DOCX/PDF final dirender menjadi 48 halaman dan diperiksa seluruhnya.
- Presentasi final berisi 35 slide; pemeriksaan otomatis melaporkan tidak ada overflow dan seluruh montage diperiksa.
- Build Android release flavor Apotik lulus. Audit APK mengonfirmasi package `id.zishof.ebisnis.apotik`, versionName `1.34.24`, versionCode `186`, signature v1/v2 valid, dan sertifikat Android Debug.
- Build Windows release dan kompilasi installer Inno Setup 6.7.3 lulus. Metadata installer mengonfirmasi `Apotik Setup` dan ProductVersion `1.34.24`.

## Batas distribusi dan keamanan

APK memakai sertifikat **Android Debug** karena keystore produksi belum diberikan. Gunakan hanya untuk UAT/pilot pada perangkat terkontrol; jangan publikasikan ke store dan jangan gunakan sebagai pengganti build produksi yang ditandatangani keystore resmi.

Installer Windows berstatus **unsigned/UAT** sesuai kondisi distribusi yang disetujui. Windows SmartScreen dapat menampilkan peringatan penerbit tidak dikenal. Verifikasi checksum dan sumber GitHub Release sebelum menjalankan installer.

Seluruh data pada bukti adalah data sample/UAT. Jangan memasukkan identitas pasien nyata ke tangkapan layar publik, jangan menyalin token/kredensial ke laporan, dan jangan menghapus audit trail untuk menutupi koreksi.

## Instalasi singkat

### Android

1. Unduh `app-apotik-release.apk` dan `SHA256SUMS.txt` dari rilis yang sama.
2. Cocokkan SHA-256, lalu izinkan pemasangan dari sumber tepercaya hanya pada perangkat UAT.
3. Setelah instalasi, periksa label aplikasi `Apotik`, versi `1.34.24 (186)`, server, login, role, toko `Demo`, kamera/barcode, printer, transaksi sample, dan logout.

### Windows

1. Unduh `eBisnis-POS-Apotik-Setup-1.34.24.exe` dan `SHA256SUMS.txt`.
2. Cocokkan SHA-256 sebelum menjalankan installer.
3. Selesaikan wizard, buka aplikasi, lalu periksa tampilan maximized, server, login, role, toko `Demo`, printer, dan transaksi sample.
4. Bila SmartScreen muncul, lanjutkan hanya setelah checksum serta sumber rilis terverifikasi.

## Keputusan produksi dan rollback

Ketersediaan installer tidak sama dengan persetujuan produksi. Produksi tetap memerlukan keystore Android resmi, kebijakan penandatanganan Windows yang disepakati, pemeriksaan checksum, serta sign-off Owner Apotik, Apoteker Penanggung Jawab, Procurement, Keuangan/Akuntansi, IT/DevOps, dan Keamanan/Privasi.

Rollback wajib dipicu bila stok/batch tidak dapat ditelusuri, obat kedaluwarsa dapat dipilih, transaksi ganda muncul, jurnal tidak seimbang, pembayaran kehilangan referensi dokumen, identitas pasien terekspos, atau angka laporan material tidak dapat direkonsiliasi ke jurnal posted dan dokumen sumber.
