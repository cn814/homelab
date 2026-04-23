$sonarrHeaders = @{ "X-Api-Key" = "2ac6994b6a224d5d84ebd4c7abd7381c" }
$radarrHeaders = @{ "X-Api-Key" = "a63000fb63a240a8bcb5e7d750926379" }

Write-Output "=== Sonarr Queue - Manual Interaction Required ==="
$page = 1
$sonarrCount = 0
do {
    $q = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?page=$page&pageSize=500&includeUnknownSeriesItems=true" -Headers $sonarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.trackedDownloadStatus -eq "warning" -or $item.errorMessage) {
            $title = $item.title
            if ($title.Length -gt 70) { $title = $title.Substring(0, 70) + "..." }
            $msgs = @()
            foreach ($sm in $item.statusMessages) {
                $msgs += $sm.title
                foreach ($m in $sm.messages) { $msgs += "    - $m" }
            }
            if ($item.errorMessage) { $msgs += $item.errorMessage }
            $reason = $msgs -join "`n    "
            Write-Output "  $title"
            Write-Output "    $reason"
            Write-Output ""
            $sonarrCount++
        }
    }
    $page++
} while ($q.records.Count -eq 500)
Write-Output "  Total: $sonarrCount items needing attention"

Write-Output ""
Write-Output "=== Radarr Queue - Manual Interaction Required ==="
$page = 1
$radarrCount = 0
do {
    $q = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue?page=$page&pageSize=500&includeUnknownMovieItems=true" -Headers $radarrHeaders -TimeoutSec 60
    foreach ($item in $q.records) {
        if ($item.trackedDownloadStatus -eq "warning" -or $item.errorMessage) {
            $title = $item.title
            if ($title.Length -gt 70) { $title = $title.Substring(0, 70) + "..." }
            $msgs = @()
            foreach ($sm in $item.statusMessages) {
                $msgs += $sm.title
                foreach ($m in $sm.messages) { $msgs += "    - $m" }
            }
            if ($item.errorMessage) { $msgs += $item.errorMessage }
            $reason = $msgs -join "`n    "
            Write-Output "  $title"
            Write-Output "    $reason"
            Write-Output ""
            $radarrCount++
        }
    }
    $page++
} while ($q.records.Count -eq 500)
Write-Output "  Total: $radarrCount items needing attention"
