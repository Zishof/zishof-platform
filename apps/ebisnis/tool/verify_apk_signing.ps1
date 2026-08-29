param(
    [Parameter(Mandatory = $true)]
    [string]$Apk,
    [switch]$AllowDebug
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Apk)) {
    throw "APK tidak ditemukan: $Apk"
}

$sdkCandidates = @(
    $env:ANDROID_SDK_ROOT,
    $env:ANDROID_HOME,
    'C:\opt\android-sdk'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

$apksigner = $null
foreach ($sdk in $sdkCandidates) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') `
        -Directory -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Name -replace '[^0-9.]', '') } -Descending |
        ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1
    if ($candidate) {
        $apksigner = $candidate
        break
    }
}

if (-not $apksigner) {
    throw 'apksigner.bat tidak ditemukan. Signing APK tidak dapat diverifikasi.'
}

$output = & $apksigner verify --verbose --print-certs $Apk 2>&1
if ($LASTEXITCODE -ne 0 -or -not ($output -match '^Verifies$')) {
    throw "Verifikasi signature APK gagal: $Apk"
}

$certificateLine = $output | Where-Object {
    $_ -match '^Signer #1 certificate DN:'
} | Select-Object -First 1

if (-not $certificateLine) {
    throw "Identitas sertifikat APK tidak ditemukan: $Apk"
}

$isDebug = $certificateLine -match 'CN=Android Debug'
if ($isDebug -and -not $AllowDebug) {
    throw @"
APK masih ditandatangani sertifikat Android Debug: $Apk
Sediakan android/key.properties atau environment signing produksi. Untuk UAT internal saja,
jalankan build dengan -IzinkanDebugSigning / -AllowDebug secara eksplisit.
"@
}

$mode = if ($isDebug) { 'DEBUG/UAT' } else { 'PRODUKSI' }
Write-Host "Signing APK terverifikasi [$mode]: $certificateLine"

