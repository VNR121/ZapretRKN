# update_engine.ps1 - скачивает последний winws.exe + .bin из Flowseal
$ErrorActionPreference = "Stop"

$root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$binDir    = Join-Path $root "bin"
$backupDir = Join-Path $root "utils\backup"
$repo      = "Flowseal/zapret-discord-youtube"
$apiUrl    = "https://api.github.com/repos/$repo/releases/latest"

Write-Host "Получаю информацию о последнем релизе..."
try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "ZapretRKN" } -TimeoutSec 15
} catch {
    Write-Host "[ОШИБКА] Не удалось получить информацию о релизе: $_"
    exit 1
}

$tag = $release.tag_name
$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
if (-not $asset) {
    Write-Host "[ОШИБКА] В релизе $tag нет ZIP-архива."
    exit 1
}

Write-Host "Релиз: $tag"
Write-Host "Скачиваю: $($asset.name) ($([math]::Round($asset.size/1MB, 2)) MB)"

$tempZip = Join-Path $env:TEMP "zapret_engine_$tag.zip"
$tempDir = Join-Path $env:TEMP "zapret_engine_$tag"

if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }

try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -TimeoutSec 120
} catch {
    Write-Host "[ОШИБКА] Не удалось скачать: $_"
    exit 1
}

Write-Host "Распаковываю..."
try {
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
} catch {
    Write-Host "[ОШИБКА] Не удалось распаковать: $_"
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    exit 1
}

$newBin = Get-ChildItem -Path $tempDir -Directory -Recurse | Where-Object { $_.Name -eq "bin" } | Select-Object -First 1
if (-not $newBin) {
    Write-Host "[ОШИБКА] В архиве нет папки bin."
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

if (Test-Path $binDir) {
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $oldBackup = Join-Path $backupDir "bin_backup_$stamp"
    Copy-Item -Path $binDir -Destination $oldBackup -Recurse -Force
    Write-Host "Бэкап старого bin: $oldBackup"
} else {
    New-Item -ItemType Directory -Path $binDir | Out-Null
}

Write-Host "Копирую новые файлы в bin\..."

function Copy-WithRetry {
    param($src, $dst, $maxAttempts = 5)
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            Copy-Item -Path $src -Destination $dst -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            if ($i -lt $maxAttempts) {
                Write-Host "  Попытка $i не удалась, ждём 3 сек..."
                Start-Sleep -Seconds 3
            } else {
                Write-Host "[ОШИБКА] Не удалось скопировать после $maxAttempts попыток: $_"
                return $false
            }
        }
    }
}

if (-not (Copy-WithRetry -src (Join-Path $newBin.FullName "*") -dst $binDir)) {
    Write-Host ""
    Write-Host "Рекомендация: перезагрузите ПК и запустите обновление снова."
    exit 1
}

$tag | Out-File -FilePath (Join-Path $binDir "engine_version.txt") -Encoding UTF8

Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Готово. Версия движка: $tag"