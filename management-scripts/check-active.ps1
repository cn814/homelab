$qbtUrl = "http://localhost:8090"
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

$prefs = Invoke-RestMethod -Uri "$qbtUrl/api/v2/app/preferences" -WebSession $session
$info = Invoke-RestMethod -Uri "$qbtUrl/api/v2/transfer/info" -WebSession $session
$torrents = Invoke-RestMethod -Uri "$qbtUrl/api/v2/torrents/info" -WebSession $session

$active = $torrents | Where-Object { $_.dlspeed -gt 0 }
$totalSpeed = [math]::Round($info.dl_info_speed / 1MB, 2)

Write-Output "=== CURRENT SETTINGS ==="
Write-Output "  max_active_downloads: $($prefs.max_active_downloads)"
Write-Output "  max_active_torrents: $($prefs.max_active_torrents)"
Write-Output ""
Write-Output "=== ACTUAL ACTIVITY ==="
Write-Output "  Total download speed: $totalSpeed MB/s"
Write-Output "  Torrents with active transfer: $($active.Count)"
Write-Output ""
Write-Output "=== PER-TORRENT BREAKDOWN ==="

foreach ($t in $active | Sort-Object -Property dlspeed -Descending) {
    $speed = [math]::Round($t.dlspeed / 1MB, 2)
    $pct = [math]::Round($t.progress * 100, 1)
    $seeds = $t.num_complete
    $shortName = $t.name
    if ($shortName.Length -gt 45) { $shortName = $shortName.Substring(0, 45) + "..." }
    Write-Output "  $speed MB/s | $pct% | $seeds seeds | $shortName"
}

if ($active.Count -gt 0) {
    $avgSpeed = [math]::Round($totalSpeed / $active.Count, 2)
    Write-Output ""
    Write-Output "  Avg per torrent: $avgSpeed MB/s"
}
