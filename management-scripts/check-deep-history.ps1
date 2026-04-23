# Check Sonarr history with specific event type filter
Write-Output "=== Sonarr: Looking for ANY import events ==="
try {
    $h = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=10&eventType=downloadFolderImported&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 60
    Write-Output "Import events total: $($h.totalRecords)"
    $h.records | ForEach-Object {
        Write-Output "  $($_.eventType) | $($_.date) | $($_.sourceTitle)"
    }
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}

# Check other event types
Write-Output ""
Write-Output "=== Sonarr: Event type 3 (downloadFolderImported) ==="
try {
    $h2 = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=5&eventType=3&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 60
    Write-Output "Total: $($h2.totalRecords)"
    $h2.records | ForEach-Object {
        Write-Output "  $($_.eventType) | $($_.date) | $($_.sourceTitle)"
    }
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}

# Check Sonarr episode files count
Write-Output ""
Write-Output "=== Sonarr: Library Stats ==="
try {
    $series = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 60
    $totalSeries = $series.Count
    $totalEpisodeFiles = ($series | Measure-Object -Property statistics -Sum).Sum
    $withFiles = ($series | Where-Object { $_.statistics.episodeFileCount -gt 0 }).Count
    $totalFiles = ($series | ForEach-Object { $_.statistics.episodeFileCount } | Measure-Object -Sum).Sum
    $totalEpisodes = ($series | ForEach-Object { $_.statistics.totalEpisodeCount } | Measure-Object -Sum).Sum
    Write-Output "Total series: $totalSeries"
    Write-Output "Series with files: $withFiles"
    Write-Output "Total episode files: $totalFiles"
    Write-Output "Total episodes (all): $totalEpisodes"
    Write-Output "Percentage with files: $([Math]::Round($totalFiles / $totalEpisodes * 100, 1))%"
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}

# Check Sonarr history total by event type using different pages
Write-Output ""
Write-Output "=== Sonarr: History breakdown ==="
try {
    $grabbed = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=1&eventType=grabbed&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
    Write-Output "Grabbed events: $($grabbed.totalRecords)"
    $imported = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=1&eventType=downloadFolderImported&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
    Write-Output "DownloadFolderImported events: $($imported.totalRecords)"
    if ($imported.totalRecords -gt 0) {
        $imported2 = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/history?pageSize=5&eventType=downloadFolderImported&sortKey=date&sortDirection=descending" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
        Write-Output "Last imports:"
        $imported2.records | ForEach-Object {
            Write-Output "  $($_.date) | $($_.sourceTitle)"
        }
    }
} catch {
    Write-Output "Error: $($_.Exception.Message)"
}
