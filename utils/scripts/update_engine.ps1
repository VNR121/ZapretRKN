# update_engine.ps1
$ErrorActionPreference = "Stop"

$root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$binDir    = Join-Path $root "bin"
$backupDir = Join-Path $root "utils\backup"
$repo      = "Flowseal/zapret-discord-youtube"
$apiUrl    = "https://api.github.com/repos/$repo/releases/latest"

Write-Host "Получаю информацию о релизе..."
try { $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "ZapretRKN" } -TimeoutSec 15 }
catch { Write-Host "[ОШИБКА] $_"; exit 1 }

$tag   = $release.tag_name
$asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
if (-not $asset) { Write-Host "[ОШИБКА] Нет ZIP"; exit 1 }

Write-Host "Релиз: $tag"

$tempZip = Join-Path $env:TEMP "zapret_engine_$tag.zip"
$tempDir = Join-Path $env:TEMP "zapret_engine_$tag"
$staging = Join-Path $root "bin_staging"
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }

try {
    try { Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -TimeoutSec 120 }
    catch { Write-Host "[ОШИБКА] $_"; exit 1 }

    Write-Host "Распаковываю..."
    try { Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force }
    catch { Write-Host "[ОШИБКА] $_"; exit 1 }

    $newBin = Get-ChildItem -Path $tempDir -Directory -Recurse | Where-Object { $_.Name -eq "bin" } | Select-Object -First 1
    if (-not $newBin) { Write-Host "[ОШИБКА] Нет папки bin в архиве."; exit 1 }

    foreach ($r in @("winws.exe", "WinDivert64.sys")) {
        if (-not (Test-Path (Join-Path $newBin.FullName $r))) {
            Write-Host "[ОШИБКА] В архиве нет $r"
            exit 1
        }
    }

    # --- Стадирование: собираем новый bin рядом, НЕ трогая рабочий ---
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Copy-Item -Path (Join-Path $newBin.FullName "*") -Destination $staging -Recurse -Force

    $stageOk = $true
    foreach ($r in @("winws.exe", "WinDivert64.sys")) {
        if (-not (Test-Path (Join-Path $staging $r))) { $stageOk = $false }
    }
    if (-not $stageOk) {
        Get-ChildItem -Path $staging -ErrorAction SilentlyContinue | Select-Object Name | ForEach-Object {
            Write-Host "  - $($_.Name)"
        }
        Write-Host "[ОШИБКА] Стадирование не удалось. Содержимое выше."
        exit 1
    }

    # --- Бэкап старого bin (до удаления!) ---
    $backup = $null
    if (Test-Path $binDir) {
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backup = Join-Path $backupDir "bin_backup_$stamp"
        Copy-Item -Path $binDir -Destination $backup -Recurse -Force
        Write-Host "Бэкап: $backup"
    }

    # --- Обмен: удаляем старый ТОЛЬКО после успешного стадирования ---
    $swapOk = $true
    try {
        if (Test-Path $binDir) { Remove-Item -Path $binDir -Recurse -Force -ErrorAction Stop }
        Move-Item -Path $staging -Destination $binDir -ErrorAction Stop
        foreach ($r in @("winws.exe", "WinDivert64.sys")) {
            if (-not (Test-Path (Join-Path $binDir $r))) { throw "Не найден $r после обмена." }
        }
    } catch {
        $swapOk = $false
        Write-Host "[ОШИБКА] $_"
    }

    if (-not $swapOk) {
        # --- Откат: восстанавливаем старый bin из бэкапа ---
        if ($backup -and (Test-Path $backup)) {
            Remove-Item -Path $binDir -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item -Path $backup -Destination $binDir -Recurse -Force
            Write-Host "[ОТКАТ] Старый движок восстановлен из бэкапа."
        } else {
            Write-Host "[ОШИБКА] Откат невозможен: бэкапа нет."
        }
        exit 1
    }

    [System.IO.File]::WriteAllText((Join-Path $binDir "engine_version.txt"), $tag, [System.Text.Encoding]::ASCII)

    Write-Host ""
    Write-Host "Готово. Версия движка: $tag"
    exit 0
} finally {
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue
}
