# Build SELURUH varian (Android APK + installer Windows) pada satu versi yang sama,
# lalu kumpulkan artefaknya di satu folder siap unggah ke GitHub Release.
#
# Kenapa satu skrip: sebelumnya tiap varian punya skrip sendiri (build_apk_*.ps1,
# build_all_non_albahjah.ps1) sehingga rilis "semua varian" mudah timpang -- satu varian
# terbangun dari commit lain daripada varian berikutnya. Di sini seluruh varian dibangun
# berurutan dari pohon kerja yang sama, memakai versi yang dibaca sekali dari pubspec.
#
# Pemakaian:
#   powershell -File tool\build_semua_varian.ps1                 # semua varian, APK + Windows
#   powershell -File tool\build_semua_varian.ps1 -SkipAndroid    # installer Windows saja
#   powershell -File tool\build_semua_varian.ps1 -SkipWindows    # APK saja
#   powershell -File tool\build_semua_varian.ps1 -Hanya ebisnis,petra
param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [string[]]$Hanya
)
$ErrorActionPreference = 'Stop'
$appDir = Split-Path $PSScriptRoot -Parent
Set-Location $appDir

$versi = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$artifactDir = Join-Path $appDir "release-artifacts\semua-varian\$versi"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) { $flutterCommand.Source }
           elseif (Test-Path 'C:\opt\flutter\bin\flutter.bat') { 'C:\opt\flutter\bin\flutter.bat' }
           else { $null }
if (-not $flutter) { throw 'Flutter CLI tidak ditemukan di PATH maupun C:\opt\flutter\bin\flutter.bat.' }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
          'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
          'C:\Program Files\Inno Setup 6\ISCC.exe') |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $SkipWindows -and -not $iscc) { throw 'ISCC.exe (Inno Setup 6) tidak ditemukan.' }

# Target (-t) dan --dart-define WAJIB konsisten; lihat catatan di tiap lib/main_*.dart.
# Iss kosong = varian itu memang tidak punya installer Windows (mis. MitraInap).
$variants = @(
    @{ Kode='ebisnis';         Flavor='ebisnis';        Target='lib/main.dart';                    Define='';                Iss='installer/ebisnis.iss';         Apk='app-ebisnis-release.apk';        Setup="eBisnis-Setup-$versi.exe" },
    @{ Kode='albahjah';        Flavor='albahjah';       Target='lib/main.dart';                    Define='albahjah';        Iss='installer/albahjah.iss';        Apk='app-albahjah-release.apk';       Setup="Al-Bahjah-POS-Setup-$versi.exe" },
    @{ Kode='inventory-sales'; Flavor='inventorySales'; Target='lib/main_inventory_sales.dart';    Define='inventory_sales'; Iss='installer/inventory_sales.iss'; Apk='app-inventorysales-release.apk'; Setup="eBisnis-Inventory-Sales-Setup-$versi.exe" },
    @{ Kode='apotik';          Flavor='apotik';         Target='lib/main_apotik.dart';             Define='apotik';          Iss='installer/apotik.iss';          Apk='app-apotik-release.apk';         Setup="eBisnis-POS-Apotik-Setup-$versi.exe" },
    @{ Kode='emedik';          Flavor='emedik';         Target='lib/main_emedik.dart';             Define='emedik';          Iss='installer/emedik.iss';          Apk='app-emedik-release.apk';         Setup="eBisnis-POS-eMedik-Setup-$versi.exe" },
    @{ Kode='petra';           Flavor='petra';          Target='lib/main_petra.dart';              Define='petra';           Iss='installer/petra.iss';           Apk='app-petra-release.apk';          Setup="eKantin-Petra-Setup-$versi.exe" },
    @{ Kode='mitrainap';       Flavor='mitrainap';      Target='lib/main_mitrainap.dart';          Define='mitrainap';       Iss='';                              Apk='app-mitrainap-release.apk';      Setup='' }
)
if ($Hanya) { $variants = $variants | Where-Object { $Hanya -contains $_.Kode } }

$mulai = Get-Date
$gagal = @()
foreach ($variant in $variants) {
    $defineArgs = @()
    if ($variant.Define) { $defineArgs = @("--dart-define=EBISNIS_VARIANT=$($variant.Define)") }

    if (-not $SkipAndroid) {
        Write-Host "==== APK $($variant.Kode) ===="
        & $flutter build apk --release --flavor $variant.Flavor -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { $gagal += "APK $($variant.Kode)"; continue }
        Copy-Item -LiteralPath (Join-Path $appDir "build\app\outputs\flutter-apk\$($variant.Apk)") `
            -Destination (Join-Path $artifactDir $variant.Apk) -Force
    }

    if (-not $SkipWindows -and $variant.Iss) {
        Write-Host "==== Windows $($variant.Kode) ===="
        & $flutter build windows --release -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { $gagal += "Windows $($variant.Kode)"; continue }
        & $iscc "/DAppVersion=$versi" $variant.Iss
        if ($LASTEXITCODE -ne 0) { $gagal += "Installer $($variant.Kode)"; continue }
        Copy-Item -LiteralPath (Join-Path $appDir "installer\dist\$($variant.Setup)") `
            -Destination (Join-Path $artifactDir $variant.Setup) -Force
    }
}

# Sidik jari tiap artefak; dipakai penerima untuk memastikan berkas tidak berubah di jalan.
Get-ChildItem -LiteralPath $artifactDir -File | Where-Object { $_.Name -notlike '*.sha256.txt' } | ForEach-Object {
    $h = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower()
    "$h  $($_.Name)" | Set-Content -LiteralPath "$($_.FullName).sha256.txt" -Encoding ascii
}

Write-Host ""
Write-Host "==== RINGKASAN ===="
Write-Host "versi   : $versi"
Write-Host "folder  : $artifactDir"
Write-Host "durasi  : $([math]::Round(((Get-Date) - $mulai).TotalMinutes,1)) menit"
Get-ChildItem -LiteralPath $artifactDir -File | Where-Object { $_.Name -notlike '*.sha256.txt' } |
    ForEach-Object { "  {0,-46} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB) }
if ($gagal.Count -gt 0) {
    Write-Host ""
    Write-Host "GAGAL: $($gagal -join ', ')"
    exit 1
}
Write-Host "SEMUA VARIAN BERHASIL"
