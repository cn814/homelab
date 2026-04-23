# Find movies in Radarr that don't have files but might exist on disk with different names

[xml]$config = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$apiKey = $config.Config.ApiKey
$radarrUrl = "http://localhost:7878"

Write-Host "=== Finding Movies Missing Files ===" -ForegroundColor Cyan

$movies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 120
$diskFolders = Get-ChildItem "D:\Movies" -Directory | Where-Object { $_.Name -notmatch "\.trickplay$" }

$missingWithMatch = @()

foreach ($movie in $movies) {
    if ($movie.hasFile) { continue }

    # Check if Radarr's path exists
    $radarrWindowsPath = $movie.path -replace "/data/Movies", "D:\Movies" -replace "/", "\"

    if (Test-Path -LiteralPath $radarrWindowsPath) {
        # Path exists but no file - check for video files
        $videoFiles = Get-ChildItem $radarrWindowsPath -File -Recurse | Where-Object { $_.Extension -match "\.(mkv|mp4|avi|m4v)$" }
        if ($videoFiles.Count -gt 0) {
            Write-Host "  Has files but Radarr doesn't see them: $($movie.title)" -ForegroundColor Yellow
            Write-Host "    Path: $radarrWindowsPath" -ForegroundColor DarkGray
        }
        continue
    }

    # Path doesn't exist - look for similar folder
    $cleanTitle = $movie.title -replace '[<>:"/\\|?*]', '' -replace '\s+', '.*'

    foreach ($folder in $diskFolders) {
        if ($folder.Name -match $movie.year -and $folder.Name -match $cleanTitle.Substring(0, [Math]::Min(10, $cleanTitle.Length))) {
            $videoFiles = Get-ChildItem $folder.FullName -File -Recurse | Where-Object { $_.Extension -match "\.(mkv|mp4|avi|m4v)$" }
            if ($videoFiles.Count -gt 0) {
                $missingWithMatch += [PSCustomObject]@{
                    Title = $movie.title
                    Year = $movie.year
                    Id = $movie.id
                    CurrentPath = $movie.path
                    ActualFolder = $folder.Name
                    NewPath = "/data/Movies/$($folder.Name)"
                }
                break
            }
        }
    }
}

Write-Host ""
Write-Host "=== Movies with Wrong Paths ===" -ForegroundColor Cyan
Write-Host "Found $($missingWithMatch.Count) movies that exist on disk with different folder names" -ForegroundColor Yellow

if ($missingWithMatch.Count -gt 0) {
    $missingWithMatch | ForEach-Object {
        Write-Host ""
        Write-Host "  $($_.Title) ($($_.Year))" -ForegroundColor Green
        Write-Host "    Radarr path: $($_.CurrentPath)" -ForegroundColor DarkGray
        Write-Host "    Actual folder: $($_.ActualFolder)" -ForegroundColor Cyan
    }

    Write-Host ""
    $confirm = Read-Host "Fix these paths? (y/n)"

    if ($confirm -eq 'y') {
        foreach ($item in $missingWithMatch) {
            $movie = $movies | Where-Object { $_.id -eq $item.Id }
            $movie.path = $item.NewPath

            $body = $movie | ConvertTo-Json -Depth 10
            try {
                Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie/$($item.Id)" -Headers @{"X-Api-Key"=$apiKey} -Method Put -Body $body -ContentType "application/json" -TimeoutSec 15 | Out-Null
                Write-Host "  Fixed: $($item.Title)" -ForegroundColor Green
            } catch {
                Write-Host "  Failed: $($item.Title) - $($_.Exception.Message)" -ForegroundColor Red
            }
            Start-Sleep -Milliseconds 100
        }

        Write-Host ""
        Write-Host "Triggering rescan..." -ForegroundColor Cyan
        $body = @{ name = "RescanMovie" } | ConvertTo-Json
        Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Headers @{"X-Api-Key"=$apiKey} -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
    }
}
