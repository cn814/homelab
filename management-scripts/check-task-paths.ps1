$tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -notmatch 'Microsoft|Windows|User|Google|Update|AMD|StartCN|StartDVR|OneDrive' }

foreach ($task in $tasks | Sort-Object TaskName) {
    $action = $task.Actions | Select-Object -First 1
    $args = $action.Arguments
    # Check if any referenced file exists
    $scriptPath = ""
    if ($args -match '-File\s+"?([^"]+\.ps1)"?') {
        $scriptPath = $Matches[1]
    } elseif ($args -match '"([^"]+\.ps1)"') {
        $scriptPath = $Matches[1]
    }

    $exists = if ($scriptPath) { Test-Path $scriptPath } else { "N/A" }
    $status = if ($exists -eq $true) { "OK" } elseif ($exists -eq $false) { "MISSING!" } else { "?" }

    Write-Output "$($task.TaskName)"
    Write-Output "  Script: $scriptPath"
    Write-Output "  Exists: $status"
    Write-Output ""
}
