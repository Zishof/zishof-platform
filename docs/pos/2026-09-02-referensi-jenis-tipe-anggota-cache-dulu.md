# Referensi Jenis dan Tipe Anggota Dibaca Cache-Dulu

Tanggal: 2 September 2026  
Lanjutan: audit Local-First daftar master/referensi kecil

## Masalah

Daftar Jenis Anggota dan Tipe Anggota adalah master referensi stabil, tetapi
sebagian layar masih memanggil API langsung. Saat jaringan putus, form Data
Member dan Aturan Diskon kehilangan pilihan target, sedangkan filter Jenis
Anggota pada Monitor Diskon menghilang meskipun snapshot referensinya pernah
tersedia di perangkat.

## Perubahan

Empat call-site sekarang memakai `MasterOffline.daftarDenganCache` dengan kunci
yang sama lintas layar:

- `jenis_anggota_list` -> `master:jenis_anggota_pilihan`;
- `tipe_anggota_list` -> `master:tipe_anggota_pilihan`.

Pemakai kunci tersebut:

- `anggota/tab_data_member.dart`;
- `diskon/tab_aturan_diskon.dart`;
- `diskon/tab_monitor_diskon.dart` (Jenis Anggota saja).

Satu hasil sinkron dari layar mana pun dapat menjadi fallback layar lain. Kunci
Tipe Anggota sengaja mengikuti kunci pilihan yang sudah dipakai Data Member;
kunci ini tidak dicampur dengan cache tab admin yang bentuk responsnya berbeda.

## Batas integritas

Hanya master dropdown yang memakai snapshot. Aksi `monitor_promo_cashback`
tetap memanggil server secara langsung karena hasilnya bergantung periode dan
toko. Statistik lama tidak boleh ditampilkan seolah-olah merupakan statistik
terkini.

## Penjaga regresi

`test/regresi_lokal_dulu_test.dart` memeriksa bahwa:

- ketiga layar memakai `MasterOffline.daftarDenganCache`;
- seluruh layar memakai kunci cache bersama yang benar;
- Monitor Diskon tetap mengambil `monitor_promo_cashback` secara online.

Hasil 2 September 2026:

- `flutter test test/regresi_lokal_dulu_test.dart`: **9/9 lulus**;
- `flutter analyze` pada tiga layar dan test: **tidak ada masalah**;
- `git diff --check`: bersih.

## Disposisi batch berikutnya

Lanjutkan satu kelompok homogen lain dari master referensi kecil. Jangan
mencampur laporan ber-rentang tanggal, hak akses, approval, saldo, atau aksi
posting ke batch cache ini; kelompok tersebut membutuhkan kontrak kesegaran
dan kunci konteks tersendiri.
