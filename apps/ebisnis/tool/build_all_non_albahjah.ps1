param(
    [switch]$SkipAndroid,
    [switch]$SkipWindows,
    [switch]$IzinkanDebugSigning,
    [switch]$IzinkanUnsignedWindows
)
$ErrorActionPreference = 'Stop'
$appDir = Split-Path $PSScriptRoot -Parent
Set-Location $appDir
& (Join-Path $PSScriptRoot 'unduh_model_wajah.ps1')
$versi = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
$artifactDir = Join-Path $appDir "release-artifacts\non-albahjah\$versi"
New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCommand) { $flutterCommand.Source } elseif (Test-Path 'C:\opt\flutter\bin\flutter.bat') { 'C:\opt\flutter\bin\flutter.bat' } else { $null }
if (-not $flutter) { throw 'Flutter CLI tidak ditemukan di PATH maupun C:\opt\flutter\bin\flutter.bat.' }

$variants = @(
    @{ Kode='ebisnis'; Flavor='ebisnis'; Target='lib/main.dart'; Define=''; Iss='installer/ebisnis.iss'; Apk='app-ebisnis-release.apk'; Setup="eBisnis-Setup-$versi.exe" },
    @{ Kode='inventory-sales'; Flavor='inventorySales'; Target='lib/main_inventory_sales.dart'; Define='inventory_sales'; Iss='installer/inventory_sales.iss'; Apk='app-inventorysales-release.apk'; Setup="eBisnis-Inventory-Sales-Setup-$versi.exe" },
    @{ Kode='apotik'; Flavor='apotik'; Target='lib/main_apotik.dart'; Define='apotik'; Iss='installer/apotik.iss'; Apk='app-apotik-release.apk'; Setup="eBisnis-POS-Apotik-Setup-$versi.exe" },
    @{ Kode='emedik'; Flavor='emedik'; Target='lib/main_emedik.dart'; Define='emedik'; Iss='installer/emedik.iss'; Apk='app-emedik-release.apk'; Setup="eBisnis-POS-eMedik-Setup-$versi.exe" }
)

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
          'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
          'C:\Program Files\Inno Setup 6\ISCC.exe') |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $SkipWindows -and -not $iscc) { throw 'ISCC.exe (Inno Setup 6) tidak ditemukan.' }

foreach ($variant in $variants) {
    $defineArgs = @()
    if ($variant.Define) { $defineArgs = @("--dart-define=EBISNIS_VARIANT=$($variant.Define)") }
    if (-not $SkipAndroid) {
        & $flutter build apk --release --flavor $variant.Flavor -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $apkHasil = Join-Path $appDir "build\app\outputs\flutter-apk\$($variant.Apk)"
        & (Join-Path $PSScriptRoot 'verify_apk_signing.ps1') -Apk $apkHasil `
            -AllowDebug:$IzinkanDebugSigning
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Copy-Item -LiteralPath $apkHasil `
            -Destination (Join-Path $artifactDir $variant.Apk) -Force
    }
    if (-not $SkipWindows) {
        & $flutter build windows --release -t $variant.Target @defineArgs
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & $iscc "/DAppVersion=$versi" $variant.Iss
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $setupHasil = Join-Path $appDir "installer\dist\$($variant.Setup)"
        & (Join-Path $PSScriptRoot 'verify_windows_signing.ps1') -Executable $setupHasil `
            -AllowUnsigned:$IzinkanUnsignedWindows
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Copy-Item -LiteralPath $setupHasil `
            -Destination (Join-Path $artifactDir $variant.Setup) -Force
    }
}
Get-ChildItem -LiteralPath $artifactDir | Select-Object Name, Length
