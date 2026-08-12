# Build APK release varian "Al-Bahjah POS".
# Sama entrypoint dgn eBisnis biasa (lib/main.dart) -- pembeda HANYA
# --flavor (applicationId/nama APK) + --dart-define (AppVariant.kode).
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter build apk --release --flavor albahjah -t lib/main.dart --dart-define=EBISNIS_VARIANT=albahjah
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-albahjah-release.apk"
