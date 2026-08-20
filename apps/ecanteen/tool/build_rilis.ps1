# Build rilis eCanteen: APK Android + installer Windows, lalu SHA256SUMS.
#
# Contoh:
#   .\tool\build_rilis.ps1 -Versi 1.0.0
#
# Artefak ditaruh di release-artifacts\v<versi>\ dan siap diunggah ke rilis
# GitHub. Nomor versi TIDAK diubah otomatis -- naikkan `version:` di
# pubspec.yaml lebih dulu supaya artefak dan sumbernya sinkron.
param(
    [Parameter(Mandatory = $true)][string]$Versi,
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

if (-not $LewatiAndroid) {
    Write-Host "=== APK Android ==="
    & $flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw 'build apk gagal.' }
    Copy-Item -LiteralPath (Join-Path $appDir 'build\app\outputs\flutter-apk\app-release.apk') `
        -Destination (Join-Path $stage "eCanteen-$Versi.apk") -Force
}

if (-not $LewatiWindows) {
    Write-Host "=== Desktop Windows ==="
    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'build windows gagal.' }

    $iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
              'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
              'C:\Program Files\Inno Setup 6\ISCC.exe') |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'ISCC.exe (Inno Setup 6) tidak ditemukan.' }

    & $iscc "/DAppVersion=$Versi" 'installer\ecanteen.iss'
    if ($LASTEXITCODE -ne 0) { throw 'ISCC gagal.' }
    Copy-Item -LiteralPath (Join-Path $appDir "installer\dist\eCanteen-Setup-$Versi.exe") `
        -Destination $stage -Force
}

$out = Join-Path $stage "SHA256SUMS-$Versi.txt"
$baris = Get-ChildItem $stage -File |
    Where-Object { $_.Name -ne "SHA256SUMS-$Versi.txt" } |
    Sort-Object Name |
    ForEach-Object { "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()) *$($_.Name)" }
Set-Content -Path $out -Value $baris -Encoding ASCII

Write-Host "=== SELESAI ==="
Get-ChildItem -LiteralPath $stage | Select-Object Name, Length | Format-Table -AutoSize
