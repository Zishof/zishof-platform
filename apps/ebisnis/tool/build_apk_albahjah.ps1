# Build APK release varian "Al-Bahjah POS".
# Sama entrypoint dgn eBisnis biasa (lib/main.dart) -- pembeda HANYA
# --flavor (applicationId/nama APK) + --dart-define (AppVariant.kode).
param([switch]$IzinkanDebugSigning)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
& (Join-Path $PSScriptRoot 'unduh_model_wajah.ps1')
flutter build apk --release --flavor albahjah -t lib/main.dart --dart-define=EBISNIS_VARIANT=albahjah
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apk = 'build\app\outputs\flutter-apk\app-albahjah-release.apk'
& (Join-Path $PSScriptRoot 'verify_apk_signing.ps1') -Apk $apk -AllowDebug:$IzinkanDebugSigning
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-albahjah-release.apk"
