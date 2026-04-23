# Search for missing content in chunks to avoid overwhelming indexers
# Tracks progress in a state file and cycles through all missing content over multiple runs

param(
    [int]$ChunkCount = 20,         # Number of chunks to divide content into
    [switch]$IncludeUpgrades,      # Also search for quality upgrades
    [switch]$SonarrOnly,
    [switch]$RadarrOnly,
    [switch]$DryRun,
    [switch]$ResetState            # Start fresh from chunk 0
)

$ErrorActionPreference = "Stop"
$stateFile = "c:\jellyfin-stack\config\search-state.json"
$logFile = "c:\jellyfin-stack\logs\search-missing.log"

# Ensure log directory exists
if (-not (Test-Path "c:\jellyfin-stack\logs")) {
    New-Item -ItemType Directory -Path "c:\jellyfin-stack\logs" -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    Add-Content -Path $logFile -Value $logMessage
}

# Get or initialize state
function Get-State {
    if ($ResetState -or -not (Test-Path $stateFile)) {
        return @{
            sonarrChunk = 0
            radarrChunk = 0
            lastRun = $null
        }
    }
    $obj = Get-Content $stateFile | ConvertFrom-Json
    return @{
        sonarrChunk = [int]$obj.sonarrChunk
        radarrChunk = [int]$obj.radarrChunk
        lastRun = $obj.lastRun
    }
}

function Save-State {
    param($state)
    $state | ConvertTo-Json | Set-Content $stateFile
}

# Get API keys
[xml]$sonarrConfig = Get-Content "c:\jellyfin-stack\config\sonarr\config.xml"
$sonarrApiKey = $sonarrConfig.Config.ApiKey

[xml]$radarrConfig = Get-Content "c:\jellyfin-stack\config\radarr\config.xml"
$radarrApiKey = $radarrConfig.Config.ApiKey

$state = Get-State

Write-Log "=== Chunked Missing Content Search ===" "Cyan"
Write-Log "Chunk size: 1/$ChunkCount of total missing content"
if ($DryRun) { Write-Log "DRY RUN MODE - No searches will be triggered" "Yellow" }
Write-Log ""

# SONARR
if (-not $RadarrOnly) {
    Write-Log "=== SONARR ===" "Cyan"

    try {
        # Get all missing episodes
        $pageSize = 1000
        $allMissing = @()
        $page = 1

        do {
            $response = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/wanted/missing?pageSize=$pageSize&page=$page&sortKey=airDateUtc&sortDirection=ascending" `
                -Headers @{"X-Api-Key"=$sonarrApiKey} -Method Get
            $allMissing += $response.records
            $page++
        } while ($allMissing.Count -lt $response.totalRecords -and $response.records.Count -eq $pageSize)

        $totalMissing = $allMissing.Count
        Write-Log "Total missing episodes: $totalMissing"

        if ($totalMissing -eq 0) {
            Write-Log "No missing episodes!" "Green"
        } else {
            # Calculate chunk boundaries
            $chunkSize = [Math]::Ceiling($totalMissing / $ChunkCount)
            $currentChunk = $state.sonarrChunk % $ChunkCount
            $startIndex = $currentChunk * $chunkSize
            $endIndex = [Math]::Min($startIndex + $chunkSize - 1, $totalMissing - 1)

            Write-Log "Processing chunk $($currentChunk + 1)/$ChunkCount (episodes $($startIndex + 1) to $($endIndex + 1))"

            # Get episodes for this chunk
            $chunkEpisodes = $allMissing[$startIndex..$endIndex]
            Write-Log "Episodes in this chunk: $($chunkEpisodes.Count)"

            if (-not $DryRun) {
                # Search by episode IDs
                $episodeIds = $chunkEpisodes | ForEach-Object { $_.id }

                $command = @{
                    name = "EpisodeSearch"
                    episodeIds = $episodeIds
                } | ConvertTo-Json

                $result = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/command" `
                    -Headers @{"X-Api-Key"=$sonarrApiKey} `
                    -Method Post `
                    -Body $command `
                    -ContentType "application/json"

                Write-Log "Search queued (Command ID: $($result.id))" "Green"
            }

            # Update state for next run
            $state.sonarrChunk = ($currentChunk + 1) % $ChunkCount
        }

        # Quality upgrades (cutoff unmet)
        if ($IncludeUpgrades) {
            Write-Log ""
            Write-Log "Checking for quality upgrades..." "Gray"

            $cutoffResponse = Invoke-RestMethod -Uri "http://localhost:8989/api/v3/wanted/cutoff?pageSize=1" `
                -Headers @{"X-Api-Key"=$sonarrApiKey} -Method Get

            Write-Log "Episodes eligible for upgrade: $($cutoffResponse.totalRecords)" "Gray"
            Write-Log "(Upgrade search not implemented in chunked mode to avoid excessive searches)" "Gray"
        }

    } catch {
        Write-Log "ERROR: $($_.Exception.Message)" "Red"
    }

    Write-Log ""
}

# RADARR
if (-not $SonarrOnly) {
    Write-Log "=== RADARR ===" "Cyan"

    try {
        # Get all missing movies
        $movies = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/movie" `
            -Headers @{"X-Api-Key"=$radarrApiKey} -Method Get

        $missingMovies = $movies | Where-Object { $_.monitored -eq $true -and $_.hasFile -eq $false }
        $totalMissing = $missingMovies.Count

        Write-Log "Total missing movies: $totalMissing"

        if ($totalMissing -eq 0) {
            Write-Log "No missing movies!" "Green"
        } else {
            # Calculate chunk boundaries
            $chunkSize = [Math]::Ceiling($totalMissing / $ChunkCount)
            $currentChunk = $state.radarrChunk % $ChunkCount
            $startIndex = $currentChunk * $chunkSize
            $endIndex = [Math]::Min($startIndex + $chunkSize - 1, $totalMissing - 1)

            Write-Log "Processing chunk $($currentChunk + 1)/$ChunkCount (movies $($startIndex + 1) to $($endIndex + 1))"

            # Get movies for this chunk
            $chunkMovies = @($missingMovies)[$startIndex..$endIndex]
            Write-Log "Movies in this chunk: $($chunkMovies.Count)"

            if (-not $DryRun) {
                # Search each movie in chunk
                $movieIds = $chunkMovies | ForEach-Object { $_.id }

                $command = @{
                    name = "MoviesSearch"
                    movieIds = $movieIds
                } | ConvertTo-Json

                $result = Invoke-RestMethod -Uri "http://localhost:7878/api/v3/command" `
                    -Headers @{"X-Api-Key"=$radarrApiKey} `
                    -Method Post `
                    -Body $command `
                    -ContentType "application/json"

                Write-Log "Search queued (Command ID: $($result.id))" "Green"
            }

            # Update state for next run
            $state.radarrChunk = ($currentChunk + 1) % $ChunkCount
        }

    } catch {
        Write-Log "ERROR: $($_.Exception.Message)" "Red"
    }

    Write-Log ""
}

# Save state
$state.lastRun = (Get-Date).ToString("o")
Save-State $state

Write-Log "=== Summary ===" "Cyan"
Write-Log "Next Sonarr chunk: $($state.sonarrChunk + 1)/$ChunkCount"
Write-Log "Next Radarr chunk: $($state.radarrChunk + 1)/$ChunkCount"
Write-Log "Full cycle completes every: $($ChunkCount * 6) hours (at 6-hour intervals)"
Write-Log ""
Write-Log "State saved to: $stateFile"
Write-Log "Log file: $logFile"
