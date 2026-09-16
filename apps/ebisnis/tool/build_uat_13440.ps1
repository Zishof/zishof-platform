param([Parameter(Mandatory=$true)][ValidateSet('albahjah','nahl')][string]$Variant)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$buildEvidence = Join-Path (Resolve-Path '..\..').Path 'output\uat-1.34.40-20260917'
foreach($buildVariant in @('albahjah','nahl')) {
  foreach($buildLog in @("regresi-$buildVariant.log", "layar-$buildVariant.log")) {
    if ((Get-Content -Raw -LiteralPath "$buildEvidence\logs\$buildLog") -notmatch 'All tests passed!') { throw "UAT belum lulus: $buildLog" }
  }
}
foreach($buildLog in @('core-db.log','core-update.log')) {
  if ((Get-Content -Raw -LiteralPath "$buildEvidence\logs\$buildLog") -notmatch 'All tests passed!') { throw "UAT belum lulus: $buildLog" }
}
if ((Get-Content -Raw pubspec.yaml) -notmatch 'version: 1.34.40\+203') { throw 'Versi sumber berbeda dari UAT.' }
$flutterUat = 'C:\opt\flutter\bin\flutter.bat'
$aaptUat = 'C:\opt\android-sdk\build-tools\36.0.0\aapt.exe'
$signerUat = 'C:\opt\android-sdk\build-tools\36.0.0\apksigner.bat'
$targetUat = if($Variant -eq 'nahl') { 'lib/main_nahl.dart' } else { 'lib/main.dart' }
$productUat = if($Variant -eq 'nahl') { 'TokoQu Al-Bahjah An Nahl' } else { 'Al-Bahjah POS' }
$installerUat = if($Variant -eq 'nahl') { 'TokoQu-Al-Bahjah-An-Nahl-Setup-1.34.40.exe' } else { 'Al-Bahjah-POS-Setup-1.34.40.exe' }
$destUat = "$buildEvidence\$Variant\release"
New-Item -ItemType Directory -Force -Path $destUat | Out-Null
& "$PSScriptRoot\unduh_model_wajah.ps1"
& $flutterUat build apk --release --flavor $Variant -t $targetUat "--dart-define=EBISNIS_VARIANT=$Variant" --no-tree-shake-icons
if($LASTEXITCODE -ne 0) { throw 'Build APK gagal.' }
$apkUat = "build\app\outputs\flutter-apk\app-$Variant-release.apk"
& "$PSScriptRoot\verify_apk_signing.ps1" -Apk $apkUat -AllowDebug
if($LASTEXITCODE -ne 0) { throw 'Verifikasi APK gagal.' }
$badgingUat = & $aaptUat dump badging $apkUat
if($LASTEXITCODE -ne 0 -or ($badgingUat -join "`n") -notmatch "package: name='id.zishof.ebisnis.$Variant' versionCode='203' versionName='1.34.40'") { throw 'Identitas/versi APK salah.' }
$badgingUat | Select-String 'package:|application-label:|native-code:'
$certificateUat = & $signerUat verify --print-certs $apkUat 2>&1
if($LASTEXITCODE -ne 0) { throw 'Sertifikat APK tidak valid.' }
$certificateUat | Select-String 'certificate DN:|certificate SHA-256'
if(($certificateUat -join "`n") -notmatch 'certificate SHA-256 digest: 455a25a1353cb4bce4777017e50ea55f7e251f402aad50832da4fb438163b9d9') { throw 'Sertifikat berbeda dari APK rilis sebelumnya; jangan publikasikan sebagai upgrade.' }
Copy-Item -LiteralPath $apkUat -Destination "$destUat\app-$Variant-release.apk"
& $flutterUat build windows --release -t $targetUat "--dart-define=EBISNIS_VARIANT=$Variant" --no-tree-shake-icons
if($LASTEXITCODE -ne 0) { throw 'Build Windows gagal.' }
$exeUat = Get-Item "build\windows\x64\runner\Release\ebisnis_$Variant.exe"
if($exeUat.VersionInfo.ProductName -ne $productUat -or $exeUat.VersionInfo.FileVersion -notmatch '^1\.34\.40') { throw 'Identitas/versi EXE salah.' }
$exeUat.VersionInfo | Format-List ProductName,FileVersion,ProductVersion,OriginalFilename
$isccUat = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
& $isccUat '/DAppVersion=1.34.40' "installer\$Variant.iss"
if($LASTEXITCODE -ne 0) { throw 'Pembuatan installer gagal.' }
& "$PSScriptRoot\verify_windows_signing.ps1" -Executable "installer\dist\$installerUat" -AllowUnsigned
if($LASTEXITCODE -ne 0) { throw 'Verifikasi installer gagal.' }
Copy-Item -LiteralPath "installer\dist\$installerUat" -Destination "$destUat\$installerUat"
Get-FileHash -Algorithm SHA256 -LiteralPath "$destUat\app-$Variant-release.apk", "$destUat\$installerUat" | Format-List
Write-Output "BUILD VERIFIED $Variant 1.34.40+203"
