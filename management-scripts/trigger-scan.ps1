# Trigger DownloadedEpisodesScan for both download paths
Write-Output "=== Triggering DownloadedEpisodesScan for /data2/Downloads ==="
$body = @{ name = "DownloadedEpisodesScan"; path = "/data2/Downloads" } | ConvertTo-Json
$result = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Method POST -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"; "Content-Type"="application/json"} -Body $body -TimeoutSec 15
Write-Output "  ID: $($result.id) | Status: $($result.status)"

Write-Output ""
Write-Output "Waiting 90 seconds for scan to complete (large folder)..."
Start-Sleep -Seconds 90

# Check result
Write-Output ""
Write-Output "=== Command Status ==="
try {
    $cmd = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command/$($result.id)" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
    Write-Output "  $($cmd.name): $($cmd.status) | Started: $($cmd.started) | Ended: $($cmd.ended)"
    if ($cmd.message) { Write-Output "  Message: $($cmd.message)" }
} catch {
    Write-Output "  Error checking: $($_.Exception.Message)"
}

# Check for new imports
Write-Output ""
Write-Output "=== Latest imports ==="
$h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=10&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
$h.records | ForEach-Object {
    Write-Output "  $($_.date) | $($_.sourceTitle)"
}
