param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$rawRoot = Join-Path $root 'screenshots\raw'
$outputRoot = Join-Path $root 'screenshots\annotated'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null

$items = @(
    @{ Name = '01-pos-riwayat'; Source = 'pos-kulakan/02-riwayat-penjualan-52-transaksi.png'; Width = 2560; Height = 1392; Kind = 'pos' },
    @{ Name = '02-kulakan'; Source = 'pos-kulakan/03-kulakan-50-faktur-volume.png'; Width = 2560; Height = 1392; Kind = 'kulakan' },
    @{ Name = '03-pr'; Source = 'pengadaan/02-pr-daftar-50.png'; Width = 1920; Height = 1057; Kind = 'proc' },
    @{ Name = '04-po'; Source = 'pengadaan/04-po-daftar-termin-nontermin.png'; Width = 1920; Height = 1057; Kind = 'proc' },
    @{ Name = '05-bast'; Source = 'pengadaan/07-bast-daftar-50.png'; Width = 1920; Height = 1057; Kind = 'proc' },
    @{ Name = '06-terima-tagihan'; Source = 'pengadaan/09-terima-tagihan-50.png'; Width = 1920; Height = 1057; Kind = 'proc' },
    @{ Name = '07-bayar-vendor'; Source = 'pengadaan/10-pembayaran-vendor-50.png'; Width = 1920; Height = 1057; Kind = 'payment' },
    @{ Name = '08-laba-rugi'; Source = 'laporan/24-laba-rugi-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' },
    @{ Name = '09-neraca'; Source = 'laporan/25-neraca-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' },
    @{ Name = '10-arus-kas'; Source = 'laporan/26-arus-kas-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' },
    @{ Name = '11-jurnal-umum'; Source = 'laporan/27-jurnal-umum-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' },
    @{ Name = '12-buku-besar'; Source = 'laporan/28-buku-besar-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' },
    @{ Name = '13-neraca-saldo'; Source = 'laporan/29-neraca-saldo-full-atas.png'; Width = 2560; Height = 1392; Kind = 'report' }
)

function Get-Marks([string]$kind) {
    switch ($kind) {
        'pos' {
            return @(
                @{ N = 1; X = 250; Y = 225; W = 420; H = 120 },
                @{ N = 2; X = 250; Y = 335; W = 2210; H = 130 },
                @{ N = 3; X = 250; Y = 470; W = 2210; H = 430 }
            )
        }
        'kulakan' {
            return @(
                @{ N = 1; X = 250; Y = 325; W = 430; H = 125 },
                @{ N = 2; X = 250; Y = 445; W = 2210; H = 800 },
                @{ N = 3; X = 2120; Y = 240; W = 335; H = 80 }
            )
        }
        'payment' {
            return @(
                @{ N = 1; X = 520; Y = 205; W = 440; H = 80 },
                @{ N = 2; X = 260; Y = 320; W = 1630; H = 675 },
                @{ N = 3; X = 1430; Y = 380; W = 220; H = 170 }
            )
        }
        'report' {
            return @(
                @{ N = 1; X = 5; Y = 70; W = 2535; H = 155 },
                @{ N = 2; X = 5; Y = 230; W = 2535; H = 810 },
                @{ N = 3; X = 2130; Y = 150; W = 390; H = 70 }
            )
        }
        default {
            return @(
                @{ N = 1; X = 260; Y = 75; W = 650; H = 115 },
                @{ N = 2; X = 275; Y = 335; W = 1605; H = 190 },
                @{ N = 3; X = 275; Y = 525; W = 1605; H = 435 }
            )
        }
    }
}

foreach ($item in $items) {
    $sourcePath = Join-Path $rawRoot ($item.Source -replace '/', '\')
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Screenshot sumber tidak ditemukan: $sourcePath"
    }
    $marks = Get-Marks $item.Kind
    $markup = foreach ($mark in $marks) {
        $circleX = $mark.X + 30
        $circleY = $mark.Y + 30
        @"
  <rect x="$($mark.X)" y="$($mark.Y)" width="$($mark.W)" height="$($mark.H)" rx="14" fill="none" stroke="#ff3b30" stroke-width="8"/>
  <circle cx="$circleX" cy="$circleY" r="25" fill="#ff3b30" stroke="#ffffff" stroke-width="4"/>
  <text x="$circleX" y="$($circleY + 9)" text-anchor="middle" font-family="Arial, sans-serif" font-size="28" font-weight="700" fill="#ffffff">$($mark.N)</text>
"@
    }
    $href = "../raw/$($item.Source)"
    $svg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$($item.Width)" height="$($item.Height)" viewBox="0 0 $($item.Width) $($item.Height)">
  <image href="$href" x="0" y="0" width="$($item.Width)" height="$($item.Height)"/>
$($markup -join "`n")
</svg>
"@
    $destination = Join-Path $outputRoot "$($item.Name).svg"
    [System.IO.File]::WriteAllText($destination, $svg, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Anotasi SVG dibuat: $($items.Count) file"
