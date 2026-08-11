# Build APK release varian "eBisnis Inventory & Sales".
# KEDUA parameter (-t + --dart-define) wajib konsisten -- lihat lib/main_inventory_sales.dart.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
flutter build apk --release --flavor inventorySales -t lib/main_inventory_sales.dart --dart-define=EBISNIS_VARIANT=inventory_sales
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "APK: build\app\outputs\flutter-apk\app-inventorysales-release.apk"
