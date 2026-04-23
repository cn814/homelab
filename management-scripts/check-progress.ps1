# Check active commands
$cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$active = $cmds | Where-Object { $_.status -ne "completed" }
Write-Output "Active commands: $($active.Count)"
$active | ForEach-Object {
    Write-Output "  $($_.name): $($_.status) | started: $($_.started)"
}

# Check recent log for where RefreshSeries is
Write-Output ""
$logContent = docker logs sonarr --tail 20 2>&1
Write-Output "=== Last 20 log lines ==="
Write-Output $logContent
