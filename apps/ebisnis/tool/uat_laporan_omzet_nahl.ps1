param(
    [string]$OutputDir = 'C:\opt\CodeBaseDesktopDanMobile\tmp\uat-laporan-omzet-nahl',
    [string]$TanggalMulai = '2026-01-01',
    [string]$TanggalSampai = '2026-09-05'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$preferensiPath = 'C:\Users\Admin1\AppData\Roaming\id.zishof\TokoQu Al-Bahjah An Nahl\shared_preferences.json'
$endpoint = 'https://an-nahl.santri.info/nahl/Api_eBisnis'
$preferensi = Get-Content -LiteralPath $preferensiPath -Raw | ConvertFrom-Json
$token = $preferensi.'flutter.token'
if ([string]::IsNullOrWhiteSpace($token)) {
    throw 'Token sesi Nahl tidak tersedia.'
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

function Invoke-NahlApi([hashtable]$Payload) {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers `
        -Body ($Payload | ConvertTo-Json -Depth 12 -Compress) -TimeoutSec 60
    $stopwatch.Stop()
    return [pscustomobject]@{ Response = $response; DurationMs = $stopwatch.ElapsedMilliseconds }
}

function Get-ColumnIndex($Report, [string]$Label) {
    for ($i = 0; $i -lt @($Report.kolom).Count; $i++) {
        if ([string]::Equals("$($Report.kolom[$i].l)", $Label, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $i
        }
    }
    throw "Kolom '$Label' tidak ditemukan."
}

function Invoke-Detail([string]$Name, [hashtable]$Dimensions, [decimal]$ExpectedTotal) {
    $payload = @{
        action = 'laporan_rincian_transaksi'
        tglMulai = $TanggalMulai
        tglSampai = $TanggalSampai
        batas = 500
    }
    foreach ($key in $Dimensions.Keys) { $payload[$key] = $Dimensions[$key] }
    $call = Invoke-NahlApi $payload
    $response = $call.Response
    $actual = [decimal]($response.totalNilai ?? 0)
    $rows = @($response.data).Count
    return [ordered]@{
        name = $Name
        status = "$($response.status)"
        rows = $rows
        expectedTotal = $ExpectedTotal
        actualTotal = $actual
        difference = $actual - $ExpectedTotal
        durationMs = $call.DurationMs
        passed = ("$($response.status)" -eq 'success' -and $rows -gt 0 -and [math]::Abs([double]($actual - $ExpectedTotal)) -lt 0.01)
        data = @($response.data)
    }
}

$reportIds = @('omzet_transaksi', 'omzet_tunai_produk', 'omzet_saldo_produk', 'omzet_rekapan')
$reportData = [ordered]@{}
$reportChecks = @()

$catalogCall = Invoke-NahlApi @{ action = 'laporan_katalog' }
$category = @($catalogCall.Response.kategori) | Where-Object { "$($_.kat)".Trim() -eq 'Omzet' } | Select-Object -First 1
$catalogIds = @($category.items | ForEach-Object { "$($_.id)" })
$catalogPassed = $null -ne $category -and @($reportIds | Where-Object { $_ -notin $catalogIds }).Count -eq 0

foreach ($id in $reportIds) {
    $call = Invoke-NahlApi @{
        action = 'laporan_jalankan'
        r = $id
        tglMulai = $TanggalMulai
        tglSampai = $TanggalSampai
    }
    $response = $call.Response
    $reportData[$id] = $response
    $reportChecks += [ordered]@{
        id = $id
        status = "$($response.status)"
        columns = @($response.kolom).Count
        rows = @($response.baris).Count
        durationMs = $call.DurationMs
        passed = ("$($response.status)" -eq 'success' -and @($response.kolom).Count -gt 0 -and @($response.baris).Count -gt 0)
    }

    $pdfCall = Invoke-NahlApi @{
        action = 'laporan_pdf'
        r = $id
        tglMulai = $TanggalMulai
        tglSampai = $TanggalSampai
    }
    $pdf = [Convert]::FromBase64String("$($pdfCall.Response.pdfBase64)")
    $pdfPath = Join-Path $OutputDir "$id.pdf"
    [IO.File]::WriteAllBytes($pdfPath, $pdf)
    $signature = if ($pdf.Length -ge 4) { [Text.Encoding]::ASCII.GetString($pdf[0..3]) } else { '' }
    $reportChecks[-1].pdf = [ordered]@{
        status = "$($pdfCall.Response.status)"
        bytes = $pdf.Length
        signature = $signature
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $pdfPath).Hash
        durationMs = $pdfCall.DurationMs
        passed = ("$($pdfCall.Response.status)" -eq 'success' -and $signature -eq '%PDF' -and $pdf.Length -gt 1000)
    }
}

$detail = $reportData.omzet_transaksi
$tunai = $reportData.omzet_tunai_produk
$saldo = $reportData.omzet_saldo_produk
$rekap = $reportData.omzet_rekapan

$detailRow = @($detail.baris)[0]
$detailIdIndex = Get-ColumnIndex $detail 'No. Transaksi'
$detailNominalIndex = Get-ColumnIndex $detail 'Nominal'
$tunaiRow = @($tunai.baris)[0]
$tunaiProdukIndex = Get-ColumnIndex $tunai 'Produk'
$tunaiOmzetIndex = Get-ColumnIndex $tunai 'Omzet'
$saldoRow = @($saldo.baris)[0]
$saldoProdukIndex = Get-ColumnIndex $saldo 'Produk'
$saldoOmzetIndex = Get-ColumnIndex $saldo 'Omzet'
$rekapRow = @($rekap.baris)[0]
$rekapTokoIndex = Get-ColumnIndex $rekap 'Toko'
$rekapTunaiIndex = Get-ColumnIndex $rekap 'Tunai / Non-Saldo'
$rekapSaldoIndex = Get-ColumnIndex $rekap 'Saldo'
$rekapTotalIndex = Get-ColumnIndex $rekap 'Total Omzet'

$detailChecks = @(
    (Invoke-Detail 'Transaksi persis - Semua Toko' @{ idTransaksi = "$($detailRow[$detailIdIndex])" } ([decimal]$detailRow[$detailNominalIndex])),
    (Invoke-Detail 'Produk Tunai / Non-Saldo' @{ namaProduk = "$($tunaiRow[$tunaiProdukIndex])"; kelompokPembayaran = 'NON_SALDO' } ([decimal]$tunaiRow[$tunaiOmzetIndex])),
    (Invoke-Detail 'Produk Saldo' @{ namaProduk = "$($saldoRow[$saldoProdukIndex])"; kelompokPembayaran = 'SALDO' } ([decimal]$saldoRow[$saldoOmzetIndex])),
    (Invoke-Detail 'Rekapan Tunai / Non-Saldo' @{ toko = "$($rekapRow[$rekapTokoIndex])"; kelompokPembayaran = 'NON_SALDO' } ([decimal]$rekapRow[$rekapTunaiIndex])),
    (Invoke-Detail 'Rekapan Saldo' @{ toko = "$($rekapRow[$rekapTokoIndex])"; kelompokPembayaran = 'SALDO' } ([decimal]$rekapRow[$rekapSaldoIndex])),
    (Invoke-Detail 'Rekapan Total Omzet' @{ toko = "$($rekapRow[$rekapTokoIndex])" } ([decimal]$rekapRow[$rekapTotalIndex]))
)

$detailTotal = [decimal](($detail.baris | ForEach-Object { [decimal]$_[$detailNominalIndex] } | Measure-Object -Sum).Sum)
$tunaiTotal = [decimal](($tunai.baris | ForEach-Object { [decimal]$_[$tunaiOmzetIndex] } | Measure-Object -Sum).Sum)
$saldoTotal = [decimal](($saldo.baris | ForEach-Object { [decimal]$_[$saldoOmzetIndex] } | Measure-Object -Sum).Sum)
$rekapTotal = [decimal](($rekap.baris | ForEach-Object { [decimal]$_[$rekapTotalIndex] } | Measure-Object -Sum).Sum)

$result = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    environment = 'Nahl live'
    endpoint = $endpoint
    period = [ordered]@{ start = $TanggalMulai; end = $TanggalSampai }
    catalog = [ordered]@{ status = "$($catalogCall.Response.status)"; durationMs = $catalogCall.DurationMs; ids = $catalogIds; passed = $catalogPassed }
    reports = $reportChecks
    details = $detailChecks
    reconciliation = [ordered]@{
        transactionTotal = $detailTotal
        nonSaldoTotal = $tunaiTotal
        saldoTotal = $saldoTotal
        productTotal = $tunaiTotal + $saldoTotal
        recapTotal = $rekapTotal
        differenceProductToTransaction = ($tunaiTotal + $saldoTotal) - $detailTotal
        differenceRecapToTransaction = $rekapTotal - $detailTotal
        passed = (($tunaiTotal + $saldoTotal) -eq $detailTotal -and $rekapTotal -eq $detailTotal)
    }
    reportData = $reportData
}
$result.allPassed = ($catalogPassed `
    -and @($reportChecks | Where-Object { -not $_.passed -or -not $_.pdf.passed }).Count -eq 0 `
    -and @($detailChecks | Where-Object { -not $_.passed }).Count -eq 0 `
    -and $result.reconciliation.passed)

$jsonPath = Join-Path $OutputDir 'uat-live-result.json'
[IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 25), [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    allPassed = $result.allPassed
    catalogPassed = $catalogPassed
    reportsPassed = @($reportChecks | Where-Object { $_.passed -and $_.pdf.passed }).Count
    reportsTotal = $reportChecks.Count
    detailsPassed = @($detailChecks | Where-Object { $_.passed }).Count
    detailsTotal = $detailChecks.Count
    reconciliationPassed = $result.reconciliation.passed
    transactionTotal = $detailTotal
    jsonPath = $jsonPath
} | ConvertTo-Json -Compress
