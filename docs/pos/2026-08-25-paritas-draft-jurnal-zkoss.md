# Paritas Draft Jurnal Desktop dengan ZKoss

Tanggal: 2026-08-25

## Tujuan

Menyamakan alur kerja halaman **Draft Jurnal** POS Desktop eBisnis dengan versi ZKoss. Implementasi bukan hanya menyalin tampilan, tetapi memakai sumber ringkasan dan rincian jurnal backend yang sama agar nilai debit/kredit, status posting, dan kategori tetap konsisten.

## Sumber acuan ZKoss

- `C:\opt\AIS\ais\src\main\webapp\WEB-INF\z\x\y\pages\master\akunting\draft_jurnal.zul`
- `C:\opt\AIS\ais\src\main\src\ais\action\master\dashboard\akunting\DrafJurnalAction.java`
- `C:\opt\AIS\ais\src\main\java\ais\action\master\dashboard\akunting\DrafJurnalAction.java`

## Implementasi Desktop

File utama:

- `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\lib\screens\draft_jurnal_screen.dart`

Fitur yang disamakan:

1. Navigasi kategori berada di atas filter, mengikuti urutan kerja ZKoss:
   - Draft Jurnal
   - Jurnal Umum
   - Uang Muka dan Kas
   - Pajak
   - Transaksi Vendor
   - Gaji
   - Siswa dan Mahasiswa
   - Fixed Asset & Penyusutan
   - Pengajuan Transfer
   - Transitori
   - Closing
   - Posting Penjualan
2. Filter tanggal mulai dan sampai serta tombol **Tampilkan**.
3. Tombol **Download** mengekspor data kategori dan periode yang sedang aktif ke Excel.
4. Kartu ringkasan Draft, Terposting, Closing, dan Total Aktivitas.
5. Indikator kesiapan closing.
6. Tabel aktivitas dengan jumlah Draft, Terposting, Closing, uraian, dan aksi.
7. Angka ringkasan yang mendukung rincian dapat dibuka untuk menampilkan bentuk jurnal debit/kredit.
8. Rincian menampilkan akun, uraian, debit, kredit, total, dan status keseimbangan.
9. Aksi posting/batal posting mengikuti flag otorisasi dan status yang diberikan backend.
10. Fallback kategori tetap tersedia untuk kompatibilitas dengan server lama yang belum mengirim atribut kategori.

## Dukungan backend

File:

- `C:\opt\AIS\ais\src\main\src\ais\action\master\akunting\util\DraftJurnalRingkasanUtil.java`
- `C:\opt\AIS\ais\src\main\src\ais\action\servlet\api\DraftJurnalApiHelper.java`

Backend mengirim `kategori` dan `kategoriNama` untuk setiap sumber jurnal serta menyediakan preview baris debit/kredit. Sumber yang dicakup meliputi jurnal umum, kas dan uang muka, pajak, transaksi vendor, gaji, siswa/mahasiswa, aset dan penyusutan, pengajuan transfer, transitori, closing, serta posting penjualan/HPP.

## Verifikasi

- `dart format lib/screens/draft_jurnal_screen.dart`: berhasil.
- `flutter analyze lib/screens/draft_jurnal_screen.dart`: **No issues found**.
- `mvn -q -DskipTests compile` pada backend AIS: berhasil (`MAVEN_EXIT=0`).

## Batas pekerjaan sesi ini

- Tidak melakukan publikasi GitHub, release, atau deployment server karena tidak diminta pada perubahan ini.
- UAT runtime yang memerlukan server dan data produksi belum dilakukan; verifikasi sesi ini mencakup analisis statis Flutter dan kompilasi backend.
- Workspace sedang berisi perubahan dari beberapa sesi. Perubahan dijaga tetap terbatas pada layar Draft Jurnal, dukungan kategorisasi backend, dan dokumentasi ini.
