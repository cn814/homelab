$sonarrHeaders = @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$radarrHeaders = @{"X-Api-Key"="a63000fb63a240a8bcb5e7d750926379"}

# Clear Sonarr warning items
Write-Output "=== Clearing Sonarr Warnings ==="
$sq = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=100" -Headers $sonarrHeaders -TimeoutSec 15
$warnings = @($sq.records | Where-Object { $_.trackedDownloadStatus -eq "warning" })
foreach ($w in $warnings) {
    Write-Output "  Removing: $($w.title)"
    Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue/$($w.id)?removeFromClient=true&blocklist=false&skipRedownload=false" -Headers $sonarrHeaders -Method DELETE -TimeoutSec 10
}
Write-Output "Removed: $($warnings.Count)"

# Clear Radarr warning items
Write-Output ""
Write-Output "=== Clearing Radarr Warnings ==="
$rq = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue?pageSize=100" -Headers $radarrHeaders -TimeoutSec 15
$rWarnings = @($rq.records | Where-Object { $_.trackedDownloadStatus -eq "warning" })
foreach ($w in $rWarnings) {
    Write-Output "  Removing: $($w.title)"
    Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue/$($w.id)?removeFromClient=true&blocklist=false&skipRedownload=false" -Headers $radarrHeaders -Method DELETE -TimeoutSec 10
}
Write-Output "Removed: $($rWarnings.Count)"

# Check remaining
Write-Output ""
$sq2 = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=1" -Headers $sonarrHeaders -TimeoutSec 10
$rq2 = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue?pageSize=1" -Headers $radarrHeaders -TimeoutSec 10
Write-Output "Sonarr queue: $($sq2.totalRecords) | Radarr queue: $($rq2.totalRecords)"
