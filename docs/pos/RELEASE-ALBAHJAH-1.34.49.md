# Al-Bahjah POS 1.34.49 (build 212)

Pembaruan khusus varian **Al-Bahjah**, Windows dan Android.

## Perbaikan
- Kesalahan SQLite tidak lagi ditampilkan sebagai sesi login kedaluwarsa.
- SQLITE_MISUSE tidak memicu penggantian database dengan database kosong.
- Penghitung antrean tidak lagi menutup koneksi database bersama saat pembacaan gagal; checkout/outbox lain tidak ikut kehilangan koneksinya akibat jalur tersebut.
- Keranjang berisi dilindungi dari perpindahan menu, toko, tombol kembali, dan keluar akun. Selesaikan atau Tahan terlebih dahulu dan pastikan penyimpanan berhasil.

Pengaman keranjang ini bukan pemulihan setelah listrik padam atau aplikasi ditutup paksa. Pemicu awal SQLITE_MISUSE di perangkat pelapor belum direproduksi. Tidak ada perubahan saldo, metode pembayaran, atau data transaksi lama.

## Validasi dan batas paket
- Source perbaikan: f94c12c dan 986be5f.
- 13 tes lokal pada source perbaikan lulus; meliputi gangguan pembacaan bersamaan, pemulihan outbox lokal, aturan member, klasifikasi error, dan pengaman navigasi.
- Paket dibangun dengan skrip resmi `tool/build_semua_varian.ps1 -Hanya albahjah -IzinkanDebugSigning -IzinkanUnsignedWindows`.
- **Windows UNSIGNED/UAT; APK DEBUG/UAT signing.** Sertifikat penandatanganan produksi tidak tersedia pada lingkungan build. Ini bukan klaim paket telah bersertifikat produksi atau telah lulus UAT perangkat kasir.
- Publikasi GitHub tidak memasang aplikasi ke perangkat dan tidak melakukan deployment server.

## Langkah pemasangan
1. Admin memeriksa transaksi yang belum jelas statusnya pada riwayat, antrean lokal, dan server. Jangan membuat transaksi pengganti sebelum pemeriksaan selesai.
2. Selesaikan/tahan keranjang dan pastikan berhasil sebelum menutup aplikasi. Jika penyimpanan masih gagal, catat isi keranjang dan minta pendampingan admin terlebih dahulu.
3. Tutup POS secara normal, lalu cadangkan folder data aplikasi termasuk berkas pendamping database yang masih ada. Jangan uninstall atau menghapus data.
4. Pilih installer Windows Al-Bahjah atau APK Al-Bahjah pada Assets. Periksa SHA-256 menggunakan berkas pendamping.
5. Untuk Android, lakukan pembaruan hanya bila tanda tangan cocok dengan aplikasi terpasang. Jika instalasi ditolak, jangan uninstall sebagai jalan pintas; minta admin memeriksa kompatibilitas sertifikat.
6. Setelah pemasangan, pastikan versi 1.34.49 build 212, toko, sesi kas, dan transaksi terdahulu tetap benar. Konfirmasi hasil bersama operator.

Tidak memerlukan patch server. Jadwal pemasangan perangkat belum dikonfirmasi. Simpan installer sebelumnya untuk rollback yang dikelola admin; jangan menimpa transaksi baru dengan backup lama secara otomatis.

## Hasil build
Build Android APK release, Windows release, dan installer Inno Setup berhasil (exit 0; 7,6 menit).
APK: `id.zishof.ebisnis.albahjah`, versionName `1.34.49`, versionCode `212`.

| Aset | Ukuran byte | SHA-256 |
| --- | ---: | --- |
| Al-Bahjah-POS-Setup-1.34.49.exe | 89920668 | 90ffa9c62bd5fe5249396247cd8aea925d078e9657cb68888111832bf7c0e38b |
| app-albahjah-release.apk | 196509214 | d0218068147b3383370a49c07a88a95b1e65f96c675bdaf911f6fb24efc5fc71 |
