# Automatically search for and re-grab torrents for monitored content
# This will make Sonarr/Radarr find and add torrents for shows/movies already in your library

param(
    [switch]$SonarrOnly = $false,
    [switch]$RadarrOnly = $false,
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=== Auto-Search for Re-Seeding ===" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE" -ForegroundColor Yellow
    Write-Host ""
}

# Get API keys
try {
    [xml]$sonarrConfig = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
    $sonarrApiKey = $sonarrConfig.Config.ApiKey

    [xml]$radarrConfig = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
    $radarrApiKey = $radarrConfig.Config.ApiKey
} catch {
    Write-Host "ERROR: Could not read API keys" -ForegroundColor Red
    exit 1
}

# Check qBittorrent current seeding count
try {
    $qbtResponse = Invoke-RestMethod -Uri "http://localhost:8090/api/v2/torrents/info?filter=completed" -Method Get -TimeoutSec 10
    Write-Host "Current seeding torrents: $($qbtResponse.Count)" -ForegroundColor Yellow
    Write-Host ""
} catch {
    Write-Host "WARNING: Could not check qBittorrent" -ForegroundColor Yellow
    Write-Host ""
}

# Sonarr: Search for monitored episodes
if (-not $RadarrOnly) {
    Write-Host "=== SONARR ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        # Get monitored series with missing episodes
        $series = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"=$sonarrApiKey} -Method Get
        $monitored = $series | Where-Object { $_.monitored -eq $true }

        Write-Host "Found $($monitored.Count) monitored series" -ForegroundColor White
        Write-Host ""

        if ($DryRun) {
            Write-Host "Would search for missing episodes in these series" -ForegroundColor Yellow
        } else {
            # Trigger search for monitored series (batch command)
            Write-Host "Triggering automatic search for missing episodes..." -ForegroundColor White

            $command = @{
                name = "MissingEpisodeSearch"
            } | ConvertTo-Json

            $response = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" `
                -Headers @{"X-Api-Key"=$sonarrApiKey} `
                -Method Post `
                -Body $command `
                -ContentType "application/json"

            Write-Host "Search command queued (ID: $($response.id))" -ForegroundColor Green
            Write-Host "This will search for ALL missing monitored episodes" -ForegroundColor Gray
        }

    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

# Radarr: Search for monitored movies
if (-not $SonarrOnly) {
    Write-Host "=== RADARR ===" -ForegroundColor Cyan
    Write-Host ""

    try {
        # Get monitored movies
        $movies = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/movie" -Headers @{"X-Api-Key"=$radarrApiKey} -Method Get
        $monitored = $movies | Where-Object { $_.monitored -eq $true -and $_.hasFile -eq $false }

        Write-Host "Found $($monitored.Count) monitored movies without files" -ForegroundColor White
        Write-Host ""

        if ($monitored.Count -eq 0) {
            Write-Host "All monitored movies already have files!" -ForegroundColor Green
        } elseif ($DryRun) {
            Write-Host "Would search for these $($monitored.Count) movies" -ForegroundColor Yellow
        } else {
            Write-Host "Triggering automatic search for missing movies..." -ForegroundColor White

            $command = @{
                name = "MissingMoviesSearch"
            } | ConvertTo-Json

            $response = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/command" `
                -Headers @{"X-Api-Key"=$radarrApiKey} `
                -Method Post `
                -Body $command `
                -ContentType "application/json"

            Write-Host "Search command queued (ID: $($response.id))" -ForegroundColor Green
            Write-Host "This will search for ALL missing monitored movies" -ForegroundColor Gray
        }

    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "What happens next:" -ForegroundColor White
Write-Host "1. Sonarr/Radarr will search indexers for missing content" -ForegroundColor Gray
Write-Host "2. When they find torrents, they'll add them to qBittorrent" -ForegroundColor Gray
Write-Host "3. qBittorrent will check files and start seeding if complete" -ForegroundColor Gray
Write-Host "4. Your upload ratio will improve, boosting download speeds" -ForegroundColor Gray
Write-Host ""
Write-Host "Monitor progress at:" -ForegroundColor White
Write-Host "  Sonarr: http://localhost:8989/queue" -ForegroundColor Gray
Write-Host "  Radarr: http://localhost:7878/queue" -ForegroundColor Gray
Write-Host "  qBittorrent: http://localhost:8090" -ForegroundColor Gray
Write-Host ""
Write-Host "NOTE: This will only find content that Sonarr/Radarr are monitoring" -ForegroundColor Yellow
Write-Host "Content must still be available on your indexers (Prowlarr)" -ForegroundColor Yellow
