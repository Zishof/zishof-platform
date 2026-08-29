param(
  [string]$ApiUrl = $env:AIS_BIOMETRIC_API_URL,
  [string]$AccessToken = $env:AIS_BIOMETRIC_UAT_TOKEN,
  [int]$TimeoutSeconds = 15,
  [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$failed = $false
$results = New-Object System.Collections.Generic.List[object]

function Write-Check([string]$Name, [bool]$Ready, [string]$Detail) {
  $status = if ($Ready) { 'PASS' } else { 'FAIL' }
  $color = if ($Ready) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1} - {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  $script:results.Add([pscustomobject]@{
      name = $Name
      ready = $Ready
      detail = $Detail
    })
  if (-not $Ready) { $script:failed = $true }
}

function Write-SafeReport {
  if ([string]::IsNullOrWhiteSpace($ReportPath)) { return }

  $resolved = [System.IO.Path]::GetFullPath($ReportPath)
  $parent = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $report = [ordered]@{
    schema = 'ais-biometric-readiness/v1'
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    machine = $env:COMPUTERNAME
    passed = (-not $script:failed)
    checks = $script:results.ToArray()
  }
  $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resolved -Encoding UTF8
  Write-Host "Laporan aman ditulis ke $resolved" -ForegroundColor Cyan
}

$tcp = [System.Net.Sockets.TcpClient]::new()
try {
  $task = $tcp.ConnectAsync('127.0.0.1', 8000)
  if (-not $task.Wait([TimeSpan]::FromSeconds(2))) {
    throw 'timeout'
  }
  Write-Check 'SecuGen WebAPI Desktop' $tcp.Connected 'HTTPS loopback port 8000 aktif.'
} catch {
  Write-Check 'SecuGen WebAPI Desktop' $false 'Pasang driver, WebAPI, lalu jalankan SgiBioSrv.'
} finally {
  $tcp.Dispose()
}

$cameras = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
    Where-Object {
      $_.PNPClass -in @('Camera', 'Image') -or $_.Name -match 'camera|webcam'
    })
$cameraDetail = if ($cameras.Count -gt 0) {
  "Perangkat kamera terdeteksi: $($cameras.Count)."
} else {
  'Webcam/kamera tidak terdeteksi.'
}
Write-Check 'Kamera wajah Desktop' ($cameras.Count -gt 0) $cameraDetail

if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
  Write-Check 'API biometrik AIS' $false 'Set AIS_BIOMETRIC_API_URL ke endpoint Api_eBisnis.'
} elseif ([string]::IsNullOrWhiteSpace($AccessToken)) {
  Write-Check 'API biometrik AIS' $false 'Set AIS_BIOMETRIC_UAT_TOKEN; token tidak pernah dicetak.'
} else {
  try {
    $headers = @{ Authorization = "Bearer $AccessToken" }
    $body = @{ action = 'biometrik_kemampuan' } | ConvertTo-Json -Compress
    $response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $headers `
      -ContentType 'application/json' -Body $body -TimeoutSec $TimeoutSeconds
    $ok = ($response.status -eq 'success' -or $response.status -eq '00')
    Write-Check 'API biometrik AIS' $ok "status=$($response.status)"
    if ($ok) {
      Write-Check 'Enkripsi template server' ($response.server_encryption_ready -eq $true) `
        'AIS_BIOMETRIC_MASTER_KEY aktif.'
      Write-Check 'Matcher fingerprint server' ($response.fingerprint_matcher_ready -eq $true) `
        'Provider ISO_19794_2 tersedia.'
      Write-Check 'Matcher wajah server' ($response.face_matcher_ready -eq $true) `
        'Provider FACE_EMBEDDING_F32_LE_V1 tersedia.'
      Write-Check 'Hak enroll pengguna lain' ($response.boleh_enroll_pengguna_lain -eq $true) `
        'Role akun UAT mengizinkan enrollment.'
    }
  } catch {
    Write-Check 'API biometrik AIS' $false $_.Exception.Message
  }
}

Write-SafeReport
if ($failed) { exit 1 }
exit 0
