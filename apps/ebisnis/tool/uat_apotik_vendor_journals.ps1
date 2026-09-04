param(
  [Parameter(Mandatory = $true)][string]$Username,
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$Uri = 'https://demo.ecampus.id/ecampus/Api_eBisnis'
)

$ErrorActionPreference = 'Stop'
$marker = 'UAT Apotik v1.34.22 - pembayaran vendor'

function Invoke-Ais([hashtable]$Payload) {
  for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
      return Invoke-RestMethod -Method Post -Uri $Uri -Headers $script:headers `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 120 `
        -Body ($Payload | ConvertTo-Json -Depth 8 -Compress)
    } catch {
      if ($attempt -eq 4) { throw }
      Start-Sleep -Seconds $attempt
    }
  }
}

$login = Invoke-RestMethod -Method Post -Uri $Uri -ContentType 'application/json; charset=utf-8' `
  -TimeoutSec 120 -Body (@{
    action = 'login'; username = $Username; password = $Password
    labelPerangkat = 'UAT-Apotik-Vendor-Jurnal'
  } | ConvertTo-Json -Compress)
$script:headers = @{ Authorization = 'Bearer ' + $login.token }

function Get-Account([string]$Code) {
  $response = Invoke-Ais @{ action = 'akun_list'; keyword = $Code; limit = 50 }
  $found = @($response.data | Where-Object { $_.kode -eq $Code -and $_.leaf -eq $true })
  if ($found.Count -ne 1) { throw "Akun $Code harus unik dan leaf." }
  return $found[0]
}

$cash = Get-Account '111.101'
$payable = Get-Account '310.500'
$paymentResponse = Invoke-Ais @{
  action = 'pengadaan_bayar_daftar'; toko_id = 1; page = 1; pageSize = 100
}
$payments = @($paymentResponse.data |
  Where-Object { $_.status -eq 'DISETUJUI' -and $_.caraBayar -eq 'Tunai' } |
  Select-Object -First 50)
if ($payments.Count -ne 50) { throw "Diperlukan 50 pembayaran vendor; ditemukan $($payments.Count)." }

$existingResponse = Invoke-Ais @{
  action = 'jurnal_umum_list'; mulai = '2026-09-01'; sampai = '2026-09-30'
  cari = $marker; status = ''
}
$byDescription = @{}
foreach ($journal in @($existingResponse.data)) { $byDescription[$journal.keterangan] = $journal }

$idsToPost = [System.Collections.Generic.List[int]]::new()
$created = 0
$index = 0
foreach ($payment in $payments) {
  $index++
  $description = "$marker $($payment.kode)"
  $journal = $byDescription[$description]
  if ($null -eq $journal) {
    $amount = [double]$payment.nilai
    $made = Invoke-Ais @{
      action = 'jurnal_umum_simpan'; tanggal = '2026-09-04'
      keterangan = $description; jenisTransaksiId = 0
      baris = @(
        @{ akunId = $payable.id; debet = $amount; kredit = 0; keterangan = "Pelunasan utang vendor $($payment.kode)" },
        @{ akunId = $cash.id; debet = 0; kredit = $amount; keterangan = "Kas keluar pembayaran vendor $($payment.kode)" }
      )
    }
    $journal = [pscustomobject]@{ id = $made.id; terposting = $false }
    $created++
  }
  if ($journal.terposting -ne $true) { $idsToPost.Add([int]$journal.id) }
  if ($index -eq 1 -or $index % 10 -eq 0 -or $index -eq 50) {
    Write-Output "UAT_VENDOR_JURNAL_PROGRESS=$index/50"
  }
}

if ($idsToPost.Count -gt 0) {
  Invoke-Ais @{ action = 'jurnal_umum_posting'; ids = @($idsToPost) } | Out-Null
}
$verified = Invoke-Ais @{
  action = 'jurnal_umum_list'; mulai = '2026-09-01'; sampai = '2026-09-30'
  cari = $marker; status = 'posting'
}
$posted = @($verified.data | Where-Object { $_.terposting -eq $true }).Count
if ($posted -lt 50) { throw "Posting jurnal terverifikasi hanya $posted dari 50." }

[pscustomobject]@{
  pembayaranDiperiksa = $payments.Count
  jurnalDibuat = $created
  jurnalDipostingPadaRun = $idsToPost.Count
  jurnalTerpostingTerverifikasi = $posted
  debet = '310.500 HUTANG VENDOR'
  kredit = '111.101 KAS YAYASAN'
} | ConvertTo-Json -Compress
