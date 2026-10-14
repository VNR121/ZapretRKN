# test_strategies.ps1
$ErrorActionPreference = "SilentlyContinue"

$root        = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$stratDir    = Join-Path $root "strategies"
$generalBat  = Join-Path $root "general.bat"
$bestFile    = Join-Path $env:TEMP "zapret_best_strategy.txt"

$targets = @(
    "https://www.youtube.com",
    "https://discord.com",
    "https://www.google.com"
)

if (-not (Test-Path $generalBat)) { Write-Host "[ОШИБКА] Нет general.bat"; exit 1 }
$originalGeneral = [System.IO.File]::ReadAllBytes($generalBat)

# на случай прошлого прерванного прогона
Remove-Item $bestFile -Force -ErrorAction SilentlyContinue

function Write-Atomic([string]$Path, [string]$Text) {
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.Encoding]::ASCII)
    Move-Item -Path $tmp -Destination $Path -Force
}

function Stop-Winws {
    Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 700
    foreach ($svc in @("WinDivert", "WinDivert14")) {
        & sc.exe query $svc 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { & sc.exe stop $svc 2>$null | Out-Null }
    }
    Start-Sleep -Milliseconds 500
}

function Wait-Winws {
    param([int]$TimeoutSec = 6)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        if (Get-Process -Name winws -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Milliseconds 300
    }
    return $false
}

function Test-Url {
    param([string]$Url)
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 5 $Url 2>$null
        return ($code -match '^(2|3)\d{2}$')
    } else {
        try { (Invoke-WebRequest -Uri $Url -TimeoutSec 5 -UseBasicParsing).StatusCode -lt 400 }
        catch { return $false }
    }
}

function Test-Strategy {
    param([string]$BatPath)
    Copy-Item -Path $BatPath -Destination $generalBat -Force
    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "`"$generalBat`" notray" `
        -WindowStyle Hidden -PassThru
    if (-not (Wait-Winws -TimeoutSec 6)) {
        try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } } catch { }
        Stop-Winws
        return $null
    }
    Start-Sleep -Milliseconds 500
    $passed = @()
    foreach ($t in $targets) { $passed += [bool](Test-Url -Url $t) }
    try { if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } } catch { }
    Stop-Winws
    return $passed
}

$strategies = @(Get-ChildItem -Path $stratDir -Filter "*.bat" | Sort-Object Name)
if ($strategies.Count -eq 0) {
    Write-Host "[ОШИБКА] Нет стратегий"
    [System.IO.File]::WriteAllBytes($generalBat, $originalGeneral)
    exit 1
}

Write-Host ""
Write-Host "Тестирование стратегий. Это займёт ~1-2 минуты."
Write-Host ""

$results = @()
try {
    foreach ($s in $strategies) {
        Write-Host ("[{0,-20}] тестирую..." -f $s.Name) -NoNewline
        $passed = Test-Strategy -BatPath $s.FullName
        if ($null -eq $passed) {
            $results += [PSCustomObject]@{ Name = $s.Name; Score = 0; Passed = @($false) * $targets.Count }
            Write-Host " не запустилась"
        } else {
            $score = ($passed | Where-Object { $_ }).Count
            $results += [PSCustomObject]@{ Name = $s.Name; Score = $score; Passed = $passed }
            Write-Host (" OK: $score / $($targets.Count)")
        }
    }
} finally {
    # в любом случае (включая Ctrl+C) возвращаем исходный general.bat
    [System.IO.File]::WriteAllBytes($generalBat, $originalGeneral)
    Stop-Winws
}

Write-Host ""
Write-Host "=== РЕЗУЛЬТАТЫ ==="
$results | Sort-Object Score -Descending | ForEach-Object {
    $marks = ($_.Passed | ForEach-Object { if ($_) { "+" } else { "-" } }) -join " "
    Write-Host ("  {0,-20} {1}/{2}  [{3}]" -f $_.Name, $_.Score, $targets.Count, $marks)
}
Write-Host ""
Write-Host "  Сайты: " + (($targets | ForEach-Object { ([System.Uri]$_).Host }) -join ", ")
Write-Host ""

$best = $results | Sort-Object Score -Descending | Select-Object -First 1
if ($best.Score -eq 0) { Write-Host "[РЕЗУЛЬТАТ] Ни одна не сработала."; exit 2 }

Write-Host "[РЕЗУЛЬТАТ] Лучшая: $($best.Name) ($($best.Score) / $($targets.Count))"
Write-Atomic -Path $bestFile -Text $best.Name
exit 0
