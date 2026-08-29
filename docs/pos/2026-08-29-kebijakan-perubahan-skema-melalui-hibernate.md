# Kebijakan Perubahan Skema Database melalui Hibernate

Tanggal: 29 Agustus 2026

## Keputusan

Semua pembuatan dan perubahan struktur database aplikasi dilakukan melalui
entity/mapping Hibernate. Kode request, helper API, JSP, ZK, Desktop, dan Android
tidak boleh mengeksekusi DDL seperti `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`,
atau `TRUNCATE TABLE`. Fitur baru juga tidak boleh bergantung pada skrip migrasi
SQL manual.

Pola implementasi yang wajib dipakai:

1. Tambahkan atau ubah entity beranotasi JPA/Hibernate.
2. Daftarkan entity pada `hibernate.cfg.xml` di kedua source tree backend.
3. Gunakan `hbm2ddl.auto=update` saat bootstrap untuk membuat/menyesuaikan tabel,
   kolom, dan constraint yang bersifat additive.
4. SQL JDBC/HQL hanya menangani data bisnis (DML). Nilai audit yang wajib,
   seperti `created_at`, `updated_at`, `event_at`, dan `version`, harus diisi oleh
   aplikasi ketika tidak didefinisikan sebagai default oleh mapping.
5. Perubahan destruktif atau transformasi data tidak dijalankan diam-diam oleh
   request. Perubahan semacam itu harus dirancang sebagai pekerjaan kompatibilitas
   aplikasi bertahap karena `hbm2ddl.auto=update` tidak menghapus data lama.

## Implementasi modul distribusi

Entity berikut menjadi sumber kebenaran struktur modul distribusi:

- `ais.database.model.inventory.DistribusiDokumen`;
- `ais.database.model.inventory.DistribusiDokumenBaris`;
- `ais.database.model.inventory.DistribusiDokumenEvent`; dan
- `ais.database.model.inventory.DistribusiPostingStok`.

Keempat entity telah didaftarkan pada:

- `C:\opt\AIS\ais\src\main\src\hibernate.cfg.xml`; dan
- `C:\opt\AIS\ais\src\main\java\hibernate.cfg.xml`.

Tabel menggunakan schema PostgreSQL `inventory_distribution`. Hibernate mengelola
objek di dalam schema tersebut, sedangkan namespace schema harus sudah tersedia
sebagai prasyarat lingkungan sebelum aplikasi bootstrap. Tidak boleh ditambahkan
DDL pemulihan otomatis pada request hanya untuk menutupi konfigurasi deployment
yang belum lengkap.

## Pengelolaan sesi

- `openSession()` dan `currentNativeSession()` wajib ditutup pada `finally` dengan
  `clear`, `disconnect`, dan `close` melalui helper penutupan yang aman.
- `currentSession()` mengikuti lifecycle transaksi/framework dan tidak ditutup
  manual.

## Verifikasi wajib

- Pastikan mapping entity dapat diparse dari kedua `hibernate.cfg.xml`.
- Cari dan tolak DDL runtime pada helper/API.
- Pastikan source tree utama dan mirror memiliki mapping yang sama.
- Kompilasi verifikasi selalu menuju direktori output sementara; file `.class`
  tidak boleh dibuat berdampingan dengan `.java`.
- Saat rollout, periksa log bootstrap Hibernate dan keberadaan tabel/constraint
  sebelum membuka endpoint distribusi untuk pengguna.

## Dampak dan alasan

Kebijakan ini membuat evolusi skema konsisten dengan model domain, mencegah race
condition akibat DDL di tengah request, menghindari kebutuhan hak DBA pada koneksi
aplikasi ketika transaksi berjalan, serta mengurangi perbedaan struktur antara
instalasi Desktop/JSP/ZK/Android yang memakai backend yang sama.
