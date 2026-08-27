# Form CRUD tetap terbuka saat proses gagal

Tanggal: 2026-08-25

## Masalah

Sejumlah dialog tambah/ubah menutup form melalui `Navigator.pop()` sebelum
validasi dan permintaan simpan selesai. Jika validasi atau server menolak,
pengguna kehilangan dialog beserta konteks isian dan harus membuka form lagi.

## Perbaikan

- Menambahkan `AppCrudDialogActions` sebagai pola submit dialog bersama.
- Proses validasi dan simpan dijalankan ketika dialog masih terbuka.
- Tombol dikunci dan menampilkan status `Menyimpan...` selama proses.
- Kegagalan tampil sebagai pesan di dalam dialog tanpa menghapus isian.
- Dialog hanya ditutup setelah callback simpan mengembalikan sukses.
- Pola diterapkan pada form Uang Muka, Dana Talangan, Kas Kecil, Kas Besar,
  Penggantian Kas Kecil, Pertanggungjawaban Uang Muka,
  Pertanggungjawaban Kas Besar, dan Reimbursement.

## Aturan wajib seluruh form

Kontrak UX berikut berlaku untuk seluruh form tambah/ubah, baik berupa dialog,
bottom sheet, maupun halaman editor tersendiri:

1. Setelah penyimpanan dinyatakan berhasil, form harus ditutup dan layar induk
   harus memuat ulang data.
2. Status server lama `00` dan status server baru `success` sama-sama berarti
   berhasil. Keduanya tidak boleh membuat pesan sukses tampil sebagai galat.
3. Simpan offline-first yang sudah aman masuk antrean lokal juga dianggap
   selesai bagi form: form ditutup dan sinkronisasi dilanjutkan di latar.
4. Jika validasi lokal, penyimpanan lokal, atau server menolak, form tetap
   terbuka dan seluruh isian pengguna dipertahankan.
5. Tombol Simpan dikunci selama proses agar satu ketukan tidak menghasilkan
   mutasi ganda.
6. Form pengaturan yang memang dirancang tetap berada pada halaman yang sama
   bukan dialog CRUD. Form seperti itu wajib menampilkan konfirmasi sukses,
   tetapi tidak perlu keluar dari halaman pengaturan.

Implementasi offline-first memakai `prosesSimpanMaster`. Fungsi ini hanya
mengembalikan hasil ketika simpan berhasil atau sudah aman di antrean lokal,
dan menormalisasi status sukses menjadi `00`. Nilai status server asli tetap
tersedia sebagai `statusAsli` untuk audit. Penolakan dilempar kembali ke form
sehingga form tidak tertutup.

Form dialog baru sebaiknya memakai `AppCrudDialogActions`. Komponen tersebut
menutup dialog hanya ketika callback mengembalikan `true` dan mempertahankannya
saat callback gagal atau melempar galat.

## Regresi

`test/app_crud_dialog_actions_test.dart` memastikan percobaan simpan yang gagal
tidak menutup dialog dan tidak menghapus nilai input; percobaan sukses berikutnya
baru menutup dialog.

`test/form_simpan_menutup_kontrak_test.dart` memastikan:

- `success`, `00`, dan hasil antrean offline dikenali sebagai penyimpanan
  berhasil;
- editor Jurnal Umum menutup dan daftar induknya dimuat ulang;
- seluruh keluarga form berbasis `AppFormSheet` memiliki jalur penutupan sukses.
