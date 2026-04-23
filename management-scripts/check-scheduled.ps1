$tasks = Get-ScheduledTask | Where-Object { $_.TaskName -match 'Jellyfin|Sonarr|Radarr|Missing|Search|Cleanup|Torrent|Reannounce' }
foreach ($t in $tasks) {
    $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -ErrorAction SilentlyContinue
    Write-Output "$($t.TaskName)"
    Write-Output "  State: $($t.State)"
    Write-Output "  Next run: $($info.NextRunTime)"
    Write-Output "  Last run: $($info.LastRunTime)"
    Write-Output "  Last result: $($info.LastTaskResult)"
    Write-Output ""
}
