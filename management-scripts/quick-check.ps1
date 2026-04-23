# Quick Sonarr status check
$headers = @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers $headers -TimeoutSec 10
Write-Output "=== Active Commands ==="
$cmds | Where-Object { $_.status -ne "completed" } | ForEach-Object {
    Write-Output "  $($_.name): $($_.status)"
}
if (-not ($cmds | Where-Object { $_.status -ne "completed" })) {
    Write-Output "  None"
}

$q = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=1" -Headers $headers -TimeoutSec 10
Write-Output ""
Write-Output "Queue: $($q.totalRecords)"
