# Riwayat perubahan data member

Tanggal implementasi: 29 Agustus 2026

## Tujuan

Halaman **Master Data > Pelanggan** memiliki tab **Riwayat CRUD** yang membaca
tabel audit Hibernate Envers di server. Tab memakai komponen audit global dalam
mode tertanam: jenis data awal adalah **Anggota/Member**, tetapi administrator
dapat mengganti pilihan Jenis Data untuk memantau CRUD POS lain tanpa keluar
dari halaman. Tab ini melengkapi tombol riwayat per-member: administrator dapat
mencari revisi lintas member, termasuk member yang sudah dihapus, lalu membuka
rincian perubahannya.

## Informasi yang ditampilkan

- nama dan kode member, identitas, kontak, waktu, nomor revisi, tipe perubahan,
  dan pelaku;
- nama field bisnis dengan istilah yang dipahami pengguna, misalnya Jenis
  Member, Tipe Member, Satuan Kerja, Status Aktif, dan Batas Kredit/Piutang;
- jenis data serta nilai **dari → menjadi** untuk setiap perubahan;
- filter rentang tanggal, jenis perubahan, kata kunci, dan toko bila entitas
  audit mempunyai relasi toko;
- maksimal 100 revisi per halaman dengan tombol memuat halaman berikutnya.

Riwayat lintas-member hanya dapat dibuka administrator karena dapat mencakup
data yang sudah dihapus dan data lintas toko. Pengguna biasa tetap dapat membuka
riwayat satu member melalui tombol jam pada baris member.

## Keamanan data audit

Endpoint audit generik wajib mengecualikan kredensial dari daftar, detail, dan
ringkasan revisi. Field PIN, password/pass, hash, salt, token, dan secret tidak
pernah dikirim ke aplikasi. Status operasional seperti `pinSudahDiatur` boleh
ditampilkan karena tidak mengandung nilai PIN.

Audit tetap online-only dan tidak disalin ke SQLite perangkat agar sumber
kebenaran jejak perubahan tidak terpecah.

## UAT

1. Tambah atau ubah satu member, misalnya nama, tipe, nomor HP, atau batas
   kredit, lalu simpan.
2. Buka **Pelanggan > Riwayat CRUD**, pastikan Jenis Data berisi
   **Anggota/Member**, pilih rentang tanggal, lalu tekan
   **Tampilkan**.
3. Pastikan nama member, waktu, pelaku, dan tipe `TAMBAH`/`UBAH` terlihat.
4. Klik baris; pastikan field menampilkan jenis data dan nilai dari → menjadi.
5. Ubah PIN member; pastikan audit boleh mencatat bahwa proses terjadi, tetapi
   nilai PIN, hash, dan salt tidak muncul dalam respons atau layar.
6. Login sebagai non-administrator; jelajah lintas-member harus ditolak dengan
   penjelasan, sedangkan riwayat satu member tetap dapat dibuka.
7. Putuskan jaringan; layar harus menjelaskan audit server belum dapat dimuat
   dan menawarkan **Coba Lagi** tanpa menghapus cache member lokal.
