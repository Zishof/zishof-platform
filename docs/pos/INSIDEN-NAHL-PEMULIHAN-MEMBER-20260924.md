# An Nahl: pemulihan member dan kegagalan sinkronisasi

## Bukti dan batas pemeriksaan

Dua screenshot serta teks log pelapor diperiksa. Form Tambah Transaksi Baru
versi 1.34.45+208 tidak mempunyai pemilih member. Source pada baseline 590f8b5
membentuk payload baru tanpa id_member/nama_member. Form tersebut juga menawarkan
metode umum tanpa validasi kebutuhan member. Ini berbeda dari perbaikan checkout
pesanan yang sudah dirilis sebelumnya.

Log terbaru menunjukkan HandshakeException sebelum jawaban HTTP diterima, bukan
penolakan izin pembayaran. Log tersebut tetap membawa member dan metode Tunai;
laporan member menjadi Umum belum dapat digeneralisasi ke seluruh nota.
HEAD HTTPS tanpa autentikasi pada 24 September 2026 sekitar 15:04 WIB mencapai
endpoint An Nahl dan mendapat HTTP 401. Ini membuktikan TLS berhasil dari lingkungan
pemeriksaan saat itu, bukan membuktikan perangkat kasir pulih atau transaksi diterima.
Tidak ada pembayaran, perubahan konfigurasi, saldo, jurnal, atau data produksi dilakukan.

## Perubahan source

Form transaksi baru supervisor memakai pemilih member POS yang sama, membaca cache
izin lebih dahulu, lalu menyegarkan izin cara bayar khusus member. Metode tidak sah
tidak diganti otomatis menjadi Tunai; member tetap dipertahankan saat jaringan gagal.
Identitas member disertakan ke payload sebelum penyimpanan outbox lokal yang sudah ada.
Voucher/saldo tanpa member ditolak di form. Metode/member yang wajib PIN/biometrik
diblok pada form ini karena verifikasi tersebut belum tersedia di alur pemulihan;
kebijakan server tidak dilemahkan. Edit transaksi yang sudah final tidak diubah.

## Penanganan data lama oleh PIC berwenang

1. Cadangkan arsip/outbox asli. Hentikan upaya membuat transaksi pengganti.
2. Cocokkan nomor nota, toko, tanggal, kasir, item, total, member asli, dan bukti voucher.
3. Bandingkan Lokal dan Server. Gangguan koneksi bukan bukti transaksi tidak ada.
4. Jika sudah ada di server, jangan kirim sebagai nota baru. Periksa riwayat saldo
   dan jurnal sebelum menentukan pembatalan/koreksi terkontrol.
5. Jika hanya lokal, jangan mengubah ID transaksi atau membuat nomor pengganti.
   Koreksi identitas/metode harus mempertahankan ID asli, audit sebelum/sesudah,
   mencegah pengiriman bersamaan, dan memeriksa apakah voucher sudah pernah dipotong.
   Jalur koreksi lama ke voucher belum tersedia pada patch ini; jangan edit SQLite
   atau mengganti izin member secara ad hoc.
6. Tombol Ganti ke Pembayaran Lokal hanya untuk metode manual yang pembayarannya
   benar-benar diterima, bukan untuk mengubah Tunai ke Voucher.
7. Tambah Transaksi Baru hanya untuk transaksi benar-benar baru/tidak tercatat,
   setelah supervisor memastikan tidak ada antrean/arsip/server dengan transaksi sama.

## Status

Perubahan source klien tidak memperbaiki transaksi lama secara otomatis. Tidak ada
perubahan backend, deployment, atau rilis installer/APK baru dalam pemeriksaan ini.
Paket 1.34.45 yang telah diunduh sebelumnya belum mengandung patch ini. Bila server
memerlukan perbaikan TLS, diagnosis log/proxy/perangkat diperlukan sebelum deployment
atau perubahan konfigurasi. Jadwal penerapan produksi belum dikonfirmasi.

Validasi: flutter test test/pemulihan_member_test.dart test/pembayaran_member_pencegahan_test.dart: 10 tes lulus. flutter analyze pada empat file terdampak: tanpa temuan. flutter build windows --debug -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl: berhasil, exit 0. UAT, APK, dan build installer rilis belum dijalankan untuk patch ini.
