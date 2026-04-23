$sonarrUrl = "http://localhost:8989"
$sonarrApi = "2ac6994b6a224d5d84ebd4c7abd7381c"
$h = @{ "X-Api-Key" = $sonarrApi }

# Find all completed/stuck queue items
Write-Output "=== Finding stuck completed items ==="
$stuckIds = @()
$page = 1
do {
    $q = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue?page=$page&pageSize=500&includeUnknownSeriesItems=true" -Headers $h -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.status -eq "completed") {
            $name = $item.title
            if ($name.Length -gt 70) { $name = $name.Substring(0, 70) + "..." }
            Write-Output "  $name (ID: $($item.id))"
            $stuckIds += $item.id
        }
    }
    $page++
} while ($q.records.Count -eq 500)

Write-Output ""
Write-Output "Found $($stuckIds.Count) stuck completed items."

if ($stuckIds.Count -eq 0) { exit }

# Remove from queue WITHOUT blocklist so Sonarr rescans fresh
Write-Output "Removing from queue (no blocklist)..."
foreach ($id in $stuckIds) {
    try {
        Invoke-RestMethod -Uri "$sonarrUrl/api/v3/queue/$($id)?removeFromClient=false&blocklist=false&skipRedownload=false" -Method DELETE -Headers $h -TimeoutSec 30 | Out-Null
    } catch {
        # May fail if already gone
    }
}
Write-Output "  Done."

# Trigger fresh scan
Write-Output ""
Write-Output "Triggering download scan..."
$sh = @{ "X-Api-Key" = $sonarrApi; "Content-Type" = "application/json" }
Invoke-RestMethod -Uri "$sonarrUrl/api/v3/command" -Method POST -Headers $sh -Body '{"name":"DownloadedEpisodesScan"}' -TimeoutSec 30 | Out-Null
Write-Output "  Scan triggered."
