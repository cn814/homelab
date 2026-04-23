$sonarrUrl = "http://localhost:8989"
$radarrUrl = "http://localhost:7878"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$radarrApi = "a63000fb63a240a8bcb5e7d750926379"

# === Clear orphaned ER items from Sonarr queue ===
Write-Output "=== Clearing orphaned ER items from Sonarr queue ==="
$sh = @{ "X-Api-Key" = $sonarrApi }
$page = 1
$erRemoved = 0
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownSeriesItems=true" -Headers $sh -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.title -match "^ER S01") {
            try {
                Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue/$($item.id)?removeFromClient=true&blocklist=false&skipRedownload=true" -Method DELETE -Headers $sh -TimeoutSec 30 | Out-Null
                Write-Output "  Removed: $($item.title)"
                $erRemoved++
            } catch {
                Write-Output "  Error removing: $($item.title) - $($_.Exception.Message)"
            }
        }
    }
    $page++
} while ($q.records.Count -eq 500)
Write-Output "  Removed $erRemoved ER queue items"

# === Check Radarr queue for stuck completed items ===
Write-Output ""
Write-Output "=== Radarr stuck completed items ==="
$rh = @{ "X-Api-Key" = $radarrApi }
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownMovieItems=true" -Headers $rh -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.status -eq "completed" -or $item.trackedDownloadStatus -eq "warning") {
            Write-Output "  $($item.title)"
            Write-Output "    Status: $($item.status) | TrackedStatus: $($item.trackedDownloadStatus)"
            $msgs = ($item.statusMessages | ForEach-Object { $_.title }) -join "; "
            if ($msgs) { Write-Output "    Messages: $msgs" }
        }
    }
    $page++
} while ($q.records.Count -eq 500)

# === Check Sonarr queue for stuck completed items ===
Write-Output ""
Write-Output "=== Sonarr stuck completed items ==="
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownSeriesItems=true" -Headers $sh -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.status -eq "completed" -or $item.trackedDownloadStatus -eq "warning") {
            Write-Output "  $($item.title)"
            Write-Output "    Status: $($item.status) | TrackedStatus: $($item.trackedDownloadStatus)"
            $msgs = ($item.statusMessages | ForEach-Object { $_.title }) -join "; "
            if ($msgs) { Write-Output "    Messages: $msgs" }
        }
    }
    $page++
} while ($q.records.Count -eq 500)
