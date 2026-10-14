# check_updates.ps1
$ErrorActionPreference = "SilentlyContinue"

$root       = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serviceBat = Join-Path $root "service.bat"
$outFile    = Join-Path $env:TEMP "zapret_update.txt"
$tmpFile    = "$outFile.tmp"

Remove-Item $outFile, $tmpFile -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $serviceBat)) { exit }

$content = Get-Content $serviceBat -Raw
if ($content -notmatch 'LOCAL_VERSION=([\d\.]+)') { exit }
$local = $matches[1]

$url = "https://raw.githubusercontent.com/VNR121/ZapretRKN/main/.service/version.txt"

$remote = $null
try {
    $remote = (Invoke-RestMethod -Uri $url -TimeoutSec 8 -Headers @{ "Cache-Control" = "no-cache" }).Trim()
} catch { exit }

if (-not $remote) { exit }

# санитизация
$remoteClean = ($remote -replace '[^0-9.]','').Trim('.')
if (-not $remoteClean) { exit }

$isNewer = $false
try {
    if ([version]$remoteClean -gt [version]$local) { $isNewer = $true }
} catch {
    if ($remoteClean -ne $local) { $isNewer = $true }
}

if ($isNewer) {
    # атомарная запись: сначала .tmp, потом переименование,
    # чтобы трей никогда не прочитал файл в середине записи
    [System.IO.File]::WriteAllText($tmpFile, "$remoteClean|$local", [System.Text.Encoding]::ASCII)
    Move-Item -Path $tmpFile -Destination $outFile -Force
}
