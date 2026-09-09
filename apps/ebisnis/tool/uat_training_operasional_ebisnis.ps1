param(
    [string]$Endpoint = 'https://ebisnis.id/ebisnis/Api_eBisnis',
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$OutputDir = '',
    [string]$TanggalMulai = '2026-09-01',
    [string]$TanggalSampai = '2026-09-10'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) '..\..\docs\pos\uat-training-operasional-20260910\evidence'
}
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

function Invoke-Api([hashtable]$Payload, [string]$Token = '') {
    $headers = @{ 'Content-Type' = 'application/json' }
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers.Authorization = "Bearer $Token" }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $Endpoint -Method Post -Headers $headers `
        -Body ($Payload | ConvertTo-Json -Depth 15 -Compress) -TimeoutSec 120
    $watch.Stop()
    [pscustomobject]@{ Response = $response; DurationMs = $watch.ElapsedMilliseconds }
}

$login = Invoke-Api @{
    action = 'login'; username = $Username; password = $Password
    labelPerangkat = 'Audit Training Operasional eBisnis'
}
$token = "$($login.Response.token)"
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Login tidak menghasilkan token.' }
(Invoke-Api @{ action = 'pilih_toko_aktif'; id_toko = 1 } $token) | Out-Null

$prefix = 'UAT-VOL-PROC-20260904'
$procurement = [ordered]@{}
foreach ($action in @(
    'pengadaan_pr_daftar', 'pengadaan_po_daftar', 'pengadaan_bast_daftar',
    'pengadaan_tagihan_daftar', 'pengadaan_bayar_daftar'
)) {
    $call = Invoke-Api @{ action = $action; cari = $prefix; page = 1; pageSize = 100 } $token
    $count = [int]($call.Response.total ?? @($call.Response.data).Count)
    $procurement[$action] = [ordered]@{
        count = $count; minimum = 100; durationMs = $call.DurationMs; passed = $count -ge 100
    }
}

$reportIds = @(
    'pnj_faktur', 'pnj_per_barang', 'pnj_rincian_barang',
    'omzet_transaksi', 'omzet_tunai_produk', 'omzet_saldo_produk', 'omzet_rekapan',
    'beli_penerimaan', 'beli_faktur',
    'margin_produk', 'margin_kategori', 'laba_kotor_harian'
)
$reportResponses = [ordered]@{}
$reports = @()
foreach ($id in $reportIds) {
    $call = Invoke-Api @{
        action = 'laporan_jalankan'; r = $id
        tglMulai = $TanggalMulai; tglSampai = $TanggalSampai
    } $token
    $response = $call.Response
    $reportResponses[$id] = $response
    $pdfCall = Invoke-Api @{
        action = 'laporan_pdf'; r = $id
        tglMulai = $TanggalMulai; tglSampai = $TanggalSampai
    } $token
    $pdfBytes = [Convert]::FromBase64String("$($pdfCall.Response.pdfBase64)")
    $signature = if ($pdfBytes.Length -ge 4) { [Text.Encoding]::ASCII.GetString($pdfBytes[0..3]) } else { '' }
    $reports += [ordered]@{
        id = $id
        status = "$($response.status)"
        rows = @($response.baris).Count
        columns = @($response.kolom).Count
        durationMs = $call.DurationMs
        pdfBytes = $pdfBytes.Length
        pdfSignature = $signature
        pdfDurationMs = $pdfCall.DurationMs
        passed = ("$($response.status)" -eq 'success' -and @($response.baris).Count -gt 0 -and
            @($response.kolom).Count -gt 0 -and "$($pdfCall.Response.status)" -eq 'success' -and
            $signature -eq '%PDF' -and $pdfBytes.Length -gt 1000)
    }
}

function Get-ColumnIndex($Report, [string]$Label) {
    for ($i = 0; $i -lt @($Report.kolom).Count; $i++) {
        if ([string]::Equals("$($Report.kolom[$i].l)", $Label, [StringComparison]::OrdinalIgnoreCase)) { return $i }
    }
    throw "Kolom '$Label' tidak ditemukan."
}

function Invoke-Detail([string]$Name, [hashtable]$Dimensions, [decimal]$Expected) {
    $payload = @{ action = 'laporan_rincian_transaksi'; tglMulai = $TanggalMulai; tglSampai = $TanggalSampai; batas = 10000 }
    foreach ($key in $Dimensions.Keys) { $payload[$key] = $Dimensions[$key] }
    $call = Invoke-Api $payload $token
    $actual = [decimal]($call.Response.totalNilai ?? 0)
    [ordered]@{
        name = $Name; rows = @($call.Response.data).Count
        expectedTotal = $Expected; actualTotal = $actual; difference = $actual - $Expected
        durationMs = $call.DurationMs
        passed = ("$($call.Response.status)" -eq 'success' -and @($call.Response.data).Count -gt 0 -and
            [Math]::Abs([double]($actual - $Expected)) -lt 0.01)
    }
}

$details = @()
$omzet = $reportResponses.omzet_transaksi
$tunai = $reportResponses.omzet_tunai_produk
$saldo = $reportResponses.omzet_saldo_produk
$rekap = $reportResponses.omzet_rekapan
$omzetRow = @($omzet.baris)[0]
$idxProdukTunai = Get-ColumnIndex $tunai 'Produk'
$tunaiRow = @($tunai.baris) |
    Sort-Object { "$($_[$idxProdukTunai])".Length } -Descending |
    Select-Object -First 1
$saldoRow = @($saldo.baris)[0]
$rekapRow = @($rekap.baris)[0]
$idxNo = Get-ColumnIndex $omzet 'No. Transaksi'
$idxNominal = Get-ColumnIndex $omzet 'Nominal'
$idxOmzetTunai = Get-ColumnIndex $tunai 'Omzet'
$idxProdukSaldo = Get-ColumnIndex $saldo 'Produk'
$idxOmzetSaldo = Get-ColumnIndex $saldo 'Omzet'
$idxToko = Get-ColumnIndex $rekap 'Toko'
$idxRekapTunai = Get-ColumnIndex $rekap 'Tunai / Non-Saldo'
$details += Invoke-Detail 'Transaksi Omzet' @{ idTransaksi = "$($omzetRow[$idxNo])" } ([decimal]$omzetRow[$idxNominal])
$details += Invoke-Detail 'Produk Non-Saldo/Tunai' @{ namaProduk = "$($tunaiRow[$idxProdukTunai])"; kelompokPembayaran = 'NON_SALDO' } ([decimal]$tunaiRow[$idxOmzetTunai])
$details += Invoke-Detail 'Produk Saldo' @{ namaProduk = "$($saldoRow[$idxProdukSaldo])"; kelompokPembayaran = 'SALDO' } ([decimal]$saldoRow[$idxOmzetSaldo])
$details += Invoke-Detail 'Rekap Omzet - Tunai / Non-Saldo' @{
    toko = "$($rekapRow[$idxToko])"; kelompokPembayaran = 'NON_SALDO'
} ([decimal]$rekapRow[$idxRekapTunai])

$result = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    environment = 'eBisnis live - Kantin Demo'
    endpoint = $Endpoint
    period = [ordered]@{ start = $TanggalMulai; end = $TanggalSampai }
    scope = 'POS, PR, PO, BAST, tagihan, pembayaran vendor, penjualan, pembelian, omzet, margin'
    accountingExcluded = $true
    procurement = $procurement
    reports = $reports
    clickableDetails = $details
}
$result.allPassed = (@($procurement.Values | Where-Object { -not $_.passed }).Count -eq 0 -and
    @($reports | Where-Object { -not $_.passed }).Count -eq 0 -and
    @($details | Where-Object { -not $_.passed }).Count -eq 0)

$outputPath = Join-Path $OutputDir 'uat-training-operasional-evidence.json'
[IO.File]::WriteAllText($outputPath, ($result | ConvertTo-Json -Depth 15), [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    allPassed = $result.allPassed
    procurementPassed = @($procurement.Values | Where-Object passed).Count
    procurementTotal = $procurement.Count
    reportsPassed = @($reports | Where-Object passed).Count
    reportsTotal = $reports.Count
    detailsPassed = @($details | Where-Object passed).Count
    detailsTotal = $details.Count
    evidence = $outputPath
} | ConvertTo-Json -Compress
