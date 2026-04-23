# Quick status check
$h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=5&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
Write-Output "=== Latest Sonarr Imports ==="
$h.records | ForEach-Object {
    Write-Output "  $($_.date) | $($_.sourceTitle)"
}

# Count imports since the fix (after 08:10 UTC = 15:50 local after the stuck commands were cleared)
$h2 = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=200&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
$newImports = $h2.records | Where-Object { $_.date -gt "2026-02-16T15:30:00Z" }
Write-Output ""
Write-Output "Imports since fix: $($newImports.Count)"

# Queue status
$q = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=200" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
Write-Output ""
Write-Output "=== Queue ==="
Write-Output "Total: $($q.totalRecords)"
$q.records | Group-Object -Property status | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}

# Active commands
$cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$active = $cmds | Where-Object { $_.status -ne "completed" }
Write-Output ""
Write-Output "=== Active Commands ==="
$active | ForEach-Object {
    Write-Output "  $($_.name): $($_.status)"
}
