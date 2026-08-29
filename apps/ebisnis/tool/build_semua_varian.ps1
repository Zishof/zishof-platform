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
#   powershell -File tool\build_semua_varian.ps1 -IzinkanDebugSigning # UAT internal saja
#   powershell -File tool\build_semua_varian.ps1 -IzinkanUnsignedWindows # UAT internal saja
#
# Tanpa -IzinkanDebugSigning, setiap APK wajib memakai sertifikat produksi.
# Tanpa -IzinkanUnsignedWindows, setiap installer wajib memiliki Authenticode valid.
# Build dihentikan sebelum artefak disalin bila signature tidak memenuhi syarat.
param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$IzinkanDebugSigning,
    [switch]$IzinkanUnsignedWindows,
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
    @{ Kode='nahl';             Flavor='nahl';            Target='lib/main_nahl.dart';               Define='nahl';             Iss='installer/nahl.iss';             Apk='app-nahl-release.apk';            Setup="TokoQu-Al-Bahjah-An-Nahl-Setup-$versi.exe" },
    @{ Kode='inventory-sales'; Flavor='inventorySales'; Target='lib/main_inventory_sales.dart';    Define='inventory_sales'; Iss='installer/inventory_sales.iss'; Apk='app-inventorysales-release.apk'; Setup="eBisnis-Inventory-Sales-Setup-$versi.exe" },
    @{ Kode='apotik';          Flavor='apotik';         Target='lib/main_apotik.dart';             Define='apotik';          Iss='installer/apotik.iss';          Apk='app-apotik-release.apk';         Setup="eBisnis-POS-Apotik-Setup-$versi.exe" },
    @{ Kode='emedik';          Flavor='emedik';         Target='lib/main_emedik.dart';             Define='emedik';          Iss='installer/emedik.iss';          Apk='app-emedik-release.apk';         Setup="eBisnis-POS-eMedik-Setup-$versi.exe" },
    @{ Kode='petra';           Flavor='petra';          Target='lib/main_petra.dart';              Define='petra';           Iss='installer/petra.iss';           Apk='app-petra-release.apk';          Setup="eKantin-Petra-Setup-$versi.exe" },
    @{ Kode='mitrainap';       Flavor='mitrainap';      Target='lib/main_mitrainap.dart';          Define='mitrainap';       Iss='';                              Apk='app-mitrainap-release.apk';      Setup='' }
)
if ($Hanya) {
    # "powershell -File skrip.ps1 -Hanya ebisnis,albahjah" TIDAK menghasilkan array:
    # dengan -File, PowerShell menyerahkan argumennya sebagai satu string mentah,
    # sehingga $Hanya berisi satu elemen "ebisnis,albahjah" dan tidak cocok dgn kode
    # varian mana pun. Dipecah di sini supaya kedua cara pemanggilan sama-sama sah.
    $Hanya = $Hanya | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } |
             Where-Object { $_ }
    $dikenal = $variants | ForEach-Object { $_.Kode }
    $asing = $Hanya | Where-Object { $dikenal -notcontains $_ }
    if ($asing) { throw "Kode varian tidak dikenal: $($asing -join ', '). Yang ada: $($dikenal -join ', ')." }
    $variants = $variants | Where-Object { $Hanya -contains $_.Kode }
}
# Daftar kosong berarti TIDAK ADA yang dibangun. Tanpa penjagaan ini skrip berjalan
# mulus, tidak menghasilkan apa-apa, lalu mencetak "SEMUA VARIAN BERHASIL" -- dan rilis
# kosong itu baru ketahuan setelah diunggah. Sudah pernah terjadi.
if (-not $variants -or @($variants).Count -eq 0) { throw 'Tidak ada varian yang terpilih untuk dibangun.' }
if ($SkipAndroid -and $SkipWindows) { throw 'SkipAndroid dan SkipWindows sekaligus: tidak ada yang dibangun.' }

$mulai = Get-Date
$gagal = @()
foreach ($variant in $variants) {
    $defineArgs = @()
    if ($variant.Define) { $defineArgs = @("--dart-define=EBISNIS_VARIANT=$($variant.Define)") }

    if (-not $SkipAndroid) {
        Write-Host "==== APK $($variant.Kode) ===="
        & $flutter build apk --release --flavor $variant.Flavor -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { $gagal += "APK $($variant.Kode)"; continue }
        $apkHasil = Join-Path $appDir "build\app\outputs\flutter-apk\$($variant.Apk)"
        & (Join-Path $PSScriptRoot 'verify_apk_signing.ps1') -Apk $apkHasil `
            -AllowDebug:$IzinkanDebugSigning
        if ($LASTEXITCODE -ne 0) { $gagal += "Signing APK $($variant.Kode)"; continue }
        Copy-Item -LiteralPath $apkHasil `
            -Destination (Join-Path $artifactDir $variant.Apk) -Force
    }

    if (-not $SkipWindows -and $variant.Iss) {
        Write-Host "==== Windows $($variant.Kode) ===="
        & $flutter build windows --release -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { $gagal += "Windows $($variant.Kode)"; continue }
        & $iscc "/DAppVersion=$versi" $variant.Iss
        if ($LASTEXITCODE -ne 0) { $gagal += "Installer $($variant.Kode)"; continue }
        $setupHasil = Join-Path $appDir "installer\dist\$($variant.Setup)"
        & (Join-Path $PSScriptRoot 'verify_windows_signing.ps1') -Executable $setupHasil `
            -AllowUnsigned:$IzinkanUnsignedWindows
        if ($LASTEXITCODE -ne 0) { $gagal += "Signing Windows $($variant.Kode)"; continue }
        Copy-Item -LiteralPath $setupHasil `
            -Destination (Join-Path $artifactDir $variant.Setup) -Force
    }
}

# Sidik jari tiap artefak; dipakai penerima untuk memastikan berkas tidak berubah di jalan.
# Get-FileHash tidak ada di Windows PowerShell 2.0 (dan pada sebagian sesi non-interaktif
# skrip ini pernah berhenti persis di sini setelah SEMUA varian selesai dibangun), jadi
# sediakan jalur cadangan lewat certutil yang selalu ada di Windows.
function Sidik-Jari([string]$berkas) {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        return (Get-FileHash -LiteralPath $berkas -Algorithm SHA256).Hash.ToLower()
    }
    $keluaran = & certutil -hashfile $berkas SHA256
    if ($LASTEXITCODE -ne 0) { throw "certutil gagal menghitung SHA256 untuk $berkas" }
    return (($keluaran | Where-Object { $_ -match '^[0-9a-fA-F ]{40,}$' } | Select-Object -First 1) -replace '\s', '').ToLower()
}

Get-ChildItem -LiteralPath $artifactDir -File | Where-Object { $_.Name -notlike '*.sha256.txt' } | ForEach-Object {
    "$(Sidik-Jari $_.FullName)  $($_.Name)" | Set-Content -LiteralPath "$($_.FullName).sha256.txt" -Encoding ascii
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
$jumlahArtefak = @(Get-ChildItem -LiteralPath $artifactDir -File | Where-Object { $_.Name -notlike '*.sha256.txt' }).Count
if ($jumlahArtefak -eq 0) { throw 'Selesai tanpa satu pun artefak -- jangan perlakukan ini sbg berhasil.' }
Write-Host "SEMUA VARIAN BERHASIL ($jumlahArtefak artefak)"
