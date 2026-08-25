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

## Regresi

`test/app_crud_dialog_actions_test.dart` memastikan percobaan simpan yang gagal
tidak menutup dialog dan tidak menghapus nilai input; percobaan sukses berikutnya
baru menutup dialog.
