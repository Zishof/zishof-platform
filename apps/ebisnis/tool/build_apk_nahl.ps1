param([switch]$IzinkanDebugSigning)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter build apk --release --flavor nahl -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$apk = 'build\app\outputs\flutter-apk\app-nahl-release.apk'
& (Join-Path $PSScriptRoot 'verify_apk_signing.ps1') -Apk $apk -AllowDebug:$IzinkanDebugSigning
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-nahl-release.apk"
