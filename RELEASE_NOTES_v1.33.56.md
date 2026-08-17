# Al-Bahjah POS v1.33.56

Rilis pemulihan dan rekonsiliasi transaksi untuk Desktop dan Android.

## Perubahan

- Supervisor/admin dapat menambahkan transaksi pemulihan dari halaman Riwayat Penjualan menggunakan form koreksi yang sama.
- Sinkronisasi dua arah membandingkan kode transaksi unik: data yang belum ada di lokal diarsipkan dari server, sedangkan data lokal yang belum ada di server dikirim kembali.
- Kode unik tetap idempoten pada retry, respons hilang, dan kondisi balapan; transaksi yang sudah ada ditandai tersinkron tanpa dibuat ulang.
- Transaksi ditulis ke SQLite sebelum dikirim ke server dan arsip lokal yang sudah tersinkron tetap dipertahankan.
- Database lokal tetap memakai satu tabel berindeks dengan constraint unik, ditambah indeks toko/waktu/status untuk rekap cepat tanpa tabel dinamis per tanggal.
- Backend memvalidasi hak supervisor, kasir yang dipilih, alasan audit, stok, harga, diskon, dan seluruh logika transaksi lama.
- Daftar transaksi server kini menyertakan kode idempotensi mentah; klien tetap kompatibel dengan server lama dengan mengekstrak kode dari label nota.

## Verifikasi

- Flutter analyze: tidak ada error baru.
- UAT otomatis kritis: 7/7 lulus (otorisasi, retry, persistensi, sinkronisasi, dan deduplikasi).
- Backend berhasil dikompilasi dengan `-source 7 -target 7`.
- Windows release dan installer Inno Setup berhasil dibangun.
- APK release lolos verifikasi signature v1/v2 dan menggunakan sertifikat yang sama dengan v1.33.55.
