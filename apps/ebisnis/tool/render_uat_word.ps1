param([Parameter(Mandatory=$true)][ValidateSet('albahjah','nahl')][string]$Variant)
$ErrorActionPreference = 'Stop'
$repoUat = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$reportUat = Join-Path $repoUat "output\uat-1.34.40-20260917\$Variant\UAT-$Variant-1.34.40-build203.docx"
if (-not (Test-Path -LiteralPath $reportUat)) { throw "Laporan belum dibuat: $reportUat" }
$renderUat = Join-Path (Split-Path $reportUat -Parent) 'render'
New-Item -ItemType Directory -Force -Path $renderUat | Out-Null
$pdfUat = Join-Path $renderUat "UAT-$Variant-1.34.40-build203.pdf"
# Windows runtime has no bundled LibreOffice. Render the report in a separate
# invisible Microsoft Word instance; never open or alter the user's documents.
$wordUat = New-Object -ComObject Word.Application
$wordUat.Visible = $false
$wordUat.DisplayAlerts = 0
try {
  $docUat = $wordUat.Documents.Open($reportUat, $false, $true)
  $docUat.Repaginate()
  $docUat.ExportAsFixedFormat($pdfUat, 17)
  $docUat.Close(0)
} finally {
  $wordUat.Quit(0)
  [Runtime.InteropServices.Marshal]::ReleaseComObject($wordUat) | Out-Null
}
$popplerUat = 'C:\Users\Admin1\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\poppler\Library\bin\pdftoppm.exe'
& $popplerUat -r 100 -png $pdfUat (Join-Path $renderUat 'page')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Get-ChildItem -LiteralPath $renderUat -Filter '*.png' | Select-Object Name,Length
