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

## Aset yang masih perlu diganti

`assets/images/petra/icon.png` dan `login-background.png` saat ini masih salinan
aset eBisnis (lihat `assets/images/petra/BACA-DULU.txt`). Keduanya harus diganti
dengan aset asli sebelum rilis ke pengguna.

Ikon Windows juga belum bercabang: `windows/runner/Runner.rc` bagian `Icon`
masih jatuh ke `app_icon.ico`. Setelah logo asli tersedia, buat
`windows/runner/resources/icon_petra.ico` lalu tambahkan cabang
`#elif defined(EBISNIS_VARIANT_PETRA)` di bagian tersebut, dan arahkan
`SetupIconFile` di `installer/petra.iss` ke ikon itu.

## Catatan pemaketan

Setiap installer varian memakai folder `build/windows/x64/runner/Release` yang
sama, dan `copy_if_different` tidak menghapus exe varian sebelumnya. Karena itu
`ebisnis_petra.exe` sudah ditambahkan ke daftar `Excludes` pada installer
albahjah, apotik, ebisnis, dan emedik. `inventory_sales.iss` sudah aman karena
memakai pola `ebisnis*.exe` lalu menambahkan exe-nya sendiri secara eksplisit —
pola yang sama dipakai `petra.iss`.
