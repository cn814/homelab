# Find movies on disk that aren't tracked in Radarr

$ErrorActionPreference = "Stop"

[xml]$config = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$apiKey = $config.Config.ApiKey
$radarrUrl = "http://localhost:7878"

Write-Host "=== Finding Untracked Movies ===" -ForegroundColor Cyan
Write-Host ""

# Get all movies from Radarr
Write-Host "Fetching Radarr movie list..." -ForegroundColor Gray
$radarrMovies = Invoke-RestMethod -Uri "$radarrUrl/api/v3/movie" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 180

# Build lookup sets
$radarrTitlesLower = @{}
foreach ($m in $radarrMovies) {
    $radarrTitlesLower[$m.title.ToLower()] = $true
    # Also add without special chars
    $simplified = $m.title.ToLower() -replace '[^a-z0-9\s]', ''
    $radarrTitlesLower[$simplified] = $true
}

Write-Host "Found $($radarrMovies.Count) movies in Radarr" -ForegroundColor Gray
Write-Host ""

# Folders to skip (personal, non-movie, or known collections)
$skipPatterns = @(
    '\.trickplay$',
    '^3D$',
    '^backup$',
    '^temp$',
    '^Charlie',
    '^wedding',
    '^2006BC',
    '^North America',
    # Collection folders (contents already tracked individually)
    '^007\.James\.Bond',
    '^Harry Potter UHD$',
    '^Lord of the Rings Trilogy',
    '^Star Wars Complete',
    '^Terminator Trilogy$',
    '^Jurassic\.Park\.Trilogy$',
    '^How To Train Your Dragon Trilogy$',
    '^Madagascar Trilogy$',
    '^Alien Quadrilogy$',
    '^Starship Troopers.*Collection',
    '^The Exorcist.*Anthology',
    '^The Final Destination Trilogy$',
    '^Resident\.Evil.*Box',
    '^Shrek 1 and 2$'
)

# Get all movie folders on disk
Write-Host "Scanning D:\Movies..." -ForegroundColor Gray
$diskFolders = Get-ChildItem -Path "D:\Movies" -Directory -ErrorAction SilentlyContinue

$untracked = @()

foreach ($folder in $diskFolders) {
    $folderName = $folder.Name

    # Skip based on patterns
    $skip = $false
    foreach ($pattern in $skipPatterns) {
        if ($folderName -match $pattern) {
            $skip = $true
            break
        }
    }
    if ($skip) { continue }

    # Extract movie title from folder name
    # Remove year, quality info, release group, etc.
    $cleanName = $folderName
    $cleanName = $cleanName -replace '\s*[\(\[]\d{4}[\)\]].*$', ''  # (2020) or [2020] and everything after
    $cleanName = $cleanName -replace '\s*\d{4}\s*$', ''  # trailing year
    $cleanName = $cleanName -replace '\.\d{4}\..*$', ''  # .2020. and everything after
    $cleanName = $cleanName -replace '\s*\d{3,4}p.*$', ''  # 1080p and everything after
    $cleanName = $cleanName -replace '\.', ' '
    $cleanName = $cleanName -replace '_', ' '
    $cleanName = $cleanName -replace '\s+', ' '
    $cleanName = $cleanName.Trim().ToLower()
    $simplifiedName = $cleanName -replace '[^a-z0-9\s]', ''

    # Check if tracked
    $isTracked = $false

    if ($radarrTitlesLower.ContainsKey($cleanName) -or $radarrTitlesLower.ContainsKey($simplifiedName)) {
        $isTracked = $true
    }

    # Fuzzy match - check if Radarr has something very similar
    if (-not $isTracked) {
        foreach ($title in $radarrTitlesLower.Keys) {
            if ($title.Length -gt 3 -and $cleanName.Length -gt 3) {
                if ($title.Contains($cleanName) -or $cleanName.Contains($title)) {
                    $isTracked = $true
                    break
                }
            }
        }
    }

    if (-not $isTracked) {
        $untracked += [PSCustomObject]@{
            Folder = $folderName
            ParsedTitle = $cleanName
        }
    }
}

Write-Host ""
Write-Host "=== Potentially Untracked Movies ===" -ForegroundColor Yellow
Write-Host "(These are on disk but may not be in Radarr)" -ForegroundColor Gray
Write-Host ""

$untracked | Sort-Object ParsedTitle | ForEach-Object {
    Write-Host "  $($_.Folder)" -ForegroundColor White
}

Write-Host ""
Write-Host "Total: $($untracked.Count) potentially untracked" -ForegroundColor Yellow
