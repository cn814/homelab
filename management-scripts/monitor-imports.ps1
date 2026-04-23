# Monitor Sonarr import status every 3 minutes for 1 hour
$logFile = "c:\jellyfin-stack\logs\import-monitor.log"
$startTime = Get-Date
$endTime = $startTime.AddHours(1)
$checkInterval = 180  # seconds

function Log($msg) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Output $line
    Add-Content -Path $logFile -Value $line
}

# Clear old log
Set-Content -Path $logFile -Value "=== Import Monitor Started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

$lastImportDate = $null
$totalNewImports = 0

while ((Get-Date) -lt $endTime) {
    Log "--- Check ---"

    # Check active commands
    try {
        $cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
        $active = $cmds | Where-Object { $_.status -ne "completed" }
        $activeNames = ($active | ForEach-Object { "$($_.name):$($_.status)" }) -join ", "
        if ($active.Count -eq 0) {
            Log "Commands: none active (idle)"
        } else {
            Log "Commands ($($active.Count)): $activeNames"
        }
    } catch {
        Log "Commands: API error - $($_.Exception.Message)"
    }

    # Check latest import
    try {
        $h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=5&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
        $latestImport = $h.records | Select-Object -First 1
        if ($latestImport) {
            $importDate = $latestImport.date
            if ($lastImportDate -eq $null) {
                $lastImportDate = $importDate
                Log "Latest import: $importDate | $($latestImport.sourceTitle)"
            } elseif ($importDate -ne $lastImportDate) {
                # New import since last check!
                $newImports = ($h.records | Where-Object { $_.date -gt $lastImportDate }).Count
                $totalNewImports += $newImports
                $lastImportDate = $importDate
                Log "NEW IMPORTS! +$newImports (total new: $totalNewImports) | Latest: $($latestImport.sourceTitle)"
            } else {
                Log "No new imports (last: $importDate)"
            }
        }
    } catch {
        Log "History: API error - $($_.Exception.Message)"
    }

    # Check queue
    try {
        $q = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=200" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 15
        $states = $q.records | Group-Object -Property trackedDownloadState
        $stateStr = ($states | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ", "
        $statuses = $q.records | Group-Object -Property status
        $statusStr = ($statuses | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ", "
        Log "Queue: $($q.totalRecords) total | States: $stateStr | Statuses: $statusStr"
    } catch {
        Log "Queue: API error - $($_.Exception.Message)"
    }

    # Check Radarr too
    try {
        $rh = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/history?pageSize=3&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="a63000fb63a240a8bcb5e7d750926379"} -TimeoutSec 15
        $rLatest = $rh.records | Select-Object -First 1
        if ($rLatest) {
            Log "Radarr latest import: $($rLatest.date) | $($rLatest.sourceTitle)"
        }
    } catch {
        Log "Radarr: API error"
    }

    # If imports started flowing, also trigger a DownloadedEpisodesScan
    if ($totalNewImports -eq 0) {
        # Check if RefreshSeries is done
        $refreshDone = -not ($active | Where-Object { $_.name -eq "RefreshSeries" })
        if ($refreshDone) {
            # RefreshSeries is done, try triggering a scan
            try {
                $scanBody = @{ name = "DownloadedEpisodesScan"; path = "/data2/Downloads" } | ConvertTo-Json
                $scanResult = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Method POST -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"; "Content-Type"="application/json"} -Body $scanBody -TimeoutSec 15
                Log "Triggered DownloadedEpisodesScan (ID: $($scanResult.id))"
            } catch {
                Log "Scan trigger: $($_.Exception.Message)"
            }
        }
    }

    Log ""
    Start-Sleep -Seconds $checkInterval
}

Log "=== Monitor Complete ==="
Log "Total new imports during monitoring: $totalNewImports"
