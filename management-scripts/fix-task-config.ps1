# Fix Cleanup Dead Torrents - remove broken redirect
$taskName = "Cleanup Dead Torrents"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"C:\jellyfin-stack\scripts\Cleanup-DeadTorrents.ps1`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 2)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Remove 0-seeder torrents every 2 hours" | Out-Null
Write-Output "Fixed: $taskName"

# Fix SearchMissingChunked - add -WindowStyle Hidden for consistency
$taskName2 = "Jellyfin-SearchMissingChunked"
$task2 = Get-ScheduledTask -TaskName $taskName2
$action2 = $task2.Actions[0]
Write-Output ""
Write-Output "SearchMissingChunked args: $($action2.Arguments)"
Write-Output "  (already has -WindowStyle Hidden, should be fine)"

# Test run
Write-Output ""
Write-Output "Test running Cleanup Dead Torrents task..."
Start-ScheduledTask -TaskName "Cleanup Dead Torrents"
Start-Sleep -Seconds 10
$info = Get-ScheduledTaskInfo -TaskName "Cleanup Dead Torrents"
Write-Output "Result: $($info.LastTaskResult)"
