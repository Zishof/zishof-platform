# v1.34.45 build 208 — pencegahan salah metode pembayaran member

Perbaikan bersama POS Desktop dan Android dari commit 84669c0:
- Pesanan yang dibuka kembali tetap menggunakan izin metode pembayaran member, bukan daftar umum.
- Penyegaran tidak menimpa pilihan kasir yang masih sah dengan metode default. Kunci metode dari tipe member tetap dihormati.
- Jika izin metode dicabut, kasir diminta memilih ulang, termasuk saat cache dan respons server diterapkan berurutan.
- Penolakan izin yang menyebut batas utang tidak lagi dipetakan menjadi kesalahan limit utang.
- Petunjuk pemulihan mengutamakan pemeriksaan bukti pembayaran dan membedakan antrean pending dari arsip selesai lokal.

## Batas perubahan

Tidak ada perubahan izin member, saldo, nominal, metode transaksi lama, atau database produksi. Transaksi lama wajib dicocokkan berdasarkan nomor nota dan bukti pembayaran. Jangan mengaktifkan Tunai untuk meloloskan transaksi yang sebenarnya memakai voucher. Jangan menggunakan Tandai Selesai sebagai bukti penerimaan server.

## Penerapan

Gunakan paket sesuai varian. Cadangkan data lokal sebelum pemasangan dan jangan menghapus penyimpanan aplikasi. Admin memeriksa izin Jenis Member, Tipe Member, Cara Bayar Default, dan Cakupan Toko sesuai kebijakan. Setelah pembaruan, uji pemilihan member, metode, pembukaan ulang pesanan, dan pencocokan Lokal ↔ Server pada perangkat uji terlebih dahulu.

## Status paket

Paket UAT: APK memakai signing debug/UAT dan installer Windows belum memiliki Authenticode. Build release bukan bukti penandatanganan produksi, pemasangan, atau UAT pengguna. Publikasi GitHub tidak mengubah perangkat maupun server secara otomatis.

## Validasi build

58 tes lokal lulus. Empat artefak Android/Windows berhasil dibangun dengan skrip build_semua_varian.ps1, exit 0. Kedua APK versionName 1.34.45 dan versionCode 208; identitas paket albahjah/nahl, signing UAT, konfigurasi varian Windows, dan checksum SHA-256 diperiksa. Belum ada UAT pengguna atau pemasangan produksi.
