# Check torrent activity breakdown
$session = Invoke-WebRequest -Uri "http://localhost:8090/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -SessionVariable qbSession -UseBasicParsing
$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -WebSession $qbSession

# State breakdown
Write-Output "=== All Torrents by State ==="
$torrents | Group-Object -Property state | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}

# Category breakdown
Write-Output ""
Write-Output "=== By Category ==="
$torrents | Group-Object -Property category | Sort-Object Count -Descending | ForEach-Object {
    Write-Output "  $($_.Name): $($_.Count)"
}

# Active download stats
$active = $torrents | Where-Object { $_.state -eq "downloading" }
$totalDL = [Math]::Round(($active | Measure-Object -Property dlspeed -Sum).Sum / 1MB, 1)
Write-Output ""
Write-Output "=== Active Downloads ==="
Write-Output "Count: $($active.Count) | Speed: $totalDL MB/s"

# Stalled/queued eating slots
$stalled = $torrents | Where-Object { $_.state -eq "stalledDL" }
$queued = $torrents | Where-Object { $_.state -eq "queuedDL" }
$metaDL = $torrents | Where-Object { $_.state -eq "metaDL" }
Write-Output ""
Write-Output "=== Slot Eaters ==="
Write-Output "stalledDL: $($stalled.Count)"
Write-Output "queuedDL: $($queued.Count)"
Write-Output "metaDL: $($metaDL.Count)"

# Current limits
$prefs = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/app/preferences" -WebSession $qbSession
Write-Output ""
Write-Output "=== Limits ==="
Write-Output "max_active_downloads: $($prefs.max_active_downloads)"
Write-Output "max_active_torrents: $($prefs.max_active_torrents)"
Write-Output "max_active_uploads: $($prefs.max_active_uploads)"
Write-Output "dont_count_slow: $($prefs.dont_count_slow_torrents)"
Write-Output "slow_torrent_dl_rate: $($prefs.slow_torrent_dl_rate_threshold) KB/s"

# Seeding stats
$seeding = $torrents | Where-Object { $_.state -match "uploading|stalledUP" }
Write-Output ""
Write-Output "=== Seeding ==="
Write-Output "Total seeding: $($seeding.Count)"
$totalUP = [Math]::Round(($seeding | Measure-Object -Property upspeed -Sum).Sum / 1MB, 1)
Write-Output "Upload speed: $totalUP MB/s"
