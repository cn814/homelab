$qbtUrl = "http://localhost:8090"
$sonarrUrl = "http://localhost:8989"
$sonarrKey = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrUrl = "http://localhost:7878"
$radarrKey = "a63000fb63a240a8bcb5e7d750926379"

$torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
$now = [int](Get-Date -UFormat %s)

# Stuck on metadata for over 2 hours = dead magnet links
$meta = $torrents | Where-Object { $_.state -eq "metaDL" -and ($now - $_.added_on) -gt 7200 }

Write-Output "Removing $($meta.Count) torrents stuck on metadata (2h+):"
foreach ($t in $meta) {
    $age = [math]::Round(($now - $t.added_on) / 3600, 1)
    Write-Output "  [$($age)h] $($t.name)"
}

if ($meta.Count -gt 0) {
    $hashes = ($meta | ForEach-Object { $_.hash }) -join "|"
    Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=true" -UseBasicParsing -TimeoutSec 60 | Out-Null
    Write-Output ""
    Write-Output "Deleted $($meta.Count) from qBittorrent"

    Start-Sleep -Seconds 10

    # Blocklist in Sonarr
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
    Write-Output "Blocklisted $sonarrRemoved in Sonarr"

    # Blocklist in Radarr
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
    Write-Output "Blocklisted $radarrRemoved in Radarr"
}

Write-Output ""
Write-Output "Done. Sonarr/Radarr will search for alternatives."
