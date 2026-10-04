# Standalone update checker. Запускается треем, пишет результат в файл.
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serviceBat = Join-Path $root "service.bat"
$outFile = Join-Path $env:TEMP "zapret_update.txt"

Remove-Item $outFile -Force -ErrorAction SilentlyContinue
if (-not (Test-Path $serviceBat)) { exit }

$content = Get-Content $serviceBat -Raw
if ($content -notmatch 'LOCAL_VERSION=([\d\.]+)') { exit }
$local = $matches[1]

$url = "https://raw.githubusercontent.com/VNR121/ZapretRKN/main/.service/version.txt"
try {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Timeout = 8000
    $req.Headers.Add("Cache-Control", "no-cache")
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $remote = $reader.ReadToEnd().Trim()
    $reader.Close(); $resp.Close()
    if ($remote -and $remote -ne $local) {
        "$remote|$local" | Out-File -Encoding UTF8 $outFile
    }
} catch { }