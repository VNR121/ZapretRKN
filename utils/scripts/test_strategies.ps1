# test_strategies.ps1 - прогоняет все стратегии, возвращает имя лучшей
$ErrorActionPreference = "SilentlyContinue"

$root      = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stratDir  = Join-Path $root "strategies"
$binDir    = Join-Path $root "bin"
$listsDir  = Join-Path $root "lists"
$generalBat = Join-Path $root "general.bat"

$targets = @(
    @{ Name = "YouTube"; Url = "https://www.youtube.com" },
    @{ Name = "Discord"; Url = "https://discord.com" },
    @{ Name = "Google";  Url = "https://www.google.com" }
)

function Stop-Winws {
    Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 500
}

function Test-Curl {
    param([string]$Url)
    $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 5 $Url 2>$null
    if ($code -match '^(2|3)\d{2}$') { return $true } else { return $false }
}

function Test-Strategy {
    param([string]$BatPath)

    $bat = Get-Content -Path $BatPath -Raw

    # Извлекаем строку с winws.exe и аргументы
    $lines = $bat -split "`r?`n"
    $winwsLine = $lines | Where-Object { $_ -match "winws\.exe" } | Select-Object -First 1
    if (-not $winwsLine) { return 0 }

    # Собираем все строки аргументов (многострочная команда с ^)
    $startIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "winws\.exe") { $startIdx = $i; break }
    }
    $fullCmd = $lines[$startIdx]
    for ($i = $startIdx + 1; $i -lt $lines.Count; $i++) {
        $fullCmd += " " + $lines[$i].TrimEnd("^").Trim()
        if (-not $lines[$i].TrimEnd().EndsWith("^")) { break }
    }

    # Убираем start "..." /min и кавычки
    $fullCmd = $fullCmd -replace '.*winws\.exe"?', 'winws.exe'
    $fullCmd = $fullCmd -replace '"%BIN%', '"' + $binDir
    $fullCmd = $fullCmd -replace '"%LISTS%', '"' + $listsDir
    $fullCmd = $fullCmd -replace '"%BIN%', '"' + $binDir

    # Заменяем переменные BIN и LISTS
    $fullCmd = $fullCmd.Replace('%BIN%', $binDir + "\")
    $fullCmd = $fullCmd.Replace('%LISTS%', $listsDir + "\")
    $fullCmd = $fullCmd.Replace('%GameFilterTCP%', '12').Replace('%GameFilterUDP%', '12')

    # Убираем префикс winws.exe
    $argPart = $fullCmd -replace '^\s*winws\.exe\s*', ''

    $exePath = Join-Path $binDir "winws.exe"
    if (-not (Test-Path $exePath)) { return 0 }

    try {
        Start-Process -FilePath $exePath -ArgumentList $argPart -WorkingDirectory $binDir -WindowStyle Hidden | Out-Null
    } catch { return 0 }

    Start-Sleep -Seconds 3

    $ok = 0
    foreach ($t in $targets) {
        if (Test-Curl -Url $t.Url) { $ok++ }
    }

    Stop-Winws
    Start-Sleep -Milliseconds 700
    return $ok
}

# --- Main ---
$strategies = @(Get-ChildItem -Path $stratDir -Filter "*.bat" | Sort-Object Name)
if ($strategies.Count -eq 0) {
    Write-Host "[ОШИБКА] В папке strategies нет .bat"
    exit 1
}

Write-Host ""
Write-Host "Тестирование стратегий. Это займёт ~1-2 минуты."
Write-Host ""

$results = @()
foreach ($s in $strategies) {
    Write-Host ("[{0,-20}] тестирую..." -f $s.Name) -NoNewline
    $score = Test-Strategy -BatPath $s.FullName
    $results += [PSCustomObject]@{ Name = $s.Name; Score = $score }
    Write-Host (" OK: $score / $($targets.Count)")
}

Write-Host ""
Write-Host "=== РЕЗУЛЬТАТЫ ==="
$results | Sort-Object Score -Descending | ForEach-Object {
    Write-Host ("  {0,-20} {1} / {2}" -f $_.Name, $_.Score, $targets.Count)
}
Write-Host ""

$best = $results | Sort-Object Score -Descending | Select-Object -First 1
if ($best.Score -eq 0) {
    Write-Host "[РЕЗУЛЬТАТ] Ни одна стратегия не сработала."
    Write-Host "Проверьте, что провайдер не блокирует всё полностью, или запустите диагностику (пункт 11)."
    exit 2
}

Write-Host "[РЕЗУЛЬТАТ] Лучшая стратегия: $($best.Name) ($($best.Score) / $($targets.Count))"
$best.Name | Out-File -FilePath (Join-Path $env:TEMP "zapret_best_strategy.txt") -Encoding UTF8 -Force
exit 0