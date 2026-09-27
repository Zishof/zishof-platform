# Al-Bahjah POS: SQLite MISUSE pada pembacaan sesi kas

Baseline pemeriksaan: 976c6dd, hasil pull --ff-only dari main. Log pelapor berisi
SqfliteFfiException / SqliteException(21) saat SELECT sesi_kas_lokal status BUKA.
SQLite mendefinisikan 21 sebagai SQLITE_MISUSE (https://www.sqlite.org/rescode.html#misuse).
Ini bukan bukti sesi autentikasi kedaluwarsa, database korup, atau gangguan server.

## Temuan dan perubahan

AppErrorInfo.dari sebelumnya mencocokkan substring sesi tanpa membedakan error
SQLite; nama tabel sesi_kas_lokal menyebabkan judul login kedaluwarsa yang keliru.
Klasifikasi penyimpanan lokal sekarang mendahului heuristik login/jaringan.
Pesan tidak menyatakan transaksi sudah tersimpan atau sudah diterima server.

CoreDb._buka sebelumnya memperlakukan setiap kegagalan buka/verifikasi sebagai
korupsi dan menjalankan penggantian file. Patch mencegah SQLITE_MISUSE masuk
jalur tersebut. Tidak ada retry pembayaran, penonaktifan validasi, atau perubahan
file database pelanggan. Pengaman ini tidak membuktikan pemicu MISUSE sudah hilang.

Dalam source checkout saat ini, sesiKasAktif dipanggil sebelum simpan outbox dan
aksi bayar. Untuk percobaan yang gagal tepat pada pembacaan itu, jalur pembayaran
belum mencapai kedua tahap tersebut. Riwayat percobaan lain tetap harus diperiksa
sebelum input ulang; source lokal bukan bukti status seluruh transaksi produksi.

## Batas dan prosedur

Belum mereproduksi SQLITE_MISUSE asli di perangkat pelapor; lifecycle koneksi/driver
masih perlu pemeriksaan versi terpasang dan log sebelum kejadian. Tidak ada akses
ke database pelanggan, perubahan produksi, build installer/APK rilis, atau deploy.
Jangan menghapus database, WAL/SHM, cache aplikasi, atau melakukan uninstall.
Catat keranjang; admin menutup POS secara normal lalu mencadangkan seluruh folder
data termasuk sidecar yang masih ada. Setelah itu buka satu instance aplikasi.
Jika masih gagal, hentikan pembayaran pada perangkat itu dan periksa salinan data
serta log, bukan mencoba Bayar berulang. Cocokkan nota/outbox/server sebelum mengulang.

Perbaikan pesan dan pengaman perlu paket klien baru agar berlaku. Tidak ada patch
server dalam perubahan ini. Penerapan produksi belum dijadwalkan.

Validasi: 10 tes aplikasi dan 2 tes CoreDb lulus. Analisis dua file aplikasi tanpa temuan; analisis CoreDb mencatat empat info lint pada baris lama di luar patch. Build Windows debug varian albahjah berhasil (exit 0). Error MISUSE asli belum direproduksi.

Pull folder utama CodeBaseDesktopDanMobile tertahan oleh tujuh perubahan tracked dan satu file tes untracked. Tidak dilakukan stash/reset. Worktree kasus sudah pada origin/main 976c6dd sebelum patch.

## Perbaikan lanjutan: koneksi bersama dan keranjang (baseline 986be5f)

Ditemukan risiko konkret dalam jumlahTransaksiPending: saat SQLite 21 terjadi,
fungsi penghitung menutup koneksi bersama dan membukanya ulang. Checkout/outbox
lain dapat sedang memakai koneksi itu. Jalur close/retry tersembunyi dihapus;
error tetap diteruskan, data tidak dihapus dan jumlah antrean tidak dipalsukan.
Tes injeksi kegagalan menjalankan pembacaan sesi kas bersamaan dengan penghitung
error: sesi tetap selesai, koneksi tidak ditutup, pembacaan selanjutnya berhasil.
Tes ini membuktikan kontrak konkurensi, bukan reproduksi driver perangkat pelapor.
Pemicu pertama SQLITE_MISUSE di perangkat tetap belum dikonfirmasi.

Kasir kini memiliki pengaman navigasi untuk keranjang berisi: pindah menu,
pindah toko, penggantian halaman global, tombol kembali, dan keluar akun meminta
kasir kembali ke keranjang serta berhasil Tahan/Bayar terlebih dahulu. Pengaman
memeriksa isi aktual, bukan status pembayaran buatan. Tidak ada penyimpanan saldo,
pemulihan otomatis setelah listrik padam, atau pengiriman pembayaran tambahan.
Tombol Transaksi Baru masih memerlukan konfirmasi pengosongan yang sudah ada.

Validasi lanjutan: 3 tes CoreDb (termasuk SQLite nyata/pemulihan outbox), 10 tes
aplikasi (klasifikasi galat, kebijakan member, penjaga navigasi) lulus. Analyzer
lima file aplikasi yang berubah tanpa temuan. Build Windows debug Al-Bahjah lulus.
Media: tiga screenshot WhatsApp terbaru diperiksa; keluhan kembali menyebabkan
barang harus dipindai ulang sesuai dengan risiko navigasi dari form belum disimpan.
Tidak ada akses database produksi atau reproduksi pada komputer kasir.

Tidak ada perubahan server, skema, saldo, atau data transaksi lama. Paket klien
harus dipasang untuk menerapkan patch. Publikasi source/paket tidak memasang ke
perangkat secara otomatis. Rencana pemasangan tengah malam WIB belum memiliki
jadwal terkonfirmasi. Sebelum pemasangan: selesaikan/tahan keranjang, cocokkan
status transaksi, tutup aplikasi normal dan cadangkan folder data beserta sidecar.
Rollback memakai installer sebelumnya dan cadangan yang diperiksa admin; jangan
menimpa data baru dengan backup lama secara otomatis.
