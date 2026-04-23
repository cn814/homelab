# Search deeper in Sonarr history for the last import event
Write-Output "=== Sonarr History - Searching for last import ==="
$page = 1
$found = $false
while ($page -le 20 -and -not $found) {
    $h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=100&page=$page&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
    $imports = $h.records | Where-Object { $_.eventType -eq "downloadFolderImported" }
    if ($imports.Count -gt 0) {
        Write-Output "Found imports on page $page!"
        $imports | Select-Object -First 5 | ForEach-Object {
            Write-Output "  $($_.eventType) | $($_.date) | $($_.sourceTitle)"
        }
        $found = $true
    } else {
        $oldest = $h.records | Select-Object -Last 1
        Write-Output "  Page $page (100 entries): All grabbed. Oldest: $($oldest.date)"
    }
    if ($h.records.Count -lt 100) {
        Write-Output "  Reached end of history on page $page"
        break
    }
    $page++
}

if (-not $found) {
    Write-Output ""
    Write-Output "NO import events found in last $($page * 100) history entries!"
}

# Also check event type breakdown across all history
Write-Output ""
Write-Output "=== History Event Type Summary ==="
$h2 = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=1&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
Write-Output "Total history records: $($h2.totalRecords)"

# Check Radarr last import for comparison
Write-Output ""
Write-Output "=== Radarr History - Last imports ==="
$rPage = 1
$rFound = $false
while ($rPage -le 10 -and -not $rFound) {
    $rh = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/history?pageSize=100&page=$rPage&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="a63000fb63a240a8bcb5e7d750926379"} -TimeoutSec 30
    $rImports = $rh.records | Where-Object { $_.eventType -eq "downloadFolderImported" }
    if ($rImports.Count -gt 0) {
        Write-Output "Found imports on page $rPage!"
        $rImports | Select-Object -First 5 | ForEach-Object {
            Write-Output "  $($_.eventType) | $($_.date) | $($_.sourceTitle)"
        }
        $rFound = $true
    } else {
        $rOldest = $rh.records | Select-Object -Last 1
        Write-Output "  Page ${rPage}: No imports. Oldest: $($rOldest.date)"
    }
    if ($rh.records.Count -lt 100) { break }
    $rPage++
}

# Check the Sonarr command history for when ProcessMonitoredDownloads stopped working normally
Write-Output ""
Write-Output "=== When did ProcessMonitoredDownloads last process an import? ==="
Write-Output "(Checking Sonarr logs for import-related messages)"
$logs = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/log?pageSize=200&sortKey=time&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$importLogs = $logs.records | Where-Object { $_.message -like "*imported*" -or $_.message -like "*Import*" }
Write-Output "Import-related log entries (last 200 logs): $($importLogs.Count)"
$importLogs | Select-Object -First 10 | ForEach-Object {
    Write-Output "  [$($_.level)] $($_.time): $($_.message)"
}
