# POS Apotik v1.34.23 (build 185)

Tanggal rilis: 4 September 2026

Target server UAT: `https://demo.ecampus.id/ecampus/`

Keputusan: **LULUS BERSYARAT untuk UAT/pilot terkontrol; belum disetujui untuk produksi**

Rilis ini menyediakan dua paket aplikasi langsung pakai—APK Android dan installer Windows `Setup.exe`, tanpa paket ZIP—beserta laporan UAT/manual gabungan dalam Word dan PDF, serta PPTX presentasi. UAT memeriksa alur penjualan obat jadi, obat racik, transaksi gabungan, procure-to-pay, stok, batch kedaluwarsa, jurnal/posting, laporan penjualan/kulakan, dan laporan keuangan pada tenant demo nyata. Status bersyarat dipakai karena fungsi transaksi utama lulus, tetapi katalog server, endpoint antrean farmasi, beberapa jalur akuntansi/laporan, dan signing produksi belum memenuhi exit criterion.

## Aset distribusi

- `POS-Apotik-v1.34.23-Android.apk` — APK flavor Apotik, application ID `id.zishof.ebisnis.apotik`, versionName `1.34.23`, versionCode `185`.
- `POS-Apotik-v1.34.23-Windows-Setup.exe` — installer Inno Setup 64-bit. Installer membawa executable, data Flutter, DLL/plugin, dan Visual C++ Runtime yang diperlukan. Tidak perlu mengekstrak ZIP.
- `Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.docx` — dokumen Word 50 halaman.
- `Laporan-UAT-dan-Manual-POS-Apotik-v1.34.23.pdf` — PDF 50 halaman yang diekspor dari Word final dan diperiksa hasil render-nya.
- `Presentasi-UAT-POS-Apotik-v1.34.23.pptx` — presentasi 25 slide; tiap bukti utama memiliki slide diagram editable dan catatan pembicara berisi narasi 953–997 kata.
- `RELEASE_NOTES.md` dan `SHA256SUMS.txt` — catatan rilis serta checksum seluruh aset.

## Perubahan aplikasi

1. Jendela utama Windows sekarang langsung dibuka dalam keadaan **maximized** pada work area monitor. Lebar dan tinggi aplikasi otomatis memakai area kerja layar seluas mungkin sehingga tampilan operasional dan tangkapan layar lebih luas, sementara taskbar tetap dapat diakses. Ini bukan exclusive fullscreen dan tidak mengubah penempatan layar pasien pada monitor kedua.
2. Versi aplikasi dinaikkan dari `1.34.22+184` menjadi `1.34.23+185` untuk Android dan Windows.
3. Skenario UAT volume diperbarui menjadi minimal 100 dan maksimal 10.000 record per skenario, dengan target rilis `apotik-v1.34.23`, kode transaksi unik, pemeriksaan idempotensi, dan ringkasan mesin yang tidak lagi tertimpa ketika tahap capture UI dijalankan.
4. Skenario pengadaan dan jurnal vendor diperluas untuk 100 rangkaian data serta bukti hubungan PR, PO, BAST, penerimaan tagihan, pembayaran vendor, jurnal, posting, dan pembacaan ulang.
5. Dokumen baru menyatukan laporan UAT dengan manual pengguna, matriks status, prosedur, troubleshooting, use case, flowchart, ERD/data flow, pemetaan akun, checklist, temuan, exit criterion, dan ruang sign-off.

## Volume dan hasil UAT nyata

### Penjualan obat

- **100/100 penjualan obat jadi PASS.** Setiap request memakai kode transaksi unik rilis dan diverifikasi berstatus sukses.
- **100/100 penjualan obat racik PASS.** Seratus resep tersedia dan ditautkan ke transaksi penebusan.
- **100/100 penjualan gabungan PASS.** Setiap transaksi menggabungkan item obat jadi dan referensi resep/racik.
- Total transaksi penjualan yang lulus pada run: **300**.
- Retest kode transaksi pertama mengembalikan indikator idempoten, sehingga request ulang tidak membuat transaksi ganda.
- Katalog endpoint hanya mengembalikan **2 item**, dan hanya satu item non-terkendali dengan batch aktif yang layak menjadi anchor volume. Karena itu status formal adalah PASS transaksi tetapi BLOCKED cakupan katalog. UAT ini tidak mengklaim telah menyediakan 100 master obat berbeda.

### Layar pasien dan antrean farmasi

- Komponen layar publik berhasil dirender dengan data pratinjau terkontrol, pembagian obat jadi/racik, status, loket, jam, dan identitas tersamar.
- Endpoint live `apotik_antrean_farmasi_list` belum tersedia pada deployment demo. Bukti yang disertakan adalah **PASS komponen / BLOCKED integrasi live**, bukan bukti antrean server sudah bekerja.
- Retest wajib membuat sedikitnya 50 antrean nyata, menjalankan transisi `MENUNGGU → DISIAPKAN → SIAP`, membuka satu atau lebih monitor pasien, memeriksa polling, privasi, pergantian status, arsip, dan pemulihan koneksi.

### Kulakan / procure-to-pay

- **100 PR** dibuat.
- **100 PO** dibuat.
- **100 BAST** dibuat dan diproses.
- **100 penerimaan tagihan vendor** dilakukan.
- **100 pembayaran vendor** dilakukan.
- Relasi dan status setiap tahap disimpan ke ringkasan mesin serta divisualkan pada screenshot pengadaan.
- Pencarian pembayaran dengan marker UAT mengembalikan nol baris walaupun operasi pembayaran berhasil. Ini dicatat sebagai defect filter/listing, sehingga pembayaran harus ditelusuri menggunakan ID sumber sampai filter backend diperbaiki.

### Stok dan kedaluwarsa

- Batch aktif dapat dipilih untuk transaksi, dan pemantauan kedaluwarsa serta laporan kedaluwarsa mengembalikan data.
- Kategori yang wajib dicakup pada retest produksi adalah bahan baku racikan, obat jadi, obat terkendali, alat kesehatan, bahan habis pakai, dan barang lain sesuai kebijakan apotek.
- Karena deployment demo hanya mengembalikan dua master item, target 100–10.000 master stok belum terpenuhi. Seed/provision katalog harus dilakukan di server, kemudian diverifikasi lewat endpoint klien; keberadaan data di tabel atau script saja belum cukup.
- Gate stok produksi: stok awal, penerimaan, penjualan, retur, koreksi, FEFO, batch, tanggal kedaluwarsa, stok negatif, kartu stok, dan nilai persediaan harus direkonsiliasi per item.

### Akuntansi

- **100 jurnal pembayaran vendor** berhasil dibuat, diposting, dan dibaca ulang.
- Contoh mapping yang diuji: debit `310.500 HUTANG VENDOR` dan kredit `111.101 KAS YAYASAN`.
- Workbook akun pengguna diaudit berisi 317 akun data tanpa kode duplikat pada pembacaan UAT.
- Kode sumber `112,102` dan `121,109` memuat tanda koma. Sistem dan dokumen tidak mengubahnya diam-diam; pemilik COA harus menetapkan apakah koma merupakan karakter kode yang sah atau kesalahan sumber.
- Saldo awal dan jurnal penyesuaian masih menemukan masalah parsing respons. Sejumlah preview posting belum menghasilkan detail yang dapat direkonsiliasi. Status bagian tersebut tetap BLOCKED sampai hasil debit/kredit, periode, referensi dokumen, dan saldo akhir dapat ditelusuri konsisten.

### Laporan

- Enam layar inti berhasil dibuka dan dirender: Laba Rugi, Neraca, Arus Kas, Keseluruhan Jurnal, Buku Besar, dan Neraca Saldo/Trial Balance.
- Katalog laporan juga menyediakan laporan penjualan, kulakan, stok/kedaluwarsa, dan perbandingan periode.
- Keberhasilan render tidak dianggap validasi angka. Endpoint laporan penjualan pada run E2E mengembalikan status sukses tetapi **0 baris**, sedangkan bukti UI pada tenant bersama menampilkan Rp1.531.000 dan kuantitas 507. Perbedaan rute/periode/tenant ini harus direkonsiliasi sebelum sign-off laporan.
- Laporan bulanan dan tahunan, perbandingan periode, Buku Besar, Trial Balance, Laba Rugi, Neraca, Arus Kas, penjualan, kulakan, HPP, dan nilai persediaan wajib dibandingkan dengan dokumen sumber dan jurnal posted.

## Quality gate teknis

- `dart format` terhadap empat file skenario UAT: PASS, tidak ada perubahan format tersisa.
- `flutter analyze` terhadap empat file skenario UAT: PASS, tidak ada issue.
- Build Windows release flavor Apotik: PASS.
- Uji runtime Win32 terhadap executable hasil build: `IsMaximized=True`, judul jendela `eBisnis POS Apotik`.
- Build Android `assembleApotikRelease`: PASS; APK berukuran sekitar 148 MB.
- Audit APK: signature v1 dan v2 valid; certificate subject `C=US, O=Android, CN=Android Debug`; application ID dan nomor versi cocok.
- Kompilasi installer Inno Setup 6.7.3: PASS; metadata ProductName `eBisnis POS Apotik`, ProductVersion `1.34.23`.
- Audit Authenticode installer: `NotSigned`.
- Dokumen: Word/PDF 50 halaman; sembilan screenshot utama masing-masing memiliki narasi 953–997 kata dan tiga diagram.
- Presentasi: 25 slide, pengujian overflow otomatis PASS, lalu slide bukti/risiko/distribusi/go-live/sign-off diperiksa secara visual.

## Batasan keamanan dan keputusan distribusi

APK memakai **Android Debug certificate** karena `android/key.properties`/keystore produksi belum diberikan. APK dapat dipakai untuk UAT atau pilot perangkat terkontrol, tetapi bukan upgrade resmi produksi dan tidak boleh dipublikasikan ke store sebagai build produksi. Installer Windows **belum ditandatangani Authenticode**, sehingga Windows/SmartScreen dapat menampilkan peringatan penerbit tidak dikenal. GitHub Release ditandai sebagai pre-release untuk mencegah salah tafsir sebagai rilis produksi.

Jangan memasukkan data pribadi pasien nyata ke pratinjau atau screenshot. Gunakan identitas sintetis/tersamar, batasi akses role, hapus ekspor lokal setelah dipindahkan ke lokasi audit yang disetujui, dan pastikan tidak ada token/kredensial dalam dokumen maupun log.

## Cara instalasi

### Windows

1. Unduh `POS-Apotik-v1.34.23-Windows-Setup.exe` dan `SHA256SUMS.txt`.
2. Cocokkan SHA-256 sebelum menjalankan installer.
3. Jalankan installer, pilih pembuatan shortcut bila diperlukan, lalu selesaikan wizard.
4. Saat pertama dibuka, jendela utama otomatis maximized. Pilih konfigurasi server demo hanya untuk UAT.
5. Bila SmartScreen muncul, verifikasi checksum dan sumber GitHub Release terlebih dahulu; jangan mengabaikan warning pada distribusi yang sumbernya tidak diketahui.

### Android

1. Unduh `POS-Apotik-v1.34.23-Android.apk` dan cocokkan SHA-256.
2. Izinkan pemasangan dari sumber tepercaya hanya untuk aplikasi/file manager yang digunakan, lalu nonaktifkan kembali setelah instalasi.
3. Karena signature adalah Android Debug, gunakan perangkat UAT/pilot dan jangan menimpa aplikasi produksi yang ditandatangani keystore berbeda.
4. Uji login, role, toko, kamera/barcode, printer, koneksi HTTPS, transaksi sampel, sinkronisasi, dan logout sebelum perangkat diserahkan ke operator.

## Exit criterion sebelum produksi

1. Deploy endpoint antrean farmasi dan jalur laporan yang benar pada AIS.
2. Provision minimal 100 master item lintas kategori dan batch; target lebih besar boleh sampai 10.000 selama performa, duplikasi, dan idempotensi tetap terkontrol.
3. Retest 300 penjualan, 100 siklus P2P, 100 jurnal vendor, antrean live, dan laporan angka pada tenant yang diisolasi.
4. Rekonsiliasi stok, utang vendor, kas/bank, pendapatan, HPP, pajak, Buku Besar, Trial Balance, Laba Rugi, Neraca, dan Arus Kas.
5. Selesaikan error saldo awal/jurnal penyesuaian, preview posting kosong, filter pembayaran, dan overflow layout laporan yang tercatat.
6. Dapatkan keystore Android produksi dan sertifikat Authenticode; bangun ulang, verifikasi certificate digest/publisher, lalu lakukan upgrade test.
7. Dapatkan sign-off Owner Apotik, Apoteker Penanggung Jawab, Procurement, Keuangan/Akuntansi, IT/DevOps, serta Keamanan/Privasi.

Rollback wajib dilakukan bila stok atau batch tidak dapat ditelusuri, obat kedaluwarsa dapat dijual, transaksi berganda muncul, pembayaran tidak memiliki dokumen sumber, jurnal tidak seimbang, identitas pasien bocor, atau laporan material berbeda dari dokumen/jurnal posted.
