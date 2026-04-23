$qbtUrl = "http://localhost:8090"
$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrKey = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrKey = "a63000fb63a240a8bcb5e7d750926379"

$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json

# Get stalled torrents with 0 seeds (skip ones that have at least 1 seed)
$dead = $torrents | Where-Object {
    $_.state -eq "stalledDL" -and
    $_.num_complete -eq 0
}

Write-Output "Found $($dead.Count) stalled torrents with 0 seeds:"
foreach ($t in $dead) {
    $pct = [math]::Round($t.progress * 100, 1)
    Write-Output "  [$pct%] $($t.name)"
}

if ($dead.Count -gt 0) {
    $hashes = ($dead | ForEach-Object { $_.hash }) -join "|"
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=true" -UseBasicParsing -TimeoutSec 60 | Out-Null
    Write-Output ""
    Write-Output "Deleted $($dead.Count) torrents from qBittorrent"

    # Wait for Sonarr/Radarr to notice
    Start-Sleep -Seconds 10

    # Blocklist warnings in Sonarr
    $sonarrRemoved = 0
    $page = 1
    do {
        $queue = (Invoke-WebRequest -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=200&apikey=$sonarrKey" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
        $warnings = $queue.records | Where-Object { $_.trackedDownloadStatus -eq "warning" }
        foreach ($item in $warnings) {
            try {
                Invoke-WebRequest -Uri "$sonarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=true&apikey=$sonarrKey" -Method DELETE -UseBasicParsing -TimeoutSec 10 | Out-Null
                $sonarrRemoved++
            } catch {}
        }
        $page++
    } while (($page - 1) * 200 -lt $queue.totalRecords)
    Write-Output "Blocklisted $sonarrRemoved items in Sonarr"

    # Blocklist warnings in Radarr
    $radarrRemoved = 0
    try {
        $rQueue = (Invoke-WebRequest -Uri "$radarrUrl/api/v3/queue?page=1&pageSize=200&apikey=$radarrKey" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
        $rWarnings = $rQueue.records | Where-Object { $_.trackedDownloadStatus -eq "warning" }
        foreach ($item in $rWarnings) {
            try {
                Invoke-WebRequest -Uri "$radarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=true&apikey=$radarrKey" -Method DELETE -UseBasicParsing -TimeoutSec 10 | Out-Null
                $radarrRemoved++
            } catch {}
        }
    } catch {}
    Write-Output "Blocklisted $radarrRemoved items in Radarr"
}

Write-Output ""
Write-Output "Done. Sonarr/Radarr will automatically search for alternatives."
