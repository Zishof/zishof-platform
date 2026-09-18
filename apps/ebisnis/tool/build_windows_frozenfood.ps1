param([switch]$IzinkanUnsignedWindows)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& (Join-Path $PSScriptRoot 'unduh_model_wajah.ps1')
$version = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value -split '\+')[0]
flutter build windows --release -t lib/main_frozenfood.dart --dart-define=EBISNIS_VARIANT=frozenfood
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (Test-Path $iscc) {
    & $iscc "/DAppVersion=$version" installer\frozenfood.iss
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $setup = "installer\dist\Sarimpi-Jaya-Frozen-Setup-$version.exe"
    if (Test-Path (Join-Path $PSScriptRoot 'verify_windows_signing.ps1')) {
        & (Join-Path $PSScriptRoot 'verify_windows_signing.ps1') -Executable $setup `
            -AllowUnsigned:$IzinkanUnsignedWindows
    }
    Write-Host "Installer: $setup"
} else {
    Write-Host "Build selesai: build\windows\x64\runner\Release\ebisnis_frozenfood.exe (Inno Setup 6 tidak terpasang, installer diskip)"
}
