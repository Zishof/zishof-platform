# Build Ulang Varian eBisnis 1.34.02

Tanggal verifikasi: 28 Agustus 2026
Varian: `ebisnis`
Versi aplikasi: `1.34.02+160`
Sumber Git: `19178507c77491f8a2adbe1083712da916dff19b`

## Ruang lingkup

- Memeriksa ulang kode terbaru di working tree, termasuk perubahan biometrik anggota dari sesi lain.
- Memastikan seluruh menu yang saat ini terdaftar memiliki definisi, pemeriksaan akses, navigasi, dan route yang terhubung.
- Memastikan administrator melewati pembatas menu melalui pemeriksaan awal `Sesi.instance.isAdmin`.
- Melakukan pengujian dan build ulang Android serta Desktop Windows khusus varian `ebisnis`.
- Mempublikasikan perubahan tervalidasi dan artefak varian `ebisnis` ke GitHub.

## Audit menu

- Jumlah menu terdaftar: 86.
- Seluruh 86 menu mempunyai referensi pemakaian yang memadai; tidak ditemukan menu terdaftar yang yatim atau tidak terhubung.
- Menu UOM/satuan sudah terdaftar, diimpor, memiliki route, dan tercakup oleh mekanisme hak akses.
- Catatan: hasil ini menyatakan kelengkapan menu yang sudah terdaftar di kode saat pemeriksaan, bukan klaim bahwa seluruh fitur roadmap masa depan telah diimplementasikan.

## Hasil verifikasi

- `flutter pub get`: berhasil.
- `flutter analyze`: tidak ada error; terdapat 53 informasi lint/deprecation dan 1 warning `unnecessary_cast` yang tidak menghambat build.
- Pengujian terarah admin, konfigurasi server, dan biometrik anggota: 12/12 lulus.
- Seluruh test Flutter: 424/424 lulus.
- Build APK Android varian `ebisnis`: berhasil.
- Build aplikasi dan installer Windows varian `ebisnis`: berhasil.

## Artefak

### Android

- File: `apps/ebisnis/release-artifacts/semua-varian/1.34.02/app-ebisnis-release.apk`
- Ukuran: 126.981.954 byte (sekitar 121,1 MB)
- SHA-256: `09CC6767A86456FE21079A9DC26938259556D101ADA9BC08DDFC082646CD0197`

### Desktop Windows

- File: `apps/ebisnis/release-artifacts/semua-varian/1.34.02/eBisnis-Setup-1.34.02.exe`
- Ukuran: 47.164.893 byte (sekitar 45,0 MB)
- SHA-256: `B5866D2F05DF5F314EBA9DAA08646498CA2FC7CE72C84D1F61B45A0725BDBCB4`

## Kondisi working tree

Build dilakukan dari working tree terbaru dan tidak membuang perubahan sesi lain. Perubahan biometrik anggota yang sudah ada sebelum build tetap dipertahankan. File log/skrip sementara lama di root repository juga tidak diubah atau dihapus.

## Publikasi

- Tag rilis: `v1.34.02-build160`
- Isi rilis: APK Android dan installer Desktop Windows varian `ebisnis`.
- File sementara lokal tidak dimasukkan ke commit maupun rilis.
