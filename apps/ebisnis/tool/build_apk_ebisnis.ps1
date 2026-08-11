# Build APK release varian eBisnis POS (perilaku lama).
# Sejak flavor Android dideklarasikan (varian inventory_sales), --flavor WAJIB --
# script ini menggantikan perintah lama `flutter build apk --release` polos.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter build apk --release --flavor ebisnis -t lib/main.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-ebisnis-release.apk"
