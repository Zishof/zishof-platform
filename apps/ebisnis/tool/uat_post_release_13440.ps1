param([ValidateSet('albahjah','nahl')][string]$Variant = 'albahjah')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$evidence = Join-Path (Resolve-Path '..\..').Path 'output\uat-1.34.40-20260917'
New-Item -ItemType Directory -Force -Path "$evidence\logs" | Out-Null
$tests = @(
  'test/rincian_produk_metode_test.dart', 'test/rincian_produk_cache_test.dart',
  'test/rincian_produk_halaman_test.dart', 'test/rincian_produk_terpotong_test.dart',
  'test/produk_hpp_cache_test.dart', 'test/produk_hpp_dan_faktur_cetak_test.dart',
  'test/produk_lingkup_toko_test.dart', 'test/uom_produk_contract_test.dart',
  'test/produk_hak_test.dart', 'test/histori_pelunasan_test.dart',
  'test/mutasi_piutang_detail_test.dart', 'test/piutang_kasbon_rincian_test.dart',
  'test/form_simpan_menutup_kontrak_test.dart', 'test/master_offline_kontrak_test.dart',
  'test/master_offline_retry_server_error_test.dart',
  'test/master_offline_paginasi_lokal_test.dart',
  'test/variant_installer_isolation_test.dart', 'test/update_channel_active_test.dart',
  'test/app_variant_login_branding_test.dart'
)
& C:\opt\flutter\bin\flutter.bat test @tests "--dart-define=EBISNIS_VARIANT=$Variant" --reporter expanded --concurrency=1 2>&1 | Tee-Object -FilePath "$evidence\logs\regresi-$Variant.log"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
