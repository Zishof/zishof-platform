$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter build apk --release --flavor nahl -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl --no-tree-shake-icons
Write-Host "APK: build\app\outputs\flutter-apk\app-nahl-release.apk"
