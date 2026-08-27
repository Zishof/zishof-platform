# Fase 12 — Paritas Platform Desktop, Android, JSP, dan ZK

Tanggal: 26 Agustus 2026  
Status: fondasi kontrak dan UAT teknis selesai; adapter layar per layar serta sign-off Product Owner/QA masih pending.

## Tujuan

Fase ini menetapkan satu kontrak perilaku agar menu dan aksi bisnis yang sama tidak mempunyai arti, hak akses, pola error, atau aturan penyimpanan yang berbeda pada Desktop, Android, JSP, dan ZK.

## Implementasi fondasi

- Registry Java kanonis berada di `C:\opt\AIS\ais\src\main\src\ais\common\EbisnisPlatformParityRegistry.java` dan dimirror ke jalur kompatibilitas `src\main\java`.
- Self-test Java tanpa dependensi framework berada di `C:\opt\AIS\ais\src\main\src\ais\common\test\EbisnisPlatformParityRegistrySelfTest.java` dan harus selalu dikompilasi ke direktori `.codex-build`, bukan ke direktori source.
- Kontrak Flutter berada di `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\lib\services\platform_parity_contract.dart`.
- UAT Flutter berada di `C:\opt\CodeBaseDesktopDanMobile\apps\ebisnis\test\platform_parity_contract_test.dart`.
- Menu dan aksi tetap menggunakan `EbisnisMenuBlueprintRegistry` dan `EbisnisMenuActionRegistry` sebagai sumber identitas kanonis.

## Aturan lintas platform

1. Desktop, Android, JSP, dan ZK harus memakai kode menu dan aksi kanonis yang sama.
2. Administrator memperoleh bypass akses yang terkontrol; pengguna non-admin wajib mempunyai izin `TbmroleAction` yang sesuai.
3. Aksi tanpa izin harus tersembunyi sekaligus tidak dapat dieksekusi dari endpoint.
4. Paging memakai nilai awal 10 baris dan batas maksimum 100 baris.
5. Semua aksi tulis wajib membawa idempotency key.
6. Perubahan selain create wajib membawa versi optimistik untuk mendeteksi konflik pembaruan.
7. Respons gagal menggunakan kontrak `EBISNIS_ERROR_V1` agar judul, pesan, kode, solusi, dan referensi teknis dapat ditampilkan konsisten.
8. Ekspor PDF, Excel, cetak, dan bantuan kontekstual merupakan kapabilitas inti pada seluruh platform.
9. Pemindaian barcode/QR dan antrean offline hanya dinyatakan tersedia pada Desktop dan Android. JSP dan ZK tidak mengiklankan kapabilitas yang tidak dimilikinya.
10. Navigasi responsif dan work queue wajib tersedia pada keempat platform.

## Hasil UAT teknis

- Java 1.7: **LULUS**, 76 pemeriksaan kontrak.
- Flutter: **LULUS**, 3 kelompok pengujian kontrak.
- Kompilasi Java diarahkan ke `C:\opt\AIS\ais\.codex-build\fase12`; tidak menghasilkan `.class` baru di direktori sumber.

## Yang belum diaktifkan

- Belum ada perubahan database atau migrasi yang dijalankan.
- Belum ada writer produksi atau route baru yang diaktifkan.
- Adapter setiap layar Desktop, Android, JSP, dan ZK belum dinyatakan selesai.
- UAT visual, end-to-end, konkurensi, offline/online, dan sign-off Product Owner/QA masih wajib dilakukan.

## Gerbang penerimaan

1. Satu golden flow dijalankan pada empat platform untuk aksi view, create, edit draft, retry, conflict, dan export.
2. Hasil data, hak akses, paging, pesan error, dan audit trail harus identik secara semantik.
3. Retry dengan idempotency key yang sama tidak boleh menambah transaksi kedua.
4. Versi data basi harus ditolak dengan konflik yang informatif, bukan menimpa data terbaru.
5. Product Owner dan QA menandatangani matriks paritas setelah UAT layar selesai.

## Rollback

Adapter UI dan endpoint harus diaktifkan per modul/platform melalui feature flag. Jika hasil paritas menyimpang, nonaktifkan adapter platform terkait dan kembali ke jalur lama tanpa menghapus data atau kontrak kanonis.
