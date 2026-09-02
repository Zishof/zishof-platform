# 71. Jalur SQL Tulis Anonim pada `/Data` Ditutup

Tanggal: 2 September 2026  
Lanjutan langsung: dok. 70 (permukaan SQL dari klien)  
Sifat: **temuan keamanan** + perbaikan lapis pertama

## Rantai temuan

Tiga hal yang masing-masing tampak wajar, tetapi bila digabung membuka jalan
menjalankan perintah tulis ke basis data tanpa pernah masuk:

1. **Endpoint `/Data` dapat dijangkau tanpa login.** Aturan penutup Spring
   Security untuk `/**` adalah `IS_AUTHENTICATED_ANONYMOUSLY`, dan `/Data` tidak
   disebut sebagai pola khusus.
2. **Pemeriksaan login di dalam servlet dapat dilewati oleh pemanggilnya
   sendiri.** Payload cukup memuat `"tanpaLogin":"true"` dan pemeriksaan
   pengguna dilompati. Penanda itu dikirim oleh halaman, sehingga pemanggil mana
   pun dapat menyetelnya — termasuk yang tidak pernah membuka halaman kita.
3. **Penjaga SQL bawaan mati.** `mode_proteksi_sql_endpoint` bawaannya `off`
   (dok. 70), jadi `action=update_data` menerima perintah tulis apa adanya.

Gabungannya: siapa pun yang dapat menjangkau endpoint ini dapat menjalankan
`UPDATE`/`DELETE` bebas terhadap basis data.

## Yang diperbaiki

Aksi yang menjalankan SQL tulis bebas — `update_data` dan `update_file_data` —
kini **selalu** menuntut pengguna yang sudah masuk, apa pun isi payload.

Ini pertahanan **lapis pertama** yang tidak bergantung pada konfigurasi: berlaku
bahkan pada instalasi yang belum pernah menyetel mode proteksi. Lapis keduanya,
`SqlSecurityGuard`, tetap menjadi keputusan pemilik.

## Dampaknya diperiksa lebih dulu, bukan diasumsikan

Seluruh JSP disisir: **tidak ada satu pun** halaman yang mengirim `update_data`
bersama `tanpaLogin`. Enam halaman yang memang memakai jalur tulis (persetujuan
pengajuan harga, penyesuaian stok, penandaan transaksi terlayani, dan lainnya)
semuanya dipakai pengguna yang sudah masuk. Jadi penutupan ini tidak memutus
fungsi apa pun.

## Yang sengaja TIDAK disentuh

Jalur **baca** (`action=sql`) tetap dapat dipanggil tanpa login, karena beberapa
halaman publik yang sah memang mengandalkannya: landing page les, pendaftaran
calon anggota koperasi, toko online, dan statistik alumni. Menutupnya di sini
akan memutus halaman yang memang dirancang publik.

Mitigasi untuk jalur baca adalah menyalakan `SqlSecurityGuard` (dok. 70), yang
membatasi `action=sql` menjadi read-only satu statement, menolak objek sistem
basis data, dan menolak pola kolom sensitif seperti kata sandi. **Selama mode
masih `off`, pembacaan basis data secara bebas oleh pihak tak dikenal masih
mungkin** — inilah alasan terkuat untuk menaikkannya ke `log` lalu `enforce`.

## Tindakan yang disarankan kepada pemilik

1. Nyalakan `mode_proteksi_sql_endpoint` = `log`, amati keluaran server
   berawalan `[SqlSecurityGuard]` selama beberapa hari.
2. Bila tidak ada kueri sah yang tertolak, naikkan ke `enforce`.
3. Pertimbangkan menambahkan `/Data` sebagai pola ber-otentikasi pada aturan
   keamanan, dengan pengecualian eksplisit hanya untuk halaman publik yang
   benar-benar membutuhkannya.
4. Jangka panjang: pindahkan operasi tulis ke endpoint ber-aksi, sebagaimana
   jalur POS — server menyusun kuerinya, klien hanya mengirim maksud dan
   parameter (dok. 70).
