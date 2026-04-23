# Full queue breakdown
$page = 1
$allRecs = @()
do {
    $sq = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=200&page=$page" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"} -TimeoutSec 30
    $allRecs += $sq.records
    $page++
} while ($allRecs.Count -lt $sq.totalRecords -and $sq.records.Count -eq 200)

Write-Output "=== Sonarr Queue: $($sq.totalRecords) total ==="
Write-Output "By trackedDownloadState:"
$allRecs | Group-Object -Property trackedDownloadState | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}
Write-Output "By trackedDownloadStatus:"
$allRecs | Group-Object -Property trackedDownloadStatus | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}

# Warning items
$warnings = $allRecs | Where-Object { $_.trackedDownloadStatus -eq "warning" }
Write-Output ""
Write-Output "=== Warning Items: $($warnings.Count) ==="
$warnings | Select-Object -First 5 | ForEach-Object {
    Write-Output "  $($_.title)"
    $_.statusMessages | ForEach-Object {
        Write-Output "    Msg: $($_.title) - $($_.messages -join '; ')"
    }
}

# qBittorrent state
Write-Output ""
Write-Output "=== qBittorrent Status ==="
$login = Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -SessionVariable qbSession -UseBasicParsing
$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession
$tvTorrents = $torrents | Where-Object { $_.category -eq "tv-sonarr" }
$tvTorrents | Group-Object -Property state | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}
$downloading = $tvTorrents | Where-Object { $_.state -eq "downloading" }
$dlSpeed = ($downloading | Measure-Object -Property dlspeed -Sum).Sum / 1MB
Write-Output ""
Write-Output "Downloading: $($downloading.Count) at $([Math]::Round($dlSpeed, 1)) MB/s"

# Transfer info
$transfer = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/transfer/info" -WebSession $qbSession
Write-Output "Global DL: $([Math]::Round($transfer.dl_info_speed / 1MB, 1)) MB/s | UP: $([Math]::Round($transfer.up_info_speed / 1MB, 1)) MB/s"

# Completed but not imported
$completed = $tvTorrents | Where-Object { $_.progress -eq 1 }
Write-Output ""
Write-Output "Completed tv-sonarr in qBit: $($completed.Count)"

# Active commands
Write-Output ""
Write-Output "=== Sonarr Commands ==="
$cmds = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" -Headers @{"X-Api-Key"="2ac6994b6a224d5d84ebd4c7abd7381c"}
$active = $cmds | Where-Object { $_.status -ne "completed" }
if ($active.Count -eq 0) { Write-Output "  No active commands (idle)" }
$active | ForEach-Object { Write-Output "  $($_.name): $($_.status)" }
