param([switch]$IzinkanUnsignedWindows)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
flutter build windows --release -t lib/main_nahl.dart --dart-define=EBISNIS_VARIANT=nahl
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { throw 'Inno Setup 6 tidak ditemukan.' }
& $iscc "/DAppVersion=$version" installer\nahl.iss
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$setup = "installer\dist\FF-Fajrul-Falah-Mart-Setup-$version.exe"
& (Join-Path $PSScriptRoot 'verify_windows_signing.ps1') -Executable $setup `
    -AllowUnsigned:$IzinkanUnsignedWindows
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Installer: $setup"
