# Find downloads for movies we already have on disk

[xml]$config = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$apiKey = $config.Config.ApiKey
$radarrUrl = "http://localhost:7878"

Write-Host "=== Checking for Unnecessary Downloads ===" -ForegroundColor Cyan

# Get movies with files
$movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 120
$moviesWithFiles = $movies | Where-Object { $_.hasFile -eq $true }

Write-Host "Movies with files on disk: $($moviesWithFiles.Count)" -ForegroundColor Gray

# Get queue
$queue = Invoke-RestMethod -Uri "$radarrUrl/api/v3/queue?pageSize=500" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 60

Write-Host "Items in download queue: $($queue.records.Count)" -ForegroundColor Gray
Write-Host ""

# Find queue items for movies we already have
$unnecessary = @()

foreach ($item in $queue.records) {
    $movie = $moviesWithFiles | Where-Object { $_.id -eq $item.movieId }
    if ($movie) {
        # Check if download quality is same or lower than existing
        $unnecessary += [PSCustomObject]@{
            Id = $item.id
            Title = $movie.title
            Year = $movie.year
            DownloadQuality = $item.quality.quality.name
            Status = $item.status
            HasFile = $true
        }
    }
}

if ($unnecessary.Count -gt 0) {
    Write-Host "=== Downloads for Movies Already on Disk ===" -ForegroundColor Yellow
    Write-Host "Found $($unnecessary.Count) potentially unnecessary downloads:" -ForegroundColor Yellow
    Write-Host ""

    $unnecessary | ForEach-Object {
        Write-Host "  $($_.Title) ($($_.Year))" -ForegroundColor Gray
        Write-Host "    Downloading: $($_.DownloadQuality) | Status: $($_.Status)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "These movies already have files. Downloads may be upgrades or duplicates." -ForegroundColor Cyan
} else {
    Write-Host "No unnecessary downloads found - all queue items are for movies without files." -ForegroundColor Green
}

# Also check qBittorrent for orphaned torrents (not in Radarr/Sonarr queue)
Write-Host ""
Write-Host "=== Checking qBittorrent for Orphaned Torrents ===" -ForegroundColor Cyan

$torrents = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info" -TimeoutSec 30
$downloading = $torrents | Where-Object { $_.state -match "downloading|stalledDL|queuedDL|metaDL" }

# Get Sonarr queue too
[xml]$sonarrConfig = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
$sonarrKey = $sonarrConfig.Config.ApiKey
$sonarrQueue = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/queue?pageSize=500" -Headers @{"X-Api-Key"=$sonarrKey} -TimeoutSec 60

# Combine download hashes from both queues
$radarrHashes = $queue.records | ForEach-Object { $_.downloadId } | Where-Object { $_ }
$sonarrHashes = $sonarrQueue.records | ForEach-Object { $_.downloadId } | Where-Object { $_ }
$allQueueHashes = $radarrHashes + $sonarrHashes

$orphaned = $downloading | Where-Object {
    $hash = $_.hash.ToUpper()
    -not ($allQueueHashes | Where-Object { $_ -and $_.ToUpper() -eq $hash })
}

Write-Host "Downloading torrents: $($downloading.Count)" -ForegroundColor Gray
Write-Host "Orphaned (not in Radarr/Sonarr): $($orphaned.Count)" -ForegroundColor $(if ($orphaned.Count -gt 0) { "Yellow" } else { "Green" })

if ($orphaned.Count -gt 0) {
    Write-Host ""
    Write-Host "Orphaned torrents (not managed by Radarr/Sonarr):" -ForegroundColor Yellow
    $orphaned | Select-Object -First 20 | ForEach-Object {
        $progress = [math]::Round($_.progress * 100, 1)
        Write-Host "  [$($_.state)] $($_.name) ($progress%)" -ForegroundColor Gray
    }
    if ($orphaned.Count -gt 20) {
        Write-Host "  ... and $($orphaned.Count - 20) more" -ForegroundColor DarkGray
    }
}
