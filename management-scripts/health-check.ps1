# System Health Check

Write-Host "=== System Health Check ===" -ForegroundColor Cyan
Write-Host ""

# Container status
Write-Host "=== Containers ===" -ForegroundColor Yellow
$containers = docker ps --format "{{.Names}}|{{.Status}}" 2>$null
foreach ($c in $containers) {
    $parts = $c -split '\|'
    $name = $parts[0]
    $status = $parts[1]
    $color = if ($status -match "healthy|Up") { "Green" } else { "Red" }
    Write-Host "  $name : $status" -ForegroundColor $color
}

Write-Host ""

# qBittorrent
Write-Host "=== qBittorrent ===" -ForegroundColor Yellow
try {
    $transfer = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/transfer/info" -TimeoutSec 10
    $speedMB = [math]::Round($transfer.dl_info_speed / 1MB, 2)
    Write-Host "  Connection: $($transfer.connection_status)" -ForegroundColor $(if ($transfer.connection_status -eq "connected") { "Green" } else { "Red" })
    Write-Host "  DHT Nodes: $($transfer.dht_nodes)" -ForegroundColor White
    Write-Host "  Download: $speedMB MB/s" -ForegroundColor $(if ($speedMB -gt 1) { "Green" } elseif ($speedMB -gt 0.1) { "Yellow" } else { "Red" })

    $torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -TimeoutSec 30
    $downloading = ($torrents | Where-Object { $_.state -eq "downloading" }).Count
    $stalled = ($torrents | Where-Object { $_.state -eq "stalledDL" }).Count
    $seeding = ($torrents | Where-Object { $_.state -match "UP|seeding" }).Count
    Write-Host "  Downloading: $downloading | Stalled: $stalled | Seeding: $seeding | Total: $($torrents.Count)" -ForegroundColor White
} catch {
    Write-Host "  ERROR: Cannot connect to qBittorrent" -ForegroundColor Red
}

Write-Host ""

# Sonarr
Write-Host "=== Sonarr ===" -ForegroundColor Yellow
try {
    [xml]$config = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml" -ErrorAction Stop
    $status = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/system/status" -Headers @{"X-Api-Key"=$config.Config.ApiKey} -TimeoutSec 10
    Write-Host "  Version: $($status.version)" -ForegroundColor Green
    $queue = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=1" -Headers @{"X-Api-Key"=$config.Config.ApiKey} -TimeoutSec 10
    Write-Host "  Queue: $($queue.totalRecords) items" -ForegroundColor White
} catch {
    Write-Host "  ERROR: Cannot connect" -ForegroundColor Red
}

Write-Host ""

# Radarr
Write-Host "=== Radarr ===" -ForegroundColor Yellow
try {
    [xml]$config = Get-Content "c:\jellyfin-stack\config\radarr\config.xml" -ErrorAction Stop
    $status = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/system/status" -Headers @{"X-Api-Key"=$config.Config.ApiKey} -TimeoutSec 10
    Write-Host "  Version: $($status.version)" -ForegroundColor Green
    $queue = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue?pageSize=1" -Headers @{"X-Api-Key"=$config.Config.ApiKey} -TimeoutSec 10
    Write-Host "  Queue: $($queue.totalRecords) items" -ForegroundColor White
} catch {
    Write-Host "  ERROR: Cannot connect" -ForegroundColor Red
}

Write-Host ""

# Disk Space
Write-Host "=== Disk Space ===" -ForegroundColor Yellow
$drive = Get-PSDrive D -ErrorAction SilentlyContinue
if ($drive) {
    $usedGB = [math]::Round($drive.Used / 1GB, 1)
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    $totalGB = $usedGB + $freeGB
    $pctUsed = [math]::Round(($usedGB / $totalGB) * 100, 1)
    Write-Host "  D: Drive: $usedGB GB used / $totalGB GB total ($pctUsed%)" -ForegroundColor $(if ($pctUsed -gt 90) { "Red" } elseif ($pctUsed -gt 80) { "Yellow" } else { "Green" })
    Write-Host "  Free: $freeGB GB" -ForegroundColor White
}

Write-Host ""
Write-Host "=== Health Check Complete ===" -ForegroundColor Cyan
