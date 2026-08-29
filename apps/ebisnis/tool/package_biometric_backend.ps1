param(
  [string]$BackendRoot = 'C:\opt\AIS\ais\src\main',
  [string]$OutputDirectory = '',
  [string]$JavaCompiler = 'C:\opt\temurin17\bin\javac.exe',
  [string]$JavaRuntime = 'C:\opt\temurin17\bin\java.exe'
)

$ErrorActionPreference = 'Stop'

function Assert-Path([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "$Label tidak ditemukan: $Path"
  }
}

function Copy-CompiledFamily(
  [string]$CompiledRoot,
  [string]$RelativeDirectory,
  [string]$Pattern,
  [string]$BundleClassesRoot
) {
  $sourceDirectory = Join-Path $CompiledRoot $RelativeDirectory
  $files = @(Get-ChildItem -LiteralPath $sourceDirectory -Filter $Pattern -File)
  if ($files.Count -eq 0) {
    throw "Kelas hasil kompilasi tidak ditemukan: $RelativeDirectory\$Pattern"
  }
  $targetDirectory = Join-Path $BundleClassesRoot $RelativeDirectory
  New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
  foreach ($file in $files) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $targetDirectory $file.Name)
  }
}

$sourceRoot = Join-Path $BackendRoot 'src'
$webInfRoot = Join-Path $BackendRoot 'webapp\WEB-INF'
$libRoot = Join-Path $webInfRoot 'lib'
$hibernateConfig = Join-Path $sourceRoot 'hibernate.cfg.xml'
$selfTestSource = Join-Path $sourceRoot 'ais\action\servlet\api\biometric\test\BiometricCoreSelfTest.java'

Assert-Path $sourceRoot 'Source root backend'
Assert-Path $libRoot 'Library backend'
Assert-Path $hibernateConfig 'hibernate.cfg.xml'
Assert-Path $selfTestSource 'BiometricCoreSelfTest'
Assert-Path $JavaCompiler 'javac'
Assert-Path $JavaRuntime 'java'

$hibernateText = Get-Content -LiteralPath $hibernateConfig -Raw
if ($hibernateText -notmatch '<property\s+name="hbm2ddl\.auto">\s*update\s*</property>') {
  throw 'hbm2ddl.auto harus update agar tabel/kolom biometrik dibuat saat deployment.'
}
foreach ($mapping in @(
  'ais.database.model.biometric.BiometricCredential',
  'ais.database.model.biometric.BiometricEvent',
  'ais.database.model.biometric.IzinGerbangPesantren'
)) {
  if ($hibernateText -notmatch [regex]::Escape("<mapping class=`"$mapping`" />")) {
    throw "Mapping Hibernate belum tersedia: $mapping"
  }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $PSScriptRoot '..\release-artifacts\biometric-backend'
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bundleName = "ais-biometric-backend-$stamp"
$bundleRoot = Join-Path $OutputDirectory $bundleName
$bundleClassesRoot = Join-Path $bundleRoot 'WEB-INF\classes'
$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ais-biometric-package-" + [guid]::NewGuid().ToString('N'))
$compiledRoot = Join-Path $scratchRoot 'classes'
New-Item -ItemType Directory -Path $compiledRoot -Force | Out-Null

try {
  $posApiSource = Join-Path $sourceRoot 'ais\action\servlet\PosApi.java'
  $posApiCompileSource = $posApiSource
  $posApiSourceLabel = 'working copy bersih'
  $svnRevision = 'tidak tersedia'
  $svnCommand = Get-Command svn -ErrorAction SilentlyContinue
  if ($null -ne $svnCommand) {
    $svnRevisionText = & $svnCommand.Source info --show-item revision -- $posApiSource 2>$null
    if ($LASTEXITCODE -eq 0 -and $svnRevisionText) {
      $svnRevision = ($svnRevisionText | Select-Object -First 1).Trim()
    }
    $posApiStatus = & $svnCommand.Source status -- $posApiSource 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($posApiStatus -join ''))) {
      $baseLines = & $svnCommand.Source cat --revision BASE -- $posApiSource 2>$null
      if ($LASTEXITCODE -ne 0 -or $null -eq $baseLines) {
        throw 'PosApi.java kotor dan SVN BASE tidak dapat dibaca; packaging dihentikan agar perubahan lain tidak tercampur.'
      }
      $posApiCompileSource = Join-Path $scratchRoot 'PosApi.java'
      $baseText = ($baseLines -join [Environment]::NewLine) + [Environment]::NewLine
      [System.IO.File]::WriteAllText(
        $posApiCompileSource,
        $baseText,
        [System.Text.UTF8Encoding]::new($false)
      )
      $posApiSourceLabel = "SVN BASE r$svnRevision (working copy kotor tidak dipaketkan)"
    }
  }

  $classpath = Join-Path $libRoot '*'
  $sources = @(
    (Join-Path $sourceRoot 'ais\action\servlet\api\BiometricApi.java'),
    (Join-Path $sourceRoot 'ais\action\servlet\api\GerbangPesantrenApi.java'),
    $posApiCompileSource,
    (Join-Path $sourceRoot 'ais\action\servlet\api\biometric\BiometricCrypto.java'),
    (Join-Path $sourceRoot 'ais\action\servlet\api\biometric\BiometricMatcherProvider.java'),
    (Join-Path $sourceRoot 'ais\action\servlet\api\biometric\BiometricMatcherRegistry.java'),
    (Join-Path $sourceRoot 'ais\action\servlet\api\biometric\BiometricMatchResult.java'),
    (Join-Path $sourceRoot 'ais\database\model\biometric\BiometricCredential.java'),
    (Join-Path $sourceRoot 'ais\database\model\biometric\BiometricEvent.java'),
    (Join-Path $sourceRoot 'ais\database\model\biometric\IzinGerbangPesantren.java'),
    $selfTestSource
  )
  foreach ($source in $sources) { Assert-Path $source 'Source Java' }

  & $JavaCompiler -encoding UTF-8 -nowarn -proc:none -cp $classpath `
    -sourcepath $sourceRoot -d $compiledRoot @sources
  if ($LASTEXITCODE -ne 0) { throw "Kompilasi backend gagal (exit $LASTEXITCODE)." }

  & $JavaRuntime -cp "$compiledRoot;$classpath" `
    ais.action.servlet.api.biometric.test.BiometricCoreSelfTest
  if ($LASTEXITCODE -ne 0) { throw "BiometricCoreSelfTest gagal (exit $LASTEXITCODE)." }

  New-Item -ItemType Directory -Path $bundleClassesRoot -Force | Out-Null
  Copy-CompiledFamily $compiledRoot 'ais\action\servlet' 'PosApi*.class' $bundleClassesRoot
  Copy-CompiledFamily $compiledRoot 'ais\action\servlet\api' 'BiometricApi*.class' $bundleClassesRoot
  Copy-CompiledFamily $compiledRoot 'ais\action\servlet\api' 'GerbangPesantrenApi*.class' $bundleClassesRoot
  Copy-CompiledFamily $compiledRoot 'ais\action\servlet\api\biometric' '*.class' $bundleClassesRoot
  Copy-CompiledFamily $compiledRoot 'ais\database\model\biometric' '*.class' $bundleClassesRoot
  $hibernateChanges = @(
    'JANGAN mengganti hibernate.cfg.xml server dengan file dari workstation.',
    'Pastikan konfigurasi server existing memuat baris berikut di dalam <session-factory>:',
    '',
    '  <property name="hbm2ddl.auto">update</property>',
    '  <mapping class="ais.database.model.biometric.BiometricCredential" />',
    '  <mapping class="ais.database.model.biometric.BiometricEvent" />',
    '  <mapping class="ais.database.model.biometric.IzinGerbangPesantren" />',
    '',
    'Packager telah memvalidasi bahwa source hibernate.cfg.xml memiliki property dan mapping ini.',
    'File konfigurasi asli sengaja TIDAK disalin karena dapat memuat kredensial database.'
  )
  Set-Content -LiteralPath (Join-Path $bundleRoot 'HIBERNATE_CHANGES.txt') `
    -Value $hibernateChanges -Encoding UTF8

  $requiredEnvironment = @(
    'AIS_BIOMETRIC_MASTER_KEY_BASE64 (32-byte AES key, Base64)',
    'AIS_BIOMETRIC_KEY_VERSION',
    'AIS_BIOMETRIC_MATCHER_CLASS (wajib jika fingerprint diaktifkan)',
    'AIS_BIOMETRIC_FACE_THRESHOLD',
    'AIS_BIOMETRIC_LIVENESS_THRESHOLD'
  )
  $manifestLines = @(
    "Bundle: $bundleName",
    "Dibuat: $((Get-Date).ToString('o'))",
    "Backend source: $BackendRoot",
    "SVN revision PosApi: $svnRevision",
    "Sumber PosApi: $posApiSourceLabel",
    '',
    'ISI:',
    '- PosApi beserta seluruh inner class hasil kompilasi',
    '- BiometricApi dan GerbangPesantrenApi beserta inner class',
    '- primitive crypto/matcher biometrik',
    '- entity BiometricCredential, BiometricEvent, IzinGerbangPesantren',
    '- HIBERNATE_CHANGES.txt berisi mapping yang harus dipastikan pada konfigurasi server existing',
    '',
    'ENVIRONMENT PRODUKSI (nilai secret tidak ada di bundle):'
  ) + ($requiredEnvironment | ForEach-Object { "- $_" }) + @(
    '',
    'DEPLOY:',
    '1. Cadangkan database dan WEB-INF/classes server.',
    '2. Set environment produksi melalui secret manager.',
    '3. Salin isi WEB-INF/classes dari bundle ke WEB-INF/classes aplikasi.',
    '4. Periksa HIBERNATE_CHANGES.txt; pertahankan hibernate.cfg.xml server dan kredensial existing.',
    '5. Restart AIS agar Hibernate membuat/memperbarui struktur tabel.',
    '6. Panggil action biometrik_kemampuan; seluruh provider yang dipakai harus ready.',
    '7. Jalankan UAT fisik sebelum mengaktifkan kewajiban biometrik.',
    '',
    'ROLLBACK:',
    '- Kembalikan backup WEB-INF/classes dan database jika migrasi/health check gagal.',
    '- Nonaktifkan kebijakan biometrik sampai provider kembali sehat.',
    '',
    'CATATAN: Bundle ini tidak memuat password, token, master key, template, probe, atau data biometrik.'
  )
  Set-Content -LiteralPath (Join-Path $bundleRoot 'MANIFEST.txt') `
    -Value $manifestLines -Encoding UTF8

  $forbiddenFiles = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
    Where-Object { $_.Name -match '(^|\.)((env)|(properties))$|hibernate\.cfg\.xml$' })
  if ($forbiddenFiles.Count -gt 0) {
    throw "Paket memuat file konfigurasi terlarang: $($forbiddenFiles.FullName -join ', ')"
  }

  $hashFile = Join-Path $bundleRoot 'SHA256SUMS.txt'
  $filesToHash = @(Get-ChildItem -LiteralPath $bundleRoot -Recurse -File |
    Where-Object { $_.FullName -ne $hashFile } |
    Sort-Object FullName)
  $hashLines = foreach ($file in $filesToHash) {
    $relative = $file.FullName.Substring($bundleRoot.Length + 1).Replace('\', '/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
  }
  Set-Content -LiteralPath $hashFile -Value $hashLines -Encoding ASCII

  $zipPath = "$bundleRoot.zip"
  Compress-Archive -LiteralPath $bundleRoot -DestinationPath $zipPath -CompressionLevel Optimal
  $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath "$zipPath.sha256" -Value "$zipHash  $([IO.Path]::GetFileName($zipPath))" -Encoding ASCII

  Write-Host "PASS: bundle backend biometrik dibuat." -ForegroundColor Green
  Write-Host "Folder : $bundleRoot"
  Write-Host "ZIP    : $zipPath"
  Write-Host "SHA-256: $zipHash"
} finally {
  if (Test-Path -LiteralPath $scratchRoot) {
    $resolvedScratch = [System.IO.Path]::GetFullPath($scratchRoot)
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $scratchLeaf = [System.IO.Path]::GetFileName($resolvedScratch)
    if (-not $resolvedScratch.StartsWith(
        $resolvedTemp,
        [System.StringComparison]::OrdinalIgnoreCase
      ) -or -not $scratchLeaf.StartsWith('ais-biometric-package-')) {
      throw "Scratch directory tidak aman untuk dihapus: $resolvedScratch"
    }
    Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
  }
}
