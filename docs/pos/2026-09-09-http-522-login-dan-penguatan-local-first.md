# Penanganan HTTP 522 pada Login dan Penguatan Local-First POS

Tanggal: 9 September 2026

Versi aplikasi: `1.34.31+194`
Cakupan paket: POS Desktop Al-Bahjah dan TokoQu Al-Bahjah An Nahl

## Ringkasan insiden

Pada permintaan login ke endpoint Nahl, gateway Cloudflare mengembalikan HTTP
522 dengan `Content-Type: text/plain` dan badan respons `error code: 522`.
Versi aplikasi sebelumnya langsung mencoba mengurai setiap badan respons sebagai
JSON. Karena huruf pertama respons adalah `e`, parser Dart melempar
`FormatException: Unexpected character` dan pengguna menerima informasi teknis
yang seolah-olah merupakan kerusakan aplikasi atau kesalahan akun.

Uji reproduksi terkontrol pada endpoint produksi menggunakan identitas UAT yang
tidak valid menghasilkan HTTP 522 yang sama. Artinya, pada saat pengujian,
gateway belum berhasil menjangkau origin/data-centre. Kredensial pengguna belum
pernah dinilai oleh server sehingga pengguna tidak boleh diarahkan untuk
mengganti kata sandi hanya karena insiden ini.

## Perilaku setelah perbaikan

1. HTTP 500–599, 408, dan 425 dikenali sebagai gangguan teknis sementara.
2. Respons 522 berupa teks tidak lagi tampil sebagai `FormatException` pada
   pesan utama. Layar menampilkan **Layanan server sedang terganggu**, status
   HTTP, penjelasan bahwa akun dan kata sandi belum dinilai, serta langkah yang
   dapat dilakukan pengguna.
3. Request ID, endpoint, action, cuplikan respons, dan stack trace tetap tersedia
   di bagian **Informasi Teknis** untuk admin/developer.
4. HTTP 400/401/403/404/422 dan penolakan bisnis tetap diperlakukan sebagai
   keputusan server; aplikasi tidak mengalihkannya menjadi sukses offline.
5. Login baru tetap membutuhkan server. Aplikasi tidak membuat autentikasi semu.
   Perangkat yang telah mempunyai sesi sah dapat memakai mekanisme layar kunci
   dan bukti sandi lokal sesuai batas keamanan yang sudah berlaku.

## Penguatan local-first yang menyertai perbaikan

- Mutasi master programatik kini ditulis ke `outbox_master` sebelum permintaan
  jaringan dimulai. Percobaan pertama dan retry membaca payload persis dari
  outbox sehingga memakai `client_mutation_id` yang sama.
- Outbox Inventory & Sales juga menulis lokal terlebih dahulu dan melakukan
  deduplikasi berdasarkan `kode_unik`.
- Rating pada layar pelanggan dan pembuatan produk dari Bulk Entry Kulakan tidak
  hilang ketika gateway mengembalikan 5xx.
- Pratinjau posting toko dapat menampilkan salinan terakhir ketika offline.
  Hak `create` tidak pernah dipulihkan dari cache; posting final baru aktif
  setelah server saat ini memvalidasi akun, periode, hak akses, dan keseimbangan
  jurnal.
- Pembayaran POS biasa yang telah memperoleh snapshot metode pembayaran sah
  tetap masuk outbox lokal. Validasi saldo, PIN/biometrik, approval, login baru,
  dan posting final tetap fail-closed.

## Matriks UAT

| Skenario | Hasil yang diharapkan |
|---|---|
| Login menerima HTTP 522 teks | Pesan gangguan server tampil; tidak ada `FormatException` sebagai pesan utama |
| Login menerima HTTP 401/403 | Penolakan autentikasi tetap ditampilkan dan tidak dialihkan ke sukses offline |
| Baca master/laporan saat 5xx dan cache tersedia | Salinan lokal tetap dapat dibaca dengan penanda data tersimpan |
| Mutasi master saat jaringan putus/5xx | Payload tersimpan PENDING sebelum kirim dan dicoba ulang dengan ID mutasi yang sama |
| Mutasi mendapat validasi bisnis | Baris ditandai GAGAL, isian lokal dipertahankan, pengguna wajib memperbaiki data |
| Pratinjau posting saat offline | Pratinjau cache dapat dibaca; tombol posting final nonaktif |
| Server pulih | Sinkronisasi mengirim antrean sesuai urutan tanpa menggandakan kode unik |
| Varian dipasang berdampingan | Namespace data dan kanal update Al-Bahjah/Nahl tetap terpisah |

## Hasil verifikasi

- 108 pengujian terfokus gateway, login, error UI, autentikasi, cache, outbox,
  pembayaran offline, posting, dan konfigurasi varian: lulus.
- 6 pengujian database outbox master/Inventory & Sales: lulus.
- 6 pengujian inti pemilihan aset dan kanal auto-update: lulus. Suite profil
  varian tambahan (13 eksekusi) juga lulus.
- Sapuan seluruh test aplikasi menjalankan 835 skenario: 827 lulus dan 8 tidak
  dapat dijalankan karena dependensi baseline di luar repo tidak tersedia pada
  layout workspace ini (1 skrip runner volume Apotik dan 7 pembacaan mirror
  source Java AIS). Seluruh 8 kegagalan tersebut berada di test kontrak eksternal
  dan tidak menyentuh kode perbaikan 522, login, outbox, atau kedua varian rilis.
- Analisis statis: tidak ada error atau warning; informasi lint lama yang tidak
  terkait tetap dicatat sebagai baseline.
- Reproduksi awal pada endpoint produksi Nahl menghasilkan HTTP 522. Pemeriksaan
  ulang pra-rilis pada 9 September 2026 pukul 15.16 WIB memakai identitas UAT
  dummy sudah menerima HTTP 401 dengan JSON terstruktur. Hal ini membuktikan
  jalur Cloudflare–origin kembali merespons dan klasifikasi penolakan bisnis
  tetap benar. Login dengan akun nyata tidak dilakukan dan tidak diklaim lulus.

## Kebutuhan deploy

Tidak ada perubahan servlet, skema basis data server, atau kontrak payload API.
Perbaikan 522 berada di aplikasi POS Desktop dan tidak membutuhkan build/deploy
WAR. Administrator hanya perlu memasang rilis Desktop `1.34.31` pada varian yang
sesuai. Pemulihan endpoint 522 tetap merupakan pekerjaan infrastruktur
data-centre/origin.

## Prosedur pengguna

1. Jika pesan 522 muncul, jangan mengubah kata sandi dan jangan menekan Masuk
   berulang-ulang dengan cepat.
2. Pastikan jaringan perangkat tersambung dan Alamat Server masih benar.
3. Tunggu pemberitahuan bahwa pusat data pulih, kemudian tekan **Masuk** satu
   kali.
4. Jika tetap gagal, buka **Informasi Teknis**, salin Kode Referensi, lalu
   kirimkan kepada admin.
5. Setelah berhasil masuk, tekan **Sinkronkan** dan periksa **Riwayat
   Sinkronisasi** sebelum melakukan proses final yang memerlukan server.
