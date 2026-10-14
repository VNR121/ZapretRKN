# check_connectivity.ps1
$outFile = Join-Path $env:TEMP "zapret_connectivity.txt"
$tmpFile = "$outFile.tmp"

$targets = @(
    "https://www.youtube.com",
    "https://www.google.com",
    "https://www.cloudflare.com",
    "https://discord.com"
)

function Test-Url {
    param([string]$Url)
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        $code = & curl.exe -s -o NUL -w "%{http_code}" --max-time 6 $Url 2>$null
        return ($code -match '^(2|3)\d{2}$')
    } else {
        try {
            $r = Invoke-WebRequest -Uri $Url -TimeoutSec 6 -UseBasicParsing -MaximumRedirection 3
            return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 400)
        } catch { return $false }
    }
}

$ok = 0
foreach ($t in $targets) { if (Test-Url -Url $t) { $ok++ } }

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
# атомарная запись (tmp + move): формат совместим с парсером трея ^(\d+)\|(\d+)\|(\d+)$
[System.IO.File]::WriteAllText($tmpFile, "$ok|$($targets.Count)|$ts", [System.Text.Encoding]::ASCII)
Move-Item -Path $tmpFile -Destination $outFile -Force
