$qbtUrl = "http://localhost:8090"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$torrents = Invoke-RestMethod -Uri "$qbtUrl/api/v2/torrents/info" -WebSession $session
$dl = $torrents | Where-Object { $_.state -in @("downloading", "stalledDL", "forcedDL") }

if ($dl.Count -eq 0) {
    Write-Output "No downloading torrents to reannounce."
    exit
}

$hashes = ($dl | ForEach-Object { $_.hash }) -join "|"
Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/reannounce" -Method POST -Body "hashes=$hashes" -WebSession $session -UseBasicParsing -ContentType "application/x-www-form-urlencoded" | Out-Null

$stalled = ($dl | Where-Object { $_.dlspeed -eq 0 }).Count
$active = $dl.Count - $stalled
Write-Output "Reannounced $($dl.Count) torrents ($active active, $stalled stalled)"
