# Cleanup-DeadTorrents.ps1
# Automatically removes dead torrents (0 seeds) and blocklists them in Sonarr/Radarr
# so they re-search for alternatives. Also reannounces stalled torrents that have
# partial progress to try to revive them.
# Run via Task Scheduler every 2 hours.

param(
    [int]$MinAgeMinutes = 120  # Only remove torrents that have been actively downloading with 0 seeds for this long
)

$qbtUrl = "http://localhost:8090"
$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrKey = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrKey = "a63000fb63a240a8bcb5e7d750926379"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Output "[$timestamp] Starting dead torrent cleanup..."

# Get all torrents
try {
    $torrents = (Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/info" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
} catch {
    Write-Output "ERROR: Cannot reach qBittorrent API"
    exit 1
}

$now = [int](Get-Date -UFormat %s)

# === 1. Remove dead torrents (0 seeds, actively trying to download) ===
# Only remove torrents that are ACTIVELY downloading or stalled (not queued)
# Queued torrents haven't had a chance to connect yet - leave them alone
# Also remove torrents stuck downloading metadata (dead magnet links)
$dead = $torrents | Where-Object {
    (
        ($_.state -in @("downloading", "stalledDL") -and
         $_.num_complete -eq 0 -and
         $_.num_incomplete -eq 0 -and
         $_.progress -eq 0)
        -or
        ($_.state -eq "metaDL")
    ) -and
    ($now - $_.added_on) -gt ($MinAgeMinutes * 60)
}

$deleted = 0
if ($dead.Count -gt 0) {
    Write-Output "[$timestamp] Found $($dead.Count) dead torrents (0 seeds, older than $MinAgeMinutes min)"
    for ($i = 0; $i -lt $dead.Count; $i += 20) {
        $batch = $dead[$i..([Math]::Min($i + 19, $dead.Count - 1))]
        $hashes = ($batch | ForEach-Object { $_.hash }) -join "|"
        try {
            Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=true" -UseBasicParsing -TimeoutSec 60 | Out-Null
            $deleted += $batch.Count
        } catch {}
        Start-Sleep -Seconds 3
    }
    Write-Output "[$timestamp] Deleted $deleted dead torrents"
} else {
    Write-Output "[$timestamp] No dead torrents found"
}

# === 2. Reannounce stalled torrents that have partial progress ===
$stalledPartial = $torrents | Where-Object {
    $_.state -eq "stalledDL" -and $_.progress -gt 0 -and $_.progress -lt 1 -and $_.num_complete -gt 0
}
if ($stalledPartial.Count -gt 0) {
    $hashes = ($stalledPartial | ForEach-Object { $_.hash }) -join "|"
    try {
        Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/reannounce" -Method POST -Body "hashes=$hashes" -UseBasicParsing -TimeoutSec 10 | Out-Null
        Write-Output "[$timestamp] Reannounced $($stalledPartial.Count) stalled torrents with partial progress"
    } catch {}
}

# === 3. Recheck stalled torrents at 100% (stuck completing) ===
$stalledComplete = $torrents | Where-Object {
    $_.state -eq "stalledDL" -and $_.progress -eq 1
}
if ($stalledComplete.Count -gt 0) {
    $hashes = ($stalledComplete | ForEach-Object { $_.hash }) -join "|"
    try {
        Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/recheck" -Method POST -Body "hashes=$hashes" -UseBasicParsing -TimeoutSec 10 | Out-Null
        Write-Output "[$timestamp] Rechecking $($stalledComplete.Count) stalled torrents at 100%"
    } catch {}
}

# === 4. Remove orphaned torrents (files already imported/moved) ===
$orphaned = $torrents | Where-Object { $_.state -eq "missingFiles" }
if ($orphaned.Count -gt 0) {
    $hashes = ($orphaned | ForEach-Object { $_.hash }) -join "|"
    try {
        Invoke-WebRequest -Uri "$qbtUrl/api/v2/torrents/delete" -Method POST -Body "hashes=$hashes&deleteFiles=false" -UseBasicParsing -TimeoutSec 60 | Out-Null
        $deleted += $orphaned.Count
        Write-Output "[$timestamp] Removed $($orphaned.Count) orphaned torrents (missingFiles)"
    } catch {}
}

# === 5. Blocklist removed items in Sonarr/Radarr ===
if ($deleted -gt 0) {
    Start-Sleep -Seconds 15

    $sonarrRemoved = 0
    $page = 1
    do {
        try {
            $queue = (Invoke-WebRequest -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=200&apikey=$sonarrKey" -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
            $warnings = $queue.records | Where-Object { $_.trackedDownloadStatus -eq "warning" }
            foreach ($item in $warnings) {
                try {
                    Invoke-WebRequest -Uri "$sonarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=true&apikey=$sonarrKey" -Method DELETE -UseBasicParsing -TimeoutSec 10 | Out-Null
                    $sonarrRemoved++
                } catch {}
            }
            $page++
        } catch { break }
    } while (($page - 1) * 200 -lt $queue.totalRecords)
    Write-Output "[$timestamp] Blocklisted $sonarrRemoved items in Sonarr"

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
    Write-Output "[$timestamp] Blocklisted $radarrRemoved items in Radarr"
}

Write-Output "[$timestamp] Cleanup complete: $deleted removed, stalled reannounced/rechecked"
