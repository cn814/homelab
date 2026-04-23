$tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -notmatch 'Microsoft|Windows|User|Google|Update|AMD|StartCN|StartDVR' }

Write-Output "=== RECENT TASK RUNS ==="
Write-Output ""
foreach ($task in $tasks | Sort-Object TaskName) {
    $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
    $lastRun = $info.LastRunTime
    $lastResult = $info.LastTaskResult
    $resultText = switch ($lastResult) {
        0 { "SUCCESS" }
        1 { "FAILED (incorrect function)" }
        2 { "FAILED (file not found)" }
        267009 { "RUNNING" }
        267014 { "TERMINATED" }
        default { "CODE: $lastResult" }
    }

    # Highlight if ran in last 30 min
    $recent = ""
    if ($lastRun -and $lastRun -gt (Get-Date).AddMinutes(-30)) {
        $recent = " <-- RECENT"
    }

    Write-Output "$($task.TaskName)"
    Write-Output "  Last run: $lastRun"
    Write-Output "  Result: $resultText$recent"
    Write-Output ""
}
