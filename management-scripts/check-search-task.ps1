$task = Get-ScheduledTask -TaskName 'Jellyfin-SearchMissingChunked'
$action = $task.Actions[0]
Write-Output "Execute: $($action.Execute)"
Write-Output "Arguments: $($action.Arguments)"
Write-Output "WorkingDir: $($action.WorkingDirectory)"
Write-Output ""
$info = Get-ScheduledTaskInfo -TaskName 'Jellyfin-SearchMissingChunked'
Write-Output "Last run: $($info.LastRunTime)"
Write-Output "Last result: $($info.LastTaskResult)"
Write-Output "Next run: $($info.NextRunTime)"
