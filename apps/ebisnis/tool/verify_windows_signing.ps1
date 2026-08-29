param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [switch]$AllowUnsigned,
    [string]$ExpectedThumbprint = $env:AIS_WINDOWS_SIGNING_THUMBPRINT
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Executable)) {
    throw "Berkas Windows tidak ditemukan: $Executable"
}

$signature = Get-AuthenticodeSignature -LiteralPath $Executable
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    if ($AllowUnsigned -and
        $signature.Status -eq [System.Management.Automation.SignatureStatus]::NotSigned) {
        Write-Host "Signing Windows terverifikasi [UNSIGNED/UAT]: $Executable"
        exit 0
    }
    throw @"
Installer Windows belum memiliki signature Authenticode yang valid: $Executable
Status: $($signature.Status). Tanda tangani installer dengan sertifikat code-signing.
Untuk UAT internal saja, jalankan build dengan -IzinkanUnsignedWindows / -AllowUnsigned.
"@
}

if (-not [string]::IsNullOrWhiteSpace($ExpectedThumbprint)) {
    $actual = ($signature.SignerCertificate.Thumbprint -replace '\s', '').ToUpperInvariant()
    $expected = ($ExpectedThumbprint -replace '\s', '').ToUpperInvariant()
    if ($actual -ne $expected) {
        throw "Thumbprint penanda tangan Windows tidak sesuai allowlist AIS_WINDOWS_SIGNING_THUMBPRINT."
    }
}

$subject = $signature.SignerCertificate.Subject
Write-Host "Signing Windows terverifikasi [PRODUKSI]: $subject"
