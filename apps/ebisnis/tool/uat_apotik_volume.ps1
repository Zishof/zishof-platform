param(
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Password,
    [string]$Endpoint = 'https://demo.ecampus.id/ecampus/Api_eBisnis',
    [int]$TargetPerAlur = 100,
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
$hasil = [ordered]@{
    runId = $runId
    mulai = (Get-Date).ToString('o')
    endpoint = $Endpoint
    targetPerAlur = $TargetPerAlur
    alur = [ordered]@{}
}

function Invoke-ApotikRaw {
    param([hashtable]$Body, [hashtable]$Headers = @{})
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $Headers `
                -ContentType 'application/json' `
                -Body ($Body | ConvertTo-Json -Depth 14 -Compress) -TimeoutSec 45
        } catch {
            if ($attempt -eq 4) { throw }
            Start-Sleep -Milliseconds (500 * $attempt)
        }
    }
}

function Invoke-ApotikApi {
    param([hashtable]$Body)
    $response = Invoke-ApotikRaw -Body $Body -Headers $script:authHeaders
    if ($response.status -notin @('success', '00')) {
        $pesan = $response.message
        if (-not $pesan) { $pesan = $response.description }
        throw "Aksi $($Body.action) ditolak: $pesan"
    }
    return $response
}

function Get-CaraBayarTunai {
    $daftar = (Invoke-ApotikApi @{ action = 'apotik_cara_bayar_list' }).data
    $cara = $daftar | Where-Object { $_.adaKembalian -eq $true } | Select-Object -First 1
    if (-not $cara) { $cara = $daftar | Select-Object -First 1 }
    if (-not $cara) { throw 'Tidak ada metode pembayaran Apotik yang aktif.' }
    return $cara
}

function New-Pembayaran {
    param($Cara, [double]$Total)
    return @(@{
        cara_bayar_id = $Cara.id
        nominal = $Total
        tunai = $Total
        kembalian = 0
    })
}

function Add-HasilAlur {
    param([string]$Nama, [int]$Sukses, [System.Collections.IList]$Contoh, [System.Collections.IList]$Gagal)
    $hasil.alur[$Nama] = [ordered]@{
        sukses = $Sukses
        gagal = $Gagal.Count
        lulus = $Sukses -ge $TargetPerAlur
        contoh = @($Contoh | Select-Object -First 5)
        kegagalan = @($Gagal | Select-Object -First 20)
    }
    Write-Host "UAT $Nama selesai: sukses=$Sukses gagal=$($Gagal.Count)"
}

$login = Invoke-ApotikRaw @{
    action = 'login'
    username = $Username
    password = $Password
    labelPerangkat = 'UAT-Apotik-Volume'
}
if (-not $login.token) { throw 'Login tidak mengembalikan token.' }
$script:authHeaders = @{ Authorization = "Bearer $($login.token)" }
$cara = Get-CaraBayarTunai

$items = @((Invoke-ApotikApi @{
    action = 'apotik_item_cari'; keyword = 'DEMO-OBT-'; page = 1; page_size = 100
}).data | Where-Object { [double]$_.stok -ge 3 } | Select-Object -First $TargetPerAlur)
if ($items.Count -lt $TargetPerAlur) {
    throw "Katalog obat berstok hanya $($items.Count), target $TargetPerAlur."
}

foreach ($jenis in @('otc', 'resep_dokter')) {
    $sukses = 0; $contoh = [System.Collections.ArrayList]::new(); $gagal = [System.Collections.ArrayList]::new()
    for ($i = 0; $i -lt $items.Count -and $sukses -lt $TargetPerAlur; $i++) {
        $item = $items[$i]
        try {
            $batch = (Invoke-ApotikApi @{ action = 'apotik_item_batch'; item_id = $item.id }).data |
                Where-Object { $_.lotLayak -eq $true -and $_.kedaluwarsa -ne $true -and [double]$_.sisa -ge 1 } |
                Select-Object -First 1
            if (-not $batch) { throw 'Batch FEFO layak tidak tersedia.' }
            $harga = [double]$item.hargaJual
            $payload = @{
                action = 'apotik_bayar'
                kode = "UAT-$($jenis.ToUpper())-$runId-$('{0:D3}' -f ($i + 1))"
                cara_bayar_id = $cara.id
                pembayaran = New-Pembayaran $cara $harga
                items = @(@{
                    item_id = $item.id; qty = 1; harga_satuan = $harga
                    batch = @(@{ kadaluarsa_id = $batch.kadaluarsaId; qty = 1 })
                })
            }
            if ($jenis -eq 'resep_dokter') {
                $payload.nama_dokter = 'dr. UAT Apotik'
                $payload.pembeli = @{ nama = "Pasien UAT $($i + 1)"; alamat = 'Alamat Demo' }
            }
            $r = Invoke-ApotikApi $payload
            $sukses++
            [void]$contoh.Add(@{ id = $r.id; kode = $r.kode; total = $r.total; item = $item.kode })
        } catch {
            [void]$gagal.Add(@{ indeks = $i + 1; item = $item.kode; pesan = $_.Exception.Message })
        }
        if (($i + 1) % 10 -eq 0) { Write-Host "UAT $jenis $($i + 1)/$TargetPerAlur" }
    }
    Add-HasilAlur -Nama $jenis -Sukses $sukses -Contoh $contoh -Gagal $gagal
}

$racikan = @((Invoke-ApotikApi @{
    action = 'apotik_racikan_list'; page = 1; page_size = 100
}).data | Where-Object { [double]$_.stok -ge 1 } | Select-Object -First $TargetPerAlur)
$sukses = 0; $contoh = [System.Collections.ArrayList]::new(); $gagal = [System.Collections.ArrayList]::new()
for ($i = 0; $i -lt $racikan.Count -and $sukses -lt $TargetPerAlur; $i++) {
    $row = $racikan[$i]
    try {
        $total = [double]$row.hargaJual
        $r = Invoke-ApotikApi @{
            action = 'apotik_bayar_racikan'
            kode = "UAT-RACIKAN-$runId-$('{0:D3}' -f ($i + 1))"
            nama_dokter = 'dr. UAT Racikan'
            pembeli = @{ nama = "Pasien Racikan $($i + 1)"; alamat = 'Alamat Demo' }
            cara_bayar_id = $cara.id
            pembayaran = New-Pembayaran $cara $total
            items = @(@{ racikan_id = $row.id; qty = 1; harga_satuan = $total })
        }
        $sukses++; [void]$contoh.Add(@{ id = $r.id; kode = $r.kode; total = $r.total; racikan = $row.kode })
    } catch { [void]$gagal.Add(@{ indeks = $i + 1; racikan = $row.kode; pesan = $_.Exception.Message }) }
    if (($i + 1) % 10 -eq 0) { Write-Host "UAT racikan $($i + 1)/$TargetPerAlur" }
}
Add-HasilAlur -Nama 'racikan' -Sukses $sukses -Contoh $contoh -Gagal $gagal

$produksi = @((Invoke-ApotikApi @{
    action = 'apotik_produksi_katalog'; page = 1; page_size = 100
}).data | Where-Object { [double]$_.stok -ge 1 } | Select-Object -First $TargetPerAlur)
$sukses = 0; $contoh = [System.Collections.ArrayList]::new(); $gagal = [System.Collections.ArrayList]::new()
$ed = (Get-Date).AddYears(1).ToString('yyyy-MM-dd')
for ($i = 0; $i -lt $produksi.Count -and $sukses -lt $TargetPerAlur; $i++) {
    $row = $produksi[$i]
    try {
        $kode = "UAT-PROD-$runId-$('{0:D3}' -f ($i + 1))"
        $r = Invoke-ApotikApi @{
            action = 'apotik_produksi_proses'; kode = $kode
            nomor_batch = "BATCH-$runId-$('{0:D3}' -f ($i + 1))"
            tanggal_kadaluarsa = $ed
            items = @(@{ item_id = $row.id; qty = 1 })
        }
        $sukses++; [void]$contoh.Add(@{ kode = $r.kode; item = $row.kode })
    } catch { [void]$gagal.Add(@{ indeks = $i + 1; item = $row.kode; pesan = $_.Exception.Message }) }
    if (($i + 1) % 10 -eq 0) { Write-Host "UAT produksi $($i + 1)/$TargetPerAlur" }
}
Add-HasilAlur -Nama 'produksi_farmasi' -Sukses $sukses -Contoh $contoh -Gagal $gagal

$reseps = @((Invoke-ApotikApi @{
    action = 'apotik_resep_list'; page = 1; page_size = 100; hanya_menunggu = $true
}).data)
$sukses = 0; $contoh = [System.Collections.ArrayList]::new(); $gagal = [System.Collections.ArrayList]::new()
for ($i = 0; $i -lt $reseps.Count -and $sukses -lt $TargetPerAlur; $i++) {
    $resep = $reseps[$i]
    try {
        $detail = Invoke-ApotikApi @{ action = 'apotik_resep_detail'; resep_id = $resep.id }
        $lines = [System.Collections.ArrayList]::new(); $total = 0.0
        foreach ($x in $detail.data) {
            $qty = [double]$x.jumlah; $harga = [double]$x.hargaJual
            if ($x.racikan -eq $true) {
                [void]$lines.Add(@{ racikan_id = $x.racikanId; qty = $qty; harga_satuan = $harga })
            } else {
                [void]$lines.Add(@{ item_id = $x.itemId; qty = $qty; harga_satuan = $harga })
            }
            $total += $qty * $harga
        }
        if ($lines.Count -eq 0 -or $total -le 0) { throw 'Detail resep tidak memiliki baris bernilai.' }
        $r = Invoke-ApotikApi @{
            action = 'apotik_bayar_racikan'
            kode = "UAT-TEBUS-$runId-$('{0:D3}' -f ($i + 1))"
            resep_id = $resep.id
            nama_dokter = 'dr. UAT Tebus Resep'
            pembeli = @{ nama = "Pasien Tebus $($i + 1)"; alamat = 'Alamat Demo' }
            cara_bayar_id = $cara.id
            pembayaran = New-Pembayaran $cara $total
            items = @($lines)
        }
        $sukses++; [void]$contoh.Add(@{ id = $r.id; kode = $r.kode; total = $r.total; resep = $resep.kode })
    } catch { [void]$gagal.Add(@{ indeks = $i + 1; resep = $resep.kode; pesan = $_.Exception.Message }) }
    if (($i + 1) % 10 -eq 0) { Write-Host "UAT tebus_resep $($i + 1)/$TargetPerAlur" }
}
Add-HasilAlur -Nama 'tebus_resep' -Sukses $sukses -Contoh $contoh -Gagal $gagal

$hasil.selesai = (Get-Date).ToString('o')
$hasil.lulus = @($hasil.alur.Values | Where-Object { -not $_.lulus }).Count -eq 0
$json = $hasil | ConvertTo-Json -Depth 12
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot "..\docs\uat-apotik-volume-$runId.json"
}
$folder = Split-Path -Parent $OutputPath
if ($folder -and -not (Test-Path -LiteralPath $folder)) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}
[System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "Bukti: $OutputPath"
Write-Host "LULUS=$($hasil.lulus)"
if (-not $hasil.lulus) { exit 2 }
