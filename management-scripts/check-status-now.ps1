# Quick status check
Write-Output "=== Sonarr Latest Imports ==="
$h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=5&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
$h.records | ForEach-Object {
    Write-Output "  $($_.date) | $($_.sourceTitle)"
}

Write-Output ""
Write-Output "=== Sonarr Commands ==="
$cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$active = $cmds | Where-Object { $_.status -ne "completed" }
if ($active.Count -eq 0) { Write-Output "  None active" }
$active | ForEach-Object { Write-Output "  $($_.name): $($_.status) | started: $($_.started)" }

Write-Output ""
Write-Output "=== Sonarr Queue ==="
$q = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=200" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
Write-Output "Total: $($q.totalRecords)"
$q.records | Group-Object -Property trackedDownloadStatus | ForEach-Object { Write-Output "  $($_.Name): $($_.Count)" }

$warnings = $q.records | Where-Object { $_.trackedDownloadStatus -eq "warning" }
if ($warnings.Count -gt 0) {
    Write-Output ""
    Write-Output "=== Warning Items ==="
    $warnings | Select-Object -First 10 | ForEach-Object {
        Write-Output "  $($_.title)"
        $_.statusMessages | ForEach-Object { Write-Output "    $($_.title) - $($_.messages -join '; ')" }
    }
}

Write-Output ""
Write-Output "=== Sonarr Health ==="
$health = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/health" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$health | ForEach-Object { Write-Output "  [$($_.type)] $($_.source): $($_.message)" }

Write-Output ""
Write-Output "=== Drive Space ==="
$d = Get-PSDrive D; $e = Get-PSDrive E
Write-Output "  D: Free: $([Math]::Round($d.Free/1GB, 1)) GB"
Write-Output "  E: Free: $([Math]::Round($e.Free/1GB, 1)) GB"

Write-Output ""
Write-Output "=== Discord Notification Config ==="
$notifs = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/notification" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$notifs | ForEach-Object {
    Write-Output "  $($_.name): onGrab=$($_.onGrab) onDownload=$($_.onDownload) onImportComplete=$($_.onImportComplete)"
}
