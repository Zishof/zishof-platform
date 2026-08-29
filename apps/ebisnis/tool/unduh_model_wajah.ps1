# Unduh model wajah on-device dari OpenCV Zoo dengan verifikasi SHA-256.
#
# Model TIDAK disimpan di git (SFace 38,7 MB); script ini adalah sumber
# kebenarannya: URL ter-pin ke commit branch main opencv_zoo dan hash wajib
# cocok, sehingga build di mesin mana pun memakai berkas yang persis sama.
#
# Lisensi (salinannya di assets/face/):
#   - SFace  (face_recognition_sface_2021dec.onnx) : Apache-2.0
#   - YuNet  (face_detection_yunet_2023mar.onnx)   : MIT (c) 2020 Shiqi Yu
$ErrorActionPreference = 'Stop'

$tujuan = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\face'
New-Item -ItemType Directory -Force $tujuan | Out-Null

$daftar = @(
  @{
    Nama = 'face_recognition_sface_2021dec.onnx'
    Url  = 'https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx'
    Sha  = '0BA9FBFA01B5270C96627C4EF784DA859931E02F04419C829E83484087C34E79'
  },
  @{
    Nama = 'face_detection_yunet_2023mar.onnx'
    Url  = 'https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx'
    Sha  = '8F2383E4DD3CFBB4553EA8718107FC0423210DC964F9F4280604804ED2552FA4'
  }
)

foreach ($m in $daftar) {
  $path = Join-Path $tujuan $m.Nama
  if (Test-Path $path) {
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash
    if ($hash -eq $m.Sha) {
      Write-Host "[OK] $($m.Nama) sudah ada dan hash cocok." -ForegroundColor Green
      continue
    }
    Write-Host "[!] $($m.Nama) ada tetapi hash beda -- diunduh ulang." -ForegroundColor Yellow
  }
  Write-Host "Mengunduh $($m.Nama) ..."
  Invoke-WebRequest -UseBasicParsing $m.Url -OutFile $path -TimeoutSec 600
  $hash = (Get-FileHash $path -Algorithm SHA256).Hash
  if ($hash -ne $m.Sha) {
    Remove-Item $path -Force
    throw "Hash $($m.Nama) TIDAK cocok (dapat $hash). Berkas dibuang -- periksa sumber."
  }
  Write-Host "[OK] $($m.Nama) terverifikasi SHA-256." -ForegroundColor Green
}

Write-Host "Model wajah siap di $tujuan"
