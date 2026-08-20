# Varian eKantin Petra

Varian untuk kantin Universitas Kristen Petra, dikelola Direktorat Pengembangan
Usaha Sosial. Fitur aplikasinya sama persis dengan POS eBisnis; yang berbeda
hanya identitas, aset, server bawaan, dan tata letak layar Masuk.

## Identitas

| Hal | Nilai |
|---|---|
| Kode varian (`EBISNIS_VARIANT`) | `petra` |
| Entrypoint | `lib/main_petra.dart` |
| Flavor Android | `petra` |
| applicationId | `id.zishof.ebisnis.petra` |
| Nama aplikasi | eKantin Petra |
| Exe Windows | `ebisnis_petra.exe` |
| Installer | `eKantin-Petra-Setup-<versi>.exe` |
| Namespace penyimpanan lokal | `petra` |
| Prefix tag pembaruan | `petra-` |
| Server bawaan | `https://kantinpcu.ecampus.id/petra` |

Namespace penyimpanan dan keyword pembaruan sengaja terpisah supaya data lokal
tidak tercampur dengan varian lain pada komputer yang sama, dan updater tidak
menarik installer varian lain.

## Perintah build

```
flutter build windows --release -t lib/main_petra.dart --dart-define=EBISNIS_VARIANT=petra
flutter build apk --release --flavor petra -t lib/main_petra.dart --dart-define=EBISNIS_VARIANT=petra
```

Kedua parameter wajib dan harus konsisten — kombinasi yang salah terdeteksi
`AppProductProfile.cocokDenganDartDefine()` dan tercatat ke error_log.

## Layar Masuk dua kolom

`AppVariant.loginDuaKolom` menyalakan tata letak dua kolom: panel biru berisi
logo, nama organisasi, dan kotak "HUBUNGI KAMI"; panel putih berisi formulir.
Tata letak ini hanya aktif bila lebar tersedia >= 720 px — di ponsel dan jendela
sempit otomatis kembali ke kartu satu kolom supaya formulir tidak terhimpit.

Teks kontak diambil dari `AppVariant.alamatKontakLogin`, `teleponKontakLogin`,
dan `emailKontakLogin`.

## Aset

| Berkas | Sumber |
|---|---|
| `assets/images/petra/icon.png` | Logo resmi UKP, diunduh dari `https://www.petra.ac.id/img/icons/android-chrome-512x512.png` (512x512 RGBA), disimpan ulang non-interlaced |
| `assets/images/petra/login-background.png` | Dibangkitkan sendiri: gradasi biru korporat 1920x1080 dgn watermark logo transparan 10% |
| `windows/runner/resources/icon_petra.ico` | Dari icon.png, berisi 256/128/64/48/32/16 |

Latar layar Masuk sengaja TIDAK memakai foto kampus: gradasi buatan sendiri
menghindari soal hak pakai foto pihak lain, dan karena kartu Masuk menutup
bagian tengah layar, bidang warna rapi lebih terbaca daripada foto ramai.

Ikon Windows sudah bercabang di `windows/runner/Runner.rc`
(`#elif defined(EBISNIS_VARIANT_PETRA)`) dan `installer/petra.iss` memakai
`icon_petra.ico`.

## Catatan pemaketan

Setiap installer varian memakai folder `build/windows/x64/runner/Release` yang
sama, dan `copy_if_different` tidak menghapus exe varian sebelumnya. Karena itu
`ebisnis_petra.exe` sudah ditambahkan ke daftar `Excludes` pada installer
albahjah, apotik, ebisnis, dan emedik. `inventory_sales.iss` sudah aman karena
memakai pola `ebisnis*.exe` lalu menambahkan exe-nya sendiri secara eksplisit —
pola yang sama dipakai `petra.iss`.
