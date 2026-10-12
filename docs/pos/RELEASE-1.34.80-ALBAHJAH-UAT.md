# Al-Bahjah POS 1.34.80 (build 243) — UAT

## Perubahan

- Menambahkan snapshot penuh SQLite otomatis pada Windows saat basis data pertama kali dibuka dan setiap 15 menit.
- Menyimpan setiap snapshot di dua direktori terpisah: `Application Support/eBisnis/<varian>/BackupDatabase` dan `Documents/eBisnis/<varian>/BackupDatabase`.
- Snapshot dibuat dengan `VACUUM INTO`, diperiksa menggunakan `PRAGMA quick_check`, lalu salinan kedua diverifikasi kembali sebelum cadangan lama dibersihkan.
- Menyimpan tujuh snapshot terakhir di setiap lokasi. Kegagalan pencadangan dicatat di menu Log Error dan dicoba kembali pada siklus berikutnya.
- Menetapkan SQLite WAL dengan `synchronous=FULL` untuk memperkuat ketahanan commit terhadap listrik padam.
- Pemulihan otomatis hanya berjalan untuk error korupsi SQLite yang dikenali. Berkas DB/WAL/SHM tidak dihapus jika pengarsipan gagal; pembukaan ulang dibatalkan supaya transaksi lokal tidak tertutup oleh database kosong.

## Batas perlindungan

Kedua direktori bawaan berada di profil komputer yang sama dan biasanya pada kandar fisik yang sama. Ini membantu bila satu file database rusak atau aplikasi dipasang ulang, tetapi bukan cadangan terhadap kerusakan seluruh kandar/komputer. Untuk perlindungan perangkat, gunakan UPS dan siapkan tujuan salinan di NAS/kandar eksternal melalui kebijakan pencadangan perangkat. Interval snapshot penuh paling lama 15 menit; arsip transaksi lokal tetap menjadi jalur tambahan.

Snapshot memuat data lokal POS dan harus dijaga aksesnya seperti data kasir lainnya. Jangan mengirim berkas tersebut melalui WhatsApp atau layanan publik.

## Validasi build dan pemeriksaan

- Seluruh tes pada package `core_db`: lulus (19 tes).
- `flutter analyze` pada package `core_db`: lulus tanpa temuan.
- `flutter analyze` pada aplikasi `ebisnis`: gagal dengan 45 temuan lama pada berkas lain (3 warning dan 42 info); file aplikasi tidak diubah selain nomor versi.
- Clean build Windows varian Al-Bahjah: lulus. Build Windows menampilkan warning konversi angka pada dependency `flutter_zxing`; build tetap selesai sukses.
- Snapshot di kedua lokasi berhasil dibuka, lolos `quick_check`, dan memuat transaksi uji.
- Installer: `Al-Bahjah-POS-Setup-1.34.80.exe`, 90,012,260 byte, SHA-256 `0d7173256a923bae093fd5acab65833078577a8370a5a0b2c205a79192b00733`.
- Status tanda tangan installer: unsigned, untuk UAT/internal.

Build berhasil hanya membuktikan paket lokal dapat dibuat; UAT di perangkat kasir dan penerapan ke produksi belum dilakukan.
