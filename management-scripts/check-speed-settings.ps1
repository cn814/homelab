$qbtUrl = "http://localhost:8090"

# Login
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$null = Invoke-WebRequest -Uri "$qbtUrl/api/v2/auth/login" -Method POST -Body "username=$env:QBIT_USER&password=$env:QBIT_PASS" -WebSession $session -UseBasicParsing

# Get preferences
$prefs = Invoke-RestMethod -Uri "$qbtUrl/api/v2/app/preferences" -WebSession $session

Write-Output "=== Speed & Queue Settings ==="
Write-Output "  Max active downloads: $($prefs.max_active_downloads)"
Write-Output "  Max active uploads: $($prefs.max_active_uploads)"
Write-Output "  Max active torrents: $($prefs.max_active_torrents)"
Write-Output "  Download speed limit: $(if ($prefs.dl_limit -eq 0) { 'Unlimited' } else { "$([math]::Round($prefs.dl_limit / 1MB, 1)) MB/s" })"
Write-Output "  Upload speed limit: $(if ($prefs.up_limit -eq 0) { 'Unlimited' } else { "$([math]::Round($prefs.up_limit / 1MB, 1)) MB/s" })"
Write-Output "  Max connections total: $($prefs.max_connec)"
Write-Output "  Max connections per torrent: $($prefs.max_connec_per_torrent)"
Write-Output "  Max uploads per torrent: $($prefs.max_uploads_per_torrent)"
Write-Output "  Max uploads total: $($prefs.max_uploads)"
Write-Output "  DHT: $($prefs.dht)"
Write-Output "  PeX: $($prefs.pex)"
Write-Output "  LSD: $($prefs.lsd)"
Write-Output "  Encryption: $($prefs.encryption)"
Write-Output "  Max ratio: $($prefs.max_ratio)"
Write-Output "  Max seed time: $($prefs.max_seeding_time) min"
Write-Output "  Slow torrent DL threshold: $($prefs.slow_torrent_dl_rate_threshold) KiB/s"
Write-Output "  Slow torrent UL threshold: $($prefs.slow_torrent_ul_rate_threshold) KiB/s"
Write-Output "  Slow torrent inactive secs: $($prefs.slow_torrent_inactive_timer)"

# Current transfer info
$transfer = Invoke-RestMethod -Uri "$qbtUrl/api/v2/transfer/info" -WebSession $session
Write-Output ""
Write-Output "=== Current Speeds ==="
Write-Output "  Download: $([math]::Round($transfer.dl_info_speed / 1MB, 2)) MB/s"
Write-Output "  Upload: $([math]::Round($transfer.up_info_speed / 1MB, 2)) MB/s"

# Queue breakdown
$torrents = Invoke-RestMethod -Uri "$qbtUrl/api/v2/torrents/info" -WebSession $session
$downloading = ($torrents | Where-Object { $_.state -match "downloading|stalledDL" }).Count
$active = ($torrents | Where-Object { $_.state -eq "downloading" }).Count
$stalled = ($torrents | Where-Object { $_.state -eq "stalledDL" }).Count
$queued = ($torrents | Where-Object { $_.state -eq "queuedDL" }).Count
$seeding = ($torrents | Where-Object { $_.state -match "uploading|stalledUP|queuedUP" }).Count
$total = $torrents.Count

Write-Output ""
Write-Output "=== Queue Breakdown ==="
Write-Output "  Actively downloading: $active"
Write-Output "  Stalled (waiting for peers): $stalled"
Write-Output "  Queued: $queued"
Write-Output "  Seeding/uploading: $seeding"
Write-Output "  Total: $total"

# Show slowest active downloads
Write-Output ""
Write-Output "=== Active Downloads by Speed ==="
$activeTorrents = $torrents | Where-Object { $_.state -eq "downloading" } | Sort-Object dlspeed
foreach ($t in $activeTorrents) {
    $name = $t.name
    if ($name.Length -gt 60) { $name = $name.Substring(0, 60) + "..." }
    $speed = [math]::Round($t.dlspeed / 1KB, 0)
    $pct = [math]::Round($t.progress * 100, 1)
    $seeds = $t.num_seeds
    Write-Output "  $speed KB/s | $pct% | $seeds seeds | $name"
}
