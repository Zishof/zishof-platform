$ErrorActionPreference = 'Stop'

$repoRoot = 'C:\opt\CodeBaseDesktopDanMobile'
$artifactRoot = Join-Path $repoRoot 'apps\ebisnis\release-artifacts\semua-varian\1.33.83'
$statusFile = Join-Path $repoRoot '.tmp-release-status.txt'
$releaseNotes = Join-Path $repoRoot 'docs\pos\2026-08-26-release-desktop-albahjah-ebisnis-1.33.83.md'
$tag = 'v1.33.83-build141'
$title = 'POS Desktop Al-Bahjah dan eBisnis v1.33.83 (build 141)'

Set-Location -LiteralPath $repoRoot
Remove-Item -LiteralPath $statusFile -Force -ErrorAction SilentlyContinue

function Find-Installer($name) {
    return Get-ChildItem -LiteralPath $artifactRoot -Filter $name -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Run-Build($variant) {
    $log = Join-Path $repoRoot ('.tmp-build-' + $variant + '-1.33.83.log')
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'apps\ebisnis\tool\build_semua_varian.ps1') -SkipAndroid -Hanya $variant *> $log
    if ($LASTEXITCODE -ne 0) {
        throw ('Build ' + $variant + ' gagal. Periksa ' + $log)
    }
}

$albahjah = Find-Installer 'Al-Bahjah-POS-Setup-1.33.83.exe'
$ebisnis = Find-Installer 'eBisnis-Setup-1.33.83.exe'

if ($null -eq $albahjah) {
    Run-Build 'albahjah'
    $albahjah = Find-Installer 'Al-Bahjah-POS-Setup-1.33.83.exe'
}
if ($null -eq $ebisnis) {
    Run-Build 'ebisnis'
    $ebisnis = Find-Installer 'eBisnis-Setup-1.33.83.exe'
}
if ($null -eq $albahjah -or $null -eq $ebisnis) {
    throw 'Installer 1.33.83 belum lengkap setelah proses build.'
}

& git diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check gagal.' }

& git add -- 'apps/ebisnis/pubspec.yaml' 'docs/pos/2026-08-26-release-desktop-albahjah-ebisnis-1.33.83.md'
if ($LASTEXITCODE -ne 0) { throw 'git add gagal.' }

& git diff --cached --quiet
$cachedExit = $LASTEXITCODE
if ($cachedExit -eq 1) {
    & git commit -m 'release(pos): desktop albahjah dan ebisnis 1.33.83'
    if ($LASTEXITCODE -ne 0) { throw 'git commit gagal.' }
} elseif ($cachedExit -ne 0) {
    throw 'Pemeriksaan staged changes gagal.'
}

$branch = (& git branch --show-current).Trim()
if ([string]::IsNullOrEmpty($branch)) { throw 'Branch Git tidak terdeteksi.' }
& git push origin $branch
if ($LASTEXITCODE -ne 0) { throw 'git push gagal.' }

& gh release view $tag --repo 'Zishof/zishof-platform' *> $null
if ($LASTEXITCODE -eq 0) {
    & gh release upload $tag $albahjah.FullName $ebisnis.FullName --clobber --repo 'Zishof/zishof-platform'
    if ($LASTEXITCODE -ne 0) { throw 'Upload ulang aset GitHub Release gagal.' }
    & gh release edit $tag --title $title --notes-file $releaseNotes --repo 'Zishof/zishof-platform'
    if ($LASTEXITCODE -ne 0) { throw 'Pembaruan GitHub Release gagal.' }
} else {
    & gh release create $tag $albahjah.FullName $ebisnis.FullName --target $branch --title $title --notes-file $releaseNotes --repo 'Zishof/zishof-platform'
    if ($LASTEXITCODE -ne 0) { throw 'Pembuatan GitHub Release gagal.' }
}

$commit = (& git rev-parse HEAD).Trim()
$alHash = (Get-FileHash -LiteralPath $albahjah.FullName -Algorithm SHA256).Hash
$ebHash = (Get-FileHash -LiteralPath $ebisnis.FullName -Algorithm SHA256).Hash
$lines = @(
    'STATUS=OK',
    ('VERSION=1.33.83+141'),
    ('TAG=' + $tag),
    ('COMMIT=' + $commit),
    ('BRANCH=' + $branch),
    ('ALBAHJAH=' + $albahjah.FullName),
    ('ALBAHJAH_SIZE=' + $albahjah.Length),
    ('ALBAHJAH_SHA256=' + $alHash),
    ('EBISNIS=' + $ebisnis.FullName),
    ('EBISNIS_SIZE=' + $ebisnis.Length),
    ('EBISNIS_SHA256=' + $ebHash),
    ('URL=https://github.com/Zishof/zishof-platform/releases/tag/' + $tag)
)
Set-Content -LiteralPath $statusFile -Value $lines -Encoding UTF8
