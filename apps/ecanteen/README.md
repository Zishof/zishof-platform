# eCanteen — aplikasi member kantin

Aplikasi belanja untuk anggota/member kantin, toko, outlet, dan cafe.
Tersedia untuk **Android** dan **Desktop Windows**.

Logikanya mengikuti versi web pada modul kantin/member di AIS
(`landing_page.jsp` → `beranda.jsp` → `_beranda_anggota.jsp`) dan memakai API
member yang sudah ada di server: servlet `/Api` dengan aksi berawalan
`kantin_` (lihat `ApiRouteRegistry`).

## Varian build

Satu basis kode, dua identitas. Varian dipilih saat build lewat
`--dart-define=ECANTEEN_VARIANT` **dan** `--flavor`. Keduanya wajib seiring:
dart-define menentukan nama di dalam aplikasi, flavor menentukan label
peluncur Android (`resValue app_name`).

| Varian  | Nama tampilan                        | applicationId               |
|---------|--------------------------------------|-----------------------------|
| `umum`  | eCanteen                             | `com.ecanteen.zishof`       |
| `petra` | Direktorat Pengembangan Usaha Sosial | `com.ecanteen.zishof.petra` |

`applicationId` petra diberi akhiran supaya kedua varian dapat terpasang
berdampingan tanpa saling menimpa. AppId installer Windows dan namespace
penyimpanan lokal juga dipisah untuk alasan yang sama.

## Build

Satu perintah untuk analisis + uji + APK + installer + SHA256SUMS:

```powershell
.\tool\build_rilis.ps1 -Versi 1.0.0                 # kedua varian
.\tool\build_rilis.ps1 -Versi 1.0.0 -Varian petra   # satu varian
```

Skrip menolak berjalan bila `-Versi` tidak sama dengan `version:` di
`pubspec.yaml`, supaya artefak tidak pernah salah label.

Manual:

```powershell
flutter build apk --release --flavor petra --dart-define=ECANTEEN_VARIANT=petra
flutter build windows --release --dart-define=ECANTEEN_VARIANT=petra
```

## Ikon

Seluruh ikon dibangkitkan dari satu sumber oleh `tool/buat_ikon.py`:

```powershell
python tool\buat_ikon.py .
```

Menghasilkan lima densitas mipmap Android, `app_icon.ico` Windows, dan aset
layar Masuk. Jalankan ulang setelah mengubah gambar/warna di skrip.

## Penandatanganan APK — PERLU DIKERJAKAN sebelum distribusi luas

> **APK rilis saat ini ditandatangani dengan kunci DEBUG.**
> `android/app/build.gradle` masih memakai
> `signingConfig = signingConfigs.debug` pada `buildTypes.release`, warisan
> `flutter create`.

Ini disepakati **sementara** (Agustus 2026) supaya distribusi internal bisa
jalan lebih dulu. Konsekuensinya:

- APK tidak dapat diunggah ke Google Play.
- Kunci debug tidak stabil antar mesin/instalasi Flutter, sehingga pembaruan
  bisa ditolak dengan galat "signatures do not match" bila APK berikutnya
  dibangun di komputer lain.
- Tidak ada jaminan keaslian penerbit bagi pengguna yang memasang.

Sebelum distribusi sungguhan, siapkan keystore rilis sendiri mengikuti pola
aplikasi `apps/ebisnis` (`key.properties` + `signingConfigs.release`), lalu
ganti `signingConfig` pada blok `release`. **Simpan keystore dan sandinya di
luar repo** — jangan pernah di-commit.

## Kebutuhan server

Perlu AIS revisi SVN **r77785** atau lebih baru:

- `kantin_meja_cek` — menerjemahkan QR meja lewat query berparameter.
- `mobile_auth.jsp` menerima parameter tujuan yang di-whitelist (dipakai untuk
  membuka halaman topup dan notifikasi tanpa login ulang).
- Gerbang kepemilikan pada `bayarOnline`.

## Uji

```powershell
flutter test
```

`test/diskon_engine_test.dart` mengunci perilaku perhitungan diskon terhadap
`evaluateDiscount()` versi JSP — urutan aturan pertama-yang-cocok, persentase
mendahului nominal, batas maksimal, dan pagu harian per aturan yang dibagi
lintas baris keranjang.
