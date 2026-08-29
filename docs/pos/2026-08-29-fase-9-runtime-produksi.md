# Fase 9 — Runtime Produksi Desktop dan Android

Tanggal verifikasi: 29 Agustus 2026  
Status: implementasi runtime dan UAT kontrak **lulus**

## Ruang lingkup

Fase ini mengaktifkan satu layar Produksi bersama untuk build Desktop dan Android
Flutter. Layar tersebut tidak menduplikasi domain Pergudangan/Distribusi dan
menggunakan kontrak backend kanonis untuk tujuh proses berikut:

| Hak akses/menu | Jenis dokumen backend |
| --- | --- |
| `produksi_bill_of_material` | `bill_of_material` |
| `produksi_work_order` | `work_order` |
| `produksi_material_issue` | `material_issue` |
| `produksi_material_return` | `material_return` |
| `produksi_production_output` | `production_output` |
| `produksi_production_waste` | `production_waste` |
| `produksi_production_cost` | `production_cost` |

Administrator tetap memperoleh seluruh menu melalui kebijakan global shell,
sedangkan pengguna non-admin mengikuti hak akses granular di atas.

## Kontrak API

Flutter memakai `ApiClient.instance.aksi(...)` untuk:

- `produksi_list`: daftar dokumen menurut jenis, toko, kata kunci, dan status;
- `produksi_detail`: master, rincian bahan/baris, dan genealogi;
- `produksi_simpan`: create/update idempoten dengan `clientMutationId`;
- `produksi_status`: transisi status dokumen.

Payload mempertahankan rincian `baris`, `genealogi`, kuantitas, harga/biaya, toko,
lokasi, produk, serta identitas mutasi. UI tidak menggunakan method `ApiClient.post`
yang tidak tersedia.

Backend dirutekan oleh `PosApi` ke `ProduksiApiHelper`. Persistensi menggunakan
Hibernate ORM; fase ini tidak menambahkan DDL/manual SQL schema.

## Lifecycle session backend

Seluruh pemakaian `openSession()` pada `ProduksiApiHelper` ditutup di blok
`finally` melalui `HibernateUtil.closeSessionQuietly(session)`. Implementasi helper
bersama tersebut sudah diaudit dan melakukan:

1. melepas thread-local session yang sama;
2. `clear()`;
3. rollback transaksi Hibernate/JDBC yang masih aktif bila diperlukan;
4. `disconnect()`;
5. `close()`.

Tidak ada `currentSession()` yang ditutup manual pada helper Produksi.

## Sinkronisasi source backend

Salinan kanonis dan mirror berikut mempunyai SHA-256 identik saat diverifikasi:

- `src/main/src/ais/action/servlet/api/ProduksiApiHelper.java` dan
  `src/main/java/ais/action/servlet/api/ProduksiApiHelper.java`;
- `src/main/src/ais/action/servlet/PosApi.java` dan
  `src/main/java/ais/action/servlet/PosApi.java`.

## UAT dan bukti verifikasi

### Java backend

- Kompilasi target dilakukan terisolasi dengan `javac -source 1.7 -target 1.7
  -implicit:none`.
- Hasil: `JAVAC_EXIT=0` (hanya peringatan bootstrap classpath JDK modern).
- Output target berada di `.codex-build/produksi-targeted-20260829`, bukan di
  direktori sumber.
- Pemeriksaan source tree: `SOURCE_CLASS_COUNT=0`.

### Flutter Desktop/Android

Perintah:

```text
C:\opt\flutter\bin\flutter.bat analyze lib\screens\produksi_screen.dart lib\widgets\app_shell.dart
C:\opt\flutter\bin\flutter.bat test test\produksi_menu_contract_test.dart
```

Hasil:

- analyzer: `No issues found!`;
- 3 pengujian kontrak lulus:
  - shell responsif menyediakan seluruh submenu dan hak akses Produksi;
  - layar memakai tujuh jenis dokumen backend kanonis;
  - form mempertahankan rincian bahan dan genealogi.

Karena Desktop dan Android memakai source Flutter yang sama, kontrak menu dan
runtime yang diuji berlaku untuk kedua platform. Build artefak installer/APK dan
publikasi release bukan bagian dari verifikasi ini.

## Berkas implementasi

- `apps/ebisnis/lib/screens/produksi_screen.dart`
- `apps/ebisnis/lib/widgets/app_shell.dart`
- `apps/ebisnis/test/produksi_menu_contract_test.dart`
- `src/main/src/ais/action/servlet/api/ProduksiApiHelper.java`
- `src/main/src/ais/action/servlet/PosApi.java`

## Catatan handover

- Jangan mengompilasi `.class` ke direktori yang sama dengan `.java`.
- Pertahankan Java 1.7/gaya Java 1.6 pada backend legacy.
- Jika kontrak backend berubah, perbarui test kontrak sebelum build semua varian.
- Jangan mengganti jenis produksi dengan route distribusi yang namanya mirip.

