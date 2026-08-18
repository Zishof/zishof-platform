# Build APK release varian "MitraInap" (admin hotel/penginapan).
# KEDUA parameter (-t + --dart-define) wajib konsisten -- lihat lib/main_mitrainap.dart.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter build apk --release --flavor mitrainap -t lib/main_mitrainap.dart --dart-define=EBISNIS_VARIANT=mitrainap
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-mitrainap-release.apk"
