$tasks = @("Cleanup Dead Torrents", "Jellyfin-SearchMissingChunked")
foreach ($name in $tasks) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {
        $action = $task.Actions[0]
        Write-Output "$name"
        Write-Output "  Execute: $($action.Execute)"
        Write-Output "  Arguments: $($action.Arguments)"
        Write-Output "  WorkingDir: $($action.WorkingDirectory)"
        Write-Output ""
    }
}
