# Signing rilis (Android APK & installer Windows)

Status: **scaffold siap; keystore + password = milik/tanggung jawab pemilik.**
Claude tidak membuat keystore/password (rahasia yang harus Anda pegang sendiri).

## Android (APK)

Gradle sudah wired (`apps/ebisnis/android/app/build.gradle`): bila
`apps/ebisnis/android/key.properties` ada, build release ditandatangani dengan
keystore itu; bila tidak, fallback ke debug key (perilaku lama).

Langkah sekali-saja (di mesin rilis pemilik):

1. Buat keystore (simpan file `.jks` di luar repo, password rahasia):
   ```bash
   keytool -genkey -v -keystore C:/keystore/ebisnis-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias ebisnis
   ```
2. Salin template lalu isi nilai asli (file ini sudah di-gitignore):
   ```bash
   cp apps/ebisnis/android/key.properties.example apps/ebisnis/android/key.properties
   ```
   Isi `storeFile`/`storePassword`/`keyAlias`/`keyPassword`.
3. Build seperti biasa (`flutter build apk --release --flavor apotik ...`). APK
   kini ditandatangani produksi. **Alias/keystore harus KONSISTEN antar rilis**
   (Play/instalasi menolak upgrade bila signature berubah).

> Keystore hilang = tidak bisa merilis update yang meng-upgrade instalasi lama.
> Backup keystore + password di tempat aman.

## Windows (installer)

Installer Inno Setup saat ini **belum ditandatangani** -> Windows SmartScreen bisa
memperingatkan saat unduhan pertama. Untuk menandatangani perlu **sertifikat
code-signing** (OV/EV) dari CA, lalu `signtool sign /f cert.pfx /p <pwd> /tr
<timestamp-url> /td sha256 /fd sha256 <setup>.exe`. Sertifikat + password =
milik pemilik; belum diserahkan, jadi langkah ini menunggu.
