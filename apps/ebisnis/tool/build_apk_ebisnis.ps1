# Build APK release varian eBisnis POS (perilaku lama).
# Sejak flavor Android dideklarasikan (varian inventory_sales), --flavor WAJIB --
# script ini menggantikan perintah lama `flutter build apk --release` polos.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
# Model wajah ikut APK sbg asset bundle (pubspec assets/face/); pastikan
# berkasnya ada + hash cocok SEBELUM build supaya APK tidak diam-diam
# terbit tanpa fitur wajah.
& (Join-Path $PSScriptRoot 'unduh_model_wajah.ps1')
flutter build apk --release --flavor ebisnis -t lib/main.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-ebisnis-release.apk"
