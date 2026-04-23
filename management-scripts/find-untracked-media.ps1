# Find media folders not tracked by Sonarr/Radarr

Write-Host "=== Finding Untracked Media ===" -ForegroundColor Cyan

# Get Radarr movies
Write-Host ""
Write-Host "Loading Radarr library..." -ForegroundColor Yellow
[xml]$radarrConfig = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$radarrKey = $radarrConfig.Config.ApiKey
$radarrMovies = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/movie" -Headers @{"X-Api-Key"=$radarrKey} -TimeoutSec 120

# Get Radarr paths (convert Docker paths to Windows)
$radarrPaths = $radarrMovies | ForEach-Object {
    $_.path -replace "/data/Movies", "D:\Movies" -replace "/", "\"
}

# Get Sonarr series
Write-Host "Loading Sonarr library..." -ForegroundColor Yellow
[xml]$sonarrConfig = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
$sonarrKey = $sonarrConfig.Config.ApiKey
$sonarrSeries = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/series" -Headers @{"X-Api-Key"=$sonarrKey} -TimeoutSec 120

# Get Sonarr paths
$sonarrPaths = $sonarrSeries | ForEach-Object {
    $_.path -replace "/data/TV", "D:\TV" -replace "/", "\"
}

# Check Movies folders
Write-Host ""
Write-Host "=== Untracked Movie Folders ===" -ForegroundColor Cyan
$movieFolders = Get-ChildItem "D:\Movies" -Directory | Where-Object { $_.Name -notmatch "\.trickplay$" }
$untrackedMovies = @()

foreach ($folder in $movieFolders) {
    $isTracked = $radarrPaths | Where-Object { $_ -eq $folder.FullName -or $_ -like "$($folder.FullName)*" }
    if (-not $isTracked) {
        # Check if folder has video files
        $hasVideo = Get-ChildItem $folder.FullName -Recurse -File | Where-Object { $_.Extension -match "\.(mkv|mp4|avi|m4v)$" } | Select-Object -First 1
        if ($hasVideo) {
            $untrackedMovies += $folder.Name
        }
    }
}

if ($untrackedMovies.Count -gt 0) {
    Write-Host "Found $($untrackedMovies.Count) untracked movie folders:" -ForegroundColor Yellow
    $untrackedMovies | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
} else {
    Write-Host "All movie folders are tracked in Radarr" -ForegroundColor Green
}

# Check TV folders
Write-Host ""
Write-Host "=== Untracked TV Folders ===" -ForegroundColor Cyan
$tvFolders = Get-ChildItem "D:\TV" -Directory | Where-Object { $_.Name -notmatch "\.trickplay$" }
$untrackedTV = @()

foreach ($folder in $tvFolders) {
    $isTracked = $sonarrPaths | Where-Object { $_ -eq $folder.FullName -or $_ -like "$($folder.FullName)*" }
    if (-not $isTracked) {
        # Check if folder has video files
        $hasVideo = Get-ChildItem $folder.FullName -Recurse -File | Where-Object { $_.Extension -match "\.(mkv|mp4|avi|m4v)$" } | Select-Object -First 1
        if ($hasVideo) {
            $untrackedTV += $folder.Name
        }
    }
}

if ($untrackedTV.Count -gt 0) {
    Write-Host "Found $($untrackedTV.Count) untracked TV folders:" -ForegroundColor Yellow
    $untrackedTV | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
} else {
    Write-Host "All TV folders are tracked in Sonarr" -ForegroundColor Green
}

# Summary
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "  Movies in Radarr: $($radarrMovies.Count)"
Write-Host "  Movie folders on disk: $($movieFolders.Count)"
Write-Host "  Untracked movie folders: $($untrackedMovies.Count)" -ForegroundColor $(if ($untrackedMovies.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host ""
Write-Host "  Series in Sonarr: $($sonarrSeries.Count)"
Write-Host "  TV folders on disk: $($tvFolders.Count)"
Write-Host "  Untracked TV folders: $($untrackedTV.Count)" -ForegroundColor $(if ($untrackedTV.Count -gt 0) { "Yellow" } else { "Green" })
