## Exports all custom scheduled tasks to XML files for disaster recovery.
## Run: powershell -ExecutionPolicy Bypass -File export-scheduled-tasks.ps1

$exportDir = "c:\jellyfin-stack\scheduled-tasks"
if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir | Out-Null }

$tasks = Get-ScheduledTask | Where-Object {
    $_.TaskPath -eq '\' -and
    $_.TaskName -notmatch 'Microsoft|Windows|User_Feed|GoogleUpdate|OneDrive|MsCtfMonitor|Adobe|AMDInstallLauncher|StartCN|StartDVR'
}

Write-Output "Exporting $($tasks.Count) scheduled tasks to $exportDir..."
foreach ($task in $tasks) {
    $name = $task.TaskName -replace '[^\w\-]', '_'
    Export-ScheduledTask -TaskName $task.TaskName | Out-File "$exportDir\$name.xml" -Encoding UTF8
    Write-Output "  Exported: $($task.TaskName)"
}

# Also create a human-readable summary
$summary = "# Scheduled Tasks - Jellyfin Stack`n"
$summary += "# Exported: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
$summary += "# To re-import: Register-ScheduledTask -Xml (Get-Content 'task.xml' | Out-String) -TaskName 'TaskName'`n`n"

foreach ($task in $tasks) {
    $action = $task.Actions | Select-Object -First 1
    $trigger = $task.Triggers | Select-Object -First 1
    $summary += "## $($task.TaskName)`n"
    $summary += "  State: $($task.State)`n"
    $summary += "  Execute: $($action.Execute)`n"
    $summary += "  Arguments: $($action.Arguments)`n"
    if ($trigger.Repetition.Interval) {
        $summary += "  Repeat: $($trigger.Repetition.Interval)`n"
    }
    $summary += "`n"
}

$summary | Out-File "$exportDir\TASKS-SUMMARY.txt" -Encoding UTF8
Write-Output ""
Write-Output "Summary written to $exportDir\TASKS-SUMMARY.txt"
Write-Output "Done!"
