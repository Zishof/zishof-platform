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

## Revisi paket Al-Bahjah — HPP hasil opname (24 September 2026)

Nomor versi tetap 1.34.45+208 sesuai permintaan. Hanya paket Al-Bahjah dibangun ulang;
rilis Nahl tidak diganti. Input Opname > Riwayat Hari Ini menampilkan HPP/unit dari
harga beli master saat ini, per satuan dasar, bukan snapshot historis saat opname.
Cache dibaca terlebih dahulu dan diberi label tersimpan, lalu diperbarui melalui
API baca so_produk_scan yang sudah tersedia. Maksimal tiga permintaan bersamaan,
satu per produk unik. Harga yang belum tersedia tidak dianggap nol. Tidak mengubah
harga produk, stok, atau jurnal. Ekspor Excel/PDF tetap menggunakan format sebelumnya.

Tidak ada perubahan source server atau deployment pada revisi ini. Dukungan field
hargaBeli diverifikasi pada source server, belum pada runtime tenant produksi.
Karena versi tidak naik, pembaruan otomatis mungkin tidak menawarkan paket revisi;
unduh ulang aset Al-Bahjah dan pasang menimpa instalasi dengan identitas/signing yang
cocok, setelah mencadangkan data lokal. Jangan uninstall atau menghapus data aplikasi.
Signing tetap UAT/debug Android dan Windows tanpa Authenticode.

Validasi revisi HPP: lima tes perilaku lokal lulus dan analisis tiga file Dart tanpa temuan.
Uji pada perangkat pengguna dan pemeriksaan data produksi belum dilakukan.
