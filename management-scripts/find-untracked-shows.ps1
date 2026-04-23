# Find TV shows on disk that aren't tracked in Sonarr

$ErrorActionPreference = "Stop"

[xml]$config = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
$apiKey = $config.Config.ApiKey
$sonarrUrl = "http://localhost:8989"

Write-Host "=== Finding Untracked TV Shows ===" -ForegroundColor Cyan
Write-Host ""

# Get all series from Sonarr
Write-Host "Fetching Sonarr series list..." -ForegroundColor Gray
$sonarrSeries = Invoke-RestMethod -Uri "$sonarrUrl/api/v3/series" -Headers @{"X-Api-Key"=$apiKey} -TimeoutSec 180

# Build lookup sets
$sonarrTitlesLower = @{}
foreach ($s in $sonarrSeries) {
    $sonarrTitlesLower[$s.title.ToLower()] = $true
    # Also add without special chars
    $simplified = $s.title.ToLower() -replace '[^a-z0-9\s]', ''
    $sonarrTitlesLower[$simplified] = $true
    # Add sort title too
    if ($s.sortTitle) {
        $sonarrTitlesLower[$s.sortTitle.ToLower()] = $true
    }
}

Write-Host "Found $($sonarrSeries.Count) series in Sonarr" -ForegroundColor Gray
Write-Host ""

# Folders to skip
$skipPatterns = @(
    '\.trickplay$',
    '^temp$',
    '^backup$'
)

# Get all TV show folders on disk
Write-Host "Scanning D:\TV..." -ForegroundColor Gray
$diskFolders = Get-ChildItem -Path "D:\TV" -Directory -ErrorAction SilentlyContinue

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

    # Extract show title from folder name
    $cleanName = $folderName
    $cleanName = $cleanName -replace '\s*[\(\[]\d{4}[\)\]].*$', ''  # (2020) and everything after
    $cleanName = $cleanName -replace '\s*\(\d{4}\)$', ''  # just (2020)
    $cleanName = $cleanName -replace '\s*Season.*$', ''  # Season info
    $cleanName = $cleanName -replace '\s*S\d+.*$', ''  # S1-4 etc
    $cleanName = $cleanName -replace '\s*\d{4}$', ''  # trailing year
    $cleanName = $cleanName.Trim().ToLower()
    $simplifiedName = $cleanName -replace '[^a-z0-9\s]', ''

    # Check if tracked
    $isTracked = $false

    if ($sonarrTitlesLower.ContainsKey($cleanName) -or $sonarrTitlesLower.ContainsKey($simplifiedName)) {
        $isTracked = $true
    }

    # Fuzzy match
    if (-not $isTracked) {
        foreach ($title in $sonarrTitlesLower.Keys) {
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
Write-Host "=== Potentially Untracked TV Shows ===" -ForegroundColor Yellow
Write-Host "(These are on disk but may not be in Sonarr)" -ForegroundColor Gray
Write-Host ""

$untracked | Sort-Object ParsedTitle | ForEach-Object {
    Write-Host "  $($_.Folder)" -ForegroundColor White
}

Write-Host ""
Write-Host "Total: $($untracked.Count) potentially untracked" -ForegroundColor Yellow
