# Build rilis eCanteen: APK Android + installer Windows, lalu SHA256SUMS.
#
# Contoh:
#   .\tool\build_rilis.ps1 -Versi 1.0.1                 # kedua varian
#   .\tool\build_rilis.ps1 -Versi 1.0.1 -Varian petra   # satu varian saja
#
# Artefak ditaruh di release-artifacts\v<versi>\ dan siap diunggah ke rilis
# GitHub. Nomor versi TIDAK diubah otomatis -- naikkan `version:` di
# pubspec.yaml lebih dulu supaya artefak dan sumbernya sinkron.
param(
    [Parameter(Mandatory = $true)][string]$Versi,
    # 'umum'  = eCanteen
    # 'petra' = Direktorat Pengembangan Usaha Sosial
    [ValidateSet('umum', 'petra', 'semua')][string]$Varian = 'semua',
    [switch]$LewatiAndroid,
    [switch]$LewatiWindows
)
$ErrorActionPreference = 'Stop'

$appDir = Split-Path $PSScriptRoot -Parent
Set-Location $appDir

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
$flutter = if ($flutterCmd) { $flutterCmd.Source }
           elseif (Test-Path 'C:\opt\flutter\bin\flutter.bat') { 'C:\opt\flutter\bin\flutter.bat' }
           else { $null }
if (-not $flutter) { throw 'Flutter CLI tidak ditemukan di PATH maupun C:\opt\flutter\bin\flutter.bat.' }

$versiPubspec = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
if ($versiPubspec -ne $Versi) {
    throw "Versi di pubspec.yaml ($versiPubspec) tidak sama dgn -Versi ($Versi). Samakan dulu supaya artefak tidak salah label."
}

$stage = Join-Path $appDir "release-artifacts\v$Versi"
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Write-Host "=== Uji & analisis ==="
& $flutter analyze lib test
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze gagal.' }
& $flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test gagal.' }

$daftarVarian = if ($Varian -eq 'semua') { @('umum', 'petra') } else { @($Varian) }

$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
          'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
          'C:\Program Files\Inno Setup 6\ISCC.exe') |
    Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $LewatiWindows -and -not $iscc) { throw 'ISCC.exe (Inno Setup 6) tidak ditemukan.' }

foreach ($v in $daftarVarian) {
    if ($v -eq 'petra') {
        $apkNama = "eCanteen-Petra-$Versi.apk"
        $iss     = 'installer\ecanteen_petra.iss'
        $setup   = "eCanteen-Petra-Setup-$Versi.exe"
    } else {
        $apkNama = "eCanteen-$Versi.apk"
        $iss     = 'installer\ecanteen.iss'
        $setup   = "eCanteen-Setup-$Versi.exe"
    }

    if (-not $LewatiAndroid) {
        Write-Host "=== [$v] APK Android ==="
        # --flavor dan --dart-define WAJIB seiring: flavor menentukan label
        # peluncur, dart-define menentukan nama di dalam aplikasi.
        & $flutter build apk --release --flavor $v --dart-define=ECANTEEN_VARIANT=$v
        if ($LASTEXITCODE -ne 0) { throw "build apk varian $v gagal." }
        Copy-Item -LiteralPath (Join-Path $appDir "build\app\outputs\flutter-apk\app-$v-release.apk") `
            -Destination (Join-Path $stage $apkNama) -Force
    }

    if (-not $LewatiWindows) {
        Write-Host "=== [$v] Desktop Windows ==="
        & $flutter build windows --release --dart-define=ECANTEEN_VARIANT=$v
        if ($LASTEXITCODE -ne 0) { throw "build windows varian $v gagal." }
        & $iscc "/DAppVersion=$Versi" $iss
        if ($LASTEXITCODE -ne 0) { throw "ISCC varian $v gagal." }
        Copy-Item -LiteralPath (Join-Path $appDir "installer\dist\$setup") `
            -Destination $stage -Force
    }
}

$out = Join-Path $stage "SHA256SUMS-$Versi.txt"
$baris = Get-ChildItem $stage -File |
    Where-Object { $_.Name -ne "SHA256SUMS-$Versi.txt" } |
    Sort-Object Name |
    ForEach-Object { "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()) *$($_.Name)" }
Set-Content -Path $out -Value $baris -Encoding ASCII

Write-Host "=== SELESAI ==="
Get-ChildItem -LiteralPath $stage | Select-Object Name, Length | Format-Table -AutoSize
