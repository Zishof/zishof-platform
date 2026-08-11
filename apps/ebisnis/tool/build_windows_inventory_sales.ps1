# Build Windows release varian "eBisnis Inventory & Sales" + (opsional) installer Inno Setup.
# KEDUA parameter (-t + --dart-define) wajib konsisten -- lihat lib/main_inventory_sales.dart.
# Hasil: build\windows\x64\runner\Release\ berisi ebisnis.exe + ebisnis_inventory_sales.exe;
# installer memakai installer\inventory_sales.iss (exclude ebisnis.exe).
param([switch]$Installer)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter build windows --release -t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "EXE: build\windows\x64\runner\Release\ebisnis_inventory_sales.exe"
if ($Installer) {
    $versi = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
    $iscc = @('C:\Program Files (x86)\Inno Setup 6\ISCC.exe', 'C:\Program Files\Inno Setup 6\ISCC.exe') |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'ISCC.exe (Inno Setup 6) tidak ditemukan.' }
    & $iscc "/DAppVersion=$versi" installer\inventory_sales.iss
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "Installer: installer\dist\eBisnis-Inventory-Sales-Setup-$versi.exe"
}
