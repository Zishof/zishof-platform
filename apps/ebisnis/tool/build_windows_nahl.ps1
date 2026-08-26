$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
flutter build windows --release -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { throw 'Inno Setup 6 tidak ditemukan.' }
& $iscc "/DAppVersion=$version" installer\nahl.iss
Write-Host "Installer: installer\dist\Al-Bahjah-An-Nahl-POS-Setup-$version.exe"
