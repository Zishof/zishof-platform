param(
    [string]$Endpoint = 'https://ebisnis.id/ebisnis/Api_eBisnis',
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$OutputDir = '',
    [string]$TanggalMulai = '2026-09-01',
    [string]$TanggalSampai = '2026-09-10',
    [int]$TokoId = 1
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path (Split-Path $PSScriptRoot -Parent) '..\..\docs\pos\uat-e2e-ebisnis-v1.34.35-20260910\evidence'
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

function Get-ColumnIndex($Report, [string]$Label) {
    for ($i = 0; $i -lt @($Report.kolom).Count; $i++) {
        if ([string]::Equals("$($Report.kolom[$i].l)", $Label, [StringComparison]::OrdinalIgnoreCase)) {
            return $i
        }
    }
    throw "Kolom '$Label' tidak ditemukan."
}

$login = Invoke-Api @{
    action = 'login'; username = $Username; password = $Password
    labelPerangkat = 'Audit Laporan Omzet eBisnis'
}
$token = "$($login.Response.token)"
if ([string]::IsNullOrWhiteSpace($token)) { throw 'Login tidak menghasilkan token.' }
(Invoke-Api @{ action = 'pilih_toko_aktif'; id_toko = $TokoId } $token) | Out-Null

function Invoke-Detail(
    [string]$Name,
    [hashtable]$Dimensions,
    [decimal]$ExpectedTotal,
    [string]$DetailMulai = $TanggalMulai,
    [string]$DetailSampai = $TanggalSampai
) {
    $payload = @{
        action = 'laporan_rincian_transaksi'
        tglMulai = $DetailMulai
        tglSampai = $DetailSampai
        batas = 10000
    }
    foreach ($key in $Dimensions.Keys) { $payload[$key] = $Dimensions[$key] }
    $call = Invoke-Api $payload $token
    $response = $call.Response
    $actual = [decimal]($response.totalNilai ?? 0)
    $rows = @($response.data).Count
    [ordered]@{
        name = $Name
        status = "$($response.status)"
        rows = $rows
        expectedTotal = $ExpectedTotal
        actualTotal = $actual
        difference = $actual - $ExpectedTotal
        period = [ordered]@{ start = $DetailMulai; end = $DetailSampai }
        durationMs = $call.DurationMs
        passed = ("$($response.status)" -eq 'success' -and $rows -gt 0 -and
            [Math]::Abs([double]($actual - $ExpectedTotal)) -lt 0.01)
    }
}

$reportIds = @('omzet_transaksi', 'omzet_tunai_produk', 'omzet_saldo_produk', 'omzet_rekapan')
$reportData = [ordered]@{}
$reportChecks = @()

$catalogCall = Invoke-Api @{ action = 'laporan_katalog' } $token
$category = @($catalogCall.Response.kategori) |
    Where-Object { "$($_.kat)".Trim() -eq 'Omzet' } |
    Select-Object -First 1
$catalogIds = if ($null -ne $category) { @($category.items | ForEach-Object { "$($_.id)" }) } else { @() }
$catalogPassed = $null -ne $category -and @($reportIds | Where-Object { $_ -notin $catalogIds }).Count -eq 0

foreach ($id in $reportIds) {
    $call = Invoke-Api @{
        action = 'laporan_jalankan'; r = $id
        tglMulai = $TanggalMulai; tglSampai = $TanggalSampai
    } $token
    $response = $call.Response
    $reportData[$id] = $response

    $pdfCall = Invoke-Api @{
        action = 'laporan_pdf'; r = $id
        tglMulai = $TanggalMulai; tglSampai = $TanggalSampai
    } $token
    $pdfBytes = [Convert]::FromBase64String("$($pdfCall.Response.pdfBase64)")
    $pdfPath = Join-Path $OutputDir "$id.pdf"
    [IO.File]::WriteAllBytes($pdfPath, $pdfBytes)
    $signature = if ($pdfBytes.Length -ge 4) {
        [Text.Encoding]::ASCII.GetString($pdfBytes[0..3])
    } else { '' }

    $reportChecks += [ordered]@{
        id = $id
        status = "$($response.status)"
        columns = @($response.kolom).Count
        rows = @($response.baris).Count
        durationMs = $call.DurationMs
        passed = ("$($response.status)" -eq 'success' -and
            @($response.kolom).Count -gt 0 -and @($response.baris).Count -gt 0)
        pdf = [ordered]@{
            status = "$($pdfCall.Response.status)"
            bytes = $pdfBytes.Length
            signature = $signature
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pdfPath).Hash
            durationMs = $pdfCall.DurationMs
            passed = ("$($pdfCall.Response.status)" -eq 'success' -and
                $signature -eq '%PDF' -and $pdfBytes.Length -gt 1000)
        }
    }
}

$transactions = $reportData.omzet_transaksi
$cash = $reportData.omzet_tunai_produk
$balance = $reportData.omzet_saldo_produk
$recap = $reportData.omzet_rekapan

$transactionRow = @($transactions.baris)[0]
$transactionIdIndex = Get-ColumnIndex $transactions 'No. Transaksi'
$transactionValueIndex = Get-ColumnIndex $transactions 'Nominal'

$cashProductIndex = Get-ColumnIndex $cash 'Produk'
$cashValueIndex = Get-ColumnIndex $cash 'Omzet'
$cashRow = @($cash.baris) |
    Sort-Object { "$($_[$cashProductIndex])".Length } -Descending |
    Select-Object -First 1

$balanceProductIndex = Get-ColumnIndex $balance 'Produk'
$balanceValueIndex = Get-ColumnIndex $balance 'Omzet'
$balanceRow = @($balance.baris)[0]

$recapStoreIndex = Get-ColumnIndex $recap 'Toko'
$recapCashIndex = Get-ColumnIndex $recap 'Tunai / Non-Saldo'
$recapBalanceIndex = Get-ColumnIndex $recap 'Saldo'
$recapTotalIndex = Get-ColumnIndex $recap 'Total Omzet'
$recapRow = @($recap.baris)[0]

# Jalur klik Total Omzet diuji pada satu hari representatif agar seluruh nota
# penyusun dapat dikembalikan dalam satu respons. Rekonsiliasi lintas periode
# tetap dihitung terpisah di bawah terhadap seluruh 504 transaksi.
$recapDetailCall = Invoke-Api @{
    action = 'laporan_jalankan'; r = 'omzet_rekapan'
    tglMulai = $TanggalSampai; tglSampai = $TanggalSampai
} $token
$recapDetail = $recapDetailCall.Response
$recapDetailStoreIndex = Get-ColumnIndex $recapDetail 'Toko'
$recapDetailTotalIndex = Get-ColumnIndex $recapDetail 'Total Omzet'
$recapDetailRow = @($recapDetail.baris)[0]

$detailChecks = @(
    (Invoke-Detail 'Transaksi Omzet' `
        @{ idTransaksi = "$($transactionRow[$transactionIdIndex])" } `
        ([decimal]$transactionRow[$transactionValueIndex])),
    (Invoke-Detail 'Produk Non-Saldo/Tunai' `
        @{ namaProduk = "$($cashRow[$cashProductIndex])"; kelompokPembayaran = 'NON_SALDO' } `
        ([decimal]$cashRow[$cashValueIndex])),
    (Invoke-Detail 'Produk Saldo' `
        @{ namaProduk = "$($balanceRow[$balanceProductIndex])"; kelompokPembayaran = 'SALDO' } `
        ([decimal]$balanceRow[$balanceValueIndex])),
    (Invoke-Detail 'Rekap Omzet - Tunai / Non-Saldo' `
        @{ toko = "$($recapRow[$recapStoreIndex])"; kelompokPembayaran = 'NON_SALDO' } `
        ([decimal]$recapRow[$recapCashIndex])),
    (Invoke-Detail 'Rekap Omzet - Saldo' `
        @{ toko = "$($recapRow[$recapStoreIndex])"; kelompokPembayaran = 'SALDO' } `
        ([decimal]$recapRow[$recapBalanceIndex])),
    (Invoke-Detail 'Rekap Omzet - Total (sampel satu hari)' `
        @{ toko = "$($recapDetailRow[$recapDetailStoreIndex])" } `
        ([decimal]$recapDetailRow[$recapDetailTotalIndex]) `
        $TanggalSampai $TanggalSampai)
)

$transactionTotal = [decimal](($transactions.baris | ForEach-Object {
    [decimal]$_[$transactionValueIndex]
} | Measure-Object -Sum).Sum)
$cashTotal = [decimal](($cash.baris | ForEach-Object {
    [decimal]$_[$cashValueIndex]
} | Measure-Object -Sum).Sum)
$balanceTotal = [decimal](($balance.baris | ForEach-Object {
    [decimal]$_[$balanceValueIndex]
} | Measure-Object -Sum).Sum)
$recapTotal = [decimal](($recap.baris | ForEach-Object {
    [decimal]$_[$recapTotalIndex]
} | Measure-Object -Sum).Sum)

$result = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    environment = 'eBisnis live - Kantin Demo'
    endpoint = $Endpoint
    period = [ordered]@{ start = $TanggalMulai; end = $TanggalSampai }
    catalog = [ordered]@{
        status = "$($catalogCall.Response.status)"
        durationMs = $catalogCall.DurationMs
        ids = $catalogIds
        passed = $catalogPassed
    }
    reports = $reportChecks
    details = $detailChecks
    reconciliation = [ordered]@{
        transactionTotal = $transactionTotal
        nonSaldoTotal = $cashTotal
        saldoTotal = $balanceTotal
        productTotal = $cashTotal + $balanceTotal
        recapTotal = $recapTotal
        differenceProductToTransaction = ($cashTotal + $balanceTotal) - $transactionTotal
        differenceRecapToTransaction = $recapTotal - $transactionTotal
        passed = ([Math]::Abs([double](($cashTotal + $balanceTotal) - $transactionTotal)) -lt 0.01 -and
            [Math]::Abs([double]($recapTotal - $transactionTotal)) -lt 0.01)
    }
    reportData = $reportData
}
$result.allPassed = ($catalogPassed -and
    @($reportChecks | Where-Object { -not $_.passed -or -not $_.pdf.passed }).Count -eq 0 -and
    @($detailChecks | Where-Object { -not $_.passed }).Count -eq 0 -and
    $result.reconciliation.passed)

$jsonPath = Join-Path $OutputDir 'uat-laporan-omzet-ebisnis-v1.34.35.json'
[IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 25), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    allPassed = $result.allPassed
    catalogPassed = $catalogPassed
    reportsPassed = @($reportChecks | Where-Object { $_.passed -and $_.pdf.passed }).Count
    reportsTotal = $reportChecks.Count
    detailsPassed = @($detailChecks | Where-Object passed).Count
    detailsTotal = $detailChecks.Count
    reconciliationPassed = $result.reconciliation.passed
    transactionTotal = $transactionTotal
    difference = $result.reconciliation.differenceRecapToTransaction
    jsonPath = $jsonPath
} | ConvertTo-Json -Compress
