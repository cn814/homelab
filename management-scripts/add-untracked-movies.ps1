# Add untracked movie folders to Radarr
Add-Type -AssemblyName System.Web

[xml]$config = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$apiKey = $config.Config.ApiKey
$radarrUrl = "http://localhost:7878"

Write-Host "=== Adding Untracked Movies to Radarr ===" -ForegroundColor Cyan

# Get existing movies, root folders, quality profiles
$existingMovies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 120
$rootFolders = Invoke-RestMethod -Uri "$radarrUrl/api/v3/rootfolder" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 10
$qualityProfiles = Invoke-RestMethod -Uri "$radarrUrl/api/v3/qualityprofile" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 10

$rootPath = $rootFolders[0].path
$defaultProfileId = $qualityProfiles[0].id

# Get existing paths
$existingPaths = $existingMovies | ForEach-Object {
    $_.path -replace "/data/Movies", "D:\Movies" -replace "/", "\"
}

# Untracked folders list
$untrackedFolders = @(
    "007.James.Bond.Complete.Set.1962-2015.720p.BluRay.x264-ETRG",
    "21 Jump Street (2012)",
    "3 Ninjas (1992)",
    "65 (2023)",
    "A.Minecraft.Movie.2025.2160p.AMZN.WEB-DL.HDR10+.DDP5.1.H265-BEN.THE.MEN",
    "Alien Quadrilogy",
    "Avatar The Way of Water (2022)",
    "Avengers Age of Ultron (2015)",
    "Batman.v.Superman.Dawn.of.Justice.2016.EXTENDED.1080p.BluRay.x264.DTS-JYK",
    "Bill Maher Be More Cynical (2000)",
    "Bill Maher The Decider (2007)",
    "Borat (2006)",
    "Captain America Civil War (2016)",
    "Captain.America.Brave.New.World.2025.2160p.DCP.WEBRIP.DD5.1.SDR.H265-AOC",
    "Charlie Brown",
    "Clifford the Big Red Dog (2021)",
    "Daniel Tosh Completely Serious (2007)",
    "Despicable.Me.3.2017.2160p.UHD.BluRay.x265-SWAGGERUHD",
    "Despicable.Me.4.2024.1080p",
    "Dune Part Two (2024)",
    "Elf.2003.2160p.UHD.BluRay.Hybrid.REMUX.DV.HDR10+.MULTi.DTS-HD.MA.H265-BEN.THE.MEN",
    "Fantastic Four Rise of the Silver Surfer (2007)",
    "Frost Nixon (2008)",
    "Furiosa A Mad Max Saga (2024)",
    "G.I. Joe The Rise of Cobra (2009)",
    "Gabby's Dollhouse The Movie (2025)",
    "Ghostbusters Afterlife (2021)",
    "Godzilla.x.Kong.The.New.Empire.2024.2160p",
    "Harry Potter 20th Anniversary Return to Hogwarts (2022)",
    "Hellboy II The Golden Army (2008)",
    "Hitman's Wife's Bodyguard (2021)",
    "Hocus Pocus (1993)",
    "I Am Legend (2007)",
    "Lone Survivor (2013) 720p BrRip x264 - YIFY",
    "Mad Max Fury Road (2015)",
    "Michael Jackson Number Ones (2003)",
    "Minions The Rise of Gru (2022)",
    "Mission Impossible - The Final Reckoning (2025)",
    "Obi-Wan Kenobi A Jedi's Return (2022)",
    "Onward.2020.1080p.WEB-DL.DD5.1.H264-FGT",
    "PAW Patrol Brave Heroes, Big Rescues (2016)",
    "Paw Patrol Jungle Rescues 2017 DVDRip  XviD AC3-CMRG",
    "PAW Patrol Mighty Pups (2018)",
    "PAW Patrol Ready, Race, Rescue! (2019)",
    "Peter Rabbit 2 The Runaway (2021)",
    "Planes  Fire and Rescue Smokejumpers (2014)",
    "Punisher War Zone (2008)",
    "Roofman.2025.2160p.iT.WEB-DL.DV.HDR10+.DDP5.1.H265.MP4-BEN.THE.MEN",
    "Snake Eyes G.I. Joe Origins (2021)",
    "Sonic the Hedgehog 3 (2024)",
    "Spider-Man All Roads Lead to No Way Home (2022)",
    "Spider-Man Into the Spider-Verse (2018)",
    "Spider-Man No Way Home (2021)",
    "Spider-Man.Across.The.Spider-Verse.2023.2160",
    "StarTrek 10 - Nemesis - Special Collector's Edition",
    "Step Up 2 The Streets (2008)",
    "Superman (2025)",
    "Taken (2008)",
    "TAYLOR SWIFT  THE ERAS TOUR (2023)",
    "Teenage Mutant Ninja Turtles Mutant Mayhem (2023)",
    "The Andromeda Strain (2008)",
    "The Batman (2022)",
    "The Conjuring Last Rites (2025)",
    "The Falcon and the Snowman (1985)",
    "The Grinch (2018)",
    "The Hunger Games The Ballad of Songbirds & Snakes (2023)",
    "The Iron Giant (1999)",
    "The X Files I Want to Believe (2008)",
    "The.Accountant.2.2025.1080",
    "The.Amateur.2025.2160p",
    "The.Greatest.Showman.2017.2160p.UHD.BluRay.x265-EMERALD",
    "Thor Love and Thunder (2022)",
    "Thunderbolts (2025)",
    "Transformers Dark of the Moon (2011)",
    "Transporter 2 (2005)",
    "TRON Ares (2025)",
    "Venom Let There Be Carnage (2021)",
    "Venom The Last Dance (2024)",
    "X-Men Origins Wolverine (2009)"
)

# Skip collections/trilogies and personal videos - these need manual handling
$skipFolders = @(
    "007.James.Bond.Complete.Set.1962-2015.720p.BluRay.x264-ETRG",
    "Alien Quadrilogy",
    "Charlie Brown",
    "CharlieVideos",
    "Harry Potter UHD",
    "Harry.Potter",
    "How To Train Your Dragon Trilogy",
    "Jurassic.Park.Trilogy",
    "Lord of the Rings Trilogy UHD",
    "Madagascar Trilogy",
    "North America (series)",
    "Shrek 1 and 2",
    "Star Wars Complete Saga",
    "Terminator Trilogy",
    "The Final Destination Trilogy",
    "The Making of 'The X Files Fight the Future' (1998)",
    "UFC 101 Declaration (2009)",
    "weddingvids",
    "Michael Jackson Number Ones (2003)"
)

$added = 0
$skipped = 0
$failed = @()

foreach ($folder in $untrackedFolders) {
    if ($skipFolders -contains $folder) {
        Write-Host "  Skipping (collection/personal): $folder" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Parse movie name and year from folder
    $movieName = $folder
    $year = $null

    # Try to extract year
    if ($folder -match '[\.\s\(\[]*((?:19|20)\d{2})[\.\s\)\]]*') {
        $year = $matches[1]
        $movieName = $folder -replace '[\.\s\(\[]*(?:19|20)\d{2}.*$', ''
    }

    # Clean up movie name
    $movieName = $movieName -replace '\.', ' '
    $movieName = $movieName -replace '\[.*?\]', ''
    $movieName = $movieName -replace '\(.*?\)', ''
    $movieName = $movieName -replace '720p.*|1080p.*|2160p.*|4K.*|UHD.*|BluRay.*|WEB.*|REMUX.*|HDR.*|DTS.*|x264.*|x265.*|HEVC.*', ''
    $movieName = $movieName -replace '\s+', ' '
    $movieName = $movieName.Trim()

    if ([string]::IsNullOrWhiteSpace($movieName)) {
        $failed += [PSCustomObject]@{ Folder = $folder; Reason = "Can't parse name" }
        continue
    }

    Write-Host "  Searching: $movieName $(if ($year) { "($year)" })" -ForegroundColor Yellow

    # Search Radarr
    $searchQuery = [System.Web.HttpUtility]::UrlEncode($movieName)
    try {
        $results = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie/lookup?term=$searchQuery" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 30
    } catch {
        $failed += [PSCustomObject]@{ Folder = $folder; Reason = "Search failed" }
        continue
    }

    # Find best match
    $match = $null
    if ($year) {
        $match = $results | Where-Object { $_.year -eq [int]$year } | Select-Object -First 1
    }
    if (-not $match -and $results.Count -gt 0) {
        $match = $results[0]
    }

    if (-not $match) {
        $failed += [PSCustomObject]@{ Folder = $folder; Reason = "No match for: $movieName" }
        continue
    }

    # Check if already exists
    $exists = $existingMovies | Where-Object { $_.tmdbId -eq $match.tmdbId }
    if ($exists) {
        Write-Host "    Already in Radarr: $($match.title)" -ForegroundColor DarkGray
        $skipped++
        continue
    }

    # Add to Radarr
    $movie = @{
        title = $match.title
        tmdbId = $match.tmdbId
        year = $match.year
        qualityProfileId = $defaultProfileId
        rootFolderPath = $rootPath
        path = "$rootPath/$folder"
        monitored = $false
        addOptions = @{ searchForMovie = $false }
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{"X-Api-Key"=$apiKey} -Method Post -Body $movie -ContentType "application/json" -TimeoutSec 15 | Out-Null
        Write-Host "    Added: $($match.title) ($($match.year))" -ForegroundColor Green
        $added++
    } catch {
        $failed += [PSCustomObject]@{ Folder = $folder; Reason = "Add failed: $($_.Exception.Message)" }
    }

    Start-Sleep -Milliseconds 300
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "  Added: $added" -ForegroundColor Green
Write-Host "  Skipped: $skipped" -ForegroundColor Gray
Write-Host "  Failed: $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { "Yellow" } else { "Green" })

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Failed ===" -ForegroundColor Yellow
    $failed | ForEach-Object {
        Write-Host "  $($_.Folder)" -ForegroundColor Gray
        Write-Host "    $($_.Reason)" -ForegroundColor DarkGray
    }
}

# Trigger rescan
Write-Host ""
Write-Host "Triggering Radarr rescan..." -ForegroundColor Cyan
$body = @{ name = "RescanMovie" } | ConvertTo-Json
Invoke-RestMethod -Uri "$radarrUrl/api/v3/command" -Headers @{"X-Api-Key"=$apiKey} -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 | Out-Null
Write-Host "Done!" -ForegroundColor Green
