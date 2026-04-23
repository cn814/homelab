# Check Sonarr and Radarr queue status

# Get API keys
[xml]$sonarrConfig = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
$sonarrApiKey = $sonarrConfig.Config.ApiKey

[xml]$radarrConfig = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$radarrApiKey = $radarrConfig.Config.ApiKey

# Check Sonarr queue
Write-Host "=== SONARR QUEUE ===" -ForegroundColor Cyan
$sonarrQueue = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue" -Headers @{"X-Api-Key"=$sonarrApiKey}
Write-Host "Items in queue: $($sonarrQueue.records.Count)" -ForegroundColor White

if ($sonarrQueue.records.Count -gt 0) {
    Write-Host ""
    foreach ($item in ($sonarrQueue.records | Select-Object -First 5)) {
        $title = $item.title
        if ($title.Length -gt 60) { $title = $title.Substring(0, 57) + "..." }
        Write-Host "  [$($item.status)] $title"
    }
}

Write-Host ""

# Check Radarr queue
Write-Host "=== RADARR QUEUE ===" -ForegroundColor Cyan
$radarrQueue = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/queue" -Headers @{"X-Api-Key"=$radarrApiKey}
Write-Host "Items in queue: $($radarrQueue.records.Count)" -ForegroundColor White

if ($radarrQueue.records.Count -gt 0) {
    Write-Host ""
    foreach ($item in ($radarrQueue.records | Select-Object -First 5)) {
        $title = $item.title
        if ($title.Length -gt 60) { $title = $title.Substring(0, 57) + "..." }
        Write-Host "  [$($item.status)] $title"
    }
}

Write-Host ""

# Check qBittorrent
Write-Host "=== QBITTORRENT ===" -ForegroundColor Cyan
$qbt = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info"
$seeding = ($qbt | Where-Object { $_.state -match "UP" }).Count
$downloading = ($qbt | Where-Object { $_.state -eq "downloading" }).Count

Write-Host "Total torrents: $($qbt.Count)" -ForegroundColor White
Write-Host "Downloading: $downloading" -ForegroundColor Green
Write-Host "Seeding: $seeding" -ForegroundColor Yellow
